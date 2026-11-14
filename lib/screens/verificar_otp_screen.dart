import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/correo_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

// VerificarOtpScreen: segunda mitad de HU-01.
//
// Al abrirse envia un codigo de 6 digitos al correo del usuario (EmailJS,
// ver CorreoService). El usuario lo escribe aqui y, si coincide, su
// cuenta queda verificada.
//
// Reglas del codigo:
//  - vence a los [_minutosValidez] minutos,
//  - se puede reenviar, pero esperando [_segundosReenvio] segundos entre
//    un envio y otro,
//  - despues de [_maxIntentos] codigos incorrectos hay que pedir uno nuevo.
class VerificarOtpScreen extends StatefulWidget {
  final String uid;
  final String email;
  final String nombre;

  const VerificarOtpScreen({
    super.key,
    required this.uid,
    required this.email,
    required this.nombre,
  });

  @override
  State<VerificarOtpScreen> createState() => _VerificarOtpScreenState();
}

class _VerificarOtpScreenState extends State<VerificarOtpScreen> {
  static const _minutosValidez = 10;
  static const _segundosReenvio = 60;
  static const _maxIntentos = 5;

  final _codigoCtrl = TextEditingController();
  final _authService = AuthService();

  // El codigo enviado solo vive en memoria mientras la pantalla esta
  // abierta: no se guarda en Firestore ni se muestra.
  String? _codigo;
  DateTime? _venceEn;
  int _intentos = 0;

  bool _enviando = false;
  bool _cargando = false;
  String? _errorMensaje;
  String? _aviso;

  Timer? _timer;
  int _esperaReenvio = 0;

  @override
  void initState() {
    super.initState();
    _enviarCodigo();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviarCodigo() async {
    setState(() {
      _enviando = true;
      _errorMensaje = null;
      _aviso = null;
    });

    final codigo = _authService.generarCodigoOtp();
    try {
      await CorreoService().enviarCodigo(email: widget.email, nombre: widget.nombre, codigo: codigo);
      if (!mounted) return;
      setState(() {
        _codigo = codigo;
        _venceEn = DateTime.now().add(const Duration(minutes: _minutosValidez));
        _intentos = 0;
        _codigoCtrl.clear();
        _aviso = 'Te enviamos un código a ${widget.email}. Revisa también la carpeta de spam.';
      });
      _iniciarEsperaReenvio();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMensaje = e is CorreoException ? e.mensaje : 'No se pudo enviar el correo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _iniciarEsperaReenvio() {
    _timer?.cancel();
    setState(() => _esperaReenvio = _segundosReenvio);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _esperaReenvio--);
      if (_esperaReenvio <= 0) timer.cancel();
    });
  }

  Future<void> _verificar() async {
    final codigo = _codigo;
    if (codigo == null) {
      setState(() => _errorMensaje = 'Primero pide que te enviemos el código.');
      return;
    }
    if (_venceEn != null && DateTime.now().isAfter(_venceEn!)) {
      setState(() => _errorMensaje = 'El código venció. Pide uno nuevo.');
      return;
    }
    if (_intentos >= _maxIntentos) {
      setState(() => _errorMensaje = 'Demasiados intentos. Pide un código nuevo.');
      return;
    }

    setState(() {
      _cargando = true;
      _errorMensaje = null;
    });

    try {
      final correcto = await _authService.verificarOtp(widget.uid, _codigoCtrl.text, codigo);
      if (!mounted) return;

      if (correcto) {
        // Verificado con exito: manda al login para que inicie sesion con
        // el correo y contraseña que acaba de crear.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Cuenta verificada! Ya puedes iniciar sesión.')),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        return;
      }

      _intentos++;
      final quedan = _maxIntentos - _intentos;
      setState(() => _errorMensaje = quedan > 0
          ? 'Código incorrecto. Te quedan $quedan ${quedan == 1 ? 'intento' : 'intentos'}.'
          : 'Demasiados intentos. Pide un código nuevo.');
    } catch (_) {
      if (mounted) setState(() => _errorMensaje = 'No se pudo verificar. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verificar correo')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Ingresa el código de verificación',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textoClaro),
            ),
            const SizedBox(height: 8),
            Text(
              _aviso ?? (_enviando ? 'Enviando el código a ${widget.email}...' : ''),
              style: const TextStyle(color: AppColors.textoSecundario),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _codigoCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: AppTheme.textoCodigo.copyWith(fontSize: 24),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Código de 6 dígitos'),
            ),
            if (_errorMensaje != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_errorMensaje!, style: const TextStyle(color: AppColors.error)),
              ),
            ElevatedButton(
              onPressed: _cargando || _enviando ? null : _verificar,
              child: _cargando
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Verificar'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _enviando || _esperaReenvio > 0 ? null : _enviarCodigo,
              child: Text(
                _enviando
                    ? 'Enviando...'
                    : _esperaReenvio > 0
                        ? 'Reenviar código en $_esperaReenvio s'
                        : 'Reenviar código',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
