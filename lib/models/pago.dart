import 'package:cloud_firestore/cloud_firestore.dart';

// Modelo de datos "Pago" (HU-10, HU-11 y HU-12).
//
// Cada documento de la coleccion "pagos" es el pago de UNA reserva. Lo
// crea el jugador al confirmar su reserva (HU-10) y lo revisa el dueño
// de la cancha o el administrador (HU-12). La lista de pagos del jugador
// es su historial (HU-11).
//
// El cobro es SIMULADO: no hay pasarela real. Con Yape o Plin el jugador
// adjunta la captura de su pago y el numero de operacion; con tarjeta se
// simula el cobro y se genera un numero de operacion.
//
// La foto del comprobante NO se guarda aqui sino en la coleccion
// "comprobantes" (mismo id que el pago), asi las listas de pagos cargan
// rapido y la imagen solo se descarga cuando alguien abre el detalle.
//
// Estados posibles:
//  - "en_revision": enviado, esperando que el complejo lo revise.
//  - "aprobado": el complejo lo valido; la reserva pasa a confirmada.
//  - "rechazado": el complejo lo rechazo; la reserva se cancela y el
//    horario se libera.
//  - "anulado": el jugador cancelo su reserva despues de pagar.
class Pago {
  static const estadoEnRevision = 'en_revision';
  static const estadoAprobado = 'aprobado';
  static const estadoRechazado = 'rechazado';
  static const estadoAnulado = 'anulado';

  static const medioYape = 'Yape';
  static const medioPlin = 'Plin';
  static const medioTarjeta = 'Tarjeta';
  static const medios = [medioYape, medioPlin, medioTarjeta];

  final String id;
  final String reservaId;
  final String usuarioId;
  final String usuarioNombre;
  final String canchaId;
  final String canchaNombre;
  final String propietarioId;
  final String fecha; // fecha del partido, formato "2026-10-05"
  final int hora;
  final double monto;
  final String medio; // Yape, Plin o Tarjeta
  final String numeroOperacion;
  final String? ultimosDigitos; // solo tarjeta: los 4 ultimos numeros
  final bool tieneComprobante; // true si se adjunto una foto
  final String estado;
  final String? motivoRechazo;
  final DateTime? creadoEn;
  final DateTime? revisadoEn;

  Pago({
    required this.id,
    required this.reservaId,
    required this.usuarioId,
    required this.usuarioNombre,
    required this.canchaId,
    required this.canchaNombre,
    required this.propietarioId,
    required this.fecha,
    required this.hora,
    required this.monto,
    required this.medio,
    required this.numeroOperacion,
    this.ultimosDigitos,
    this.tieneComprobante = false,
    this.estado = estadoEnRevision,
    this.motivoRechazo,
    this.creadoEn,
    this.revisadoEn,
  });

  String get estadoTexto {
    switch (estado) {
      case estadoAprobado:
        return 'Aprobado';
      case estadoRechazado:
        return 'Rechazado';
      case estadoAnulado:
        return 'Anulado';
      default:
        return 'En revisión';
    }
  }

  static DateTime? _fecha(dynamic valor) => valor is Timestamp ? valor.toDate() : null;

  factory Pago.fromMap(String id, Map<String, dynamic> data) {
    final monto = data['monto'];
    return Pago(
      id: id,
      reservaId: (data['reservaId'] ?? '').toString(),
      usuarioId: (data['usuarioId'] ?? '').toString(),
      usuarioNombre: (data['usuarioNombre'] ?? '').toString(),
      canchaId: (data['canchaId'] ?? '').toString(),
      canchaNombre: (data['canchaNombre'] ?? '').toString(),
      propietarioId: (data['propietarioId'] ?? '').toString(),
      fecha: (data['fecha'] ?? '').toString(),
      hora: data['hora'] is num ? (data['hora'] as num).toInt() : 0,
      monto: monto is num ? monto.toDouble() : 0,
      medio: (data['medio'] ?? '').toString(),
      numeroOperacion: (data['numeroOperacion'] ?? '').toString(),
      ultimosDigitos: data['ultimosDigitos']?.toString(),
      tieneComprobante: data['tieneComprobante'] == true,
      estado: (data['estado'] ?? estadoEnRevision).toString(),
      motivoRechazo: data['motivoRechazo']?.toString(),
      creadoEn: _fecha(data['creadoEn']),
      revisadoEn: _fecha(data['revisadoEn']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'reservaId': reservaId,
      'usuarioId': usuarioId,
      'usuarioNombre': usuarioNombre,
      'canchaId': canchaId,
      'canchaNombre': canchaNombre,
      'propietarioId': propietarioId,
      'fecha': fecha,
      'hora': hora,
      'monto': monto,
      'medio': medio,
      'numeroOperacion': numeroOperacion,
      'ultimosDigitos': ultimosDigitos,
      'tieneComprobante': tieneComprobante,
      'estado': estado,
      'motivoRechazo': motivoRechazo,
    };
  }
}

// DatosPago: lo que el jugador llena en la pantalla de pago antes de
// enviarlo. Se arma en ConfirmarReservaScreen y lo usa ReservaService.
class DatosPago {
  final String medio;
  final String numeroOperacion;
  final String? ultimosDigitos;
  final String? comprobanteBase64; // foto ya comprimida, o null

  DatosPago({
    required this.medio,
    required this.numeroOperacion,
    this.ultimosDigitos,
    this.comprobanteBase64,
  });
}
