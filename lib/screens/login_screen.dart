import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/bloqueo_login_service.dart';
import '../theme/app_theme.dart';
import 'registro_screen.dart';
import 'inicio_screen.dart';
import 'verificar_otp_screen.dart';

// LoginScreen: implementa HU-02 (Inicio de sesion).
//
// - El login es real contra Firebase Authentication, con las cuentas que
//   se crean en el registro (HU-01).
// - Si el correo o la contraseña estan mal, siempre se muestra el mismo
//   mensaje generico ("Correo o contraseña incorrectos"), sin decir cual
//   de los dos fallo, para no revelar si un correo esta registrado.
// - Despues de 5 intentos fallidos con el mismo correo, ese correo queda
//   bloqueado unos minutos (ver BloqueoLoginService).
// - Si la cuenta nunca confirmo su codigo OTP al registrarse, se le pide
//   verificar con un codigo nuevo antes de entrar.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _authService = AuthService();
  final _bloqueoService = BloqueoLoginService();

  bool _cargando = false;
  String? _errorMensaje;

  // Datos del bloqueo activo (si hay uno): el correo bloqueado, los
  // segundos que faltan y el Timer que los va descontando cada segundo.
  String? _emailBloqueado;
  int _segundosBloqueo = 0;
  Timer? _timerBloqueo;

  bool get _estaBloqueado => _segundosBloqueo > 0;

  // Codigos de Firebase Auth que significan "credenciales incorrectas".
  // Solo estos cuentan como intento fallido; un error de red, por
  // ejemplo, no deberia acercar al usuario al bloqueo.
  static const _erroresDeCredenciales = {
    'user-not-found',
    'wrong-password',
    'invalid-credential',
    'invalid-email',
    'user-disabled',
  };

  @override
  void dispose() {
    _timerBloqueo?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // _iniciarCuentaRegresiva: arranca el contador del bloqueo y actualiza
  // la pantalla cada segundo hasta llegar a cero.
  void _iniciarCuentaRegresiva(String email, Duration restante) {
    _timerBloqueo?.cancel();
    setState(() {
      _emailBloqueado = email;
      _segundosBloqueo = restante.inSeconds + 1;
    });

    _timerBloqueo = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _segundosBloqueo--;
        if (_segundosBloqueo <= 0) {
          timer.cancel();
          _emailBloqueado = null;
          _errorMensaje = null;
        }
      });
    });
  }

  // Si el usuario escribe otro correo, el bloqueo en pantalla deja de
  // aplicar (el bloqueo es por correo). Igual se vuelve a revisar al
  // presionar "Iniciar sesion".
  void _alCambiarEmail(String valor) {
    if (_emailBloqueado != null && valor.trim().toLowerCase() != _emailBloqueado) {
      _timerBloqueo?.cancel();
      setState(() {
        _emailBloqueado = null;
        _segundosBloqueo = 0;
        _errorMensaje = null;
      });
    }
  }

  String _formatoTiempo(int segundos) {
    final minutos = segundos ~/ 60;
    final resto = (segundos % 60).toString().padLeft(2, '0');
    return '$minutos:$resto';
  }

  Future<void> _iniciarSesion() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMensaje = 'Ingresa tu correo y tu contraseña.');
      return;
    }

    // Antes de ir a Firebase, se revisa si este correo esta bloqueado.
    final restante = await _bloqueoService.tiempoRestanteBloqueo(email);
    if (!mounted) return;
    if (restante != null) {
      setState(() => _errorMensaje = 'Demasiados intentos fallidos. Espera para volver a intentarlo.');
      _iniciarCuentaRegresiva(email.toLowerCase(), restante);
      return;
    }

    setState(() {
      _cargando = true;
      _errorMensaje = null;
    });

    try {
      await _authService.iniciarSesion(email: email, password: password);
      // Login correcto: se borra el contador de intentos de este correo.
      await _bloqueoService.reiniciar(email);

      // La cuenta tiene que haber confirmado su codigo OTP (HU-01).
      final uid = _authService.usuarioActual!.uid;
      final verificado = await _authService.estaVerificado(uid);
      if (!mounted) return;

      if (!verificado) {
        final otp = _authService.nuevoOtpSimulado();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => VerificarOtpScreen(uid: uid, otpSimulado: otp)),
        );
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const InicioScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (_erroresDeCredenciales.contains(e.code)) {
        final quedan = await _bloqueoService.registrarIntentoFallido(email);
        if (!mounted) return;
        if (quedan == 0) {
          setState(() => _errorMensaje = 'Demasiados intentos fallidos. Espera para volver a intentarlo.');
          _iniciarCuentaRegresiva(email.toLowerCase(), BloqueoLoginService.duracionBloqueo);
        } else {
          final palabra = quedan == 1 ? 'intento' : 'intentos';
          setState(() => _errorMensaje = 'Correo o contraseña incorrectos. Te quedan $quedan $palabra.');
        }
      } else {
        // Otros errores (sin internet, etc.) usan el traductor comun.
        if (mounted) setState(() => _errorMensaje = _authService.mensajeError(e));
      }
    } catch (e) {
      if (mounted) setState(() => _errorMensaje = _authService.mensajeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Marca pequeña arriba, igual que en el diseño de Stitch
                // ("CANCHAMATCH" en mayusculas chicas, con separacion entre
                // letras).
                const Text(
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
                const Text(
                  'ENCUENTRA TU CANCHA EN CAJAMARCA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textoSecundario,
                    letterSpacing: 1.5,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: _alCambiarEmail,
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
                if (_estaBloqueado)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Podrás intentarlo de nuevo en ${_formatoTiempo(_segundosBloqueo)}',
                      textAlign: TextAlign.center,
                      style: AppTheme.textoCodigo.copyWith(fontSize: 14),
                    ),
                  ),
                ElevatedButton(
                  onPressed: (_cargando || _estaBloqueado) ? null : _iniciarSesion,
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
      ),
    );
  }
}
