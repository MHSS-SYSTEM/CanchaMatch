import 'package:flutter/material.dart';
import '../models/equipo.dart';
import '../models/usuario.dart';
import '../services/campeonato_service.dart';
import '../theme/app_theme.dart';
import '../utils/constantes.dart';
import '../utils/validaciones.dart';

// MiEquipoScreen: primera parte de HU-14 (Inscribir un equipo).
//
// El capitan arma su equipo: nombre, deporte y la lista de jugadores.
// Con el equipo listo (al menos Equipo.minJugadores jugadores) ya lo
// puede inscribir en un campeonato desde la pantalla del campeonato.
class MiEquipoScreen extends StatefulWidget {
  final Usuario capitan;

  const MiEquipoScreen({super.key, required this.capitan});

  @override
  State<MiEquipoScreen> createState() => _MiEquipoScreenState();
}

class _MiEquipoScreenState extends State<MiEquipoScreen> {
  final _service = CampeonatoService();
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _jugadorCtrl = TextEditingController();

  String _deporte = deportes.first;
  final List<String> _jugadores = [];

  bool _cargando = true;
  bool _guardando = false;
  String? _errorCarga;

  // true si el equipo ya esta en un campeonato que no termino: entonces el
  // nombre y el deporte no se pueden cambiar (el campeonato los usa), solo
  // la lista de jugadores.
  bool _inscrito = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _jugadorCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final equipo = await _service.obtenerMiEquipo();
      final inscrito = equipo != null && await _service.equipoEnCampeonatoActivo();
      if (!mounted) return;
      _inscrito = inscrito;
      if (equipo != null) {
        _nombreCtrl.text = equipo.nombre;
        if (deportes.contains(equipo.deporte)) _deporte = equipo.deporte;
        _jugadores.addAll(equipo.jugadores);
      } else {
        // El capitan tambien juega: se agrega primero a la lista.
        _jugadores.add(widget.capitan.nombreCompleto.trim());
      }
    } catch (_) {
      // Sin conexion no se muestra un formulario vacio: si el capitan lo
      // guardara, borraria su equipo real.
      _errorCarga = 'No se pudo cargar tu equipo. Revisa tu conexión e inténtalo de nuevo.';
    }
    if (mounted) setState(() => _cargando = false);
  }

  void _agregarJugador() {
    final nombre = _jugadorCtrl.text.trim();
    if (nombre.isEmpty) return;
    final error = validarNombre(nombre, 'nombre del jugador');
    if (error != null) {
      _mensaje(error);
      return;
    }
    if (_jugadores.length >= Equipo.maxJugadores) {
      _mensaje('Máximo ${Equipo.maxJugadores} jugadores.');
      return;
    }
    if (_jugadores.any((j) => j.toLowerCase() == nombre.toLowerCase())) {
      _mensaje('Ese jugador ya está en la lista.');
      return;
    }
    setState(() {
      _jugadores.add(nombre);
      _jugadorCtrl.clear();
    });
  }

  void _mensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_jugadores.length < Equipo.minJugadores) {
      _mensaje('Agrega al menos ${Equipo.minJugadores} jugadores.');
      return;
    }
    setState(() => _guardando = true);
    try {
      await _service.guardarEquipo(Equipo(
        id: widget.capitan.uid,
        nombre: _nombreCtrl.text.trim(),
        capitanNombre: widget.capitan.nombreCompleto.trim(),
        deporte: _deporte,
        jugadores: List.of(_jugadores),
      ));
      if (!mounted) return;
      _mensaje('Equipo guardado.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _mensaje(CampeonatoService.mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi equipo')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _errorCarga != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_errorCarga!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _cargando = true;
                              _errorCarga = null;
                            });
                            _cargar();
                          },
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  TextFormField(
                    controller: _nombreCtrl,
                    enabled: !_inscrito,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 30,
                    decoration: const InputDecoration(labelText: 'Nombre del equipo'),
                    validator: (valor) => (valor ?? '').trim().length < 3 ? 'Escribe el nombre del equipo' : null,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _deporte,
                    decoration: const InputDecoration(labelText: 'Deporte'),
                    items: [for (final d in deportes) DropdownMenuItem(value: d, child: Text(d))],
                    onChanged: _inscrito ? null : (valor) => setState(() => _deporte = valor ?? _deporte),
                  ),
                  if (_inscrito)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Tu equipo está en un campeonato: el nombre y el deporte no se pueden cambiar hasta que termine.',
                        style: TextStyle(color: AppColors.textoSecundario, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'Jugadores (${_jugadores.length}) · mínimo ${Equipo.minJugadores}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _jugadorCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Nombre del jugador'),
                          onSubmitted: (_) => _agregarJugador(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.person_add, color: AppColors.verdeLima),
                        tooltip: 'Agregar',
                        onPressed: _agregarJugador,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _jugadores.length; i++)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.borde,
                          child: Text('${i + 1}', style: const TextStyle(color: AppColors.textoClaro)),
                        ),
                        title: Text(_jugadores[i]),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textoSecundario),
                          tooltip: 'Quitar',
                          onPressed: () => setState(() => _jugadores.removeAt(i)),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _guardando ? null : _guardar,
                    child: _guardando
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Guardar equipo'),
                  ),
                ],
              ),
            ),
    );
  }
}
