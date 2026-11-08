import 'package:flutter/material.dart';
import '../models/campeonato.dart';
import '../models/cancha.dart';
import '../models/usuario.dart';
import '../services/campeonato_service.dart';
import '../services/canchas_admin_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';

// CrearCampeonatoScreen: implementa HU-13 (Crear un campeonato).
//
// El organizador elige el nombre, el formato (liga, eliminatoria o
// grupos), el numero maximo de equipos, las fechas y la cancha (una de
// SUS canchas). El deporte se toma de la cancha elegida. Al guardar, el
// campeonato queda con inscripciones abiertas (HU-14); el fixture lo
// genera el sistema cuando el organizador cierra las inscripciones.
class CrearCampeonatoScreen extends StatefulWidget {
  final Usuario organizador;

  const CrearCampeonatoScreen({super.key, required this.organizador});

  @override
  State<CrearCampeonatoScreen> createState() => _CrearCampeonatoScreenState();
}

class _CrearCampeonatoScreenState extends State<CrearCampeonatoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();

  // El organizador ve solo sus canchas; el administrador, todas.
  late final Future<List<Cancha>> _canchas = CanchasAdminService()
      .observarTodas(propietarioId: widget.organizador.esAdmin ? null : widget.organizador.uid)
      .first
      .then((lista) => lista.where((c) => c.disponible).toList());

  String _formato = Campeonato.formatoLiga;
  int _maxEquipos = 8;
  Cancha? _cancha;
  int? _hora;
  DateTime? _inicio;
  DateTime? _fin;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  int get _minEquipos => _formato == Campeonato.formatoGrupos ? Campeonato.minEquiposGrupos : Campeonato.minEquipos;

  Future<void> _elegirFecha({required bool esInicio}) async {
    // El campeonato empieza como pronto mañana.
    final hoy = soloFecha(DateTime.now()).add(const Duration(days: 1));
    final primera = esInicio ? hoy : (_inicio ?? hoy);
    final elegida = await showDatePicker(
      context: context,
      initialDate: (esInicio ? _inicio : _fin) ?? primera,
      firstDate: primera,
      lastDate: hoy.add(const Duration(days: 365)),
    );
    if (elegida == null) return;
    setState(() {
      if (esInicio) {
        _inicio = elegida;
        if (_fin != null && _fin!.isBefore(elegida)) _fin = null;
      } else {
        _fin = elegida;
      }
    });
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_inicio == null || _fin == null) {
      setState(() => _error = 'Elige la fecha de inicio y de fin.');
      return;
    }
    final cancha = _cancha!;

    // Las fechas tienen que alcanzar para todos los partidos aunque se
    // llenen todos los cupos; si no, el fixture no se podria generar.
    final problema = CampeonatoService.problemaConFechas(
      formato: _formato,
      maxEquipos: _maxEquipos,
      partidosPorDia: (cancha.horaCierre - _hora!).clamp(1, 24).toInt(),
      diasAbiertos: cancha.diasAbiertos,
      inicio: _inicio!,
      fin: _fin!,
    );
    if (problema != null) {
      setState(() => _error = problema);
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await CampeonatoService().crear(Campeonato(
        id: '',
        nombre: _nombreCtrl.text.trim(),
        deporte: cancha.tipoDeporte,
        formato: _formato,
        maxEquipos: _maxEquipos,
        fechaInicio: fechaClave(_inicio!),
        fechaFin: fechaClave(_fin!),
        canchaId: cancha.id,
        canchaNombre: cancha.nombre,
        horaPartidos: _hora!,
        horaCierre: cancha.horaCierre,
        diasAbiertos: cancha.diasAbiertos,
        organizadorId: widget.organizador.uid,
        organizadorNombre: widget.organizador.nombreCompleto.trim(),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campeonato creado. Ya pueden inscribirse los equipos.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = CampeonatoService.mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _botonFecha(String etiqueta, DateTime? fecha, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today, size: 18),
      label: Text(fecha == null ? etiqueta : '$etiqueta: ${fechaTexto(fecha)}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo campeonato')),
      body: FutureBuilder<List<Cancha>>(
        future: _canchas,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se pudieron cargar tus canchas.', style: TextStyle(color: AppColors.error)),
            );
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final canchas = snapshot.data!;
          if (canchas.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Primero registra una cancha activa en "Mis canchas".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textoSecundario),
                ),
              ),
            );
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextFormField(
                  controller: _nombreCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Nombre del campeonato'),
                  validator: (valor) => (valor ?? '').trim().length < 4 ? 'Escribe un nombre' : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _formato,
                  decoration: const InputDecoration(labelText: 'Formato'),
                  items: [
                    for (final f in Campeonato.formatos)
                      DropdownMenuItem(value: f, child: Text(Campeonato.nombreFormato(f))),
                  ],
                  onChanged: (valor) => setState(() {
                    _formato = valor ?? _formato;
                    if (_maxEquipos < _minEquipos) _maxEquipos = _minEquipos;
                  }),
                ),
                if (_formato == Campeonato.formatoGrupos)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Los 2 primeros de cada grupo pasan a la eliminatoria.',
                      style: TextStyle(color: AppColors.textoSecundario),
                    ),
                  ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _maxEquipos,
                  decoration: const InputDecoration(labelText: 'Número máximo de equipos'),
                  items: [
                    for (var n = _minEquipos; n <= Campeonato.maxEquiposPermitidos; n++)
                      DropdownMenuItem(value: n, child: Text('$n equipos')),
                  ],
                  onChanged: (valor) => setState(() => _maxEquipos = valor ?? _maxEquipos),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Cancha>(
                  value: _cancha,
                  decoration: const InputDecoration(labelText: 'Cancha'),
                  items: [
                    for (final c in canchas)
                      DropdownMenuItem(value: c, child: Text('${c.nombre} (${c.tipoDeporte})')),
                  ],
                  validator: (valor) => valor == null ? 'Elige la cancha' : null,
                  onChanged: (valor) => setState(() {
                    _cancha = valor;
                    _hora = null;
                  }),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  // La key cambia con la cancha para que el campo se reinicie
                  // con las horas de la cancha nueva.
                  key: ValueKey(_cancha?.id),
                  value: _hora,
                  decoration: const InputDecoration(labelText: 'Hora del primer partido de cada fecha'),
                  items: [
                    for (final h in _cancha?.horasDelDia ?? <int>[])
                      DropdownMenuItem(value: h, child: Text(horaTexto(h))),
                  ],
                  validator: (valor) => valor == null ? 'Elige la hora' : null,
                  onChanged: (valor) => setState(() => _hora = valor),
                ),
                const SizedBox(height: 16),
                _botonFecha('Inicio', _inicio, () => _elegirFecha(esInicio: true)),
                const SizedBox(height: 8),
                _botonFecha(
                  'Fin',
                  _fin,
                  _inicio == null
                      ? () => setState(() => _error = 'Elige primero la fecha de inicio.')
                      : () => _elegirFecha(esInicio: false),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: const TextStyle(color: AppColors.error)),
                  ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Crear campeonato'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
