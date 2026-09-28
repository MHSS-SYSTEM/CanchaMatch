import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/cancha.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';

// BuscarCanchasScreen: implementa HU-06 (Buscar canchas disponibles).
//
// Muestra las canchas reales que registro el administrador (HU-21) y que
// estan activas. El jugador puede combinar tres filtros:
//  - distrito,
//  - deporte,
//  - fecha: solo quedan las canchas que atienden ese dia (y, si es hoy,
//    que todavia tienen algun turno por delante).
//
// Arriba hay un mapa (OpenStreetMap via flutter_map) con un marcador por
// cancha y la ubicacion real del usuario (GPS con geolocator); debajo, la
// lista con la distancia aproximada a cada cancha.
class BuscarCanchasScreen extends StatefulWidget {
  const BuscarCanchasScreen({super.key});

  @override
  State<BuscarCanchasScreen> createState() => _BuscarCanchasScreenState();
}

class _BuscarCanchasScreenState extends State<BuscarCanchasScreen> {
  final _firestoreService = FirestoreService();
  final _mapController = MapController();

  // Centro por defecto: Plaza de Armas de Cajamarca. Se usa mientras se
  // obtiene (o si falla) la ubicacion real del usuario.
  static const _centroCajamarca = LatLng(-7.1611, -78.5127);

  StreamSubscription<List<Cancha>>? _suscripcion;
  List<Cancha> _canchas = [];
  bool _cargando = true;
  String? _errorCarga;

  LatLng? _miUbicacion;
  String? _errorUbicacion;

  // Filtros elegidos. null significa "todos" / "cualquier dia".
  String? _filtroDistrito;
  String? _filtroDeporte;
  DateTime? _filtroFecha;

  @override
  void initState() {
    super.initState();
    _escucharCanchas();
    // La ubicacion se pide aparte, para que la lista de canchas se vea
    // aunque el usuario rechace el permiso de GPS.
    _obtenerUbicacionActual();
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }

  // _escucharCanchas: se suscribe al Stream de canchas activas. Cada vez
  // que el administrador cambia algo, llega la lista nueva y se redibuja.
  void _escucharCanchas() {
    _suscripcion = _firestoreService.observarCanchasDisponibles().listen(
      (canchas) {
        if (!mounted) return;
        setState(() {
          _canchas = canchas;
          _cargando = false;
          _errorCarga = null;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _cargando = false;
          _errorCarga = 'No se pudieron cargar las canchas. Revisa tu conexión.';
        });
      },
    );
  }

  // _reintentar: despues de un error el Stream se cierra; este boton lo
  // vuelve a abrir.
  void _reintentar() {
    _suscripcion?.cancel();
    setState(() {
      _cargando = true;
      _errorCarga = null;
    });
    _escucharCanchas();
  }

