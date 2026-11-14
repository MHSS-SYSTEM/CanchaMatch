// Datos de la cuenta de EmailJS (https://www.emailjs.com) que envia el
// codigo de verificacion del registro (HU-01) al correo del usuario.
//
// Se copian del panel de EmailJS:
//  - serviceId: en "Email Services", el servicio conectado al Gmail.
//  - templateId: en "Email Templates", la plantilla del codigo. La
//    plantilla usa las variables {{to_email}}, {{nombre}} y {{codigo}}.
//  - publicKey: en "Account" > "General" (Public Key).
//
// La Public Key esta hecha para usarse dentro de apps: no es una
// contraseña. Ademas, en "Account" > "Security" debe estar activada la
// opcion "Allow EmailJS API for non-browser applications", porque la app
// del celular no es un navegador.
class CorreoConfig {
  static const serviceId = 'PEGAR_SERVICE_ID';
  static const templateId = 'PEGAR_TEMPLATE_ID';
  static const publicKey = 'PEGAR_PUBLIC_KEY';

  static bool get configurado => !serviceId.startsWith('PEGAR') && !publicKey.startsWith('PEGAR');
}
