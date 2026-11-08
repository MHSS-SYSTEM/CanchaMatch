import '../models/campeonato.dart';
import '../models/partido.dart';
import 'formato.dart';

// Logica para armar el fixture de un campeonato (HU-13). Son funciones
// "puras": no leen ni escriben
// en Firestore, solo reciben datos y devuelven el resultado. Asi se pueden
// probar y explicar por separado; CampeonatoService es quien guarda lo
// que se genera aqui.

// ---------------------------------------------------------------------
// HU-13: Generar el fixture
// ---------------------------------------------------------------------

// todosContraTodos: "metodo del circulo". Se fija el primer equipo y los
// demas rotan una posicion en cada ronda; asi cada equipo juega una vez
// contra todos los demas. Si son impares, se agrega un "descanso" ('')
// y al equipo que le toca contra el descanso no juega esa fecha.
List<List<(String, String)>> todosContraTodos(List<String> ids) {
  final lista = [...ids];
  if (lista.length.isOdd) lista.add('');
  final n = lista.length;
  final rondas = <List<(String, String)>>[];

  for (var r = 0; r < n - 1; r++) {
    final ronda = <(String, String)>[];
    for (var i = 0; i < n ~/ 2; i++) {
      final a = lista[i];
      final b = lista[n - 1 - i];
      if (a.isEmpty || b.isEmpty) continue;
      // Se alterna quien es local para que no sea siempre el mismo.
      ronda.add(r.isEven ? (a, b) : (b, a));
    }
    rondas.add(ronda);
    lista.insert(1, lista.removeLast());
  }
  return rondas;
}

// primeraRondaEliminatoria: si los equipos no son 2, 4, 8 o 16, algunos
// pasan directo a la siguiente ronda (los primeros de la lista). Ej: con
// 6 equipos la llave es de 8, asi que 2 pasan directo y 4 juegan.
// Un par con visita '' significa "pasa directo".
List<(String, String)> primeraRondaEliminatoria(List<String> ids) {
  var llave = 1;
  while (llave < ids.length) {
    llave *= 2;
  }
  final directos = llave - ids.length;
  return [
    for (var i = 0; i < directos; i++) (ids[i], ''),
    for (var i = directos; i + 1 < ids.length; i += 2) (ids[i], ids[i + 1]),
  ];
}

// nombreRonda: nombre de una ronda de eliminatoria segun cuantos equipos
// la juegan.
String nombreRonda(int equipos) {
  switch (equipos) {
    case 2:
      return 'Final';
    case 4:
      return 'Semifinal';
    case 8:
      return 'Cuartos de final';
    case 16:
      return 'Octavos de final';
    default:
      return 'Ronda de $equipos';
  }
}

// numeroDeGrupos: siempre 2 o 4 grupos de al menos 3 equipos. Asi pasan
// 4 u 8 equipos a la eliminatoria (una llave exacta, sin pases directos),
// la fase de grupos siempre deja a alguien fuera y dos equipos del mismo
// grupo nunca se cruzan en la primera ronda eliminatoria.
int numeroDeGrupos(int equipos) => equipos < 12 ? 2 : 4;

// diasPorRonda: cuantos dias ocupa una ronda si sus partidos no entran
// todos en un solo dia de cancha.
int diasPorRonda(int equipos, int partidosPorDia) => ((equipos ~/ 2) / partidosPorDia).ceil().clamp(1, 30).toInt();

// ---------------------------------------------------------------------
// Dias de juego: el fixture solo usa los dias en que abre la cancha.
// ---------------------------------------------------------------------

// abreElDia: si la lista viene vacia (dato viejo o mal cargado) se toma
// que la cancha abre todos los dias.
bool abreElDia(DateTime dia, List<int> diasAbiertos) => diasAbiertos.isEmpty || diasAbiertos.contains(dia.weekday);

// diasDeJuego: cuantos dias de atencion hay entre inicio y fin, contando
// los dos.
int diasDeJuego(DateTime inicio, DateTime fin, List<int> diasAbiertos) {
  var total = 0;
  for (var dia = inicio; !dia.isAfter(fin); dia = dia.add(const Duration(days: 1))) {
    if (abreElDia(dia, diasAbiertos)) total++;
  }
  return total;
}

