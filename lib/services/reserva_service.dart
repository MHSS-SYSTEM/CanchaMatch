import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/cancha.dart';
import '../models/reserva.dart';
import '../utils/formato.dart';

// ReservaException: error "esperado" de las reservas (turno ya tomado,
// tiempo vencido, etc.). Trae un mensaje listo para mostrar en pantalla.
class ReservaException implements Exception {
  final String mensaje;

  ReservaException(this.mensaje);

  @override
  String toString() => mensaje;
}

// ReservaService: lectura y escritura de la coleccion "reservas".
//
//  - HU-07: ver que turnos de una cancha estan libres u ocupados.
//  - HU-08: bloquear un turno 10 minutos y confirmarlo como reserva.
//  - HU-09: ver mis reservas, cancelarlas o moverlas a otro horario.
class ReservaService {
  static final ReservaService _instancia = ReservaService._interno();

  factory ReservaService() => _instancia;

  ReservaService._interno();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _reservas => _db.collection('reservas');

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw ReservaException('Tu sesión expiró. Vuelve a iniciar sesión.');
    return uid;
  }

  // mensajeDeError: convierte cualquier error de una operacion de reservas
  // en un texto claro para el usuario.
  static String mensajeDeError(Object error) {
    if (error is ReservaException) return error.mensaje;
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          // Las reglas de Firestore rechazaron la operacion: normalmente el
          // horario ya no esta disponible o el tiempo para confirmar vencio.
          return 'No se pudo completar: el horario ya no está disponible o el tiempo venció. '
              'Si se repite, revisa que la fecha y hora de tu celular estén en automático.';
        case 'unavailable':
          return 'No hay conexión a internet. Revisa tu conexión e inténtalo de nuevo.';
      }
    }
    return 'Ocurrió un problema, inténtalo de nuevo.';
  }

  // ---------------------------------------------------------------------
  // HU-07: Ver disponibilidad en calendario
  // ---------------------------------------------------------------------

  // observarReservasDelDia: todas las reservas de una cancha en una fecha.
  // Es un Stream, asi el calendario se actualiza solo cuando otro jugador
  // reserva o cancela un turno de esa cancha.
  Stream<List<Reserva>> observarReservasDelDia(String canchaId, String fecha) {
    return _reservas
        .where('canchaId', isEqualTo: canchaId)
        .where('fecha', isEqualTo: fecha)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Reserva.fromMap(doc.id, doc.data())).toList());
  }

  // observarReservasDeFecha: las reservas de TODAS las canchas en una
  // fecha. La usa la busqueda (HU-06) para saber que canchas todavia
  // tienen turnos libres ese dia.
  Stream<List<Reserva>> observarReservasDeFecha(String fecha) {
    return _reservas
        .where('fecha', isEqualTo: fecha)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Reserva.fromMap(doc.id, doc.data())).toList());
  }

  // ---------------------------------------------------------------------
  // HU-08: Reservar una cancha
  // ---------------------------------------------------------------------

  // _problemaConTurno: revisa, con los datos ACTUALES de la cancha, que el
  // turno se pueda reservar. Devuelve el mensaje de error, o null si todo
  // esta bien. Asi, aunque la pantalla estuviera abierta desde antes, no se
  // puede reservar en una cancha desactivada, en un dia que no atiende, en
  // una hora fuera de su horario o en un turno que ya empezo.
  String? _problemaConTurno(Cancha cancha, String fecha, int hora) {
    if (!cancha.disponible) return 'Esta cancha ya no está disponible.';
    final dia = fechaDesdeClave(fecha);
    if (!cancha.abreEl(dia)) return 'La cancha no atiende ese día.';
    if (!cancha.horasDelDia.contains(hora)) return 'Ese horario está fuera del horario de atención.';
    final inicio = DateTime(dia.year, dia.month, dia.day, hora);
    if (!inicio.isAfter(DateTime.now())) return 'Ese horario ya pasó.';
    return null;
  }

  // bloquearTurno: aparta el turno para este jugador durante 10 minutos
  // mientras elige el medio de pago y confirma.
  //
  // Se hace dentro de una transaccion: Firestore lee el turno (y la cancha)
  // y escribe como una sola operacion. Si dos jugadores tocan el mismo
  // turno al mismo tiempo, Firestore repite la transaccion del que llego
  // segundo, que entonces ve el turno ocupado y recibe el error. Asi es
  // imposible que el mismo horario quede reservado dos veces.
  Future<Reserva> bloquearTurno({
    required Cancha cancha,
    required String fecha,
    required int hora,
  }) async {
    final uid = _uid;
    final refCancha = _db.collection('canchas').doc(cancha.id);
    final ref = _reservas.doc(Reserva.idPara(cancha.id, fecha, hora));

    // La transaccion devuelve la reserva o un mensaje de error; el error se
    // lanza afuera para que llegue tal cual a la pantalla.
    final (reserva, error) = await _db.runTransaction<(Reserva?, String?)>((transaccion) async {
      final docCancha = await transaccion.get(refCancha);
      final actual = await transaccion.get(ref);

      if (!docCancha.exists) return (null, 'Esta cancha ya no existe.');
      final canchaActual = Cancha.fromMap(docCancha.id, docCancha.data()!);
      final problema = _problemaConTurno(canchaActual, fecha, hora);
      if (problema != null) return (null, problema);

      if (actual.exists) {
        final existente = Reserva.fromMap(actual.id, actual.data()!);
        if (existente.ocupaHorario) {
          // Si el bloqueo es del mismo jugador (por ejemplo, salio y volvio
          // a entrar), se le devuelve el mismo para que pueda confirmarlo.
          if (existente.usuarioId == uid && existente.estado == Reserva.estadoBloqueada) {
            return (existente, null);
          }
          return (null, 'Ese horario acaba de ser tomado por otra persona. Elige otro.');
        }
      }

      // Precio, nombre y politica se toman de la cancha guardada en
      // Firestore, no de lo que tenia la pantalla.
      final nueva = Reserva(
        id: ref.id,
        canchaId: canchaActual.id,
        canchaNombre: canchaActual.nombre,
        usuarioId: uid,
        fecha: fecha,
        hora: hora,
        estado: Reserva.estadoBloqueada,
        bloqueadoEn: DateTime.now(),
        precio: canchaActual.precioPorHora,
        horasLimiteCancelacion: canchaActual.horasLimiteCancelacion,
      );

      // bloqueadoEn se guarda con la hora del SERVIDOR (serverTimestamp) y
      // no con la del celular: asi los 10 minutos vencen igual para todos,
      // aunque algun celular tenga la hora mal puesta. Si el documento ya
      // existia (turno cancelado o bloqueo vencido), se sobrescribe.
      transaccion.set(ref, {
        ...nueva.toMap(),
        'bloqueadoEn': FieldValue.serverTimestamp(),
        'creadaEn': FieldValue.serverTimestamp(),
        'actualizadaEn': FieldValue.serverTimestamp(),
      });
      return (nueva, null);
    });

    if (reserva == null) throw ReservaException(error ?? 'No se pudo apartar el horario.');
    return reserva;
  }

  // confirmarReserva: convierte el bloqueo en reserva "pendiente de pago"
  // con el medio de pago que eligio el jugador. No se cobra nada en la
  // app: el pago se hace en el complejo.
  Future<void> confirmarReserva(String reservaId, String medioPago) async {
    final uid = _uid;
    final ref = _reservas.doc(reservaId);

    final confirmada = await _db.runTransaction<bool>((transaccion) async {
      final actual = await transaccion.get(ref);
      if (!actual.exists) return false;

      final reserva = Reserva.fromMap(actual.id, actual.data()!);
      if (reserva.usuarioId != uid || reserva.estado != Reserva.estadoBloqueada || !reserva.ocupaHorario) {
        return false;
      }

      transaccion.update(ref, {
        'estado': Reserva.estadoPendientePago,
        'medioPago': medioPago,
        'confirmadaEn': FieldValue.serverTimestamp(),
        'actualizadaEn': FieldValue.serverTimestamp(),
      });
      return true;
    });

    if (!confirmada) {
      throw ReservaException('Se acabó el tiempo para confirmar y el horario se liberó.');
    }
  }

  // liberarBloqueo: si el jugador sale sin confirmar, suelta el turno de
  // inmediato en vez de esperar a que venzan los 10 minutos. Si el bloqueo
  // ya se confirmo, no hace nada.
  Future<void> liberarBloqueo(String reservaId) async {
    try {
      final uid = _uid;
      final ref = _reservas.doc(reservaId);
      await _db.runTransaction<void>((transaccion) async {
        final actual = await transaccion.get(ref);
        if (!actual.exists) return;
        final reserva = Reserva.fromMap(actual.id, actual.data()!);
        if (reserva.usuarioId != uid || reserva.estado != Reserva.estadoBloqueada) return;
        transaccion.update(ref, {
          'estado': Reserva.estadoCancelada,
          'actualizadaEn': FieldValue.serverTimestamp(),
        });
      });
    } catch (_) {
      // Si falla (por ejemplo, sin internet), el bloqueo igual vence solo
      // a los 10 minutos, asi que no hace falta avisar al usuario.
    }
  }

  // ---------------------------------------------------------------------
  // HU-09: Cancelar o reprogramar reserva
  // ---------------------------------------------------------------------

  // observarMisReservas: reservas confirmadas del jugador. Se piden solo
  // las "pendiente_pago" (y no todo el historial) para no descargar
  // reservas canceladas o viejas. Las que ya empezaron se filtran en la
  // pantalla, que se refresca sola.
  Stream<List<Reserva>> observarMisReservas() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Stream.error(ReservaException('Tu sesión expiró. Vuelve a iniciar sesión.'));
    }
    return _reservas
        .where('usuarioId', isEqualTo: uid)
        .where('estado', isEqualTo: Reserva.estadoPendientePago)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Reserva.fromMap(doc.id, doc.data())).toList());
  }

  // obtenerCancha: datos actuales de la cancha de una reserva (para
  // mostrar su politica de cancelacion y su calendario al reprogramar).
  Future<Cancha?> obtenerCancha(String canchaId) async {
    final doc = await _db.collection('canchas').doc(canchaId).get();
    if (!doc.exists) return null;
    return Cancha.fromMap(doc.id, doc.data()!);
  }

  // dentroDePolitica: la reserva solo se puede cancelar o reprogramar
  // hasta cierto numero de horas antes del partido. Se usa el limite que
  // quedo guardado en la reserva al hacerla, asi un cambio posterior de la
  // politica no afecta a las reservas que ya existian.
  static bool dentroDePolitica(Reserva reserva) {
    final limite = reserva.inicio.subtract(Duration(hours: reserva.horasLimiteCancelacion));
    return DateTime.now().isBefore(limite);
  }

  // cancelarReserva: marca la reserva como cancelada. Con eso el turno
  // vuelve a quedar libre para otros jugadores (ver Reserva.ocupaHorario).
  Future<void> cancelarReserva(Reserva reserva) async {
    if (!dentroDePolitica(reserva)) {
      throw ReservaException('Según la política del complejo, esta reserva ya no se puede cancelar.');
    }
    final uid = _uid;
    final ref = _reservas.doc(reserva.id);

    final cancelada = await _db.runTransaction<bool>((transaccion) async {
      final actual = await transaccion.get(ref);
      if (!actual.exists) return false;
      final datos = Reserva.fromMap(actual.id, actual.data()!);
      if (datos.usuarioId != uid || datos.estado != Reserva.estadoPendientePago) return false;

      transaccion.update(ref, {
        'estado': Reserva.estadoCancelada,
        'canceladaEn': FieldValue.serverTimestamp(),
        'actualizadaEn': FieldValue.serverTimestamp(),
      });
      return true;
    });

    if (!cancelada) throw ReservaException('Esta reserva ya no está activa.');
  }

  // reprogramarReserva: mueve la reserva a otro turno libre de la misma
  // cancha. En una sola transaccion:
  //  1. revisa que la cancha siga activa y que el turno nuevo sea valido y
  //     este libre,
  //  2. crea la reserva en el turno nuevo (ya confirmada, con el mismo
  //     medio de pago),
  //  3. cancela la reserva original, liberando ese horario.
  // Si cualquier paso falla, no se cambia nada.
  Future<void> reprogramarReserva({
    required Reserva original,
    required Cancha cancha,
    required String nuevaFecha,
    required int nuevaHora,
  }) async {
    if (!dentroDePolitica(original)) {
      throw ReservaException('Según la política del complejo, esta reserva ya no se puede reprogramar.');
    }
    final uid = _uid;
    final refCancha = _db.collection('canchas').doc(cancha.id);
    final refOriginal = _reservas.doc(original.id);
    final refNueva = _reservas.doc(Reserva.idPara(cancha.id, nuevaFecha, nuevaHora));
    if (refNueva.id == refOriginal.id) {
      throw ReservaException('Elige un horario distinto al que ya tienes.');
    }

    // Firestore exige hacer todas las lecturas antes de las escrituras.
    final error = await _db.runTransaction<String?>((transaccion) async {
      final docCancha = await transaccion.get(refCancha);
      final docOriginal = await transaccion.get(refOriginal);
      final docNueva = await transaccion.get(refNueva);

      if (!docOriginal.exists) return 'Tu reserva original ya no existe.';
      final actual = Reserva.fromMap(docOriginal.id, docOriginal.data()!);
      if (actual.usuarioId != uid || actual.estado != Reserva.estadoPendientePago) {
        return 'Tu reserva original ya no está activa.';
      }

      if (!docCancha.exists) return 'Esta cancha ya no existe.';
      final canchaActual = Cancha.fromMap(docCancha.id, docCancha.data()!);
      final problema = _problemaConTurno(canchaActual, nuevaFecha, nuevaHora);
      if (problema != null) return problema;

      if (docNueva.exists) {
        final existente = Reserva.fromMap(docNueva.id, docNueva.data()!);
        if (existente.ocupaHorario) {
          return existente.usuarioId == uid
              ? 'Ya tienes ese horario apartado o reservado.'
              : 'Ese horario acaba de ser tomado por otra persona. Elige otro.';
        }
      }

      final nueva = Reserva(
        id: refNueva.id,
        canchaId: canchaActual.id,
        canchaNombre: canchaActual.nombre,
        usuarioId: uid,
        fecha: nuevaFecha,
        hora: nuevaHora,
        estado: Reserva.estadoPendientePago,
        medioPago: actual.medioPago,
        precio: canchaActual.precioPorHora,
        horasLimiteCancelacion: canchaActual.horasLimiteCancelacion,
      );
      transaccion.set(refNueva, {
        ...nueva.toMap(),
        'reprogramadaDesde': original.id,
        'creadaEn': FieldValue.serverTimestamp(),
        'actualizadaEn': FieldValue.serverTimestamp(),
      });
      transaccion.update(refOriginal, {
        'estado': Reserva.estadoCancelada,
        'reprogramadaA': refNueva.id,
        'canceladaEn': FieldValue.serverTimestamp(),
        'actualizadaEn': FieldValue.serverTimestamp(),
      });
      return null;
    });

    if (error != null) throw ReservaException(error);
  }
}
