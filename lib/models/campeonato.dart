import '../utils/formato.dart';

// Modelo de datos "Campeonato" (HU-13 a HU-17).
//
// Lo crea un organizador (rol definido en HU-04) con su formato, el
// numero maximo de equipos, las fechas y la cancha donde se juega
// (HU-13). Los capitanes inscriben a sus equipos mientras haya cupos
// (HU-14). Cuando el organizador cierra las inscripciones, el sistema
// genera el fixture (ver utils/fixture.dart) y los partidos se guardan en
// la subcoleccion "partidos" del campeonato.
//
// Estados:
//  - "inscripciones": abierto para que los capitanes inscriban equipos.
//  - "en_curso": ya tiene fixture; se van registrando resultados (HU-15).
//  - "finalizado": se jugo todo y ya hay campeon.
class Campeonato {
  static const estadoInscripciones = 'inscripciones';
  static const estadoEnCurso = 'en_curso';
  static const estadoFinalizado = 'finalizado';

  // Formatos que puede elegir el organizador.
  static const formatoLiga = 'liga'; // todos contra todos
  static const formatoEliminatoria = 'eliminatoria'; // pierde y queda fuera
  static const formatoGrupos = 'grupos'; // grupos y luego eliminatoria
  static const formatos = [formatoLiga, formatoEliminatoria, formatoGrupos];

  // Equipos permitidos por campeonato.
  static const minEquipos = 2;
  static const maxEquiposPermitidos = 16;

  final String id;
  final String nombre;
  final String deporte;
  final String formato;
  final int maxEquipos;
  final String fechaInicio; // formato "2026-11-05" (ver fechaClave)
  final String fechaFin;
  final String canchaId;
  final String canchaNombre;
  final int horaPartidos; // hora del primer partido de cada fecha
  // horaCierre: hora en que cierra la cancha. El ultimo partido del dia
  // empieza una hora antes; los que no entran pasan al dia siguiente.
  final int horaCierre;
  // diasAbiertos: dias de la semana en que atiende la cancha (1 = lunes ...
  // 7 = domingo). El fixture solo pone partidos en esos dias.
  final List<int> diasAbiertos;
  final String organizadorId;
  final String organizadorNombre;
  final String estado;

  // Equipos inscritos: lista de ids (el id del equipo es el uid de su
  // capitan) y sus nombres, para no tener que leer cada equipo aparte.
  final List<String> equiposIds;
  final Map<String, String> equiposNombres;

  // Fase que se esta jugando: "liga", "grupos" o "eliminatoria".
  final String fase;

  // Dias entre una ronda y la siguiente; se calcula al generar el fixture
  // para que todas las rondas entren entre fechaInicio y fechaFin.
  final int diasEntreRondas;

  final String? campeonId;

  Campeonato({
    required this.id,
    required this.nombre,
    required this.deporte,
    required this.formato,
    required this.maxEquipos,
    required this.fechaInicio,
    required this.fechaFin,
    required this.canchaId,
    required this.canchaNombre,
    required this.horaPartidos,
    this.horaCierre = 23,
    this.diasAbiertos = const [1, 2, 3, 4, 5, 6, 7],
    required this.organizadorId,
    required this.organizadorNombre,
    this.estado = estadoInscripciones,
    this.equiposIds = const [],
    this.equiposNombres = const {},
    this.fase = '',
    this.diasEntreRondas = 7,
    this.campeonId,
  });

  int get cuposLibres => maxEquipos - equiposIds.length;
  bool get abierto => estado == estadoInscripciones;

  // Minimo de equipos para generar el fixture: en grupos se necesitan al
  // menos 6 (dos grupos de tres), para que la fase de grupos elimine a
  // alguien.
  static const minEquiposGrupos = 6;
  int get minimoParaEmpezar => formato == formatoGrupos ? minEquiposGrupos : minEquipos;

  // partidosPorDia: cuantos partidos entran en un dia en la cancha.
  int get partidosPorDia => (horaCierre - horaPartidos).clamp(1, 24).toInt();

  String nombreEquipo(String id) => equiposNombres[id] ?? 'Equipo';

  String? get campeonNombre => campeonId == null ? null : nombreEquipo(campeonId!);

  static String nombreFormato(String formato) {
    switch (formato) {
      case formatoEliminatoria:
        return 'Eliminatoria';
      case formatoGrupos:
        return 'Fase de grupos';
      default:
        return 'Liga (todos contra todos)';
    }
  }

  String get estadoTexto {
    switch (estado) {
      case estadoEnCurso:
        return 'En curso';
      case estadoFinalizado:
        return 'Finalizado';
      default:
        return 'Inscripciones abiertas';
    }
  }

  // fechasTexto -> "Lunes 3 nov al Domingo 30 nov"
  String get fechasTexto => '${fechaTexto(fechaDesdeClave(fechaInicio))} al ${fechaTexto(fechaDesdeClave(fechaFin))}';

  factory Campeonato.fromMap(String id, Map<String, dynamic> data) {
    final ids = data['equiposIds'];
    final nombres = data['equiposNombres'];
    final max = data['maxEquipos'];
    final hora = data['horaPartidos'];
    final cierre = data['horaCierre'];
    final dias = data['diasEntreRondas'];
    final abiertos = data['diasAbiertos'];
    return Campeonato(
      id: id,
      nombre: (data['nombre'] ?? '').toString(),
      deporte: (data['deporte'] ?? '').toString(),
      formato: formatos.contains(data['formato']) ? data['formato'] as String : formatoLiga,
      maxEquipos: max is num ? max.toInt() : 8,
      fechaInicio: (data['fechaInicio'] ?? '').toString(),
      fechaFin: (data['fechaFin'] ?? '').toString(),
      canchaId: (data['canchaId'] ?? '').toString(),
      canchaNombre: (data['canchaNombre'] ?? '').toString(),
      horaPartidos: hora is num ? hora.toInt() : 18,
      horaCierre: cierre is num ? cierre.toInt() : 23,
      diasAbiertos: abiertos is List
          ? abiertos.whereType<num>().map((d) => d.toInt()).where((d) => d >= 1 && d <= 7).toList()
          : const [1, 2, 3, 4, 5, 6, 7],
      organizadorId: (data['organizadorId'] ?? '').toString(),
      organizadorNombre: (data['organizadorNombre'] ?? '').toString(),
      estado: (data['estado'] ?? estadoInscripciones).toString(),
      equiposIds: ids is List ? ids.map((e) => e.toString()).toList() : [],
      equiposNombres: nombres is Map ? nombres.map((k, v) => MapEntry(k.toString(), v.toString())) : {},
      fase: (data['fase'] ?? '').toString(),
      diasEntreRondas: dias is num ? dias.toInt() : 7,
      campeonId: data['campeonId']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'deporte': deporte,
      'formato': formato,
      'maxEquipos': maxEquipos,
      'fechaInicio': fechaInicio,
      'fechaFin': fechaFin,
      'canchaId': canchaId,
      'canchaNombre': canchaNombre,
      'horaPartidos': horaPartidos,
      'horaCierre': horaCierre,
      'diasAbiertos': diasAbiertos,
      'organizadorId': organizadorId,
      'organizadorNombre': organizadorNombre,
      'estado': estado,
      'equiposIds': equiposIds,
      'equiposNombres': equiposNombres,
      'fase': fase,
      'diasEntreRondas': diasEntreRondas,
      'campeonId': campeonId,
    };
  }
}
