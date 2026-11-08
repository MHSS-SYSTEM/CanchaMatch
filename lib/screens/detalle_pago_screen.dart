import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/pago.dart';
import '../services/pago_service.dart';
import '../services/reserva_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';

// DetallePagoScreen: muestra un pago con su comprobante.
//
//  - El jugador la abre desde su historial (HU-11) para ver el estado.
//  - El dueño de la cancha la abre desde "Validar pagos" (HU-12): si el
//    pago esta en revision, ve los botones para aprobarlo o rechazarlo.
class DetallePagoScreen extends StatefulWidget {
  final Pago pago;

  // puedeRevisar: true solo cuando la abre el dueño de la cancha o el
  // administrador. Las reglas de Firestore igual impiden que un jugador
  // apruebe su propio pago.
  final bool puedeRevisar;

  const DetallePagoScreen({super.key, required this.pago, this.puedeRevisar = false});

  @override
  State<DetallePagoScreen> createState() => _DetallePagoScreenState();
}

class _DetallePagoScreenState extends State<DetallePagoScreen> {
  final _pagoService = PagoService();
  late final Future<String?> _comprobante =
      widget.pago.tieneComprobante ? _pagoService.obtenerComprobante(widget.pago.id) : Future.value(null);

  bool _procesando = false;

  Future<void> _aprobar() async {
    await _ejecutar(() => _pagoService.aprobar(widget.pago), 'Pago aprobado. La reserva quedó confirmada.');
  }

  Future<void> _rechazar() async {
    final motivo = await showDialog<String>(context: context, builder: (_) => const _DialogoMotivo());
    if (motivo == null || !mounted) return;
    await _ejecutar(
      () => _pagoService.rechazar(widget.pago, motivo),
      'Pago rechazado. El horario quedó libre.',
    );
  }

  Future<void> _ejecutar(Future<void> Function() accion, String exito) async {
    setState(() => _procesando = true);
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await accion();
      mensajero.showSnackBar(SnackBar(content: Text(exito)));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text(ReservaService.mensajeDeError(e))));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Widget _fila(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(etiqueta, style: const TextStyle(color: AppColors.textoSecundario)),
          ),
          Expanded(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pago = widget.pago;
    final enRevision = pago.estado == Pago.estadoEnRevision;

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del pago')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _fila('Estado', pago.estadoTexto),
                  if (pago.motivoRechazo != null && pago.estado == Pago.estadoRechazado)
                    _fila('Motivo', pago.motivoRechazo!),
                  _fila('Jugador', pago.usuarioNombre),
                  _fila('Cancha', pago.canchaNombre),
                  _fila('Partido', '${fechaTexto(fechaDesdeClave(pago.fecha))} · ${rangoHora(pago.hora)}'),
                  _fila('Monto', 'S/ ${pago.monto.toStringAsFixed(2)}'),
                  _fila('Medio', pago.ultimosDigitos == null ? pago.medio : '${pago.medio} •••• ${pago.ultimosDigitos}'),
                  _fila('N° operación', pago.numeroOperacion),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (pago.tieneComprobante) ...[
            const Text('Comprobante', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            FutureBuilder<String?>(
              future: _comprobante,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final imagen = snapshot.data;
                if (snapshot.hasError || imagen == null) {
                  return const Text(
                    'No se pudo cargar el comprobante.',
                    style: TextStyle(color: AppColors.error),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(base64Decode(imagen), fit: BoxFit.contain),
                );
              },
            ),
          ] else
            const Text(
              'Pago con tarjeta: el comprobante es el número de operación.',
              style: TextStyle(color: AppColors.textoSecundario),
            ),
          if (widget.puedeRevisar && enRevision) ...[
            const SizedBox(height: 24),
            if (_procesando) const LinearProgressIndicator(color: AppColors.verdeLima),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _procesando ? null : _aprobar,
              child: const Text('Aprobar pago'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: _procesando ? null : _rechazar,
              child: const Text('Rechazar pago'),
            ),
          ],
        ],
      ),
    );
  }
}

// _DialogoMotivo: pide el motivo del rechazo. Es un StatefulWidget para
// que su campo de texto se libere recien cuando el dialogo se cierra.
class _DialogoMotivo extends StatefulWidget {
  const _DialogoMotivo();

  @override
  State<_DialogoMotivo> createState() => _DialogoMotivoState();
}

class _DialogoMotivoState extends State<_DialogoMotivo> {
  final _motivoCtrl = TextEditingController();

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.tarjeta,
      title: const Text('Rechazar pago'),
      content: TextField(
        controller: _motivoCtrl,
        autofocus: true,
        maxLength: 120,
        decoration: const InputDecoration(labelText: 'Motivo (lo verá el jugador)'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Volver')),
        TextButton(
          onPressed: () {
            final texto = _motivoCtrl.text.trim();
            Navigator.of(context).pop(texto.isEmpty ? 'El pago no se encontró.' : texto);
          },
          child: const Text('Rechazar', style: TextStyle(color: AppColors.error)),
        ),
      ],
    );
  }
}
