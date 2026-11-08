import 'package:flutter/material.dart';
import '../models/campeonato.dart';
import '../models/partido.dart';
import '../models/usuario.dart';
import '../services/campeonato_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';

// DetalleCampeonatoScreen: todo lo que pasa dentro de un campeonato.
//
// Tiene dos pestañas, en vivo (Streams de Firestore):
//  - Equipos (HU-14): equipos inscritos y cupos libres. El capitan
//    inscribe a su equipo; el organizador cierra las inscripciones y el
//    sistema genera el fixture (HU-13).
//  - Fixture (HU-13): todas las rondas con sus fechas y horas.
class DetalleCampeonatoScreen extends StatefulWidget {
  final String campeonatoId;
  final Usuario usuario;

  const DetalleCampeonatoScreen({super.key, required this.campeonatoId, required this.usuario});

  @override
  State<DetalleCampeonatoScreen> createState() => _DetalleCampeonatoScreenState();
}

class _DetalleCampeonatoScreenState extends State<DetalleCampeonatoScreen> {
  final _service = CampeonatoService();
  late final Stream<Campeonato?> _campeonato = _service.observarCampeonato(widget.campeonatoId);
  late final Stream<List<Partido>> _partidos = _service.observarPartidos(widget.campeonatoId);

  bool _procesando = false;

  bool _esOrganizadorDe(Campeonato c) => widget.usuario.esAdmin || c.organizadorId == widget.usuario.uid;

  void _mensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _ejecutar(Future<void> Function() accion, String exito) async {
    setState(() => _procesando = true);
    try {
      await accion();
      if (mounted) _mensaje(exito);
    } catch (e) {
      if (mounted) _mensaje(CampeonatoService.mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _generarFixture(Campeonato c) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.tarjeta,
        title: const Text('Generar fixture'),
        content: Text(
          'Se cerrarán las inscripciones con ${c.equiposIds.length} equipos y el sistema sorteará los partidos. '
          '¿Continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Volver')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Generar')),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    var choques = 0;
    await _ejecutar(() async => choques = await _service.generarFixture(c), 'Fixture generado.');
    if (choques > 0 && mounted) {
      _mensaje(
        'Ojo: $choques ${choques == 1 ? 'partido coincide' : 'partidos coinciden'} con reservas que ya '
        'estaban hechas. Desde ahora esos horarios ya no se pueden reservar.',
      );
    }
  }

  // _cambiarFechas: el organizador elige nuevas fechas de inicio y fin
  // mientras las inscripciones siguen abiertas.
  Future<void> _cambiarFechas(Campeonato c) async {
    final manana = soloFecha(DateTime.now()).add(const Duration(days: 1));
    final actualInicio = fechaDesdeClave(c.fechaInicio);
    final inicio = await showDatePicker(
      context: context,
      helpText: 'Nueva fecha de inicio',
      initialDate: actualInicio.isBefore(manana) ? manana : actualInicio,
      firstDate: manana,
      lastDate: manana.add(const Duration(days: 365)),
    );
    if (inicio == null || !mounted) return;
    final actualFin = fechaDesdeClave(c.fechaFin);
    final fin = await showDatePicker(
      context: context,
      helpText: 'Nueva fecha de fin',
      initialDate: actualFin.isBefore(inicio) ? inicio : actualFin,
      firstDate: inicio,
      lastDate: inicio.add(const Duration(days: 365)),
    );
    if (fin == null || !mounted) return;
    await _ejecutar(() => _service.cambiarFechas(c, inicio, fin), 'Fechas actualizadas.');
  }

  // ---------------------------------------------------------------------
  // Pestaña Equipos (HU-14)
  // ---------------------------------------------------------------------

  Widget _pestanaEquipos(Campeonato c) {
    final esOrganizador = _esOrganizadorDe(c);
    final inscrito = c.equiposIds.contains(widget.usuario.uid);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (c.campeonNombre != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.emoji_events, color: AppColors.verdeLima, size: 36),
              title: Text('Campeón: ${c.campeonNombre}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.estadoTexto, style: const TextStyle(color: AppColors.verdeLima, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('${Campeonato.nombreFormato(c.formato)} · ${c.deporte}'),
                Text('${c.canchaNombre} · desde las ${horaTexto(c.horaPartidos)}'),
                Text(c.fechasTexto),
                Text('Organiza: ${c.organizadorNombre}', style: const TextStyle(color: AppColors.textoSecundario)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Equipos inscritos: ${c.equiposIds.length} de ${c.maxEquipos}'
          '${c.abierto ? ' · ${c.cuposLibres} cupos libres' : ''}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (c.equiposIds.isEmpty)
          const Text('Todavía no hay equipos inscritos.', style: TextStyle(color: AppColors.textoSecundario)),
        for (final id in c.equiposIds)
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield, color: AppColors.verdeLima),
              title: Text(c.nombreEquipo(id)),
              trailing: id == widget.usuario.uid
                  ? const Text('Tu equipo', style: TextStyle(color: AppColors.verdeLima))
                  : null,
            ),
          ),
        const SizedBox(height: 16),
        if (c.abierto && widget.usuario.esCapitan && !inscrito)
          ElevatedButton(
            onPressed: _procesando || c.cuposLibres <= 0
                ? null
                : () => _ejecutar(() => _service.inscribirEquipo(c.id), '¡Tu equipo quedó inscrito!'),
            child: Text(c.cuposLibres <= 0 ? 'Sin cupos' : 'Inscribir mi equipo'),
          ),
        if (c.abierto && esOrganizador) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _procesando || c.equiposIds.length < c.minimoParaEmpezar ? null : () => _generarFixture(c),
            child: Text(
              c.equiposIds.length < c.minimoParaEmpezar
                  ? 'Se necesitan ${c.minimoParaEmpezar} equipos para generar el fixture'
                  : 'Cerrar inscripciones y generar fixture',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _procesando ? null : () => _cambiarFechas(c),
            icon: const Icon(Icons.edit_calendar),
            label: const Text('Cambiar fechas'),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Pestaña Fixture (HU-13)
  // ---------------------------------------------------------------------

  Widget _filaPartido(Partido p) {
    if (p.pasaDirecto) {
      return ListTile(
        dense: true,
        title: Text('${p.localNombre} pasa directo a la siguiente ronda'),
        leading: const Icon(Icons.fast_forward, color: AppColors.textoSecundario),
      );
    }
    final ganoLocal = p.jugado && p.ganadorId == p.localId;
    final ganoVisita = p.jugado && p.ganadorId == p.visitaId;
    return ListTile(
      title: Row(
        children: [
          Expanded(
            child: Text(
              p.localNombre,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: ganoLocal ? FontWeight.bold : FontWeight.normal),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(p.marcador, style: AppTheme.textoCodigo.copyWith(fontSize: 16)),
          ),
          Expanded(
            child: Text(
              p.visitaNombre,
              style: TextStyle(fontWeight: ganoVisita ? FontWeight.bold : FontWeight.normal),
            ),
          ),
        ],
      ),
      subtitle: Text(
        '${fechaTexto(p.inicio)} · ${horaTexto(p.hora)}'
        '${p.grupo.isEmpty ? '' : ' · Grupo ${p.grupo}'}',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textoSecundario, fontSize: 12),
      ),
    );
  }

  Widget _pestanaFixture(List<Partido> partidos) {
    if (partidos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'El fixture se genera cuando el organizador cierra las inscripciones.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textoSecundario),
          ),
        ),
      );
    }

