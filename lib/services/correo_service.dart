import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/correo_config.dart';

// CorreoException: no se pudo enviar el correo; trae un mensaje listo
// para mostrar en pantalla.
class CorreoException implements Exception {
  final String mensaje;

  CorreoException(this.mensaje);

  @override
  String toString() => mensaje;
}

// CorreoService: envia el codigo OTP del registro (HU-01) a un correo
// real usando EmailJS, un servicio gratuito que manda correos desde una
// cuenta de Gmail sin necesidad de tener un servidor propio.
//
// La app hace un POST a la API de EmailJS con la plantilla y las
// variables; EmailJS arma el correo y lo envia.
class CorreoService {
  static final CorreoService _instancia = CorreoService._interno();

  factory CorreoService() => _instancia;

  CorreoService._interno();

  static final _url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

  Future<void> enviarCodigo({
    required String email,
    required String nombre,
    required String codigo,
  }) async {
    if (!CorreoConfig.configurado) {
      throw CorreoException('El envío de correos todavía no está configurado (ver utils/correo_config.dart).');
    }

    final http.Response respuesta;
    try {
      respuesta = await http
          .post(
            _url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'service_id': CorreoConfig.serviceId,
              'template_id': CorreoConfig.templateId,
              'user_id': CorreoConfig.publicKey,
              'template_params': {
                'to_email': email,
                'nombre': nombre.isEmpty ? 'jugador' : nombre,
                'codigo': codigo,
              },
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw CorreoException('No se pudo enviar el correo. Revisa tu conexión a internet.');
    }

    if (respuesta.statusCode != 200) {
      throw CorreoException('No se pudo enviar el correo (${respuesta.statusCode}). Inténtalo de nuevo.');
    }
  }
}
