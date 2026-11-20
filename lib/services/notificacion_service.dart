import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/campeonato.dart';
import '../models/pago.dart';
import '../models/partido.dart';
import '../models/reserva.dart';
import '../models/usuario.dart';
import '../utils/formato.dart';

// NotificacionService: implementa HU-22 (Notificaciones push).
//
// Muestra notificaciones reales del sistema (las que aparecen arriba en
// el celular) para:
//  - confirmacion de reserva (al enviar el pago) y de pago (cuando el
//    complejo lo aprueba o rechaza),
//  - recordatorio 1 hora antes de cada reserva y de cada partido del
//    equipo del capitan (quedan programadas aunque se cierre la app),
//  - resultados del campeonato para los equipos inscritos,
//  - al organizador, cuando llega un pago nuevo por revisar.
//
// El usuario puede desactivar cada categoria (reservas, pagos o
// campeonatos) desde su perfil. La eleccion se guarda en el celular con
// SharedPreferences, por cada usuario, igual que el bloqueo de HU-02.
//
// Como el proyecto usa el plan gratuito de Firebase (sin servidor ni
// Cloud Functions), las notificaciones las genera la propia app al
// escuchar los cambios de Firestore en tiempo real.
class NotificacionService {
  static final NotificacionService _instancia = NotificacionService._interno();

  factory NotificacionService() => _instancia;

  NotificacionService._interno();

  // Categorias de notificacion que se pueden desactivar desde el perfil.
  static const categoriaReservas = 'reservas';
  static const categoriaPagos = 'pagos';
  static const categoriaCampeonatos = 'campeonatos';

  // Nombre que se muestra en el perfil para cada categoria.
  static const categorias = {
    categoriaReservas: 'Reservas y recordatorios',
    categoriaPagos: 'Pagos',
    categoriaCampeonatos: 'Campeonatos y partidos',
  };

  // Categorias activas del usuario que inicio sesion. Si una no aparece,
  // se toma como activa.
  final Map<String, bool> _activas = {};
  Usuario? _usuarioActivo;

  final _plugin = FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Escuchas activas de Firestore; se cancelan al cerrar sesion.
  final List<StreamSubscription<dynamic>> _escuchas = [];
  final Map<String, StreamSubscription<dynamic>> _escuchasPartidos = {};

  // Ids de los recordatorios programados, para cancelar los que ya no
  // corresponden (reserva cancelada, partido ya jugado).
  final Set<int> _recordatoriosReservas = {};
  final Set<int> _recordatoriosPartidos = {};

  // Usuario y rol con los que se activaron las escuchas. Si cambia el rol
  // en el perfil (HU-04), se vuelven a activar con los avisos del rol nuevo.
  String? _claveActiva;

  static const _detalles = NotificationDetails(
    android: AndroidNotificationDetails(
      'canchamatch',
      'CanchaMatch',
      channelDescription: 'Reservas, pagos, recordatorios y campeonatos',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  // Se llama una vez en main(), antes de abrir la app.
  Future<void> inicializar() async {
    tz.initializeTimeZones();
    // La app es para canchas de Cajamarca: se usa la hora de Peru.
    tz.setLocalLocation(tz.getLocation('America/Lima'));
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
  }

  static String _clavePreferencia(String uid, String categoria) => 'notificaciones_${uid}_$categoria';

  // preferencias: lee del celular que categorias tiene activas el usuario.
  // Por defecto todas estan activas.
  Future<Map<String, bool>> preferencias(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final categoria in categorias.keys) categoria: prefs.getBool(_clavePreferencia(uid, categoria)) ?? true,
    };
  }

