import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'perfil_screen.dart';

// InicioScreen: pantalla que se ve despues de iniciar sesion. Es solo un
// menu simple con botones hacia HU-05 (perfil) y HU-06 (buscar canchas),
// mas la opcion de cerrar sesion. No es una HU en si misma, es el punto
// de entrada a las dos pantallas que si son HU.
class InicioScreen extends StatelessWidget {
  const InicioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('CanchaMatch'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await authService.cerrarSesion();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PerfilScreen()),
              )
              ),
          ],
        ),
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
