 import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/cancha.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

// BuscarCanchasScreen: implementa HU-06 (Buscar canchas disponibles).
//
// Muestra un mapa (OpenStreetMap via flutter_map, sin necesitar API Key
// de pago) con un marcador por cada cancha disponible, mas un marcador
// especial con la ubicacion real del usuario (pedida por GPS con
// geolocator). Debajo del mapa hay una lista con las mismas canchas y la
// distancia aproximada a cada una.
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

  List<Cancha> _canchas = [];
  LatLng? _miUbicacion;
  bool _cargando = true;
  String? _errorUbicacion;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    // Primero asegura que existan canchas de ejemplo en Firestore (solo
    // crea datos la primera vez, ver FirestoreService.sembrarCanchasDeEjemplo).
    await _firestoreService.sembrarCanchasDeEjemplo();
    final canchas = await _firestoreService.obtenerCanchasDisponibles();

    if (mounted) {
      setState(() {
        _canchas = canchas;
        _cargando = false;
      });
    }

    // La ubicacion se pide aparte, para que la lista de canchas se vea
    // aunque el usuario rechace el permiso de GPS.
    await _obtenerUbicacionActual();
  }

  // _obtenerUbicacionActual: pide permiso de ubicacion (si no se ha dado
  // aun) y obtiene la posicion GPS real del telefono. Esta es la parte de
  // geolocalizacion real que pidio el usuario para HU-06.
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
      // limite de tiempo para que, si la señal esta muy debil (adentro de
      // un edificio, por ejemplo), la pantalla no se quede esperando para
      // siempre sin avisar nada.
      final posicion = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
      final ubicacion = LatLng(posicion.latitude, posicion.longitude);

      if (!mounted) return;
      setState(() => _miUbicacion = ubicacion);

      // Centra el mapa en la ubicacion real del usuario.
      _mapController.move(ubicacion, 14);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorUbicacion = 'No se pudo obtener tu ubicación: $e');
    }
  }

  // _distanciaTexto: calcula la distancia en linea recta (metros/km) entre
  // la ubicacion del usuario y una cancha, usando la formula que ya trae
  // el paquete geolocator (Geolocator.distanceBetween). Si aun no se tiene
  // la ubicacion del usuario, no muestra nada.
  String? _distanciaTexto(Cancha cancha) {
    if (_miUbicacion == null) return null;

    final metros = Geolocator.distanceBetween(
      _miUbicacion!.latitude,
      _miUbicacion!.longitude,
      cancha.latitud,
      cancha.longitud,
    );

    if (metros < 1000) {
      return '${metros.round()} m';
    }
    return '${(metros / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Canchas disponibles')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
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
                // Mapa: ocupa un poco menos de la mitad de la pantalla.
                SizedBox(
                  height: 260,
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
                          // Marcador de "donde estoy yo" (solo si ya se
                          // obtuvo el GPS).
                          if (_miUbicacion != null)
                            Marker(
                              point: _miUbicacion!,
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 32),
                            ),
                          // Un marcador por cada cancha disponible.
                          ..._canchas.map(
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
                // Lista de canchas debajo del mapa (sirve como respaldo si
                // el usuario prefiere ver los datos en texto en vez de
                // tocar el mapa).
                Expanded(
                  child: _canchas.isEmpty
                      ? const Center(
                          child: Text('No hay canchas disponibles por ahora.', style: TextStyle(color: AppColors.textoSecundario)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _canchas.length,
                          itemBuilder: (context, index) {
                            final cancha = _canchas[index];
                            final distancia = _distanciaTexto(cancha);
                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.sports_soccer, color: AppColors.verdeLima),
                                title: Text(cancha.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  '${cancha.tipoDeporte} · ${cancha.distrito} · S/ ${cancha.precioPorHora.toStringAsFixed(0)} / hora',
                                  style: const TextStyle(color: AppColors.textoSecundario),
                                ),
                                trailing: distancia != null
                                    ? Text(distancia, style: const TextStyle(color: AppColors.verdeLima))
                                    : null,
                                onTap: () => _mapController.move(
                                  LatLng(cancha.latitud, cancha.longitud),
                                  15,
                                ),
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
