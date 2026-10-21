import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'perfil_screen.dart';
import 'buscar_canchas_screen.dart';
import 'admin_canchas_screen.dart';
import 'mis_reservas_screen.dart';

// InicioScreen: pantalla que se ve despues de iniciar sesion. Es un menu
// con botones hacia las pantallas de cada HU, mas la opcion de cerrar
// sesion.
//
// Al abrirse lee el perfil del usuario para saber su rol: si es
// administrador, aparece ademas la opcion "Administrar canchas" (HU-21).
class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  final _authService = AuthService();
  bool _esAdmin = false;

  @override
  void initState() {
    super.initState();
    _cargarRol();
  }

  // _cargarRol: si falla (por ejemplo, sin internet) simplemente no se
  // muestra la opcion de admin; el resto del menu funciona igual.
  Future<void> _cargarRol() async {
    final uid = _authService.usuarioActual?.uid;
    if (uid == null) return;
    try {
      final usuario = await FirestoreService().obtenerPerfil(uid);
      if (mounted && usuario != null) setState(() => _esAdmin = usuario.esAdmin);
    } catch (_) {
      // Sin perfil no se puede saber el rol; se deja el menu de jugador.
    }
  }

  // Al volver de cualquier pantalla se vuelve a leer el rol, por si la
  // primera lectura fallo (por ejemplo, sin internet al abrir la app).
  Future<void> _ir(Widget pantalla) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla));
    if (mounted) _cargarRol();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CanchaMatch'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await _authService.cerrarSesion();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 12),
          const Text(
            '¿Qué quieres hacer?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textoClaro),
          ),
          const SizedBox(height: 20),
          _BotonMenu(
            icono: Icons.person,
            titulo: 'Mi perfil',
            subtitulo: 'Ver y editar tus datos',
            onTap: () => _ir(const PerfilScreen()),
          ),
          const SizedBox(height: 16),
          _BotonMenu(
            icono: Icons.sports_soccer,
            titulo: 'Buscar canchas',
            subtitulo: 'Ver canchas disponibles cerca de ti',
            onTap: () => _ir(const BuscarCanchasScreen()),
          ),
          const SizedBox(height: 16),
          _BotonMenu(
            icono: Icons.event_note,
            titulo: 'Mis reservas',
            subtitulo: 'Ver, cancelar o reprogramar tus reservas',
            onTap: () => _ir(const MisReservasScreen()),
          ),
          if (_esAdmin) ...[
            const SizedBox(height: 16),
            _BotonMenu(
              icono: Icons.admin_panel_settings,
              titulo: 'Administrar canchas',
              subtitulo: 'Crear, editar y desactivar canchas, horarios y precios',
              onTap: () => _ir(const AdminCanchasScreen()),
            ),
          ],
        ],
      ),
    );
  }
}

// _BotonMenu: tarjeta reutilizable para las opciones del menu principal.
class _BotonMenu extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _BotonMenu({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(icono, color: AppColors.verdeLima, size: 32),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitulo, style: const TextStyle(color: AppColors.textoSecundario)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textoSecundario),
        onTap: onTap,
      ),
    );
  }
}
