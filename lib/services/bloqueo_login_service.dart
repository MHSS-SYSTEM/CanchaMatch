import 'package:shared_preferences/shared_preferences.dart';

// BloqueoLoginService: implementa el bloqueo temporal de HU-02.
//
// Cuenta los intentos fallidos de inicio de sesion por cada correo y,
// al llegar a 5, bloquea ese correo durante unos minutos. Los datos se
// guardan en el propio celular con SharedPreferences (un pequeño
// almacenamiento clave/valor que sobrevive aunque se cierre la app).
//
// Se guarda en el celular y no en Firestore porque, antes de iniciar
// sesion, el usuario todavia no esta autenticado: para escribir en
// Firestore sin sesion habria que abrir las reglas de seguridad a
// cualquiera, y cualquiera podria bloquear o desbloquear cuentas ajenas.
class BloqueoLoginService {
  static const int maxIntentos = 5;
  static const Duration duracionBloqueo = Duration(minutes: 5);

  // El correo se normaliza (sin espacios y en minusculas) para que
  // "Juan@Mail.com" y "juan@mail.com " cuenten como el mismo usuario.
  String _normalizar(String email) => email.trim().toLowerCase();

  String _claveIntentos(String email) => 'login_intentos_${_normalizar(email)}';
  String _claveBloqueo(String email) => 'login_bloqueado_hasta_${_normalizar(email)}';

  // tiempoRestanteBloqueo: si el correo esta bloqueado devuelve cuanto
  // falta para que se desbloquee; si no lo esta, devuelve null. Cuando el
  // bloqueo ya vencio, limpia los datos para que empiece de cero.
  Future<Duration?> tiempoRestanteBloqueo(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final hastaMs = prefs.getInt(_claveBloqueo(email));
    if (hastaMs == null) return null;

    final restante = DateTime.fromMillisecondsSinceEpoch(hastaMs).difference(DateTime.now());
    if (restante <= Duration.zero) {
      await reiniciar(email);
      return null;
    }
    return restante;
  }

  // registrarIntentoFallido: suma un intento fallido y devuelve cuantos
  // intentos le quedan. Si devuelve 0, el correo acaba de quedar
  // bloqueado por [duracionBloqueo].
  Future<int> registrarIntentoFallido(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final intentos = (prefs.getInt(_claveIntentos(email)) ?? 0) + 1;

    if (intentos >= maxIntentos) {
      final hasta = DateTime.now().add(duracionBloqueo);
      await prefs.setInt(_claveBloqueo(email), hasta.millisecondsSinceEpoch);
      await prefs.remove(_claveIntentos(email));
      return 0;
    }

    await prefs.setInt(_claveIntentos(email), intentos);
    return maxIntentos - intentos;
  }

  // reiniciar: borra el contador y el bloqueo de ese correo. Se llama
  // cuando el inicio de sesion sale bien o cuando el bloqueo ya vencio.
  Future<void> reiniciar(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_claveIntentos(email));
    await prefs.remove(_claveBloqueo(email));
  }
}
