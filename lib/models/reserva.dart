import 'package:cloud_firestore/cloud_firestore.dart';

// Modelo de datos "Reserva".
//
// Cada documento de la coleccion "reservas" representa UN turno de una
// hora de una cancha en una fecha. El id del documento se arma con esos
// tres datos (ver idPara), asi dos reservas del mismo turno caerian
// siempre en el mismo documento: eso es lo que impide la doble reserva.
//
// Estados posibles:
//  - "bloqueada": el jugador eligio el turno y tiene 10 minutos para
//    confirmarlo (HU-08). Si no confirma, el bloqueo vence solo.
//  - "pendiente_pago": el jugador ya envio su pago (HU-10) y el complejo
//    todavia no lo revisa. El turno ya queda apartado para el.
//  - "confirmada": el complejo valido el pago (HU-12).
//  - "cancelada": el jugador la cancelo o la movio a otro horario (HU-09),
//    o el complejo rechazo su pago (HU-12).
//
// Ojo: un bloqueo vencido sigue guardado con estado "bloqueada". Para
// saber si un turno esta ocupado hay que usar siempre [ocupaHorario].
class Reserva {
  static const estadoBloqueada = 'bloqueada';
  static const estadoPendientePago = 'pendiente_pago';
  static const estadoConfirmada = 'confirmada';
  static const estadoCancelada = 'cancelada';

  // Minutos que dura el bloqueo mientras el jugador confirma (HU-08).
  static const minutosBloqueo = 10;

  final String id;
  final String canchaId;
  final String canchaNombre;
  final String usuarioId;
  final String fecha; // formato "2026-10-05" (ver fechaClave)
  final int hora; // hora en que empieza el turno (ej: 18 -> 18:00 - 19:00)
  final String estado;

  // bloqueadoEn: momento en que se aparto el turno, con la hora del
  // servidor de Firebase. El bloqueo vence [minutosBloqueo] despues.
  final DateTime? bloqueadoEn;

  final String? medioPago;
  final double precio;

  // Horas antes del partido hasta las que se puede cancelar o reprogramar
  // (HU-09). Se copia de la cancha al reservar, asi si el administrador
  // cambia la politica despues, no afecta a las reservas ya hechas.
  final int horasLimiteCancelacion;

  // propietarioId: dueño de la cancha (HU-04). Se copia al reservar para
  // que el organizador pueda revisar los pagos de sus canchas (HU-12).
  final String propietarioId;

  // pagoId: documento de la coleccion "pagos" con el pago de esta reserva
  // (HU-10). Vacio mientras el turno solo esta bloqueado.
  final String pagoId;

  Reserva({
    required this.id,
    required this.canchaId,
    required this.canchaNombre,
    required this.usuarioId,
    required this.fecha,
    required this.hora,
    required this.estado,
    this.bloqueadoEn,
    this.medioPago,
    this.precio = 0,
    this.horasLimiteCancelacion = 2,
    this.propietarioId = '',
    this.pagoId = '',
  });

  // activa: la reserva sigue en pie (pago en revision o ya confirmado).
  bool get activa => estado == estadoPendientePago || estado == estadoConfirmada;

  // Texto corto del estado para mostrar en pantalla.
  String get estadoTexto {
    switch (estado) {
      case estadoPendientePago:
        return 'Pago en revisión';
      case estadoConfirmada:
        return 'Confirmada';
      case estadoBloqueada:
        return 'Apartada';
      default:
        return 'Cancelada';
    }
  }

  // idPara: id del documento de un turno. Ej: "abc123_2026-10-05_18".
  static String idPara(String canchaId, String fecha, int hora) => '${canchaId}_${fecha}_$hora';

  // Momento en que vence el bloqueo (solo tiene sentido si esta bloqueada).
  DateTime? get bloqueadaHasta => bloqueadoEn?.add(const Duration(minutes: minutosBloqueo));

  // ocupaHorario: true si este documento hace que el turno NO este libre.
  // Un bloqueo vencido o una reserva cancelada ya no ocupan el turno, asi
  // el horario se libera solo, sin que nadie tenga que borrarlo.
  bool get ocupaHorario {
    if (activa) return true;
    if (estado == estadoBloqueada) {
      final hasta = bloqueadaHasta;
      return hasta != null && hasta.isAfter(DateTime.now());
    }
    return false;
  }

  // inicio: momento exacto en que empieza el partido. Las canchas estan en
  // Cajamarca, asi que la hora del turno es hora de Peru (UTC-5, sin
  // horario de verano): se arma en UTC sumando 5 horas y se muestra en la
  // hora del celular. Las reglas de Firestore hacen el mismo calculo para
  // comprobar que nadie guarde un inicio falso.
  // Si la fecha guardada estuviera mal escrita, devuelve 1970 para que la
  // reserva se trate como pasada en vez de hacer fallar la pantalla.
  DateTime get inicio {
    final partes = fecha.split('-');
    if (partes.length == 3) {
      final anio = int.tryParse(partes[0]);
      final mes = int.tryParse(partes[1]);
      final dia = int.tryParse(partes[2]);
      if (anio != null && mes != null && dia != null) {
        return DateTime.utc(anio, mes, dia, hora + 5).toLocal();
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  factory Reserva.fromMap(String id, Map<String, dynamic> data) {
    final estado = (data['estado'] ?? estadoCancelada).toString();
    final precio = data['precio'];
    final limite = data['horasLimiteCancelacion'];
    return Reserva(
      id: id,
      canchaId: (data['canchaId'] ?? '').toString(),
      canchaNombre: (data['canchaNombre'] ?? '').toString(),
      usuarioId: (data['usuarioId'] ?? '').toString(),
      fecha: (data['fecha'] ?? '').toString(),
      hora: data['hora'] is num ? (data['hora'] as num).toInt() : 0,
      estado: estado,
      bloqueadoEn: _leerBloqueadoEn(data, estado),
      medioPago: data['medioPago']?.toString(),
      precio: precio is num ? precio.toDouble() : 0,
      horasLimiteCancelacion: limite is num ? limite.toInt() : 2,
      propietarioId: (data['propietarioId'] ?? '').toString(),
      pagoId: (data['pagoId'] ?? '').toString(),
    );
  }

  static DateTime? _leerBloqueadoEn(Map<String, dynamic> data, String estado) {
    final valor = data['bloqueadoEn'];
    if (valor is Timestamp) return valor.toDate();
    // Reservas de prueba creadas con la version anterior guardaban la hora
    // de vencimiento en vez de la de inicio del bloqueo.
    final anterior = data['bloqueadaHasta'];
    if (anterior is Timestamp) {
      return anterior.toDate().subtract(const Duration(minutes: minutosBloqueo));
    }
    // Mientras el servidor todavia no confirma la escritura, la hora del
    // servidor llega vacia: se toma el momento actual.
    if (estado == estadoBloqueada) return DateTime.now();
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'canchaId': canchaId,
      'canchaNombre': canchaNombre,
      'usuarioId': usuarioId,
      'fecha': fecha,
      'hora': hora,
      // inicio se guarda tambien como fecha real para que las reglas de
      // Firestore puedan validar la politica de cancelacion.
      'inicio': Timestamp.fromDate(inicio),
      'estado': estado,
      'bloqueadoEn': bloqueadoEn == null ? null : Timestamp.fromDate(bloqueadoEn!),
      'medioPago': medioPago,
      'precio': precio,
      'horasLimiteCancelacion': horasLimiteCancelacion,
      'propietarioId': propietarioId,
      'pagoId': pagoId,
    };
  }
}
