import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/usuario.dart';

// AuthService: agrupa todo lo relacionado a crear cuenta, iniciar sesion
// y el codigo OTP de verificacion (HU-01).
//
// IMPORTANTE sobre el OTP: en esta etapa el codigo OTP es SIMULADO, no
// se envia por SMS ni correo real. Por eso aqui el codigo se genera en el
// propio celular (con Random) y se muestra en pantalla al usuario en vez
// de enviarse de verdad. Es solo para demostrar el flujo de verificacion.
//
// AuthService es un singleton (siempre devuelve la misma instancia,
// aunque se escriba "AuthService()" en varias pantallas distintas). Esto
// evita que dos pantallas terminen con copias separadas de la clase sin
// enterarse de lo que hizo la otra.
class AuthService {
  static final AuthService _instancia = AuthService._interno();

  factory AuthService() => _instancia;

  AuthService._interno();

  // Instancias de Firebase. FirebaseAuth maneja usuario/contraseña;
  // Firestore guarda los datos extra del perfil (nombre, telefono, etc.)
  // que Firebase Auth no guarda por si solo.
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // GoogleSignIn abre la ventana del celular para elegir una cuenta de
  // Google. Se usa en iniciarSesionConGoogle().
  final GoogleSignIn _google = GoogleSignIn();

  // Devuelve el usuario que tiene la sesion iniciada ahora mismo (o null
  // si nadie inicio sesion). Sirve para saber, por ejemplo, si hay que
  // mandar a la pantalla de login o directo a la app.
  User? get usuarioActual => _auth.currentUser;

  // Genera un codigo OTP simulado de 6 digitos (ej: "483920").
  // Se llama justo despues de crear la cuenta en registrarUsuario().
  //
  // El codigo no se guarda como campo de la clase: se retorna aqui, la
  // pantalla de registro lo pasa a la pantalla de verificacion, y
  // verificarOtp() lo recibe como parametro para compararlo. Asi no
  // importa si cada pantalla tiene su propia instancia del service.
  String _generarOtpSimulado() {
    final random = Random();
    // 100000-999999 asegura siempre 6 digitos (nunca empieza en 0).
    final codigo = 100000 + random.nextInt(900000);
    return codigo.toString();
  }

  // registrarUsuario: implementa HU-01 (Registro de usuario).
  // Pasos:
  //  1. Crea la cuenta en Firebase Authentication con email y contraseña.
  //  2. Crea el documento del usuario en Firestore (coleccion "usuarios")
  //     con verificado=false.
  //  3. Genera el OTP simulado y lo retorna para que la pantalla lo
  //     muestre (por ejemplo, en un SnackBar o un texto en pantalla).
  //
  // Si el paso 2 falla (por ejemplo, se corta la conexion justo despues
  // de crear la cuenta), se borra la cuenta de Firebase Auth que se
  // acababa de crear. Sin esto, quedaria una cuenta "fantasma": existe en
  // Authentication pero sin perfil en Firestore, y el usuario nunca
  // podria volver a registrarse con ese mismo correo.
  //
  // Retorna un mapa con el uid creado y el otp generado, para que la
  // pantalla de registro pueda navegar a la pantalla de verificacion.
  Future<Map<String, String>> registrarUsuario({
    required String nombre,
    required String apellido,
    required String email,
    required String telefono,
    required String password,
  }) async {
    // Paso 1: crear la cuenta en Firebase Auth.
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final nuevoUsuarioFirebase = credential.user;
    if (nuevoUsuarioFirebase == null) {
      throw Exception('No se pudo crear la cuenta, intentalo de nuevo.');
    }
    final uid = nuevoUsuarioFirebase.uid;

    // Paso 2: crear el documento de perfil en Firestore, sin verificar aun.
    final nuevoUsuario = Usuario(
      uid: uid,
      nombre: nombre,
      apellido: apellido,
      email: email,
      telefono: telefono,
      verificado: false,
    );

    try {
      await _db.collection('usuarios').doc(uid).set(nuevoUsuario.toMap());
    } catch (e) {
      // No se pudo guardar el perfil: se elimina la cuenta recien creada
      // para no dejar una cuenta sin datos que bloquee un futuro intento
      // de registro con el mismo correo.
      await nuevoUsuarioFirebase.delete();
      rethrow;
    }

    // Paso 3: generar el OTP simulado (no se envia por SMS/correo real).
    final otp = _generarOtpSimulado();

    return {'uid': uid, 'otp': otp};
  }

  // verificarOtp: compara el codigo que el usuario escribio en pantalla
  // contra el codigo que se genero al registrarse (otpEsperado, que la
  // pantalla recibe como parametro y nos pasa aqui). Si coincide, marca
  // al usuario como verificado en Firestore.
  //
  // Retorna true si el codigo es correcto, false si no.
  Future<bool> verificarOtp(String uid, String codigoIngresado, String otpEsperado) async {
    final esCorrecto = codigoIngresado.trim() == otpEsperado;
    if (esCorrecto) {
      await _db.collection('usuarios').doc(uid).update({'verificado': true});
    }
    return esCorrecto;
  }

