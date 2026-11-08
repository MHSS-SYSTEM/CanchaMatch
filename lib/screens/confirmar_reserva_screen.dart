import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/cancha.dart';
import '../models/pago.dart';
import '../models/reserva.dart';
import '../services/reserva_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';

// ConfirmarReservaScreen: segunda parte de HU-08 (Reservar una cancha) y
// HU-10 (Pagar con medios locales).
//
// Cuando el jugador toca un turno libre en el calendario, ese turno queda
// bloqueado 10 minutos a su nombre y se abre esta pantalla. Aqui ve el
// resumen y paga dentro de ese tiempo:
//  - Yape o Plin: paga desde su app y adjunta la captura del pago junto
//    con el numero de operacion.
//  - Tarjeta: llena los datos de la tarjeta y se simula el cobro.
// El cobro es SIMULADO (no se mueve dinero real). El pago queda "en
// revision" hasta que el dueño de la cancha lo valide (HU-12).
//
// Si se acaba el tiempo o sale sin pagar, el turno se libera.
class ConfirmarReservaScreen extends StatefulWidget {
  final Cancha cancha;
  final Reserva reserva;

  const ConfirmarReservaScreen({super.key, required this.cancha, required this.reserva});

  @override
  State<ConfirmarReservaScreen> createState() => _ConfirmarReservaScreenState();
}

class _ConfirmarReservaScreenState extends State<ConfirmarReservaScreen> {
  // Una foto de Firestore no puede pasar de 1 MB; con este limite el
  // documento del comprobante siempre entra con espacio de sobra.
  static const _maxBytesComprobante = 500 * 1024;

  final _reservaService = ReservaService();
  final _formKey = GlobalKey<FormState>();
  final _operacionCtrl = TextEditingController();
  final _titularCtrl = TextEditingController();
  final _tarjetaCtrl = TextEditingController();
  final _venceCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();

  String? _medioPago;
  Uint8List? _comprobante; // foto ya comprimida
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
    _operacionCtrl.dispose();
    _titularCtrl.dispose();
    _tarjetaCtrl.dispose();
    _venceCtrl.dispose();
    _cvvCtrl.dispose();
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

  bool get _esTarjeta => _medioPago == Pago.medioTarjeta;

