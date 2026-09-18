import 'package:flutter/material.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

// PerfilScreen: implementa HU-05 (Edicion de perfil).
//
// Al abrirse, carga los datos actuales del usuario desde Firestore
// (obtenerPerfil) y los muestra en un formulario. Al presionar "Guardar
// cambios", actualiza el documento en Firestore (actualizarPerfil).
class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  final _authService = AuthService();
  final _firestoreService = FirestoreService();

  final _nombreCtrl = TextEditingController();
  final _apellidoCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _distritoCtrl = TextEditingController();

  // Lista fija de deportes para el selector (Dropdown). Se podria traer
  // desde Firestore, pero para las 3 HU del curso una lista fija alcanza.
  static const _deportes = ['Futbol', 'Voley', 'Basquet', 'Tenis'];
  String? _deporteSeleccionado;

  Usuario? _usuario;
  bool _cargandoDatos = true;
  bool _guardando = false;
  String? _mensaje;

  // errorCarga: se llena si no se pudo traer el perfil de Firestore (por
  // ejemplo, si el documento nunca se creo). Sin esto, la pantalla se
  // quedaria mostrando el circulo de carga para siempre sin explicar nada.
  String? _errorCarga;

  @override
  void initState() {
    super.initState();
    // Carga el perfil apenas se abre la pantalla. Este es el equivalente
    // en Flutter a un LaunchedEffect de Jetpack Compose: codigo que
    // corre una sola vez cuando el widget aparece.
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    final uid = _authService.usuarioActual?.uid;
    if (uid == null) return;

    final usuario = await _firestoreService.obtenerPerfil(uid);
    if (!mounted) return;

    if (usuario == null) {
      setState(() {
        _cargandoDatos = false;
        _errorCarga = 'No se pudo cargar tu perfil. Cierra sesión y vuelve a entrar.';
      });
      return;
    }

    setState(() {
      _usuario = usuario;
      _nombreCtrl.text = usuario.nombre;
      _apellidoCtrl.text = usuario.apellido;
      _telefonoCtrl.text = usuario.telefono;
      _distritoCtrl.text = usuario.distrito ?? '';
      // Si el deporte guardado ya no esta en la lista de opciones (por
      // ejemplo, se edito el dato directamente en Firestore), se deja el
      // selector vacio en vez de asignar un valor que el Dropdown no
      // reconoce, porque eso hace que la pantalla se caiga.
      _deporteSeleccionado = _deportes.contains(usuario.deporteFavorito) ? usuario.deporteFavorito : null;
      _cargandoDatos = false;
    });
  }

  Future<void> _guardarCambios() async {
    if (_usuario == null) return;

    setState(() {
      _guardando = true;
      _mensaje = null;
    });

    // Actualiza los campos del objeto Usuario en memoria con lo que el
    // usuario escribio en el formulario, y lo manda a Firestore.
    _usuario!
      ..nombre = _nombreCtrl.text.trim()
      ..apellido = _apellidoCtrl.text.trim()
      ..telefono = _telefonoCtrl.text.trim()
      ..distrito = _distritoCtrl.text.trim()
      ..deporteFavorito = _deporteSeleccionado;

    try {
      await _firestoreService.actualizarPerfil(_usuario!);
      setState(() => _mensaje = 'Perfil actualizado correctamente.');
    } catch (e) {
      setState(() => _mensaje = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _apellidoCtrl.dispose();
    _telefonoCtrl.dispose();
    _distritoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: _cargandoDatos
          ? const Center(child: CircularProgressIndicator())
          : _errorCarga != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _errorCarga!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // El correo no se puede editar aqui porque cambiar el
                    // email implica reautenticar en Firebase Auth; para el
                    // alcance de HU-05 solo se muestra como referencia.
                    Text(
                      _usuario?.email ?? '',
                      style: const TextStyle(color: AppColors.textoSecundario),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _apellidoCtrl,
                      decoration: const InputDecoration(labelText: 'Apellido'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _telefonoCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Teléfono'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _distritoCtrl,
                      decoration: const InputDecoration(labelText: 'Distrito (Cajamarca)'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _deporteSeleccionado,
                      decoration: const InputDecoration(labelText: 'Deporte favorito'),
                      dropdownColor: AppColors.tarjeta,
                      items: _deportes
                          .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                          .toList(),
                      onChanged: (valor) => setState(() => _deporteSeleccionado = valor),
                    ),
                    const SizedBox(height: 20),
                    if (_mensaje != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _mensaje!,
                          style: TextStyle(
                            color: _mensaje!.startsWith('No se pudo')
                                ? AppColors.error
                                : AppColors.verdeLima,
                          ),
                        ),
                      ),
                    ElevatedButton(
                      onPressed: _guardando ? null : _guardarCambios,
                      child: _guardando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Guardar cambios'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
