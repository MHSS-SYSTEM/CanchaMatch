import 'dart:async';
import 'package:flutter/material.dart';
import '../models/cancha.dart';
import '../models/reserva.dart';
import '../services/auth_service.dart';
import '../services/reserva_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import 'confirmar_reserva_screen.dart';

// Estado de un turno en el calendario.
enum EstadoTurno { libre, ocupado, mio, pasado }

// DisponibilidadScreen: implementa HU-07 (Ver disponibilidad en calendario).
//
// Muestra, para una cancha y una fecha, una grilla con todos sus turnos de
// una hora (segun el horario que definio el administrador en HU-21) y un
// color para cada uno:
//  - libre (borde verde),
//  - ocupado por otro jugador (gris),
//  - reservado por mi (verde lleno),
//  - ya paso (apagado).
// El estado se calcula a partir de las reservas reales guardadas en
// Firestore, y se actualiza solo cuando alguien reserva o cancela.
//
// Al tocar un turno libre empieza HU-08 (Reservar): el turno se bloquea
// 10 minutos y se abre la pantalla para confirmar.
//
// La misma pantalla se usa en HU-09 para reprogramar: si llega
// [reservaAReprogramar], tocar un turno libre mueve esa reserva ahi.
class DisponibilidadScreen extends StatefulWidget {
  final Cancha cancha;
  final Reserva? reservaAReprogramar;

  const DisponibilidadScreen({super.key, required this.cancha, this.reservaAReprogramar});

  @override
  State<DisponibilidadScreen> createState() => _DisponibilidadScreenState();
}

class _DisponibilidadScreenState extends State<DisponibilidadScreen> {
  final _reservaService = ReservaService();
  final _uid = AuthService().usuarioActual?.uid;

  // Cuantos dias hacia adelante se pueden consultar.
  static const _diasVisibles = 14;

  late DateTime _fecha;
  late Stream<List<Reserva>> _reservasDelDia;

  // Un bloqueo de 10 minutos puede vencer mientras la pantalla esta
  // abierta sin que cambie nada en Firestore. Este Timer redibuja la
  // grilla cada 30 segundos para que ese turno vuelva a verse libre.
  Timer? _refresco;

  // true mientras se esta bloqueando un turno (evita doble toque).
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    // Al reprogramar se empieza mostrando el dia de la reserva original.
    final original = widget.reservaAReprogramar;
    final hoy = soloFecha(DateTime.now());
    final fechaInicial = original == null ? hoy : fechaDesdeClave(original.fecha);
    _cambiarFecha(fechaInicial.isBefore(hoy) ? hoy : fechaInicial, redibujar: false);
    _refresco = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      // Si la pantalla quedo abierta y ya paso la medianoche, la fecha
      // elegida pasa a ser "ayer": se salta a hoy.
      final hoy = soloFecha(DateTime.now());
      if (_fecha.isBefore(hoy)) {
        _cambiarFecha(hoy);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refresco?.cancel();
    super.dispose();
  }

  // El Stream se guarda en el State (y no se crea dentro de build) para
  // que Firestore no se vuelva a consultar cada vez que la pantalla se
  // redibuja; solo cambia cuando el jugador elige otra fecha.
  void _cambiarFecha(DateTime fecha, {bool redibujar = true}) {
    _fecha = fecha;
    _reservasDelDia = _reservaService.observarReservasDelDia(widget.cancha.id, fechaClave(fecha));
    if (redibujar) setState(() {});
  }

