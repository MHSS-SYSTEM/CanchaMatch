import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/cancha.dart';

// CanchasAdminService: operaciones del administrador sobre la coleccion
// "canchas" (HU-21): listar todas, crear, editar y activar/desactivar.
//
// Las reglas de Firestore solo permiten escribir en "canchas" a usuarios
// con rol "admin", asi que aunque un jugador llegara a llamar a estos
// metodos, Firestore rechazaria la escritura.
class CanchasAdminService {
  static final CanchasAdminService _instancia = CanchasAdminService._interno();

  factory CanchasAdminService() => _instancia;

  CanchasAdminService._interno();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _canchas => _db.collection('canchas');

  // observarTodas: todas las canchas, activas y desactivadas, ordenadas
  // por nombre. Es un Stream: si otro admin cambia algo, la lista se
  // actualiza sola.
  Stream<List<Cancha>> observarTodas() {
    return _canchas.snapshots().map((snapshot) {
      final lista = snapshot.docs.map((doc) => Cancha.fromMap(doc.id, doc.data())).toList();
      lista.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      return lista;
    });
  }

  // guardar: si la cancha no tiene id es nueva y se crea; si ya tiene id
  // se actualizan sus datos. Como los jugadores leen la misma coleccion,
  // los cambios se ven de inmediato en la busqueda (HU-06).
  Future<void> guardar(Cancha cancha) async {
    if (cancha.id.isEmpty) {
      await _canchas.add({
        ...cancha.toMap(),
        'creadaEn': FieldValue.serverTimestamp(),
        'actualizadaEn': FieldValue.serverTimestamp(),
      });
    } else {
      await _canchas.doc(cancha.id).update({
        ...cancha.toMap(),
        'actualizadaEn': FieldValue.serverTimestamp(),
      });
    }
  }

  // cambiarDisponible: activa o desactiva una cancha sin borrarla. Una
  // cancha desactivada deja de aparecer para los jugadores, pero se
  // conserva con todos sus datos por si se vuelve a activar.
  Future<void> cambiarDisponible(String canchaId, bool disponible) {
    return _canchas.doc(canchaId).update({
      'disponible': disponible,
      'actualizadaEn': FieldValue.serverTimestamp(),
    });
  }
}
