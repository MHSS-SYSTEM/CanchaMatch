import 'package:flutter/material.dart';
import '../models/cancha.dart';
import '../services/canchas_admin_service.dart';
import '../theme/app_theme.dart';
import 'editar_cancha_screen.dart';

// AdminCanchasScreen: implementa HU-21 (Gestion de horarios y canchas).
//
// Lista todas las canchas del complejo (activas y desactivadas). Desde
// aqui el administrador puede:
//  - crear una cancha nueva (boton +),
//  - editar una cancha (tocando la tarjeta): nombre, precio, horario, dias,
//    politica de cancelacion y ubicacion,
//  - activarla o desactivarla con el interruptor.
class AdminCanchasScreen extends StatelessWidget {
  const AdminCanchasScreen({super.key});

  void _abrirFormulario(BuildContext context, {Cancha? cancha}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditarCanchaScreen(cancha: cancha)),
    );
  }

  Future<void> _cambiarDisponible(BuildContext context, Cancha cancha, bool valor) async {
    try {
      await CanchasAdminService().cambiarDisponible(cancha.id, valor);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cambiar el estado de la cancha.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administrar canchas')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.verdeLima,
        foregroundColor: AppColors.fondoOscuro,
        tooltip: 'Nueva cancha',
        onPressed: () => _abrirFormulario(context),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Cancha>>(
        stream: CanchasAdminService().observarTodas(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No se pudieron cargar las canchas. Revisa que tu cuenta tenga rol de administrador.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final canchas = snapshot.data!;
          if (canchas.isEmpty) {
            return const Center(
              child: Text(
                'Todavía no hay canchas. Crea la primera con el botón +.',
                style: TextStyle(color: AppColors.textoSecundario),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: canchas.length,
            itemBuilder: (context, index) {
              final cancha = canchas[index];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  onTap: () => _abrirFormulario(context, cancha: cancha),
                  leading: Icon(
                    Icons.sports_soccer,
                    color: cancha.disponible ? AppColors.verdeLima : AppColors.textoSecundario,
                  ),
                  title: Text(
                    cancha.nombre,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: cancha.disponible ? AppColors.textoClaro : AppColors.textoSecundario,
                    ),
                  ),
                  subtitle: Text(
                    '${cancha.tipoDeporte} · ${cancha.distrito} · S/ ${cancha.precioPorHora.toStringAsFixed(0)} / hora\n'
                    '${cancha.horarioTexto} · ${cancha.diasTexto}'
                    '${cancha.disponible ? '' : '\nDesactivada'}',
                    style: const TextStyle(color: AppColors.textoSecundario),
                  ),
                  isThreeLine: true,
                  trailing: Switch(
                    value: cancha.disponible,
                    activeColor: AppColors.verdeLima,
                    onChanged: (valor) => _cambiarDisponible(context, cancha, valor),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