    final rondas = partidos.map((p) => p.ronda).toSet().toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final ronda in rondas) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(
              _tituloRonda(partidos.where((p) => p.ronda == ronda).toList()),
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.verdeLima),
            ),
          ),
          Card(
            child: Column(
              children: [for (final p in partidos.where((p) => p.ronda == ronda)) _filaPartido(p)],
            ),
          ),
        ],
      ],
    );
  }

  String _tituloRonda(List<Partido> deLaRonda) {
    final p = deLaRonda.first;
    if (p.fase == Partido.faseGrupos) return 'Fase de grupos · Fecha ${p.ronda}';
    return p.etiqueta;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Campeonato?>(
      stream: _campeonato,
      builder: (context, snapCampeonato) {
        final c = snapCampeonato.data;
        if (snapCampeonato.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('No se pudo cargar el campeonato.')),
          );
        }
        if (c == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        }

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(c.nombre),
              bottom: const TabBar(
                indicatorColor: AppColors.verdeLima,
                labelColor: AppColors.verdeLima,
                unselectedLabelColor: AppColors.textoSecundario,
                tabs: [Tab(text: 'Equipos'), Tab(text: 'Fixture')],
              ),
            ),
            body: Column(
              children: [
                if (_procesando) const LinearProgressIndicator(color: AppColors.verdeLima),
                Expanded(
                  child: StreamBuilder<List<Partido>>(
                    stream: _partidos,
                    builder: (context, snapPartidos) {
                      if (snapPartidos.hasError) {
                        return const Center(
                          child: Text('No se pudo cargar el fixture.', style: TextStyle(color: AppColors.error)),
                        );
                      }
                      final partidos = snapPartidos.data ?? const <Partido>[];
                      return TabBarView(
                        children: [
                          _pestanaEquipos(c),
                          _pestanaFixture(partidos),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