// diaDeJuego: el dia de atencion numero [n] (empezando en 0) desde inicio.
DateTime diaDeJuego(DateTime inicio, List<int> diasAbiertos, int n) {
  var dia = inicio;
  var contados = -1;
  while (true) {
    if (abreElDia(dia, diasAbiertos)) contados++;
    if (contados == n) return dia;
    dia = dia.add(const Duration(days: 1));
  }
}

// planificarRondas: reparte las rondas entre los dias de juego disponibles.
// Una ronda puede ocupar varios dias si sus partidos no entran en uno; la
// siguiente empieza recien cuando termina la anterior, asi nunca hay dos
// partidos a la misma hora en la cancha. Devuelve cada cuantos dias de
// juego empieza una ronda y cuantos dias de juego hacen falta en total.
({int diasEntreRondas, int diasNecesarios}) planificarRondas(
  String formato,
  int equipos,
  int partidosPorDia,
  int diasDisponibles,
) {
  final rondas = rondasEstimadas(formato, equipos);
  final duracion = diasPorRonda(equipos, partidosPorDia);
  // Dias que se pueden repartir entre una ronda y la siguiente, dejando
  // libres los que ocupa la ultima ronda.
  var entreRondas = duracion;
  final hueco = rondas > 1 ? (diasDisponibles - duracion) ~/ (rondas - 1) : 0;
  if (rondas > 1 && hueco > duracion) {
    entreRondas = hueco.clamp(1, 30).toInt();
  }
  return (diasEntreRondas: entreRondas, diasNecesarios: (rondas - 1) * entreRondas + duracion);
}

// diasMinimos: los dias de juego que necesita el campeonato en el peor
// caso, probando todas las cantidades de equipos que se pueden inscribir.
// (No siempre es el maximo: en grupos, 11 equipos necesitan mas rondas
// que 12.)
int diasMinimos(String formato, int minimoEquipos, int maxEquipos, int partidosPorDia) {
  var peor = 1;
  for (var n = minimoEquipos; n <= maxEquipos; n++) {
    // Lo minimo es una ronda detras de otra, sin dias libres entre ellas.
    final necesarios = rondasEstimadas(formato, n) * diasPorRonda(n, partidosPorDia);
    if (necesarios > peor) peor = necesarios;
  }
  return peor;
}

// rondasEstimadas: cuantas rondas tendra el campeonato. Sirve para
// repartir las rondas entre la fecha de inicio y la de fin.
int rondasEstimadas(String formato, int equipos) {
  int log2Arriba(int n) {
    var rondas = 0;
    for (var llave = 1; llave < n; llave *= 2) {
      rondas++;
    }
    return rondas;
  }

  switch (formato) {
    case Campeonato.formatoEliminatoria:
      return log2Arriba(equipos);
    case Campeonato.formatoGrupos:
      final grupos = numeroDeGrupos(equipos);
      final mayor = (equipos / grupos).ceil();
      return (mayor.isEven ? mayor - 1 : mayor) + log2Arriba(grupos * 2);
    default:
      return equipos.isEven ? equipos - 1 : equipos;
  }
}

// GeneradorFixture: arma los partidos de un campeonato con sus fechas y
// horas. Cada ronda empieza diasEntreRondas dias de juego (dias en que
// abre la cancha) despues de la anterior, un partido por hora desde
// horaPartidos.
class GeneradorFixture {
  final Campeonato campeonato;

  GeneradorFixture(this.campeonato);

  // Fecha y hora del partido numero [indice] de la ronda [ronda]. Si no
  // entran todos el mismo dia (el ultimo empieza una hora antes de que
  // cierre la cancha), siguen al dia siguiente.
  (String, int) _horario(int ronda, int indice) {
    final c = campeonato;
    final porDia = c.partidosPorDia;
    final dia = diaDeJuego(
      fechaDesdeClave(c.fechaInicio),
      c.diasAbiertos,
      (ronda - 1) * c.diasEntreRondas + indice ~/ porDia,
    );
    return (fechaClave(dia), c.horaPartidos + indice % porDia);
  }

