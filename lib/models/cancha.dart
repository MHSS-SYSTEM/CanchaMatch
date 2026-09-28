// Modelo de datos "Cancha".
//
// Representa una cancha deportiva disponible para reservar. Se usa
// principalmente en HU-06 (Buscar canchas disponibles), tanto para la
// lista de resultados como para los marcadores en el mapa (flutter_map).
//
// Igual que Usuario, esta clase solo describe los datos: no llama a
// Firestore directamente, eso lo hace FirestoreService.
class Cancha {
  // id: identificador del documento en la coleccion "canchas" de Firestore.
  final String id;

  final String nombre; // ej: "Cancha Los Andes"
  final String direccion; // direccion en texto, para mostrar en pantalla
  final String distrito; // distrito de Cajamarca (Cajamarca, Baños del Inca, etc.)
  final String tipoDeporte; // ej: "Futbol", "Voley", "Basquet"
  final double precioPorHora; // precio en soles

  // Coordenadas para ubicar la cancha en el mapa (flutter_map + OpenStreetMap).
  // Cajamarca esta aprox en latitud -7.16, longitud -78.51, asi que las
  // canchas de ejemplo deben usar valores cercanos a esos.
  final double latitud;
  final double longitud;

  // disponible: bandera simple para marcar si la cancha se puede reservar
  // ahora mismo. HU-06 pide "buscar canchas disponibles", asi que las
  // busquedas filtran por disponible == true.
  final bool disponible;

  Cancha({
    required this.id,
    required this.nombre,
    required this.direccion,
    required this.distrito,
    required this.tipoDeporte,
    required this.precioPorHora,
    required this.latitud,
    required this.longitud,
    this.disponible = true,
  });

  // _comoDouble: convierte un valor cualquiera a double de forma segura.
  // Firestore puede guardar numeros como int o double segun como se
  // hayan cargado los datos, y si alguien edita un documento a mano
  // podria dejar un tipo inesperado (texto, por ejemplo); en ese caso se
  // usa 0 en vez de que la app se caiga con un error de tipo.
  static double _comoDouble(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return 0;
  }

  // fromMap: arma una Cancha a partir de un documento de Firestore.
  // Se usa al leer la coleccion "canchas" para mostrar la lista/mapa.
  factory Cancha.fromMap(String id, Map<String, dynamic> data) {
    return Cancha(
      id: id,
      nombre: (data['nombre'] ?? '').toString(),
      direccion: (data['direccion'] ?? '').toString(),
      distrito: (data['distrito'] ?? '').toString(),
      tipoDeporte: (data['tipoDeporte'] ?? '').toString(),
      precioPorHora: _comoDouble(data['precioPorHora']),
      latitud: _comoDouble(data['latitud']),
      longitud: _comoDouble(data['longitud']),
      disponible: data['disponible'] ?? true,
    );
  }

  // toMap: convierte la Cancha a Map para guardarla en Firestore (por
  // ejemplo, al cargar canchas de ejemplo la primera vez).
  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'direccion': direccion,
      'distrito': distrito,
      'tipoDeporte': tipoDeporte,
      'precioPorHora': precioPorHora,
      'latitud': latitud,
      'longitud': longitud,
      'disponible': disponible,
    };
  }
}
