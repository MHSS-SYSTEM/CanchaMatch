import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/cancha.dart';
import '../services/canchas_admin_service.dart';
import '../theme/app_theme.dart';
import '../utils/constantes.dart';
import '../utils/formato.dart';

// EditarCanchaScreen: formulario de HU-21 para crear una cancha nueva
// (cancha == null) o editar una existente.
//
// El administrador define aqui el precio por hora, el horario de atencion
// (hora de apertura y cierre), los dias que abre, la politica de
// cancelacion y la ubicacion (tocando el mapa).
class EditarCanchaScreen extends StatefulWidget {
  final Cancha? cancha;

  const EditarCanchaScreen({super.key, this.cancha});

  @override
  State<EditarCanchaScreen> createState() => _EditarCanchaScreenState();
}

class _EditarCanchaScreenState extends State<EditarCanchaScreen> {
  // Listas fijas para los selectores. Usar opciones fijas (en vez de texto
  // libre) evita que la misma cosa quede escrita de dos formas distintas
  // ("Futbol" y "fútbol"), lo que romperia los filtros de busqueda (HU-06).
  static const _deportes = deportes;
  static const _distritos = distritosCajamarca;
  static const _horasLimite = [0, 1, 2, 6, 12, 24, 48];

  // Centro por defecto del mapa: Plaza de Armas de Cajamarca.
  static const _centroCajamarca = LatLng(-7.1611, -78.5127);

  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _politicaCtrl = TextEditingController();

  String? _deporte;
  String? _distrito;

  // Si la cancha tenia guardado un deporte o distrito que no esta en las
  // listas (por ejemplo, editado a mano en Firestore), se guarda aqui para
  // avisarle al admin, y el selector queda vacio hasta que elija uno. Asi
  // el dato nunca se reemplaza por otro sin que el admin se de cuenta.
  String? _deporteAnterior;
  String? _distritoAnterior;
  late int _horaApertura;
  late int _horaCierre;
  late Set<int> _dias;
  late int _horasLimiteCancelacion;
  late bool _disponible;
  LatLng? _ubicacion;

  bool _guardando = false;
  String? _error;

  bool get _esNueva => widget.cancha == null;