  // cambiarPreferencia: guarda la eleccion del perfil. Si el usuario ya
  // tiene las escuchas activas, se vuelven a activar para que deje de
  // recibir (o vuelva a recibir) esa categoria, incluidos los recordatorios.
  Future<void> cambiarPreferencia(String uid, String categoria, bool activa) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_clavePreferencia(uid, categoria), activa);
    final usuario = _usuarioActivo;
    if (usuario != null && usuario.uid == uid) {
      _claveActiva = null;
      await activar(usuario);
    }
  }

  bool _permitida(String categoria) => _activas[categoria] ?? true;

  // Id numerico estable a partir de un texto (el plugin pide un int).
  static int _id(String clave) => clave.hashCode & 0x7fffffff;

  Future<void> mostrar(String titulo, String texto, {String categoria = categoriaReservas}) async {
    if (!_permitida(categoria)) return;
    try {
      await _plugin.show(_id('$titulo$texto${DateTime.now()}'), titulo, texto, _detalles);
    } catch (_) {
      // Si el usuario no dio permiso, simplemente no se muestra.
    }
  }

  // _programar: notificacion para una fecha futura (recordatorios).
  Future<void> _programar(int id, DateTime cuando, String titulo, String texto, String categoria) async {
    if (!_permitida(categoria) || !cuando.isAfter(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id,
        titulo,
        texto,
        tz.TZDateTime.from(cuando, tz.local),
        _detalles,
        // "Inexacta" no necesita el permiso especial de alarmas exactas;
        // puede llegar un par de minutos despues, suficiente para avisar.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // Sin permiso de notificaciones no se programa nada.
    }
  }

  // activar: se llama al entrar a la app con el perfil ya cargado. Pide
  // permiso (Android 13 o mas) y empieza a escuchar los cambios del
  // usuario. Si ya estaba activo para el mismo usuario y rol, no hace nada.
  Future<void> activar(Usuario usuario) async {
    final clave = '${usuario.uid}|${usuario.tipoCuenta}|${usuario.rol}';
    if (_claveActiva == clave) return;
    await desactivar();
    _claveActiva = clave;
    _usuarioActivo = usuario;
    _activas
      ..clear()
      ..addAll(await preferencias(usuario.uid));

    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {
      // Si falla el pedido de permiso, la app sigue funcionando igual.
    }

    _escucharMisPagos(usuario.uid);
    _escucharMisReservas(usuario.uid);
    if (usuario.esOrganizador) _escucharPagosPorRevisar(usuario);
    if (usuario.esCapitan) _escucharMisCampeonatos(usuario.uid);
  }

  // desactivar: al cerrar sesion se dejan de escuchar los cambios y se
  // borran los recordatorios, para que otro usuario del mismo celular no
  // reciba avisos ajenos.
  Future<void> desactivar() async {
    for (final escucha in [..._escuchas, ..._escuchasPartidos.values]) {
      await escucha.cancel();
    }
    _escuchas.clear();
    _escuchasPartidos.clear();
    _recordatoriosReservas.clear();
    _recordatoriosPartidos.clear();
    _claveActiva = null;
    _usuarioActivo = null;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // Nada que cancelar.
    }
  }

  // Confirmacion de pago: cuando el complejo aprueba o rechaza un pago.
  // Se guarda el estado anterior de cada pago y solo se avisa cuando pasa
  // de "en revision" a aprobado o rechazado (no al reprogramar, ni por lo
  // que ya estaba al abrir la app).
  void _escucharMisPagos(String uid) {
    final estados = <String, String>{};
    _escuchas.add(_db.collection('pagos').where('usuarioId', isEqualTo: uid).snapshots().listen((snapshot) {
      for (final cambio in snapshot.docChanges) {
        final pago = Pago.fromMap(cambio.doc.id, cambio.doc.data()!);
        final anterior = estados[pago.id];
        estados[pago.id] = pago.estado;
        if (anterior != Pago.estadoEnRevision || pago.estado == Pago.estadoEnRevision) continue;
        final cuando = '${fechaTexto(fechaDesdeClave(pago.fecha))} ${horaTexto(pago.hora)}';
        if (pago.estado == Pago.estadoAprobado) {
          mostrar(
            '¡Pago aprobado!',
            'Tu reserva en ${pago.canchaNombre} el $cuando quedó confirmada.',
            categoria: categoriaPagos,
          );
        } else if (pago.estado == Pago.estadoRechazado) {
          mostrar(
            'Pago rechazado',
            'Tu pago para ${pago.canchaNombre} el $cuando fue rechazado: ${pago.motivoRechazo ?? ''}',
            categoria: categoriaPagos,
          );
        }
      }
    }, onError: (_) {}));
  }

  // Recordatorio 1 hora antes de cada reserva CONFIRMADA. Las que tienen
  // el pago en revision no se programan, porque el complejo todavia puede
  // rechazarlas; al aprobarse, esta escucha las recibe y las programa.
  void _escucharMisReservas(String uid) {
    _escuchas.add(_db
        .collection('reservas')
        .where('usuarioId', isEqualTo: uid)
        .where('estado', isEqualTo: Reserva.estadoConfirmada)
        .snapshots()
        .listen((snapshot) {
      final vigentes = <int>{};
      for (final doc in snapshot.docs) {
        final reserva = Reserva.fromMap(doc.id, doc.data());
        final id = _id('reserva_${reserva.id}');
        vigentes.add(id);
        _programar(
          id,
          reserva.inicio.subtract(const Duration(hours: 1)),
          'Tu reserva es en 1 hora',
          '${reserva.canchaNombre} · ${rangoHora(reserva.hora)}',
          categoriaReservas,
        );
      }
      for (final id in _recordatoriosReservas.difference(vigentes)) {
        _plugin.cancel(id);
      }
      _recordatoriosReservas
        ..clear()
        ..addAll(vigentes);
    }, onError: (_) {}));
  }

  // Al organizador: cada pago nuevo de sus canchas que llega en revision.
  void _escucharPagosPorRevisar(Usuario usuario) {
    final Query<Map<String, dynamic>> consulta = usuario.esAdmin
        ? _db.collection('pagos')
        : _db.collection('pagos').where('propietarioId', isEqualTo: usuario.uid);
    var primeraVez = true;
    _escuchas.add(consulta.snapshots().listen((snapshot) {
      if (!primeraVez) {
        for (final cambio in snapshot.docChanges) {
          if (cambio.type != DocumentChangeType.added) continue;
          final pago = Pago.fromMap(cambio.doc.id, cambio.doc.data()!);
          if (pago.estado != Pago.estadoEnRevision) continue;
          mostrar(
            'Nuevo pago por revisar',
            '${pago.usuarioNombre} · ${pago.canchaNombre} · S/ ${pago.monto.toStringAsFixed(2)} (${pago.medio})',
            categoria: categoriaPagos,
          );
        }
      }
      primeraVez = false;
    }, onError: (_) {}));
  }

  // Al capitan: resultados de los campeonatos donde esta inscrito y
  // recordatorio 1 hora antes de cada partido de su equipo.
  void _escucharMisCampeonatos(String uid) {
    final ultimos = <String, String>{};
    _escuchas.add(_db
        .collection('campeonatos')
        .where('equiposIds', arrayContains: uid)
        .snapshots()
        .listen((snapshot) {
      for (final doc in snapshot.docs) {
        final c = Campeonato.fromMap(doc.id, doc.data());
        final resultado = (doc.data()['ultimoResultado'] ?? '').toString();
        final anterior = ultimos[c.id];
        if (anterior != null && resultado.isNotEmpty && resultado != anterior) {
          mostrar(
            c.nombre,
            c.campeonNombre == null ? resultado : '$resultado · ¡Campeón: ${c.campeonNombre}!',
            categoria: categoriaCampeonatos,
          );
        }
        ultimos[c.id] = resultado;

        if (c.estado == Campeonato.estadoEnCurso && !_escuchasPartidos.containsKey(c.id)) {
          _escuchasPartidos[c.id] = _db
              .collection('campeonatos')
              .doc(c.id)
              .collection('partidos')
              .snapshots()
              .listen((partidos) => _programarPartidos(c, uid, partidos), onError: (_) {});
        }
      }
    }, onError: (_) {}));
  }

  void _programarPartidos(Campeonato c, String uid, QuerySnapshot<Map<String, dynamic>> snapshot) {
    for (final doc in snapshot.docs) {
      final partido = Partido.fromMap(doc.id, doc.data());
      if (partido.localId != uid && partido.visitaId != uid) continue;
      final id = _id('partido_${c.id}_${partido.id}');
      if (partido.jugado) {
        if (_recordatoriosPartidos.remove(id)) _plugin.cancel(id);
        continue;
      }
      _recordatoriosPartidos.add(id);
      _programar(
        id,
        partido.inicio.subtract(const Duration(hours: 1)),
        'Tu partido es en 1 hora',
        '${partido.localNombre} vs ${partido.visitaNombre} · ${c.canchaNombre} · ${horaTexto(partido.hora)}',
        categoriaCampeonatos,
      );
    }
  }
}
