import '../utils/formato.dart';

// Modelo de datos "Cancha".
//
// Representa una cancha deportiva de un complejo. La crea y edita el
// administrador (HU-21) y la ven los jugadores al buscar (HU-06), al ver
// sus horarios (HU-07) y al reservar (HU-08).
//
// Igual que Usuario, esta clase solo describe los datos: no llama a
// Firestore directamente, eso lo hacen los services.
class Cancha {
  // id: identificador del documento en la coleccion "canchas" de Firestore.
  // Es vacio ('') cuando la cancha todavia no se ha guardado.
  final String id;

  final String nombre; // ej: "Cancha Los Andes"
  final String direccion; // direccion en texto, para mostrar en pantalla
  final String distrito; // distrito de Cajamarca (Cajamarca, Baños del Inca, etc.)
  final String tipoDeporte; // ej: "Futbol", "Voley", "Basquet"
  final double precioPorHora; // precio en soles

  // Coordenadas para ubicar la cancha en el mapa (flutter_map + OpenStreetMap).
  final double latitud;
  final double longitud;

  // disponible: si es false, la cancha esta desactivada por el
  // administrador y no aparece en la busqueda de los jugadores.
  final bool disponible;

  // Horario de atencion: se reserva por horas completas, desde
  // horaApertura hasta horaCierre (ej: 8 y 22 -> de 08:00 a 22:00, el
  // ultimo turno es 21:00 - 22:00).
  final int horaApertura;
  final int horaCierre;

  // diasAbiertos: dias de la semana en que atiende, con la misma
  // numeracion de DateTime.weekday (1 = lunes ... 7 = domingo).
  final List<int> diasAbiertos;

  // Politica de cancelacion del complejo (HU-09): texto que se le muestra
  // al jugador antes de cancelar o reprogramar, y cuantas horas antes del
  // partido como minimo se permite hacerlo.
  final String politicaCancelacion;
  final int horasLimiteCancelacion;

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
    this.horaApertura = 8,
    this.horaCierre = 22,
    this.diasAbiertos = const [1, 2, 3, 4, 5, 6, 7],
    this.politicaCancelacion = '',
    this.horasLimiteCancelacion = 2,
  });

  // horasDelDia: lista de las horas en que empieza cada turno.
  // Ej: apertura 8 y cierre 11 -> [8, 9, 10].
  List<int> get horasDelDia => [for (var h = horaApertura; h < horaCierre; h++) h];

  // abreEl: indica si la cancha atiende el dia de esa fecha.
  bool abreEl(DateTime fecha) => diasAbiertos.contains(fecha.weekday);

  // horarioTexto -> "08:00 - 22:00"
  String get horarioTexto => '${horaTexto(horaApertura)} - ${horaTexto(horaCierre)}';

  // diasTexto -> "L M X J V" (solo los dias que abre)
  String get diasTexto => [for (final d in [...diasAbiertos]..sort()) diasCortos[d - 1]].join(' ');

  // Texto de la politica que se muestra al jugador. Si el administrador
  // no escribio una, se arma una a partir de las horas limite.
  String get politicaParaMostrar {
    if (politicaCancelacion.trim().isNotEmpty) return politicaCancelacion.trim();
    return 'Puedes cancelar o reprogramar sin costo hasta $horasLimiteCancelacion '
        '${horasLimiteCancelacion == 1 ? 'hora' : 'horas'} antes del partido.';
  }

  // _comoDouble / _comoInt: convierten un valor cualquiera a numero de
  // forma segura. Firestore puede guardar numeros como int o double segun
  // como se hayan cargado, y si alguien edita un documento a mano podria
  // dejar un tipo inesperado; en ese caso se usa el valor por defecto en
  // vez de que la app se caiga con un error de tipo.
  static double _comoDouble(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return 0;
  }

  static int _comoInt(dynamic valor, int porDefecto) {
    if (valor is num) return valor.toInt();
    return porDefecto;
  }

  // fromMap: arma una Cancha a partir de un documento de Firestore.
  // Las canchas creadas antes de HU-21 no tienen horario ni politica, por
  // eso cada campo nuevo tiene un valor por defecto.
  factory Cancha.fromMap(String id, Map<String, dynamic> data) {
    final dias = data['diasAbiertos'];
    return Cancha(
      id: id,
      nombre: (data['nombre'] ?? '').toString(),
      direccion: (data['direccion'] ?? '').toString(),
      distrito: (data['distrito'] ?? '').toString(),
      tipoDeporte: (data['tipoDeporte'] ?? '').toString(),
      precioPorHora: _comoDouble(data['precioPorHora']),
      latitud: _comoDouble(data['latitud']),
      longitud: _comoDouble(data['longitud']),
      disponible: data['disponible'] != false,
      // Los valores se acotan para que un dato mal cargado a mano (un dia 8,
      // una hora 30) no haga fallar las pantallas.
      horaApertura: _comoInt(data['horaApertura'], 8).clamp(0, 23).toInt(),
      horaCierre: _comoInt(data['horaCierre'], 22).clamp(1, 24).toInt(),
      diasAbiertos: dias is List
          ? (dias.whereType<num>().map((d) => d.toInt()).where((d) => d >= 1 && d <= 7).toSet().toList()..sort())
          : const [1, 2, 3, 4, 5, 6, 7],
      politicaCancelacion: (data['politicaCancelacion'] ?? '').toString(),
      horasLimiteCancelacion: _comoInt(data['horasLimiteCancelacion'], 2).clamp(0, 168).toInt(),
    );
  }

  // toMap: convierte la Cancha a Map para guardarla en Firestore.
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
      'horaApertura': horaApertura,
      'horaCierre': horaCierre,
      'diasAbiertos': diasAbiertos,
      'politicaCancelacion': politicaCancelacion,
      'horasLimiteCancelacion': horasLimiteCancelacion,
    };
  }
}
