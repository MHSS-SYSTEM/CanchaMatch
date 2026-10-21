import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/reserva.dart';

// ReservaService: lectura y escritura de la coleccion "reservas".
//
//  - HU-07: ver que turnos de una cancha estan libres u ocupados.
class ReservaService {
  static final ReservaService _instancia = ReservaService._interno();

  factory ReservaService() => _instancia;

  ReservaService._interno();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _reservas => _db.collection('reservas');

  // ---------------------------------------------------------------------
  // HU-07: Ver disponibilidad en calendario
  // ---------------------------------------------------------------------

  // observarReservasDelDia: todas las reservas de una cancha en una fecha.
  // Es un Stream, asi el calendario se actualiza solo cuando otro jugador
  // reserva o cancela un turno de esa cancha.
  Stream<List<Reserva>> observarReservasDelDia(String canchaId, String fecha) {
    return _reservas
        .where('canchaId', isEqualTo: canchaId)
        .where('fecha', isEqualTo: fecha)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Reserva.fromMap(doc.id, doc.data())).toList());
  }

  // observarReservasDeFecha: las reservas de TODAS las canchas en una
  // fecha. La usa la busqueda (HU-06) para saber que canchas todavia
  // tienen turnos libres ese dia.
  Stream<List<Reserva>> observarReservasDeFecha(String fecha) {
    return _reservas
        .where('fecha', isEqualTo: fecha)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Reserva.fromMap(doc.id, doc.data())).toList());
  }
}
