import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/pago.dart';
import '../models/reserva.dart';
import 'reserva_service.dart';

// PagoService: lectura y revision de la coleccion "pagos".
//
//  - HU-11: historial de pagos del jugador.
//  - HU-12: el dueño de la cancha (o el administrador general) ve los
//    pagos por revisar, mira el comprobante y lo aprueba o rechaza.
//
// El pago se CREA en ReservaService.confirmarReserva (HU-10), porque se
// guarda en la misma transaccion que confirma la reserva.
class PagoService {
  static final PagoService _instancia = PagoService._interno();

  factory PagoService() => _instancia;

  PagoService._interno();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _pagos => _db.collection('pagos');

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw ReservaException('Tu sesión expiró. Vuelve a iniciar sesión.');
    return uid;
  }

  // Ordena del mas reciente al mas antiguo. Se ordena aqui y no con
  // orderBy en la consulta para no tener que crear indices en Firestore.
  static List<Pago> _ordenar(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final lista = snapshot.docs.map((doc) => Pago.fromMap(doc.id, doc.data())).toList();
    // Un pago recien enviado todavia no tiene la hora del servidor: se toma
    // como el mas nuevo.
    final ahora = DateTime.now();
    lista.sort((a, b) => (b.creadoEn ?? ahora).compareTo(a.creadoEn ?? ahora));
    return lista;
  }

  // ---------------------------------------------------------------------
  // HU-11: Historial de pagos
  // ---------------------------------------------------------------------

  Stream<List<Pago>> observarMisPagos() {
    return _pagos.where('usuarioId', isEqualTo: _uid).snapshots().map(_ordenar);
  }

  // ---------------------------------------------------------------------
  // HU-12: Validar pagos manuales
  // ---------------------------------------------------------------------

  // observarPagosDelComplejo: pagos de las canchas del organizador. El
  // administrador general ve los de todas las canchas.
  Stream<List<Pago>> observarPagosDelComplejo({required bool esAdmin}) {
    final Query<Map<String, dynamic>> consulta = esAdmin ? _pagos : _pagos.where('propietarioId', isEqualTo: _uid);
    return consulta.snapshots().map(_ordenar);
  }

  // obtenerComprobante: la foto del pago (texto base64), o null si no
  // tiene. Se pide solo al abrir el detalle de un pago.
  Future<String?> obtenerComprobante(String pagoId) async {
    final doc = await _db.collection('comprobantes').doc(pagoId).get();
    return doc.data()?['imagen'] as String?;
  }

  // aprobar: el pago es correcto, la reserva pasa a "confirmada".
  Future<void> aprobar(Pago pago) => _revisar(pago, aprobado: true);

  // rechazar: el pago no se encontro o no coincide; la reserva se cancela
  // y el horario vuelve a quedar libre para otros jugadores.
  Future<void> rechazar(Pago pago, String motivo) => _revisar(pago, aprobado: false, motivo: motivo);

  // _revisar: actualiza el pago y su reserva en una sola transaccion, asi
  // nunca queda un pago aprobado con la reserva cancelada (o al reves).
  Future<void> _revisar(Pago pago, {required bool aprobado, String? motivo}) async {
    final uid = _uid;
    final refPago = _pagos.doc(pago.id);

    final error = await _db.runTransaction<String?>((transaccion) async {
      final docPago = await transaccion.get(refPago);
      if (!docPago.exists || docPago.data()?['estado'] != Pago.estadoEnRevision) {
        return 'Este pago ya fue revisado o el jugador canceló la reserva.';
      }
      // La reserva se toma del pago guardado (y no de la pantalla), por si
      // el jugador la reprogramo mientras el dueño tenia el pago abierto.
      final reservaId = (docPago.data()?['reservaId'] ?? '').toString();
      if (reservaId.isEmpty) return 'La reserva de este pago ya no existe.';
      final refReserva = _db.collection('reservas').doc(reservaId);
      final docReserva = await transaccion.get(refReserva);

      if (!docReserva.exists) return 'La reserva de este pago ya no existe.';
      final reserva = Reserva.fromMap(docReserva.id, docReserva.data()!);
      if (reserva.estado != Reserva.estadoPendientePago) {
        return 'La reserva de este pago ya no está pendiente.';
      }

      transaccion.update(refPago, {
        'estado': aprobado ? Pago.estadoAprobado : Pago.estadoRechazado,
        'motivoRechazo': aprobado ? null : motivo,
        'revisadoPor': uid,
        'revisadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
      transaccion.update(refReserva, {
        'estado': aprobado ? Reserva.estadoConfirmada : Reserva.estadoCancelada,
        if (!aprobado) 'canceladaEn': FieldValue.serverTimestamp(),
        'actualizadaEn': FieldValue.serverTimestamp(),
      });
      return null;
    });

    if (error != null) throw ReservaException(error);
  }
}
