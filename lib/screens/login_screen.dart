import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'registro_screen.dart';
import 'inicio_screen.dart';

// LoginScreen: pantalla de inicio de sesion con email y contraseña.
// No es una de las 3 HU pedidas, pero es necesaria como puerta de
// entrada: sin login no se puede llegar a "editar perfil" (HU-05) ni
// saber que usuario esta buscando canchas (HU-06).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _authService = AuthService();

  bool _cargando = false;
  String? _errorMensaje;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    setState(() {
      _cargando = true;
      _errorMensaje = null;
    });

    try {
      await _authService.iniciarSesion(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const InicioScreen()),
        (route) => false,
      );
    } catch (e) {
      // Usa el mismo traductor de errores que el registro, para distinguir
      // por ejemplo un problema de red de una contraseña incorrecta.
      setState(() => _errorMensaje = _authService.mensajeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Marca pequeña arriba, igual que en el diseño de Stitch
              // ("CANCHAMATCH" en mayusculas chicas, con separacion entre
              // letras).
              Text(
                'CANCHAMATCH',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.verdeLima,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              // Titular grande, con la misma fuente (Anybody) y peso que
              // usa "BIENVENIDO" en el diseño.
              Text(
                'Bienvenido',
                textAlign: TextAlign.center,
                style: AppTheme.tituloGrande.copyWith(fontSize: 40),
              ),
              const SizedBox(height: 6),
              Text(
                'ENCUENTRA TU CANCHA EN CAJAMARCA',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textoSecundario,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo electrónico'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña'),
              ),
              const SizedBox(height: 20),
              if (_errorMensaje != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_errorMensaje!, style: const TextStyle(color: AppColors.error)),
                ),
              ElevatedButton(
                onPressed: _cargando ? null : _iniciarSesion,
                child: _cargando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Iniciar sesión'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RegistroScreen()),
                  );
                },
                child: const Text('¿No tienes cuenta? Regístrate'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