  // _obtenerUbicacionActual: pide permiso de ubicacion (si no se ha dado
  // aun) y obtiene la posicion GPS real del telefono.
  Future<void> _obtenerUbicacionActual() async {
    try {
      // 1) Verifica que el GPS del telefono este activado.
      final servicioActivo = await Geolocator.isLocationServiceEnabled();
      // Se revisa "mounted" despues de cada await: el usuario pudo haber
      // salido de esta pantalla mientras se esperaba la respuesta del
      // GPS/permiso, y llamar a setState despues de eso hace que la app
      // se caiga.
      if (!mounted) return;
      if (!servicioActivo) {
        setState(() => _errorUbicacion = 'Activa el GPS para ver tu ubicación en el mapa.');
        return;
      }

      // 2) Revisa el permiso de ubicacion y lo pide si hace falta.
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
        setState(() => _errorUbicacion = 'Permiso de ubicación denegado.');
        return;
      }

      // 3) Ya con permiso, obtiene la posicion actual del GPS. Se pone un
      // limite de tiempo para que, si la señal esta muy debil, la pantalla
      // no se quede esperando para siempre sin avisar nada.
      final posicion = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
      final ubicacion = LatLng(posicion.latitude, posicion.longitude);

      if (!mounted) return;
      setState(() => _miUbicacion = ubicacion);
      // Centra el mapa en la ubicacion real. Si el mapa todavia no se
      // dibujo (las canchas aun estan cargando), no pasa nada: al
      // dibujarse usara _miUbicacion como centro inicial.
      try {
        _mapController.move(ubicacion, 14);
      } catch (_) {
        // El mapa aun no esta en pantalla.
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorUbicacion = 'No se pudo obtener tu ubicación.');
    }
  }

  // ---------------------------------------------------------------------
  // Filtros
  // ---------------------------------------------------------------------

  // Las opciones de distrito y deporte salen de las canchas que existen,
  // asi nunca se ofrece un filtro que no tenga resultados.
  List<String> get _distritos => (_canchas.map((c) => c.distrito).where((d) => d.isNotEmpty).toSet().toList()..sort());

  List<String> get _deportes => (_canchas.map((c) => c.tipoDeporte).where((d) => d.isNotEmpty).toSet().toList()..sort());

  // Proximos 7 dias, empezando por hoy.
  List<DateTime> get _fechas {
    final hoy = soloFecha(DateTime.now());
    return [for (var i = 0; i < 7; i++) hoy.add(Duration(days: i))];
  }

  String _etiquetaFecha(DateTime fecha) {
    final hoy = soloFecha(DateTime.now());
    final diferencia = fecha.difference(hoy).inDays;
    if (diferencia == 0) return 'Hoy';
    if (diferencia == 1) return 'Mañana';
    return '${diasCortos[fecha.weekday - 1]} ${fecha.day}';
  }

  // _atiendeEnFecha: la cancha abre ese dia de la semana y, si la fecha es
  // hoy, todavia le queda al menos un turno que no ha empezado.
  bool _atiendeEnFecha(Cancha cancha, DateTime fecha) {
    if (!cancha.abreEl(fecha)) return false;
    final ahora = DateTime.now();
    if (fecha == soloFecha(ahora)) {
      final primeraHoraLibre = max(cancha.horaApertura, ahora.hour + 1);
      return primeraHoraLibre < cancha.horaCierre;
    }
    return true;
  }

  List<Cancha> get _canchasFiltradas {
    return _canchas.where((c) {
      if (_filtroDistrito != null && c.distrito != _filtroDistrito) return false;
      if (_filtroDeporte != null && c.tipoDeporte != _filtroDeporte) return false;
      if (_filtroFecha != null && !_atiendeEnFecha(c, _filtroFecha!)) return false;
      return true;
    }).toList();
  }

  bool get _hayFiltros => _filtroDistrito != null || _filtroDeporte != null || _filtroFecha != null;

  void _limpiarFiltros() {
    setState(() {
      _filtroDistrito = null;
      _filtroDeporte = null;
      _filtroFecha = null;
    });
  }

  // _distanciaTexto: distancia en linea recta (metros/km) entre el usuario
  // y una cancha. Si aun no se tiene la ubicacion del usuario, no muestra
  // nada.
  String? _distanciaTexto(Cancha cancha) {
    if (_miUbicacion == null) return null;

    final metros = Geolocator.distanceBetween(
      _miUbicacion!.latitude,
      _miUbicacion!.longitude,
      cancha.latitud,
      cancha.longitud,
    );

    if (metros < 1000) return '${metros.round()} m';
    return '${(metros / 1000).toStringAsFixed(1)} km';
  }

  // ---------------------------------------------------------------------
  // Pantalla
  // ---------------------------------------------------------------------

  Widget _selector({
    required String etiqueta,
    required String? valor,
    required List<String> opciones,
    required ValueChanged<String?> alCambiar,
  }) {
    // Si el valor elegido ya no existe (por ejemplo, el admin desactivo la
    // unica cancha de ese distrito), se muestra "Todos" para que el
    // selector no falle.
    final valorSeguro = opciones.contains(valor) ? valor : null;
    return DropdownButtonFormField<String?>(
      value: valorSeguro,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: etiqueta,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      dropdownColor: AppColors.tarjeta,
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
        for (final opcion in opciones) DropdownMenuItem<String?>(value: opcion, child: Text(opcion)),
      ],
      onChanged: alCambiar,
    );
  }

  Widget _filtros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _selector(
                  etiqueta: 'Distrito',
                  valor: _filtroDistrito,
                  opciones: _distritos,
                  alCambiar: (v) => setState(() => _filtroDistrito = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _selector(
                  etiqueta: 'Deporte',
                  valor: _filtroDeporte,
                  opciones: _deportes,
                  alCambiar: (v) => setState(() => _filtroDeporte = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chipFecha('Cualquier día', null),
                for (final fecha in _fechas) _chipFecha(_etiquetaFecha(fecha), fecha),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipFecha(String etiqueta, DateTime? fecha) {
    final seleccionado = _filtroFecha == fecha;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(etiqueta),
        selected: seleccionado,
        selectedColor: AppColors.verdeLima,
        labelStyle: TextStyle(
          color: seleccionado ? AppColors.fondoOscuro : AppColors.textoClaro,
          fontWeight: FontWeight.w600,
        ),
        onSelected: (_) => setState(() => _filtroFecha = fecha),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canchas = _canchasFiltradas;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Canchas disponibles'),
        actions: [
          if (_hayFiltros)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              tooltip: 'Quitar filtros',
              onPressed: _limpiarFiltros,
            ),
        ],
      ),
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
                        OutlinedButton(onPressed: _reintentar, child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (_errorUbicacion != null)
                      Container(
                        width: double.infinity,
                        color: AppColors.tarjeta,
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          _errorUbicacion!,
                          style: const TextStyle(color: AppColors.textoSecundario, fontSize: 12),
                        ),
                      ),
                    _filtros(),
                    SizedBox(
                      height: 200,
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _miUbicacion ?? _centroCajamarca,
                          initialZoom: 13,
                        ),
                        children: [
                          // Capa de mapa base: tiles publicos de OpenStreetMap,
                          // gratis y sin necesitar API Key.
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.upn.canchamatch',
                          ),
                          MarkerLayer(
                            markers: [
                              if (_miUbicacion != null)
                                Marker(
                                  point: _miUbicacion!,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 32),
                                ),
                              // Un marcador por cada cancha que cumple los filtros.
                              ...canchas.map(
                                (cancha) => Marker(
                                  point: LatLng(cancha.latitud, cancha.longitud),
                                  width: 40,
                                  height: 40,
                                  child: const Icon(Icons.sports_soccer, color: AppColors.verdeLima, size: 32),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.borde),
                    Expanded(
                      child: canchas.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  _canchas.isEmpty
                                      ? 'No hay canchas disponibles por ahora.'
                                      : 'No hay canchas con esos filtros.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: AppColors.textoSecundario),
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: canchas.length,
                              itemBuilder: (context, index) {
                                final cancha = canchas[index];
                                final distancia = _distanciaTexto(cancha);
                                return Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.sports_soccer, color: AppColors.verdeLima),
                                    title: Text(cancha.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                      '${cancha.tipoDeporte} · ${cancha.distrito} · S/ ${cancha.precioPorHora.toStringAsFixed(0)} / hora\n'
                                      '${cancha.horarioTexto} · ${cancha.diasTexto}',
                                      style: const TextStyle(color: AppColors.textoSecundario),
                                    ),
                                    isThreeLine: true,
                                    trailing: distancia != null
                                        ? Text(distancia, style: const TextStyle(color: AppColors.verdeLima))
                                        : null,
                                    onTap: () => _mapController.move(LatLng(cancha.latitud, cancha.longitud), 15),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