  @override
  void initState() {
    super.initState();
    final c = widget.cancha;
    _nombreCtrl.text = c?.nombre ?? '';
    _direccionCtrl.text = c?.direccion ?? '';
    _precioCtrl.text = c == null ? '' : c.precioPorHora.toStringAsFixed(0);
    _politicaCtrl.text = c?.politicaCancelacion ?? '';

    if (c != null) {
      if (_deportes.contains(c.tipoDeporte)) {
        _deporte = c.tipoDeporte;
      } else if (c.tipoDeporte.isNotEmpty) {
        _deporteAnterior = c.tipoDeporte;
      }
      if (_distritos.contains(c.distrito)) {
        _distrito = c.distrito;
      } else if (c.distrito.isNotEmpty) {
        _distritoAnterior = c.distrito;
      }
    }
    _horaApertura = c?.horaApertura ?? 8;
    _horaCierre = c?.horaCierre ?? 22;
    _dias = {...(c?.diasAbiertos ?? const [1, 2, 3, 4, 5, 6, 7])};
    _horasLimiteCancelacion =
        _horasLimite.contains(c?.horasLimiteCancelacion) ? c!.horasLimiteCancelacion : 2;
    _disponible = c?.disponible ?? true;
    if (c != null && (c.latitud != 0 || c.longitud != 0)) {
      _ubicacion = LatLng(c.latitud, c.longitud);
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _direccionCtrl.dispose();
    _precioCtrl.dispose();
    _politicaCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    // Validaciones que no son de un solo campo.
    if (_horaCierre <= _horaApertura) {
      setState(() => _error = 'La hora de cierre debe ser después de la hora de apertura.');
      return;
    }
    if (_dias.isEmpty) {
      setState(() => _error = 'Elige al menos un día de atención.');
      return;
    }
    if (_ubicacion == null) {
      setState(() => _error = 'Toca el mapa para marcar dónde está la cancha.');
      return;
    }

    final cancha = Cancha(
      id: widget.cancha?.id ?? '',
      nombre: _nombreCtrl.text.trim(),
      direccion: _direccionCtrl.text.trim(),
      distrito: _distrito!,
      tipoDeporte: _deporte!,
      precioPorHora: double.parse(_precioCtrl.text.trim().replaceAll(',', '.')),
      latitud: _ubicacion!.latitude,
      longitud: _ubicacion!.longitude,
      disponible: _disponible,
      horaApertura: _horaApertura,
      horaCierre: _horaCierre,
      diasAbiertos: _dias.toList()..sort(),
      politicaCancelacion: _politicaCtrl.text.trim(),
      horasLimiteCancelacion: _horasLimiteCancelacion,
    );

    setState(() => _guardando = true);
    try {
      await CanchasAdminService().guardar(cancha);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_esNueva ? 'Cancha creada.' : 'Cambios guardados.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo guardar la cancha. Revisa tu conexión e inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _titulo(String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_esNueva ? 'Nueva cancha' : 'Editar cancha')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre de la cancha'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el nombre' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _direccionCtrl,
                decoration: const InputDecoration(labelText: 'Dirección'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe la dirección' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _distrito,
                decoration: InputDecoration(
                  labelText: 'Distrito',
                  helperText: _distritoAnterior == null
                      ? null
                      : 'Tenía "$_distritoAnterior", que no está en la lista. Elige uno.',
                ),
                dropdownColor: AppColors.tarjeta,
                items: _distritos.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                validator: (v) => v == null ? 'Elige el distrito' : null,
                onChanged: (v) => setState(() => _distrito = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _deporte,
                decoration: InputDecoration(
                  labelText: 'Deporte',
                  helperText: _deporteAnterior == null
                      ? null
                      : 'Tenía "$_deporteAnterior", que no está en la lista. Elige uno.',
                ),
                dropdownColor: AppColors.tarjeta,
                items: _deportes.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                validator: (v) => v == null ? 'Elige el deporte' : null,
                onChanged: (v) => setState(() => _deporte = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _precioCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Precio por hora (S/)'),
                validator: (v) {
                  final precio = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                  if (precio == null || precio <= 0) return 'Escribe un precio mayor a 0';
                  return null;
                },
              ),

              _titulo('Horario de atención'),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _horaApertura,
                      decoration: const InputDecoration(labelText: 'Abre'),
                      dropdownColor: AppColors.tarjeta,
                      items: [
                        for (var h = 0; h <= 23; h++) DropdownMenuItem(value: h, child: Text(horaTexto(h))),
                      ],
                      onChanged: (v) => setState(() => _horaApertura = v ?? _horaApertura),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _horaCierre,
                      decoration: const InputDecoration(labelText: 'Cierra'),
                      dropdownColor: AppColors.tarjeta,
                      items: [
                        for (var h = 1; h <= 24; h++) DropdownMenuItem(value: h, child: Text(horaTexto(h))),
                      ],
                      onChanged: (v) => setState(() => _horaCierre = v ?? _horaCierre),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Días que atiende', style: TextStyle(color: AppColors.textoSecundario)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(diasCortos[d - 1]),
                      selected: _dias.contains(d),
                      selectedColor: AppColors.verdeLima,
                      checkmarkColor: AppColors.fondoOscuro,
                      labelStyle: TextStyle(
                        color: _dias.contains(d) ? AppColors.fondoOscuro : AppColors.textoClaro,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (marcado) => setState(() {
                        marcado ? _dias.add(d) : _dias.remove(d);
                      }),
                    ),
                ],
              ),

              _titulo('Política de cancelación'),
              DropdownButtonFormField<int>(
                value: _horasLimiteCancelacion,
                decoration: const InputDecoration(labelText: 'Se puede cancelar hasta'),
                dropdownColor: AppColors.tarjeta,
                items: [
                  for (final h in _horasLimite)
                    DropdownMenuItem(
                      value: h,
                      child: Text(h == 0 ? 'Hasta la hora del partido' : '$h ${h == 1 ? 'hora' : 'horas'} antes'),
                    ),
                ],
                onChanged: (v) => setState(() => _horasLimiteCancelacion = v ?? _horasLimiteCancelacion),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _politicaCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Texto de la política (opcional)',
                  hintText: 'Ej: Cancelaciones con menos de 2 horas no tienen reembolso.',
                ),
              ),

              _titulo('Ubicación'),
              const Text(
                'Toca el mapa para marcar dónde está la cancha.',
                style: TextStyle(color: AppColors.textoSecundario),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 220,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: _ubicacion ?? _centroCajamarca,
                      initialZoom: 14,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                      onTap: (_, punto) => setState(() => _ubicacion = punto),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.upn.canchamatch',
                      ),
                      if (_ubicacion != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _ubicacion!,
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.location_on, color: AppColors.verdeLima, size: 40),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Cancha activa'),
                subtitle: const Text(
                  'Si la desactivas, los jugadores ya no la verán en la búsqueda.',
                  style: TextStyle(color: AppColors.textoSecundario),
                ),
                value: _disponible,
                activeColor: AppColors.verdeLima,
                onChanged: (v) => setState(() => _disponible = v),
              ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: AppColors.error)),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_esNueva ? 'Crear cancha' : 'Guardar cambios'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