  // estaVerificado: indica si la cuenta ya confirmo su codigo OTP (HU-01).
  // Se revisa al iniciar sesion (HU-02) y al abrir la app: una cuenta que
  // no termino la verificacion no puede entrar.
  Future<bool> estaVerificado(String uid) async {
    final doc = await _db.collection('usuarios').doc(uid).get();
    return doc.exists && doc.data()?['verificado'] == true;
  }

  // nuevoOtpSimulado: genera otro codigo para quien no alcanzo a
  // verificar su cuenta cuando se registro.
  String nuevoOtpSimulado() => _generarOtpSimulado();

  // iniciarSesion: login normal con email y contraseña (Firebase Auth ya
  // trae toda la logica de validar credenciales, no hay que programarla).
  Future<UserCredential> iniciarSesion({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // iniciarSesionConGoogle: entra con una cuenta de Google del celular.
  // Google ya comprobo que el correo le pertenece a esa persona, por eso
  // estas cuentas no pasan por el codigo OTP: su perfil queda con
  // verificado=true.
  //
  // Retorna false si el usuario cerro la ventana de Google sin elegir
  // ninguna cuenta (no es un error, simplemente no se inicia sesion).
  Future<bool> iniciarSesionConGoogle() async {
    final cuentaGoogle = await _google.signIn();
    if (cuentaGoogle == null) return false;

    final tokens = await cuentaGoogle.authentication;
    final credencial = GoogleAuthProvider.credential(
      accessToken: tokens.accessToken,
      idToken: tokens.idToken,
    );

    final resultado = await _auth.signInWithCredential(credencial);
    final usuario = resultado.user;
    if (usuario == null) {
      throw Exception('No se pudo iniciar sesion con Google.');
    }

    try {
      await _prepararPerfilGoogle(usuario);
    } catch (e) {
      // Sin perfil no se puede usar la app: se cierra la sesion para que
      // lo intente de nuevo en vez de quedar a medias.
      await cerrarSesion();
      rethrow;
    }
    return true;
  }

  // _prepararPerfilGoogle: la primera vez que alguien entra con Google se
  // crea su documento en "usuarios" con el nombre de su cuenta de Google.
  // El telefono queda vacio y lo completa despues en su perfil (HU-05).
  // Si ya tenia un perfil sin verificar (se registro con ese correo pero
  // no confirmo el codigo), se marca como verificado.
  Future<void> _prepararPerfilGoogle(User usuario) async {
    final ref = _db.collection('usuarios').doc(usuario.uid);
    final doc = await ref.get();

    if (!doc.exists) {
      final partes = (usuario.displayName ?? '').trim().split(RegExp(r'\s+'));
      final nuevoUsuario = Usuario(
        uid: usuario.uid,
        nombre: partes.first,
        apellido: partes.skip(1).join(' '),
        email: usuario.email ?? '',
        telefono: '',
        verificado: true,
      );
      await ref.set(nuevoUsuario.toMap());
    } else if (doc.data()?['verificado'] != true) {
      await ref.update({'verificado': true});
    }
  }

  // cerrarSesion: cierra la sesion actual (boton "Cerrar sesion" en perfil).
  // Si entro con Google, tambien se cierra alli, asi la proxima vez puede
  // elegir otra cuenta.
  Future<void> cerrarSesion() async {
    try {
      await _google.signOut();
    } catch (_) {
      // Si no habia sesion de Google no hay nada que cerrar.
    }
    await _auth.signOut();
  }

  // mensajeError: traduce los errores de Firebase Auth a un mensaje en
  // español que se le puede mostrar directamente al usuario, en vez de
  // dejar que la pantalla muestre el texto tecnico crudo del error.
  // La usan tanto login_screen como registro_screen.
  String mensajeError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return 'Ese correo ya tiene una cuenta registrada.';
        case 'invalid-email':
          return 'El correo no es válido.';
        case 'weak-password':
          return 'La contraseña es muy débil.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Correo o contraseña incorrectos.';
        case 'network-request-failed':
          return 'No hay conexión a internet. Revisa tu conexión e inténtalo de nuevo.';
        case 'account-exists-with-different-credential':
          return 'Ese correo ya tiene una cuenta. Inicia sesión con tu correo y contraseña.';
        case 'too-many-requests':
          return 'Demasiados intentos. Espera un momento e inténtalo de nuevo.';
        default:
          return 'Ocurrió un problema, inténtalo de nuevo.';
      }
    }
    return 'Ocurrió un problema, inténtalo de nuevo.';
  }
}
