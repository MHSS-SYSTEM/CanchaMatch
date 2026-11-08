// Validaciones de los formularios, en un solo lugar para que el registro
// (HU-01), el perfil (HU-05), el login (HU-02) y los demas formularios
// revisen los datos con las mismas reglas.
//
// Cada funcion devuelve el mensaje de error para mostrar debajo del campo,
// o null si el dato esta bien (es lo que espera "validator:" de un
// TextFormField).

// Letras (con tildes y ñ), espacios, apostrofe y guion. Ej: "José María".
final _soloLetras = RegExp(r"^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ' -]+$");

// usuario@dominio.algo
final _formatoEmail = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

// Celular de Peru: 9 digitos y empieza con 9 (ej: 987654321).
final _celularPeru = RegExp(r'^9\d{8}$');

String? validarNombre(String? valor, String campo) {
  final texto = (valor ?? '').trim();
  if (texto.isEmpty) return 'Ingresa tu $campo';
  if (texto.length < 2) return 'El $campo es muy corto';
  if (texto.length > 40) return 'El $campo es muy largo';
  if (!_soloLetras.hasMatch(texto)) return 'El $campo solo puede tener letras';
  return null;
}

String? validarEmail(String? valor) {
  final texto = (valor ?? '').trim();
  if (texto.isEmpty) return 'Ingresa tu correo';
  if (!_formatoEmail.hasMatch(texto)) return 'Correo no válido (ej: nombre@gmail.com)';
  return null;
}

String? validarCelular(String? valor) {
  final texto = (valor ?? '').trim();
  if (texto.isEmpty) return 'Ingresa tu celular';
  if (!RegExp(r'^\d+$').hasMatch(texto)) return 'Solo números';
  if (texto.length != 9) return 'Debe tener 9 dígitos';
  if (!_celularPeru.hasMatch(texto)) return 'Debe empezar con 9';
  return null;
}

// Firebase pide minimo 6 caracteres; ademas se pide al menos una letra y
// un numero para que no sea tan facil de adivinar.
String? validarPassword(String? valor) {
  final texto = valor ?? '';
  if (texto.length < 6) return 'Mínimo 6 caracteres';
  if (!RegExp(r'[a-zA-Z]').hasMatch(texto) || !RegExp(r'\d').hasMatch(texto)) {
    return 'Usa al menos una letra y un número';
  }
  return null;
}
