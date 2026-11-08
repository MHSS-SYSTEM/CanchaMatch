// Modelo de datos "Equipo" (HU-14).
//
// Lo arma el capitan desde "Mi equipo": un nombre y la lista de sus
// jugadores. Cada capitan tiene un solo equipo, por eso el id del
// documento en la coleccion "equipos" es el mismo uid del capitan.
class Equipo {
  // Minimo y maximo de jugadores para poder inscribirse en un campeonato.
  static const minJugadores = 5;
  static const maxJugadores = 20;

  final String id; // = uid del capitan
  final String nombre;
  final String capitanNombre;
  final String deporte;
  final List<String> jugadores;

  Equipo({
    required this.id,
    required this.nombre,
    required this.capitanNombre,
    required this.deporte,
    required this.jugadores,
  });

  bool get completo => jugadores.length >= minJugadores;

  factory Equipo.fromMap(String id, Map<String, dynamic> data) {
    final jugadores = data['jugadores'];
    return Equipo(
      id: id,
      nombre: (data['nombre'] ?? '').toString(),
      capitanNombre: (data['capitanNombre'] ?? '').toString(),
      deporte: (data['deporte'] ?? '').toString(),
      jugadores: jugadores is List ? jugadores.map((j) => j.toString()).toList() : [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'capitanNombre': capitanNombre,
      'deporte': deporte,
      'jugadores': jugadores,
    };
  }
}
