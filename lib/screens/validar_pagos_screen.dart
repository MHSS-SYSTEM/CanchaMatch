import 'package:flutter/material.dart';
import '../models/pago.dart';
import '../services/pago_service.dart';
import '../theme/app_theme.dart';
import 'detalle_pago_screen.dart';
import 'historial_pagos_screen.dart';

// ValidarPagosScreen: implementa HU-12 (Validar pagos manuales).
//
// La ve el dueño del complejo (organizador) con los pagos de SUS canchas,
// o el administrador general con los de todas. Tiene dos pestañas:
//  - Por revisar: pagos "en revision". Al abrir uno ve el comprobante y
//    lo aprueba (la reserva pasa a confirmada) o lo rechaza (la reserva
//    se cancela y el horario se libera).
//  - Revisados: los que ya se aprobaron, rechazaron o se anularon.
class ValidarPagosScreen extends StatefulWidget {
  final bool esAdmin;

  const ValidarPagosScreen({super.key, this.esAdmin = false});

  @override
  State<ValidarPagosScreen> createState() => _ValidarPagosScreenState();
}

class _ValidarPagosScreenState extends State<ValidarPagosScreen> {
  late final Stream<List<Pago>> _pagos = PagoService().observarPagosDelComplejo(esAdmin: widget.esAdmin);

  Widget _lista(List<Pago> pagos, String vacio) {
    if (pagos.isEmpty) {
      return Center(child: Text(vacio, style: const TextStyle(color: AppColors.textoSecundario)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: pagos.length,
      itemBuilder: (context, index) {
        final pago = pagos[index];
        return TarjetaPago(
          pago: pago,
          mostrarJugador: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DetallePagoScreen(pago: pago, puedeRevisar: true)),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Validar pagos'),
          bottom: const TabBar(
            indicatorColor: AppColors.verdeLima,
            labelColor: AppColors.verdeLima,
            unselectedLabelColor: AppColors.textoSecundario,
            tabs: [Tab(text: 'Por revisar'), Tab(text: 'Revisados')],
          ),
        ),
        body: StreamBuilder<List<Pago>>(
          stream: _pagos,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text('No se pudieron cargar los pagos.', style: TextStyle(color: AppColors.error)),
              );
            }
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final pagos = snapshot.data!;
            final porRevisar = pagos.where((p) => p.estado == Pago.estadoEnRevision).toList();
            final revisados = pagos.where((p) => p.estado != Pago.estadoEnRevision).toList();
            return TabBarView(
              children: [
                _lista(porRevisar, 'No hay pagos por revisar.'),
                _lista(revisados, 'Todavía no revisaste pagos.'),
              ],
            );
          },
        ),
      ),
    );
  }
}
