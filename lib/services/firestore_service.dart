import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/usuario.dart';

// FirestoreService: agrupa las operaciones de lectura/escritura contra
// Cloud Firestore que NO tienen que ver con autenticacion (eso ya lo hace
// AuthService). Aqui viven HU-05 (perfil) y HU-06 (buscar canchas).
//
// Igual que AuthService, es un singleton: "FirestoreService()" siempre
// devuelve la misma instancia, sin importar desde que pantalla se llame.
class FirestoreService {
  static final FirestoreService _instancia = FirestoreService._interno();

  factory FirestoreService() => _instancia;

  FirestoreService._interno();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------------------------------------------------------------------
  // HU-05: Edicion de perfil
  // ---------------------------------------------------------------------

  // obtenerPerfil: lee el documento del usuario en la coleccion "usuarios"
  // y lo convierte a un objeto Usuario. Se usa al abrir la pantalla de
  // perfil, para mostrar los datos actuales antes de editarlos.
  Future<Usuario?> obtenerPerfil(String uid) async {
    final doc = await _db.collection('usuarios').doc(uid).get();
    if (!doc.exists) return null;
    return Usuario.fromMap(uid, doc.data()!);
  }

  // actualizarPerfil: guarda los cambios que el usuario hizo en la
  // pantalla de edicion de perfil (nombre, telefono, deporte favorito,
  // distrito, etc.). Se usa .update() en vez de .set() para no borrar
  // por accidente campos que no se esten mandando en ese momento.
  Future<void> actualizarPerfil(Usuario usuario) {
    return _db.collection('usuarios').doc(usuario.uid).update(usuario.toMap());}
}
