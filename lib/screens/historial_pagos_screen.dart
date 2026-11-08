import 'package:flutter/material.dart';
import '../models/pago.dart';
import '../services/pago_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import 'detalle_pago_screen.dart';

// HistorialPagosScreen: implementa HU-11 (Historial de pagos).
//
// Lista todos los pagos que hizo el jugador, del mas reciente al mas
// antiguo, con su estado (en revision, aprobado, rechazado o anulado).
// Se alimenta de los pagos registrados en HU-10 y de la revision del
// complejo en HU-12, y se actualiza sola cuando el complejo los revisa.
class HistorialPagosScreen extends StatefulWidget {
  const HistorialPagosScreen({super.key});

  @override
  State<HistorialPagosScreen> createState() => _HistorialPagosScreenState();
}

class _HistorialPagosScreenState extends State<HistorialPagosScreen> {
  late final Stream<List<Pago>> _pagos = PagoService().observarMisPagos();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de pagos'),
      ),
      body: StreamBuilder<List<Pago>>(
        stream: _pagos,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se pudo cargar tu historial.', style: TextStyle(color: AppColors.error)),
            );
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final pagos = snapshot.data!;
          if (pagos.isEmpty) {
            return const Center(
              child: Text('Todavía no tienes pagos.', style: TextStyle(color: AppColors.textoSecundario)),
            );
          }

          // Total de lo pagado y aprobado, como resumen arriba de la lista.
          final total = pagos
              .where((p) => p.estado == Pago.estadoAprobado)
              .fold<double>(0, (suma, p) => suma + p.monto);

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet, color: AppColors.verdeLima),
                  title: Text('S/ ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Total pagado y aprobado', style: TextStyle(color: AppColors.textoSecundario)),
                ),
              ),
              for (final pago in pagos)
                TarjetaPago(
                  pago: pago,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => DetallePagoScreen(pago: pago)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// TarjetaPago: fila de un pago en las listas (historial del jugador y
// validacion del complejo).
class TarjetaPago extends StatelessWidget {
  final Pago pago;
  final VoidCallback onTap;
  final bool mostrarJugador;

  const TarjetaPago({super.key, required this.pago, required this.onTap, this.mostrarJugador = false});

  static Color colorEstado(String estado) {
    switch (estado) {
      case Pago.estadoAprobado:
        return AppColors.verdeLima;
      case Pago.estadoRechazado:
        return AppColors.error;
      case Pago.estadoAnulado:
        return AppColors.textoSecundario;
      default:
        return Colors.amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorEstado(pago.estado);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        onTap: onTap,
        title: Text(
          mostrarJugador ? '${pago.usuarioNombre} · ${pago.canchaNombre}' : pago.canchaNombre,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${fechaTexto(fechaDesdeClave(pago.fecha))} · ${rangoHora(pago.hora)}\n'
          '${pago.medio} · S/ ${pago.monto.toStringAsFixed(2)}',
          style: const TextStyle(color: AppColors.textoSecundario),
        ),
        isThreeLine: true,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color),
          ),
          child: Text(pago.estadoTexto, style: TextStyle(color: color, fontSize: 12)),
        ),
      ),
    );
  }
}
