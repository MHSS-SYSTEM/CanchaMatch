import 'dart:async';
import 'package:flutter/material.dart';
import '../models/cancha.dart';
import '../models/reserva.dart';
import '../services/reserva_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import 'disponibilidad_screen.dart';

// MisReservasScreen: implementa HU-09 (Cancelar o reprogramar reserva).
//
// Lista las reservas confirmadas del jugador que todavia no se juegan.
// En cada una puede:
//  - Cancelar: libera el horario.
//  - Reprogramar: elige otro horario libre de la misma cancha; el horario
//    original queda libre.
// Antes de cualquiera de las dos se le muestra la politica de cancelacion
// del complejo, y si ya paso el limite de horas, no se le deja continuar.
class MisReservasScreen extends StatefulWidget {
  const MisReservasScreen({super.key});

  @override
  State<MisReservasScreen> createState() => _MisReservasScreenState();
}

class _MisReservasScreenState extends State<MisReservasScreen> {
  final _reservaService = ReservaService();
  late final Stream<List<Reserva>> _misReservas = _reservaService.observarMisReservas();

  bool _procesando = false;

  // Redibuja cada minuto para que una reserva que ya empezo deje de
  // aparecer aunque la pantalla siga abierta.
  Timer? _refresco;

  @override
  void initState() {
    super.initState();
    _refresco = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresco?.cancel();
    super.dispose();
  }

  void _mostrarMensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  // _verPolitica: trae la cancha, muestra su politica y devuelve la cancha
  // solo si el jugador acepta continuar y todavia esta dentro del plazo.
  Future<Cancha?> _verPolitica(Reserva reserva, String accion) async {
    setState(() => _procesando = true);
    Cancha? cancha;
    try {
      cancha = await _reservaService.obtenerCancha(reserva.canchaId);
    } catch (_) {
      cancha = null;
    }
    if (!mounted) return null;
    setState(() => _procesando = false);

    if (cancha == null) {
      _mostrarMensaje('No se pudo cargar la información de la cancha.');
      return null;
    }
    final datosCancha = cancha;

    final permitido = ReservaService.dentroDePolitica(reserva);
    final horas = reserva.horasLimiteCancelacion;
    final continuar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.tarjeta,
        title: const Text('Política de cancelación'),
        content: Text(
          '${datosCancha.politicaParaMostrar}\n'
          'Para esta reserva: hasta $horas ${horas == 1 ? 'hora' : 'horas'} antes del partido.\n\n'
          '${permitido ? '¿Quieres $accion tu reserva?' : 'Ya pasó el plazo, así que esta reserva no se puede $accion.'}',
        ),
        actions: permitido
            ? [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Volver')),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('Sí, $accion'),
                ),
              ]
            : [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Entendido')),
              ],
      ),
    );

    return (continuar == true && permitido) ? datosCancha : null;
  }

  Future<void> _cancelar(Reserva reserva) async {
    final cancha = await _verPolitica(reserva, 'cancelar');
    if (cancha == null) return;
    if (!mounted) return;

    setState(() => _procesando = true);
    try {
      await _reservaService.cancelarReserva(reserva);
      if (mounted) _mostrarMensaje('Reserva cancelada. El horario quedó libre.');
    } catch (e) {
      if (mounted) _mostrarMensaje(ReservaService.mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _reprogramar(Reserva reserva) async {
    final cancha = await _verPolitica(reserva, 'reprogramar');
    if (cancha == null) return;
    if (!mounted) return;
    if (!cancha.disponible) {
      _mostrarMensaje('Esta cancha fue desactivada, así que ya no se puede reprogramar. Puedes cancelar tu reserva.');
      return;
    }

    // Se reutiliza el calendario de HU-07 en modo "reprogramar".
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DisponibilidadScreen(cancha: cancha, reservaAReprogramar: reserva),
      ),
    );
  }

  Widget _tarjeta(Reserva reserva) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sports_soccer, color: AppColors.verdeLima),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reserva.canchaNombre,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${fechaTexto(reserva.inicio)} · ${rangoHora(reserva.hora)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'S/ ${reserva.precio.toStringAsFixed(2)} · ${reserva.medioPago ?? 'Sin medio de pago'} · Pendiente de pago',
              style: const TextStyle(color: AppColors.textoSecundario),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _procesando ? null : () => _reprogramar(reserva),
                    child: const Text('Reprogramar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                    onPressed: _procesando ? null : () => _cancelar(reserva),
                    child: const Text('Cancelar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis reservas')),
      body: Column(
        children: [
          if (_procesando) const LinearProgressIndicator(color: AppColors.verdeLima),
          Expanded(
            child: StreamBuilder<List<Reserva>>(
              stream: _misReservas,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        ReservaService.mensajeDeError(snapshot.error!),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Solo las que todavia no empiezan, de la mas cercana a la mas
                // lejana. Se recalcula en cada refresco (ver _refresco).
                final ahora = DateTime.now();
                final reservas = snapshot.data!.where((r) => r.inicio.isAfter(ahora)).toList()
                  ..sort((a, b) => a.inicio.compareTo(b.inicio));
                if (reservas.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No tienes reservas próximas.\nBusca una cancha y reserva un horario.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textoSecundario),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: reservas.length,
                  itemBuilder: (context, index) => _tarjeta(reservas[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
