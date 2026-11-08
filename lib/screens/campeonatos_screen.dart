import 'package:flutter/material.dart';
import '../models/campeonato.dart';
import '../models/usuario.dart';
import '../services/campeonato_service.dart';
import '../theme/app_theme.dart';
import 'crear_campeonato_screen.dart';
import 'detalle_campeonato_screen.dart';

// CampeonatosScreen: lista de campeonatos (HU-13).
//
// Todos los usuarios ven los campeonatos y su fixture. El organizador
// tiene ademas el boton + para crear uno (HU-13) y el capitan inscribe a
// su equipo desde el detalle (HU-14).
class CampeonatosScreen extends StatefulWidget {
  final Usuario usuario;

  const CampeonatosScreen({super.key, required this.usuario});

  @override
  State<CampeonatosScreen> createState() => _CampeonatosScreenState();
}

class _CampeonatosScreenState extends State<CampeonatosScreen> {
  late final Stream<List<Campeonato>> _campeonatos = CampeonatoService().observarCampeonatos();

  @override
  Widget build(BuildContext context) {
    final usuario = widget.usuario;
    return Scaffold(
      appBar: AppBar(title: const Text('Campeonatos')),
      floatingActionButton: usuario.esOrganizador
          ? FloatingActionButton(
              backgroundColor: AppColors.verdeLima,
              foregroundColor: AppColors.fondoOscuro,
              tooltip: 'Nuevo campeonato',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CrearCampeonatoScreen(organizador: usuario)),
              ),
              child: const Icon(Icons.add),
            )
          : null,
      body: StreamBuilder<List<Campeonato>>(
        stream: _campeonatos,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se pudieron cargar los campeonatos.', style: TextStyle(color: AppColors.error)),
            );
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final campeonatos = snapshot.data!;
          if (campeonatos.isEmpty) {
            return Center(
              child: Text(
                usuario.esOrganizador ? 'Crea el primer campeonato con el botón +.' : 'Todavía no hay campeonatos.',
                style: const TextStyle(color: AppColors.textoSecundario),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: campeonatos.length,
            itemBuilder: (context, index) {
              final c = campeonatos[index];
              final inscrito = c.equiposIds.contains(usuario.uid);
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                  leading: Icon(
                    c.estado == Campeonato.estadoFinalizado ? Icons.emoji_events : Icons.sports_soccer,
                    color: AppColors.verdeLima,
                  ),
                  title: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '${Campeonato.nombreFormato(c.formato)} · ${c.deporte}\n'
                    '${c.estadoTexto} · ${c.equiposIds.length}/${c.maxEquipos} equipos'
                    '${inscrito ? ' · Tu equipo está inscrito' : ''}',
                    style: const TextStyle(color: AppColors.textoSecundario),
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textoSecundario),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DetalleCampeonatoScreen(campeonatoId: c.id, usuario: usuario),
                    ),
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
