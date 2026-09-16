import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'verificar_otp_screen.dart';

// RegistroScreen: implementa HU-01 (Registro de usuario).
//
// Es un formulario con nombre, apellido, email, telefono y contraseña.
// Al enviarlo, crea la cuenta en Firebase y genera un OTP SIMULADO
// (no se manda SMS/correo real), luego navega a VerificarOtpScreen para
// que el usuario lo ingrese y complete el registro.
class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  // GlobalKey del formulario: permite validar todos los campos de una vez
  // con _formKey.currentState!.validate().
  final _formKey = GlobalKey<FormState>();

  // Un controller por campo de texto, para leer lo que el usuario escribe.
  final _nombreCtrl = TextEditingController();
  final _apellidoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  final _authService = AuthService();

  // cargando: controla si se muestra el spinner mientras se crea la
  // cuenta en Firebase (evita que el usuario toque el boton dos veces).
  bool _cargando = false;
  String? _errorMensaje;

  @override
  void dispose() {
    // Libera los controllers cuando la pantalla se destruye, para no
    // dejar memoria ocupada sin uso.
    _nombreCtrl.dispose();
    _apellidoCtrl.dispose();
    _emailCtrl.dispose();
    _telefonoCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // _registrar: se ejecuta al presionar el boton "Registrarme".
  Future<void> _registrar() async {
    // Si algun campo no pasa las validaciones (ver validator: mas abajo),
    // no continua.
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _cargando = true;
      _errorMensaje = null;
    });

    try {
      final resultado = await _authService.registrarUsuario(
        nombre: _nombreCtrl.text.trim(),
        apellido: _apellidoCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      if (!mounted) return;

      // Navega a la pantalla de verificacion, pasando el uid recien
      // creado y el OTP simulado que genero AuthService.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VerificarOtpScreen(
            uid: resultado['uid']!,
            otpSimulado: resultado['otp']!,
          ),
        ),
      );
    } catch (e) {
      // Traduce el error de Firebase a un mensaje en español que el
      // usuario entienda (en vez de mostrar el texto tecnico crudo de
      // la excepcion).
      setState(() => _errorMensaje = _authService.mensajeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Regístrate',
                  style: AppTheme.tituloGrande.copyWith(fontSize: 28),
                ),
                const SizedBox(height: 2),
                const Text(
                  'CREA TU CUENTA EN CANCHAMATCH',
                  style: TextStyle(color: AppColors.textoSecundario, letterSpacing: 1.2, fontSize: 12),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa tu nombre' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _apellidoCtrl,
                  decoration: const InputDecoration(labelText: 'Apellido'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa tu apellido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo electrónico'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Ingresa tu correo';
                    if (!v.contains('@')) return 'Correo no válido';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefonoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa tu teléfono' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña'),
                  validator: (v) {
                    if (v == null || v.length < 6) return 'Mínimo 6 caracteres';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                if (_errorMensaje != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_errorMensaje!, style: const TextStyle(color: AppColors.error)),
                  ),
                ElevatedButton(
                  onPressed: _cargando ? null : _registrar,
                  child: _cargando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Registrarme'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
