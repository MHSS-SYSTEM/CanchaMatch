import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/campeonato.dart';
import '../models/equipo.dart';
import '../models/partido.dart';
import '../utils/fixture.dart';
import '../utils/formato.dart';

// CampeonatoException: error "esperado" de campeonatos (sin cupos, equipo
// incompleto, etc.) con un mensaje listo para mostrar en pantalla.
class CampeonatoException implements Exception {
  final String mensaje;

  CampeonatoException(this.mensaje);

  @override
  String toString() => mensaje;
}

// CampeonatoService: lectura y escritura de campeonatos, equipos y
// partidos.
//
//  - HU-13: el organizador crea el campeonato y genera el fixture.
//  - HU-14: el capitan arma su equipo y lo inscribe.
class CampeonatoService {
  static final CampeonatoService _instancia = CampeonatoService._interno();

  factory CampeonatoService() => _instancia;

  CampeonatoService._interno();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _campeonatos => _db.collection('campeonatos');
  CollectionReference<Map<String, dynamic>> get _equipos => _db.collection('equipos');
  CollectionReference<Map<String, dynamic>> _partidos(String campeonatoId) =>
      _campeonatos.doc(campeonatoId).collection('partidos');

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw CampeonatoException('Tu sesión expiró. Vuelve a iniciar sesión.');
    return uid;
  }

  static String mensajeDeError(Object error) {
    if (error is CampeonatoException) return error.mensaje;
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'No tienes permiso para hacer esto.';
        case 'unavailable':
          return 'No hay conexión a internet. Revisa tu conexión e inténtalo de nuevo.';
      }
    }
    return 'Ocurrió un problema, inténtalo de nuevo.';
  }

  // ---------------------------------------------------------------------
  // Datos en vivo
  // ---------------------------------------------------------------------

  // Todos los campeonatos, los mas proximos primero. Son Streams: si el
  // organizador registra un resultado, la tabla y el fixture se
  // actualizan solos en el celular de todos.
  Stream<List<Campeonato>> observarCampeonatos() {
    return _campeonatos.snapshots().map((snapshot) {
      final lista = snapshot.docs.map((doc) => Campeonato.fromMap(doc.id, doc.data())).toList();
      lista.sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
      return lista;
    });
  }

  Stream<Campeonato?> observarCampeonato(String id) {
    return _campeonatos.doc(id).snapshots().map((doc) => doc.exists ? Campeonato.fromMap(doc.id, doc.data()!) : null);
  }

  Stream<List<Partido>> observarPartidos(String campeonatoId) {
    return _partidos(campeonatoId).snapshots().map((snapshot) {
      final lista = snapshot.docs.map((doc) => Partido.fromMap(doc.id, doc.data())).toList();
      lista.sort((a, b) => a.ronda != b.ronda ? a.ronda.compareTo(b.ronda) : a.orden.compareTo(b.orden));
      return lista;
    });
  }

  // ---------------------------------------------------------------------
  // HU-13: Crear un campeonato
  // ---------------------------------------------------------------------

  Future<void> crear(Campeonato campeonato) async {
    await _campeonatos.add({
      ...campeonato.toMap(),
      'organizadorId': _uid,
      'estado': Campeonato.estadoInscripciones,
      'equiposIds': <String>[],
      'equiposNombres': <String, String>{},
      'creadoEn': FieldValue.serverTimestamp(),
    });
  }

  // generarFixture: cierra las inscripciones y el sistema arma todos los
  // partidos. Los equipos se mezclan al azar para que el sorteo sea justo.
  // Desde ese momento los horarios de los partidos ya no se pueden
  // reservar (ver ReservaService.horasDePartidos). Devuelve cuantos
  // partidos coinciden con reservas que ya estaban hechas, para avisarle
  // al organizador.
  //
  // Todo va en una transaccion: si un capitan se inscribe justo en ese
  // momento, Firestore repite la transaccion con la lista actualizada, asi
  // ningun equipo queda inscrito sin partidos.
  Future<int> generarFixture(Campeonato campeonato) async {
    final refCampeonato = _campeonatos.doc(campeonato.id);

    final error = await _db.runTransaction<String?>((transaccion) async {
      final doc = await transaccion.get(refCampeonato);
      if (!doc.exists) return 'El campeonato ya no existe.';
      final actual = Campeonato.fromMap(doc.id, doc.data()!);
      if (!actual.abierto) return 'El fixture ya fue generado.';
      if (actual.equiposIds.length < actual.minimoParaEmpezar) {
        return 'Se necesitan al menos ${actual.minimoParaEmpezar} equipos inscritos.';
      }

      final equipos = [...actual.equiposIds]..shuffle();

      // Si la fecha de inicio ya paso (se cerraron tarde las inscripciones),
      // el campeonato empieza mañana para que ningun partido quede en el
      // pasado.
      final manana = soloFecha(DateTime.now()).add(const Duration(days: 1));
      var inicio = fechaDesdeClave(actual.fechaInicio);
      if (inicio.isBefore(manana)) inicio = manana;
      final fin = fechaDesdeClave(actual.fechaFin);

      // Las rondas se reparten entre los dias en que abre la cancha.
      final disponibles = diasDeJuego(inicio, fin, actual.diasAbiertos);
      final plan = planificarRondas(actual.formato, equipos.length, actual.partidosPorDia, disponibles);
      if (plan.diasNecesarios > disponibles) {
        return 'Con ${equipos.length} equipos hacen falta ${plan.diasNecesarios} días de juego y solo hay '
            '$disponibles hasta el ${fechaTexto(fin)}. Usa "Cambiar fechas" para ampliar la fecha de fin.';
      }
      final diasEntreRondas = plan.diasEntreRondas;
      final fase = actual.formato == Campeonato.formatoGrupos ? Partido.faseGrupos : actual.formato;

      final conFase = Campeonato.fromMap(actual.id, {
        ...actual.toMap(),
        'fase': fase,
        'diasEntreRondas': diasEntreRondas,
        'fechaInicio': fechaClave(inicio),
      });
      for (final partido in GeneradorFixture(conFase).generarInicial(equipos)) {
        transaccion.set(_partidos(actual.id).doc(), partido.toMap());
      }
      transaccion.update(refCampeonato, {
        'estado': Campeonato.estadoEnCurso,
        'fase': fase,
        'diasEntreRondas': diasEntreRondas,
        'fechaInicio': fechaClave(inicio),
      });
      return null;
    });

    if (error != null) throw CampeonatoException(error);
    return _contarChoquesConReservas(campeonato.id, campeonato.canchaId);
  }

  // Cuenta los partidos que caen en un turno que ya tenia una reserva
  // activa. Si la consulta falla, no se avisa nada (el fixture ya quedo).
  Future<int> _contarChoquesConReservas(String campeonatoId, String canchaId) async {
    try {
      final partidos = await _partidos(campeonatoId).get();
      final ocupados = <String>{};
      final fechas = {for (final p in partidos.docs) (p.data()['fecha'] ?? '').toString()};
      for (final fecha in fechas) {
        final reservas = await _db
            .collection('reservas')
            .where('canchaId', isEqualTo: canchaId)
            .where('fecha', isEqualTo: fecha)
            .get();
        for (final r in reservas.docs) {
          final estado = r.data()['estado'];
          if (estado == 'pendiente_pago' || estado == 'confirmada') ocupados.add('${fecha}_${r.data()['hora']}');
        }
      }
      return partidos.docs.where((p) {
        final d = p.data();
        return (d['visitaId'] ?? '').toString().isNotEmpty && ocupados.contains('${d['fecha']}_${d['hora']}');
      }).length;
    } catch (_) {
      return 0;
    }
  }

  // cambiarFechas: el organizador mueve las fechas mientras las
  // inscripciones siguen abiertas (por ejemplo, si no alcanzan los dias
  // para todos los partidos).
  Future<void> cambiarFechas(Campeonato campeonato, DateTime inicio, DateTime fin) async {
    final refCampeonato = _campeonatos.doc(campeonato.id);
    final error = await _db.runTransaction<String?>((transaccion) async {
      final doc = await transaccion.get(refCampeonato);
      if (!doc.exists) return 'El campeonato ya no existe.';
      final actual = Campeonato.fromMap(doc.id, doc.data()!);
      if (!actual.abierto) return 'El fixture ya fue generado: las fechas ya no se pueden cambiar.';
      final problema = problemaConFechas(
        formato: actual.formato,
        maxEquipos: actual.maxEquipos,
        partidosPorDia: actual.partidosPorDia,
        diasAbiertos: actual.diasAbiertos,
        inicio: inicio,
        fin: fin,
      );
      if (problema != null) return problema;
      transaccion.update(refCampeonato, {'fechaInicio': fechaClave(inicio), 'fechaFin': fechaClave(fin)});
      return null;
    });
    if (error != null) throw CampeonatoException(error);
  }

  // problemaConFechas: revisa que entre inicio y fin haya dias de juego
  // suficientes para el campeonato aunque se llenen todos los cupos.
  // Devuelve el mensaje de error, o null si las fechas sirven.
  static String? problemaConFechas({
    required String formato,
    required int maxEquipos,
    required int partidosPorDia,
    required List<int> diasAbiertos,
    required DateTime inicio,
    required DateTime fin,
  }) {
    final manana = soloFecha(DateTime.now()).add(const Duration(days: 1));
    if (inicio.isBefore(manana)) return 'El campeonato debe empezar a partir de mañana.';
    if (fin.isBefore(inicio)) return 'La fecha de fin debe ser después del inicio.';
    final minimo = formato == Campeonato.formatoGrupos ? Campeonato.minEquiposGrupos : Campeonato.minEquipos;
    final necesarios = diasMinimos(formato, minimo, maxEquipos, partidosPorDia);
    final disponibles = diasDeJuego(inicio, fin, diasAbiertos);
    if (necesarios > disponibles) {
      return 'Con hasta $maxEquipos equipos hacen falta $necesarios días de juego (días en que abre la '
          'cancha) y entre esas fechas hay $disponibles. Amplía la fecha de fin.';
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // HU-14: Inscribir un equipo
  // ---------------------------------------------------------------------

  // El equipo del capitan (o null si todavia no lo armo).
  Future<Equipo?> obtenerMiEquipo() async {
    final doc = await _equipos.doc(_uid).get();
    return doc.exists ? Equipo.fromMap(doc.id, doc.data()!) : null;
  }

  // equipoEnCampeonatoActivo: si el equipo del capitan esta inscrito en un
  // campeonato que todavia no termina.
  Future<bool> equipoEnCampeonatoActivo() async {
    final campeonatos = await _campeonatos.where('equiposIds', arrayContains: _uid).get();
    return campeonatos.docs.any((doc) => doc.data()['estado'] != Campeonato.estadoFinalizado);
  }

  Future<void> guardarEquipo(Equipo equipo) {
    return _equipos.doc(_uid).set(equipo.toMap());
  }

  // inscribirEquipo: en una transaccion revisa que queden cupos, que el
  // equipo no este inscrito y que tenga los jugadores minimos. Si dos
  // capitanes se inscriben a la vez por el ultimo cupo, solo entra uno.
  Future<void> inscribirEquipo(String campeonatoId) async {
    final uid = _uid;
    final refCampeonato = _campeonatos.doc(campeonatoId);
    final refEquipo = _equipos.doc(uid);

    final error = await _db.runTransaction<String?>((transaccion) async {
      final docCampeonato = await transaccion.get(refCampeonato);
      final docEquipo = await transaccion.get(refEquipo);

      if (!docCampeonato.exists) return 'El campeonato ya no existe.';
      if (!docEquipo.exists) return 'Primero arma tu equipo en "Mi equipo".';
      final campeonato = Campeonato.fromMap(docCampeonato.id, docCampeonato.data()!);
      final equipo = Equipo.fromMap(docEquipo.id, docEquipo.data()!);

      if (!campeonato.abierto) return 'Las inscripciones ya están cerradas.';
      if (campeonato.equiposIds.contains(uid)) return 'Tu equipo ya está inscrito.';
      if (campeonato.cuposLibres <= 0) return 'Ya no quedan cupos en este campeonato.';
      if (!equipo.completo) return 'Tu equipo necesita al menos ${Equipo.minJugadores} jugadores.';
      if (equipo.deporte != campeonato.deporte) {
        return 'Tu equipo es de ${equipo.deporte} y este campeonato es de ${campeonato.deporte}.';
      }

      transaccion.update(refCampeonato, {
        'equiposIds': [...campeonato.equiposIds, uid],
        'equiposNombres.$uid': equipo.nombre,
      });
      return null;
    });

    if (error != null) throw CampeonatoException(error);
  }
}
