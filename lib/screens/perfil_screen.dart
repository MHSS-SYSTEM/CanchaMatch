import 'package:flutter/material.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/constantes.dart';

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

  // Lista fija de deportes para el selector (Dropdown). Es la misma que
  // usa el administrador al crear canchas (ver utils/constantes.dart).
  static const _deportes = deportes;
  String? _deporteSeleccionado;

  // Rol elegido (HU-04): jugador, capitan u organizador.
  String _tipoCuenta = 'jugador';

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
      _tipoCuenta = usuario.tipoCuenta;
      _cargandoDatos = false;
    });
  }

  Future<void> _guardarCambios() async {
    if (_usuario == null) return;

    // Validacion del telefono: en Peru los celulares tienen 9 digitos.
    // Si no cumple, se muestra el aviso y no se guarda nada en Firestore.
    // El mensaje empieza con "No se pudo" para que se pinte en rojo (ver
    // el Text de _mensaje mas abajo).
    final telefono = _telefonoCtrl.text.trim();
    if (!RegExp(r'^\d{9}$').hasMatch(telefono)) {
      setState(() => _mensaje = 'No se pudo guardar: el teléfono debe tener 9 dígitos.');
      return;
    }

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
      ..deporteFavorito = _deporteSeleccionado
      ..tipoCuenta = _tipoCuenta;

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
                    const SizedBox(height: 12),
                    // El administrador general se asigna en Firebase: no se cambia aqui.
                    if (_usuario?.esAdmin ?? false)
                      Text(
                        'Rol: ${_usuario!.rolTexto}',
                        style: const TextStyle(color: AppColors.textoSecundario),
                      )
                    else ...[
                      DropdownButtonFormField<String>(
                        value: _tipoCuenta,
                        decoration: const InputDecoration(labelText: 'Rol'),
                        dropdownColor: AppColors.tarjeta,
                        items: [
                          for (final tipo in Usuario.tiposCuenta)
                            DropdownMenuItem(value: tipo, child: Text(Usuario.nombreTipo(tipo))),
                        ],
                        onChanged: (valor) => setState(() => _tipoCuenta = valor ?? 'jugador'),
                      ),
                      if (_tipoCuenta == 'organizador')
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Podrás crear y administrar las canchas de tu complejo.',
                            style: TextStyle(color: AppColors.textoSecundario, fontSize: 12),
                          ),
                        ),
                    ],
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