  Partido _partido({
    required String fase,
    required int ronda,
    required String etiqueta,
    required int orden,
    required int indiceHorario,
    required String localId,
    required String visitaId,
    String grupo = '',
  }) {
    final (fecha, hora) = _horario(ronda, indiceHorario);
    final pasaDirecto = visitaId.isEmpty;
    return Partido(
      id: '',
      fase: fase,
      ronda: ronda,
      etiqueta: etiqueta,
      grupo: grupo,
      orden: orden,
      localId: localId,
      localNombre: campeonato.nombreEquipo(localId),
      visitaId: visitaId,
      visitaNombre: pasaDirecto ? '' : campeonato.nombreEquipo(visitaId),
      fecha: fecha,
      hora: hora,
      // Quien pasa directo ya "gano" su llave.
      jugado: pasaDirecto,
      ganadorId: pasaDirecto ? localId : '',
    );
  }

  // generarInicial: primeros partidos del campeonato, con los equipos ya
  // mezclados al azar (lo hace CampeonatoService).
  List<Partido> generarInicial(List<String> equipos) {
    switch (campeonato.formato) {
      case Campeonato.formatoEliminatoria:
        return _rondaEliminatoria(primeraRondaEliminatoria(equipos), 1);
      case Campeonato.formatoGrupos:
        return _faseDeGrupos(equipos);
      default:
        final rondas = todosContraTodos(equipos);
        return [
          for (var r = 0; r < rondas.length; r++)
            for (var i = 0; i < rondas[r].length; i++)
              _partido(
                fase: Partido.faseLiga,
                ronda: r + 1,
                etiqueta: 'Fecha ${r + 1}',
                orden: i,
                indiceHorario: i,
                localId: rondas[r][i].$1,
                visitaId: rondas[r][i].$2,
              ),
        ];
    }
  }

  List<Partido> _rondaEliminatoria(List<(String, String)> pares, int ronda) {
    final etiqueta = nombreRonda(pares.length * 2);
    var indiceHorario = 0;
    return [
      for (var i = 0; i < pares.length; i++)
        _partido(
          fase: Partido.faseEliminatoria,
          ronda: ronda,
          etiqueta: etiqueta,
          orden: i,
          // Los que pasan directo no ocupan horario en la cancha.
          indiceHorario: pares[i].$2.isEmpty ? 0 : indiceHorario++,
          localId: pares[i].$1,
          visitaId: pares[i].$2,
        ),
    ];
  }

  // Reparte los equipos en grupos "en serpiente" (1º al A, 2º al B, ...)
  // y arma un todos contra todos dentro de cada grupo.
  List<Partido> _faseDeGrupos(List<String> equipos) {
    final grupos = _repartirEnGrupos(equipos);
    final partidos = <Partido>[];
    final rondasPorGrupo = [for (final g in grupos) todosContraTodos(g)];
    final totalRondas = rondasPorGrupo.map((r) => r.length).reduce((a, b) => a > b ? a : b);

    for (var r = 0; r < totalRondas; r++) {
      var indice = 0;
      for (var g = 0; g < grupos.length; g++) {
        if (r >= rondasPorGrupo[g].length) continue;
        final letra = String.fromCharCode(65 + g);
        for (final par in rondasPorGrupo[g][r]) {
          partidos.add(_partido(
            fase: Partido.faseGrupos,
            ronda: r + 1,
            etiqueta: 'Grupo $letra · Fecha ${r + 1}',
            grupo: letra,
            orden: indice,
            indiceHorario: indice,
            localId: par.$1,
            visitaId: par.$2,
          ));
          indice++;
        }
      }
    }
    return partidos;
  }

  static List<List<String>> _repartirEnGrupos(List<String> equipos) {
    final cantidad = numeroDeGrupos(equipos.length);
    final grupos = [for (var i = 0; i < cantidad; i++) <String>[]];
    for (var i = 0; i < equipos.length; i++) {
      grupos[i % cantidad].add(equipos[i]);
    }
    return grupos;
  }
}
