import '../utils/formato.dart';

// Modelo de datos "Partido" (HU-15 y HU-17).
//
// Cada partido del fixture es un documento de la subcoleccion
// campeonatos/{id}/partidos. Lo crea el sistema al generar el fixture y
// el organizador le registra el resultado (HU-15).
class Partido {
  static const faseLiga = 'liga';
  static const faseGrupos = 'grupos';
  static const faseEliminatoria = 'eliminatoria';

  final String id;
  final String fase;
  final int ronda; // numero de ronda dentro de todo el campeonato
  final String etiqueta; // ej: "Fecha 2", "Semifinal", "Grupo A · Fecha 1"
  final String grupo; // "A", "B"... solo en fase de grupos
  final int orden; // posicion del partido dentro de su ronda
  final String localId;
  final String localNombre;
  final String visitaId; // vacio si el local pasa directo (eliminatoria)
  final String visitaNombre;
  final String fecha; // formato "2026-11-05"
  final int hora;
  final bool jugado;
  final int? golesLocal;
  final int? golesVisita;

  // ganadorId: en eliminatoria, quien pasa de ronda (si empatan, el que
  // gano en penales). En liga y grupos queda vacio si empatan.
  final String ganadorId;

  Partido({
    required this.id,
    required this.fase,
    required this.ronda,
    required this.etiqueta,
    this.grupo = '',
    required this.orden,
    required this.localId,
    required this.localNombre,
    required this.visitaId,
    required this.visitaNombre,
    required this.fecha,
    required this.hora,
    this.jugado = false,
    this.golesLocal,
    this.golesVisita,
    this.ganadorId = '',
  });

  // pasaDirecto: en eliminatoria, cuando los equipos no son potencia de 2
  // algunos pasan a la siguiente ronda sin jugar.
  bool get pasaDirecto => visitaId.isEmpty;

  DateTime get inicio {
    final dia = fechaDesdeClave(fecha);
    return DateTime(dia.year, dia.month, dia.day, hora);
  }

  String get marcador => jugado && !pasaDirecto ? '$golesLocal - $golesVisita' : 'vs';

  factory Partido.fromMap(String id, Map<String, dynamic> data) {
    int? entero(dynamic v) => v is num ? v.toInt() : null;
    return Partido(
      id: id,
      fase: (data['fase'] ?? faseLiga).toString(),
      ronda: entero(data['ronda']) ?? 1,
      etiqueta: (data['etiqueta'] ?? '').toString(),
      grupo: (data['grupo'] ?? '').toString(),
      orden: entero(data['orden']) ?? 0,
      localId: (data['localId'] ?? '').toString(),
      localNombre: (data['localNombre'] ?? '').toString(),
      visitaId: (data['visitaId'] ?? '').toString(),
      visitaNombre: (data['visitaNombre'] ?? '').toString(),
      fecha: (data['fecha'] ?? '').toString(),
      hora: entero(data['hora']) ?? 18,
      jugado: data['jugado'] == true,
      golesLocal: entero(data['golesLocal']),
      golesVisita: entero(data['golesVisita']),
      ganadorId: (data['ganadorId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fase': fase,
      'ronda': ronda,
      'etiqueta': etiqueta,
      'grupo': grupo,
      'orden': orden,
      'localId': localId,
      'localNombre': localNombre,
      'visitaId': visitaId,
      'visitaNombre': visitaNombre,
      'fecha': fecha,
      'hora': hora,
      'jugado': jugado,
      'golesLocal': golesLocal,
      'golesVisita': golesVisita,
      'ganadorId': ganadorId,
    };
  }
}
