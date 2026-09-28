import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/usuario.dart';
import '../models/cancha.dart';

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
    return _db.collection('usuarios').doc(usuario.uid).update(usuario.toMap());
  }

  // ---------------------------------------------------------------------
  // HU-06: Buscar canchas disponibles
  // ---------------------------------------------------------------------

  // obtenerCanchasDisponibles: trae, una sola vez, todas las canchas que
  // tienen disponible == true. Se usa para pintar la lista y los
  // marcadores del mapa en la pantalla de busqueda.
  Future<List<Cancha>> obtenerCanchasDisponibles() async {
    final snapshot = await _db
        .collection('canchas')
        .where('disponible', isEqualTo: true)
        .get();

    return snapshot.docs
        .map((doc) => Cancha.fromMap(doc.id, doc.data()))
        .toList();
  }

  // observarCanchasDisponibles: version "en vivo" de lo anterior, usando
  // un Stream. Si alguien mas agrega o cambia una cancha en Firestore, la
  // pantalla se actualiza sola sin necesidad de recargar. Es opcional,
  // pero mas comodo para el mapa (los marcadores se actualizan solos).
  Stream<List<Cancha>> observarCanchasDisponibles() {
    return _db
        .collection('canchas')
        .where('disponible', isEqualTo: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Cancha.fromMap(doc.id, doc.data())).toList());
  }

  // buscarCanchasPorDistrito: filtra canchas disponibles por distrito,
  // para cuando el usuario quiere buscar solo en su zona de Cajamarca
  // (ej: "Baños del Inca") en vez de ver todas.
  Future<List<Cancha>> buscarCanchasPorDistrito(String distrito) async {
    final snapshot = await _db
        .collection('canchas')
        .where('disponible', isEqualTo: true)
        .where('distrito', isEqualTo: distrito)
        .get();

    return snapshot.docs
        .map((doc) => Cancha.fromMap(doc.id, doc.data()))
        .toList();
  }

  // sembrarCanchasDeEjemplo: crea unas canchas de prueba en Cajamarca la
  // primera vez que se usa la app, para no tener que cargarlas a mano
  // desde la consola de Firebase.
  //
  // Se hace dentro de una transaccion (runTransaction), en vez de solo
  // revisar "¿ya hay canchas?" y despues crearlas por separado. La razon:
  // si dos personas abren esta pantalla al mismo tiempo (por ejemplo dos
  // celulares probando la app a la vez) y ambas revisan "no hay canchas"
  // antes de que la primera termine de crearlas, las dos crearian los 3
  // registros de ejemplo y quedarian duplicados. La transaccion evita
  // esto: se usa un documento marcador ("meta/semilla_canchas") que solo
  // se puede crear una vez, y Firestore garantiza que la transaccion
  // completa (marcar + crear las 3 canchas) ocurre de forma atomica.
  Future<void> sembrarCanchasDeEjemplo() async {
    final marcador = _db.collection('meta').doc('semilla_canchas');

    await _db.runTransaction((transaccion) async {
      final marcadorDoc = await transaccion.get(marcador);
      if (marcadorDoc.exists) return; // ya se sembraron antes, no duplicar

      transaccion.set(marcador, {'hecho': true});

      final canchasEjemplo = [
        Cancha(
          id: '',
          nombre: 'Cancha Los Andes',
          direccion: 'Jr. Los Andes 123',
          distrito: 'Cajamarca',
          tipoDeporte: 'Futbol',
          precioPorHora: 60,
          latitud: -7.1611,
          longitud: -78.5127,
        ),
        Cancha(
          id: '',
          nombre: 'Polideportivo Baños del Inca',
          direccion: 'Av. Manco Capac s/n',
          distrito: 'Baños del Inca',
          tipoDeporte: 'Voley',
          precioPorHora: 40,
          latitud: -7.1502,
          longitud: -78.4783,
        ),
        Cancha(
          id: '',
          nombre: 'Cancha San Sebastian',
          direccion: 'Jr. San Sebastian 456',
          distrito: 'Cajamarca',
          tipoDeporte: 'Basquet',
          precioPorHora: 35,
          latitud: -7.1550,
          longitud: -78.5100,
        ),
      ];

      for (final cancha in canchasEjemplo) {
        final nuevoDoc = _db.collection('canchas').doc();
        transaccion.set(nuevoDoc, cancha.toMap());
      }
    });
  }
}
