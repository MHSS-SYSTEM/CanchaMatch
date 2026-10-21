import 'dart:async';
import 'package:flutter/material.dart';
import '../models/cancha.dart';
import '../models/reserva.dart';
import '../services/reserva_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';

// ConfirmarReservaScreen: segunda parte de HU-08 (Reservar una cancha).
//
// Cuando el jugador toca un turno libre en el calendario, ese turno queda
// bloqueado 10 minutos a su nombre y se abre esta pantalla. Aqui ve el
// resumen, elige el medio de pago y confirma. No hay pasarela de pago: la
// reserva queda como "pendiente de pago" y se paga en el complejo.
//
// Si se acaba el tiempo o sale sin confirmar, el turno se libera.
class ConfirmarReservaScreen extends StatefulWidget {
  final Cancha cancha;
  final Reserva reserva;

  const ConfirmarReservaScreen({super.key, required this.cancha, required this.reserva});

  @override
  State<ConfirmarReservaScreen> createState() => _ConfirmarReservaScreenState();
}

class _ConfirmarReservaScreenState extends State<ConfirmarReservaScreen> {
  static const _mediosPago = ['Yape', 'Plin', 'Efectivo en el complejo', 'Tarjeta en el complejo'];

  final _reservaService = ReservaService();

  String? _medioPago;
  bool _confirmando = false;
  bool _confirmada = false;
  String? _error;

  Timer? _timer;
  Duration _restante = Duration.zero;

  bool get _vencido => _restante <= Duration.zero;

  @override
  void initState() {
    super.initState();
    _actualizarRestante();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(_actualizarRestante);
      if (_vencido) _timer?.cancel();
    });
  }

  void _actualizarRestante() {
    final hasta = widget.reserva.bloqueadaHasta ?? DateTime.now();
    final diferencia = hasta.difference(DateTime.now());
    _restante = diferencia.isNegative ? Duration.zero : diferencia;
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Si el jugador se va sin confirmar, se suelta el turno enseguida para
    // que otro lo pueda tomar (si no, igual se libera al vencer el tiempo).
    if (!_confirmada) _reservaService.liberarBloqueo(widget.reserva.id);
    super.dispose();
  }

  String _formato(Duration d) {
    final minutos = d.inMinutes;
    final segundos = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutos:$segundos';
  }

  Future<void> _confirmar() async {
    if (_medioPago == null) {
      setState(() => _error = 'Elige cómo vas a pagar.');
      return;
    }

    setState(() {
      _confirmando = true;
      _error = null;
    });

    try {
      await _reservaService.confirmarReserva(widget.reserva.id, _medioPago!);
      _confirmada = true;
      _timer?.cancel();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = ReservaService.mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  Widget _fila(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(etiqueta, style: const TextStyle(color: AppColors.textoSecundario)),
          ),
          Expanded(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reserva = widget.reserva;
    final cancha = widget.cancha;

    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar reserva')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Cuenta regresiva del bloqueo de 10 minutos.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.tarjeta,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _vencido ? AppColors.error : AppColors.verdeLima),
              ),
              child: Column(
                children: [
                  Text(
                    _vencido ? 'Se acabó el tiempo' : 'Te guardamos este horario por',
                    style: const TextStyle(color: AppColors.textoSecundario),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _vencido ? '0:00' : _formato(_restante),
                    style: AppTheme.textoCodigo.copyWith(
                      fontSize: 34,
                      color: _vencido ? AppColors.error : AppColors.verdeLima,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _fila('Cancha', cancha.nombre),
                    _fila('Dirección', '${cancha.direccion}, ${cancha.distrito}'),
                    _fila('Fecha', fechaTexto(reserva.inicio)),
                    _fila('Horario', rangoHora(reserva.hora)),
                    _fila('Precio', 'S/ ${reserva.precio.toStringAsFixed(2)}'),
                    _fila(
                      'Cancelación',
                      'Hasta ${reserva.horasLimiteCancelacion} '
                          '${reserva.horasLimiteCancelacion == 1 ? 'hora' : 'horas'} antes del partido',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('¿Cómo vas a pagar?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'El pago se hace en el complejo. Tu reserva quedará como pendiente de pago.',
              style: TextStyle(color: AppColors.textoSecundario),
            ),
            const SizedBox(height: 8),
            for (final medio in _mediosPago)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: medio,
                groupValue: _medioPago,
                activeColor: AppColors.verdeLima,
                title: Text(medio),
                onChanged: _vencido ? null : (valor) => setState(() => _medioPago = valor),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: AppColors.error)),
              ),
            const SizedBox(height: 16),
            if (_vencido)
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Volver al calendario'),
              )
            else
              ElevatedButton(
                onPressed: _confirmando ? null : _confirmar,
                child: _confirmando
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Confirmar reserva'),
              ),
          ],
        ),
      ),
    );
  }
}