  // _reservar: HU-08. Bloquea el turno y abre la pantalla de confirmacion.
  Future<void> _reservar(int hora) async {
    if (_procesando) return;
    setState(() => _procesando = true);
    final mensajero = ScaffoldMessenger.of(context);

    try {
      final reserva = await _reservaService.bloquearTurno(
        cancha: widget.cancha,
        fecha: fechaClave(_fecha),
        hora: hora,
      );
      if (!mounted) return;

      final confirmada = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ConfirmarReservaScreen(cancha: widget.cancha, reserva: reserva),
        ),
      );
      if (confirmada == true) {
        mensajero.showSnackBar(
          const SnackBar(content: Text('¡Reserva registrada! Queda pendiente de pago en el complejo.')),
        );
      }
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text(ReservaService.mensajeDeError(e))));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  // _reprogramar: HU-09. Pide confirmacion y mueve la reserva al turno
  // elegido; al terminar vuelve a "Mis reservas".
  Future<void> _reprogramar(int hora) async {
    final original = widget.reservaAReprogramar!;
    final nuevaFecha = fechaClave(_fecha);

    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.tarjeta,
        title: const Text('¿Mover tu reserva?'),
        content: Text(
          'De: ${fechaTexto(fechaDesdeClave(original.fecha))}, ${rangoHora(original.hora)}\n'
          'A: ${fechaTexto(_fecha)}, ${rangoHora(hora)}\n\n'
          'Tu horario anterior quedará libre para otros jugadores.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Sí, mover')),
        ],
      ),
    );
    if (seguro != true) return;
    if (!mounted) return;

    setState(() => _procesando = true);
    final navegador = Navigator.of(context);
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await _reservaService.reprogramarReserva(
        original: original,
        cancha: widget.cancha,
        nuevaFecha: nuevaFecha,
        nuevaHora: hora,
      );
      mensajero.showSnackBar(const SnackBar(content: Text('Reserva reprogramada.')));
      navegador.pop(true);
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text(ReservaService.mensajeDeError(e))));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _alTocarTurno(int hora, EstadoTurno estado) {
    switch (estado) {
      case EstadoTurno.libre:
        if (widget.reservaAReprogramar != null) {
          _reprogramar(hora);
        } else {
          _reservar(hora);
        }
      case EstadoTurno.mio:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Este horario ya es tuyo.')),
        );
      case EstadoTurno.ocupado:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Este horario ya está reservado. Elige otro.')),
        );
      case EstadoTurno.pasado:
        break;
    }
  }

  List<DateTime> get _fechas {
    final hoy = soloFecha(DateTime.now());
    return [for (var i = 0; i < _diasVisibles; i++) hoy.add(Duration(days: i))];
  }

  // _estadoDe: decide el color de un turno cruzando la hora con las
  // reservas de ese dia.
  EstadoTurno _estadoDe(int hora, List<Reserva> reservas) {
    final ahora = DateTime.now();
    final inicio = DateTime(_fecha.year, _fecha.month, _fecha.day, hora);
    if (!inicio.isAfter(ahora)) return EstadoTurno.pasado;

    for (final reserva in reservas) {
      if (reserva.hora == hora && reserva.ocupaHorario) {
        return reserva.usuarioId == _uid ? EstadoTurno.mio : EstadoTurno.ocupado;
      }
    }
    return EstadoTurno.libre;
  }

  Color _colorFondo(EstadoTurno estado) {
    switch (estado) {
      case EstadoTurno.mio:
        return AppColors.verdeLima;
      case EstadoTurno.ocupado:
        return AppColors.borde;
      case EstadoTurno.libre:
      case EstadoTurno.pasado:
        return AppColors.tarjeta;
    }
  }

  Color _colorTexto(EstadoTurno estado) {
    switch (estado) {
      case EstadoTurno.mio:
        return AppColors.fondoOscuro;
      case EstadoTurno.libre:
        return AppColors.textoClaro;
      case EstadoTurno.ocupado:
      case EstadoTurno.pasado:
        return AppColors.textoSecundario;
    }
  }

  String _etiqueta(EstadoTurno estado) {
    switch (estado) {
      case EstadoTurno.libre:
        return 'Libre';
      case EstadoTurno.ocupado:
        return 'Ocupado';
      case EstadoTurno.mio:
        return 'Tu reserva';
      case EstadoTurno.pasado:
        return 'Ya pasó';
    }
  }

  Widget _turno(int hora, EstadoTurno estado) {
    final contenido = Container(
      decoration: BoxDecoration(
        color: _colorFondo(estado),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: estado == EstadoTurno.libre ? AppColors.verdeLima : AppColors.borde,
          width: estado == EstadoTurno.libre ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(6),
      child: Opacity(
        opacity: estado == EstadoTurno.pasado ? 0.5 : 1,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              rangoHora(hora),
              textAlign: TextAlign.center,
              style: TextStyle(color: _colorTexto(estado), fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(_etiqueta(estado), style: TextStyle(color: _colorTexto(estado), fontSize: 12)),
          ],
        ),
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: estado == EstadoTurno.pasado ? null : () => _alTocarTurno(hora, estado),
      child: contenido,
    );
  }

  Widget _leyenda(Color fondo, Color borde, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: fondo,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borde),
          ),
        ),
        const SizedBox(width: 6),
        Text(texto, style: const TextStyle(color: AppColors.textoSecundario, fontSize: 12)),
      ],
    );
  }

  String _etiquetaFecha(DateTime fecha) {
    final diferencia = fecha.difference(soloFecha(DateTime.now())).inDays;
    if (diferencia == 0) return 'Hoy';
    if (diferencia == 1) return 'Mañana';
    return '${diasCortos[fecha.weekday - 1]} ${fecha.day}';
  }

  @override
  Widget build(BuildContext context) {
    final cancha = widget.cancha;

    return Scaffold(
      appBar: AppBar(title: Text(widget.reservaAReprogramar == null ? cancha.nombre : 'Reprogramar reserva')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.reservaAReprogramar != null)
            Container(
              color: AppColors.tarjeta,
              padding: const EdgeInsets.all(12),
              child: Text(
                'Elige el nuevo horario para tu reserva de '
                '${fechaTexto(fechaDesdeClave(widget.reservaAReprogramar!.fecha))}, '
                '${rangoHora(widget.reservaAReprogramar!.hora)}.',
                style: const TextStyle(color: AppColors.verdeLima),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '${cancha.tipoDeporte} · ${cancha.distrito} · S/ ${cancha.precioPorHora.toStringAsFixed(0)} / hora\n'
              'Atiende ${cancha.horarioTexto} · ${cancha.diasTexto}',
              style: const TextStyle(color: AppColors.textoSecundario),
            ),
          ),
          // Selector de fecha: los proximos 14 dias.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final fecha in _fechas)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_etiquetaFecha(fecha)),
                      selected: fecha == _fecha,
                      selectedColor: AppColors.verdeLima,
                      labelStyle: TextStyle(
                        color: fecha == _fecha ? AppColors.fondoOscuro : AppColors.textoClaro,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => _cambiarFecha(fecha),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(fechaTexto(_fecha), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _leyenda(AppColors.tarjeta, AppColors.verdeLima, 'Libre'),
                _leyenda(AppColors.borde, AppColors.borde, 'Ocupado'),
                _leyenda(AppColors.verdeLima, AppColors.verdeLima, 'Tu reserva'),
              ],
            ),
          ),
          if (_procesando) const LinearProgressIndicator(color: AppColors.verdeLima),
          Expanded(
            child: !cancha.abreEl(_fecha)
                ? const Center(
                    child: Text(
                      'La cancha no atiende este día.',
                      style: TextStyle(color: AppColors.textoSecundario),
                    ),
                  )
                : StreamBuilder<List<Reserva>>(
                    stream: _reservasDelDia,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text(
                            'No se pudo cargar la disponibilidad.',
                            style: TextStyle(color: AppColors.error),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final reservas = snapshot.data!;
                      final horas = cancha.horasDelDia;
                      if (horas.isEmpty) {
                        return const Center(
                          child: Text(
                            'Esta cancha no tiene un horario de atención válido.',
                            style: TextStyle(color: AppColors.textoSecundario),
                          ),
                        );
                      }
                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.5,
                        ),
                        itemCount: horas.length,
                        itemBuilder: (context, index) {
                          final hora = horas[index];
                          return _turno(hora, _estadoDe(hora, reservas));
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