  // _elegirComprobante: abre la galeria o la camara. image_picker ya
  // achica la foto (maxWidth) y baja su calidad (imageQuality), asi una
  // captura de Yape queda en unos 100 KB.
  Future<void> _elegirComprobante() async {
    final origen = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.tarjeta,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.verdeLima),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppColors.verdeLima),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (origen == null) return;

    try {
      final foto = await ImagePicker().pickImage(source: origen, maxWidth: 900, imageQuality: 55);
      if (foto == null) return;
      final bytes = await foto.readAsBytes();
      if (!mounted) return;
      if (bytes.length > _maxBytesComprobante) {
        setState(() => _error = 'La imagen es muy pesada. Prueba con una captura de pantalla.');
        return;
      }
      setState(() {
        _comprobante = bytes;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo abrir la imagen. Revisa los permisos de la app.');
    }
  }

  // _numeroValido: algoritmo de Luhn, el que usan los bancos para detectar
  // un numero de tarjeta mal escrito (no dice si la tarjeta existe).
  static bool _numeroValido(String numero) {
    var suma = 0;
    var duplicar = false;
    for (var i = numero.length - 1; i >= 0; i--) {
      var digito = int.parse(numero[i]);
      if (duplicar) {
        digito *= 2;
        if (digito > 9) digito -= 9;
      }
      suma += digito;
      duplicar = !duplicar;
    }
    return suma % 10 == 0;
  }

  String? _validarTarjeta(String? valor) {
    final numero = (valor ?? '').replaceAll(' ', '');
    if (numero.length != 16) return 'Debe tener 16 dígitos';
    if (!_numeroValido(numero)) return 'Número de tarjeta no válido';
    return null;
  }

  String? _validarVence(String? valor) {
    final partes = (valor ?? '').split('/');
    if (partes.length != 2) return 'Usa el formato MM/AA';
    final mes = int.tryParse(partes[0]);
    final anio = int.tryParse(partes[1]);
    if (mes == null || anio == null || mes < 1 || mes > 12) return 'Fecha no válida';
    // La tarjeta vale hasta el ultimo dia de ese mes.
    final vence = DateTime(2000 + anio, mes + 1);
    if (!vence.isAfter(DateTime.now())) return 'La tarjeta está vencida';
    return null;
  }

  Future<void> _confirmar() async {
    if (_medioPago == null) {
      setState(() => _error = 'Elige cómo vas a pagar.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (!_esTarjeta && _comprobante == null) {
      setState(() => _error = 'Adjunta la captura de tu pago.');
      return;
    }

    setState(() {
      _confirmando = true;
      _error = null;
    });

    try {
      final DatosPago datos;
      if (_esTarjeta) {
        // Cobro SIMULADO: se espera un momento como si respondiera el banco
        // y se genera un numero de operacion. Del numero de la tarjeta solo
        // se guardan los 4 ultimos digitos, nunca el numero completo.
        await Future.delayed(const Duration(seconds: 2));
        final numero = _tarjetaCtrl.text.replaceAll(' ', '');
        datos = DatosPago(
          medio: Pago.medioTarjeta,
          numeroOperacion: 'TAR-${100000 + Random().nextInt(900000)}',
          ultimosDigitos: numero.substring(numero.length - 4),
        );
      } else {
        datos = DatosPago(
          medio: _medioPago!,
          numeroOperacion: _operacionCtrl.text.trim(),
          comprobanteBase64: base64Encode(_comprobante!),
        );
      }
      await _reservaService.confirmarReserva(widget.reserva.id, datos);
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

  // Campos para Yape o Plin: numero de operacion y captura del pago.
  List<Widget> _camposBilletera() {
    return [
      Text(
        widget.cancha.numeroPago.isEmpty
            ? 'Paga S/ ${widget.reserva.precio.toStringAsFixed(2)} con $_medioPago al complejo y adjunta la captura.'
            : 'Paga S/ ${widget.reserva.precio.toStringAsFixed(2)} con $_medioPago al número del complejo y adjunta la captura.',
        style: const TextStyle(color: AppColors.textoSecundario),
      ),
      if (widget.cancha.numeroPago.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.tarjeta,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.verdeLima),
          ),
          child: Row(
            children: [
              const Icon(Icons.phone_android, color: AppColors.verdeLima),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${widget.cancha.numeroPago}\n${widget.cancha.nombre}',
                  style: AppTheme.textoCodigo.copyWith(fontSize: 16),
                ),
              ),
              IconButton(
                tooltip: 'Copiar número',
                icon: const Icon(Icons.copy, color: AppColors.textoSecundario),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.cancha.numeroPago));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Número copiado.')),
                  );
                },
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      TextFormField(
        controller: _operacionCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 12,
        decoration: const InputDecoration(labelText: 'Número de operación'),
        validator: (valor) =>
            (valor ?? '').trim().length < 6 ? 'Escribe el número de operación de tu pago' : null,
      ),
      if (_comprobante != null) ...[
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(_comprobante!, height: 220, fit: BoxFit.contain),
        ),
        const SizedBox(height: 8),
      ],
      OutlinedButton.icon(
        onPressed: _vencido || _confirmando ? null : _elegirComprobante,
        icon: const Icon(Icons.upload_file),
        label: Text(_comprobante == null ? 'Adjuntar captura del pago' : 'Cambiar captura'),
      ),
    ];
  }

  // Campos para tarjeta (cobro simulado).
  List<Widget> _camposTarjeta() {
    return [
      const Text(
        'Cobro simulado: no se realiza ningún cargo real a tu tarjeta.',
        style: TextStyle(color: AppColors.textoSecundario),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _titularCtrl,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nombre del titular'),
        validator: (valor) => (valor ?? '').trim().length < 3 ? 'Escribe el nombre del titular' : null,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _tarjetaCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(16)],
        decoration: const InputDecoration(labelText: 'Número de tarjeta (16 dígitos)'),
        validator: _validarTarjeta,
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: _venceCtrl,
              keyboardType: TextInputType.datetime,
              inputFormatters: [LengthLimitingTextInputFormatter(5)],
              decoration: const InputDecoration(labelText: 'Vence (MM/AA)'),
              validator: _validarVence,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _cvvCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
              decoration: const InputDecoration(labelText: 'CVV'),
              validator: (valor) => (valor ?? '').length != 3 ? '3 dígitos' : null,
            ),
          ),
        ],
      ),
    ];
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

    // Mientras se envia el pago no se puede salir de la pantalla.
    return PopScope(
      canPop: !_confirmando,
      child: Scaffold(
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
                'Tu pago quedará en revisión hasta que el complejo lo valide.',
                style: TextStyle(color: AppColors.textoSecundario),
              ),
              const SizedBox(height: 8),
              for (final medio in Pago.medios)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: medio,
                  groupValue: _medioPago,
                  activeColor: AppColors.verdeLima,
                  title: Text(medio),
                  onChanged: _vencido || _confirmando
                      ? null
                      : (valor) => setState(() {
                            _medioPago = valor;
                            _error = null;
                          }),
                ),
              if (_medioPago != null)
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _esTarjeta ? _camposTarjeta() : _camposBilletera(),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: AppColors.error)),
                ),
              const SizedBox(height: 16),
              // Si el tiempo se acaba mientras se envia el pago, se espera la
              // respuesta en vez de ofrecer volver.
              if (_vencido && !_confirmando)
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Volver al calendario'),
                )
              else
                ElevatedButton(
                  onPressed: _confirmando ? null : _confirmar,
                  child: _confirmando
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_esTarjeta ? 'Pagar y reservar' : 'Enviar pago y reservar'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
