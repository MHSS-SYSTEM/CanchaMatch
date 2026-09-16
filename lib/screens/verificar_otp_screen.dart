import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

// VerificarOtpScreen: segunda mitad de HU-01. Aqui el usuario ingresa el
// codigo OTP que se le "envio" (en realidad se muestra en pantalla, porque
// el profesor pidio que el OTP sea SIMULADO, no un SMS/correo real).
class VerificarOtpScreen extends StatefulWidget {
  final String uid;
  final String otpSimulado;

  const VerificarOtpScreen({
    super.key,
    required this.uid,
    required this.otpSimulado,
  });

  @override
  State<VerificarOtpScreen> createState() => _VerificarOtpScreenState();
}

class _VerificarOtpScreenState extends State<VerificarOtpScreen> {
  final _codigoCtrl = TextEditingController();
  final _authService = AuthService();

  bool _cargando = false;
  String? _errorMensaje;

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _verificar() async {
    setState(() {
      _cargando = true;
      _errorMensaje = null;
    });

    final correcto = await _authService.verificarOtp(widget.uid, _codigoCtrl.text, widget.otpSimulado);

    if (!mounted) return;

    if (correcto) {
      // Verificado con exito: manda al login para que inicie sesion con
      // el correo y contraseña que acaba de crear.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } else {
      setState(() {
        _errorMensaje = 'Código incorrecto. Inténtalo de nuevo.';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verificar código')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Ingresa el código de verificación',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textoClaro),
              ),
              const SizedBox(height: 8),
              // Nota: este bloque muestra el OTP directamente en pantalla
              // porque es SIMULADO (requisito del curso). En una app real
              // este codigo llegaria por SMS o correo y NO se mostraria aqui.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.tarjeta,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borde),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Código simulado (solo para pruebas del curso):',
                      style: TextStyle(color: AppColors.textoSecundario, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    // Se muestra en fuente monoespaciada (JetBrains Mono),
                    // igual que en el diseño, para que los 6 dígitos se
                    // lean claros y separados.
                    Text(widget.otpSimulado, style: AppTheme.textoCodigo.copyWith(fontSize: 22)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _codigoCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Código de 6 dígitos'),
              ),
              if (_errorMensaje != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_errorMensaje!, style: const TextStyle(color: AppColors.error)),
                ),
              ElevatedButton(
                onPressed: _cargando ? null : _verificar,
                child: _cargando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verificar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
