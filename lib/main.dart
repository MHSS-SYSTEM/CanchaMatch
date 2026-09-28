import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/inicio_screen.dart';

// main(): punto de entrada de toda la app.
//
// WidgetsFlutterBinding.ensureInitialized() se necesita porque
// Firebase.initializeApp() es asincrono y corre ANTES de que Flutter
// arranque su motor grafico; sin esta linea, Firebase podria fallar en
// algunos dispositivos/plataformas.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Conecta la app con el proyecto de Firebase usando la configuracion
  // que viene en android/app/google-services.json (ya colocado en el
  // proyecto). A partir de aqui, FirebaseAuth.instance y
  // FirebaseFirestore.instance ya funcionan en cualquier parte de la app.
  await Firebase.initializeApp();

  runApp(const CanchaMatchApp());
}

// CanchaMatchApp: widget raiz. Define el tema visual global y decide cual
// es la primera pantalla que se muestra, segun si ya hay una sesion
// iniciada o no.
class CanchaMatchApp extends StatelessWidget {
  const CanchaMatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CanchaMatch',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.tema,
      // AuthGate decide la pantalla inicial (ver clase abajo).
      home: const AuthGate(),
    );
  }
}

// AuthGate: revisa si Firebase Auth ya tiene un usuario con sesion
// iniciada (por ejemplo, si el usuario cerro la app sin cerrar sesion) y
// manda directo a InicioScreen; si no hay nadie logueado, muestra
// LoginScreen. Es el "portero" que decide por donde entra el usuario.
//
// Si hay sesion pero la cuenta nunca verifico su codigo OTP (HU-01), se
// cierra esa sesion y se muestra el login, donde se le pedira verificar.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authService = AuthService();
  late final Future<bool> _sesionValida = _revisarSesion();

  Future<bool> _revisarSesion() async {
    final usuario = _authService.usuarioActual;
    if (usuario == null) return false;
    try {
      final verificado = await _authService.estaVerificado(usuario.uid);
      if (!verificado) await _authService.cerrarSesion();
      return verificado;
    } catch (_) {
      // Sin conexion no se puede revisar: se respeta la sesion guardada.
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _sesionValida,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data! ? const InicioScreen() : const LoginScreen();
      },
    );
  }
}
