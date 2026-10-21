// Modelo de datos "Usuario".
//
// Representa al jugador que usa la app. Esta clase NO se conecta directo
// a Firebase; solo describe la forma de los datos y sabe convertirse
// hacia/desde un Map (que es el formato que Firestore usa por dentro).
//
// Se usa en:
//  - HU-01 (Registro de usuario): se crea un Usuario nuevo con verificado=false.
//  - HU-05 (Edicion de perfil): se lee un Usuario, se modifican sus campos
//    y se vuelve a guardar con toMap().
class Usuario {
  // uid: identificador unico que da Firebase Authentication al crear la
  // cuenta. Es el mismo id que se usa como nombre del documento en la
  // coleccion "usuarios" de Firestore. No se puede editar.
  final String uid;

  // Datos basicos que se piden en el registro (HU-01) y se pueden
  // modificar despues en el perfil (HU-05).
  String nombre;
  String apellido;
  String email;
  String telefono;

  // Campos opcionales de perfil, pensados para HU-05 (el jugador los
  // completa despues de registrarse, no son obligatorios al inicio).
  String? deporteFavorito; // ej: "Futbol", "Voley", "Basquet"
  String? distrito; // distrito de Cajamarca donde vive/juega

  // verificado: se pone en true cuando el usuario ingresa correctamente
  // el codigo OTP simulado (ver AuthService). Antes de eso queda en false.
  bool verificado;

  // rol: "jugador" (por defecto) o "admin". El admin es quien gestiona
  // canchas, horarios y precios (HU-21). Se asigna a mano desde la consola
  // de Firebase y la app solo lo lee: por eso NO se incluye en toMap(),
  // asi un jugador no puede cambiarse el rol a si mismo al editar su
  // perfil (las reglas de Firestore tambien lo impiden).
  final String rol;

  // tipoCuenta (HU-04): lo que el usuario eligio al registrarse:
  //  - "jugador": busca y reserva canchas,
  //  - "capitan": igual que el jugador y ademas maneja su equipo,
  //  - "organizador": dueño de complejo; crea y edita SUS canchas.
  // Es distinto de "rol": rol = "admin" (se pone a mano en Firebase) es el
  // administrador general de CanchaMatch, que puede ver y editar todas.
  String tipoCuenta;

  static const tiposCuenta = ['jugador', 'capitan', 'organizador'];

  Usuario({
    required this.uid,
    required this.nombre,
    required this.apellido,
    required this.email,
    required this.telefono,
    this.deporteFavorito,
    this.distrito,
    this.verificado = false,
    this.rol = 'jugador',
    this.tipoCuenta = 'jugador',
  });

  // fromMap: construye un Usuario a partir de los datos que llegan de
  // Firestore (un documento leido siempre llega como Map<String, dynamic>).
  // Se usa, por ejemplo, cuando se abre la pantalla de perfil y se necesita
  // cargar los datos guardados del usuario que inicio sesion.
  factory Usuario.fromMap(String uid, Map<String, dynamic> data) {
    return Usuario(
      uid: uid,
      // ".toString()" evita un error si algun campo llegara guardado con
      // un tipo distinto al esperado (por ejemplo, si alguien edita el
      // documento a mano desde la consola de Firebase).
      nombre: (data['nombre'] ?? '').toString(),
      apellido: (data['apellido'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      telefono: (data['telefono'] ?? '').toString(),
      deporteFavorito: data['deporteFavorito']?.toString(),
      distrito: data['distrito']?.toString(),
      verificado: data['verificado'] == true,
      rol: data['rol'] == 'admin' ? 'admin' : 'jugador',
      // Las cuentas creadas antes de HU-04 no tienen este campo: se toman
      // como jugador.
      tipoCuenta: tiposCuenta.contains(data['tipoCuenta']) ? data['tipoCuenta'] as String : 'jugador',
    );
  }

  // toMap: hace lo contrario a fromMap. Convierte este objeto Usuario en
  // un Map para poder guardarlo en Firestore con .set() o .update().
  // No se incluye "uid" adentro del map porque el uid ya es el nombre
  // del documento (no hace falta repetirlo como campo).
  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'apellido': apellido,
      'email': email,
      'telefono': telefono,
      'deporteFavorito': deporteFavorito,
      'distrito': distrito,
      'verificado': verificado,
      'tipoCuenta': tipoCuenta,
    };
  }

  // Nombre completo, util para mostrar en pantalla (AppBar del perfil, etc).
  String get nombreCompleto => '$nombre $apellido';

  bool get esAdmin => rol == 'admin';

  bool get esCapitan => tipoCuenta == 'capitan';

  // Puede crear y administrar canchas: el dueño de complejo, o el
  // administrador general.
  bool get esOrganizador => tipoCuenta == 'organizador' || esAdmin;

  // Texto para mostrar en pantalla.
  static String nombreTipo(String tipo) {
    switch (tipo) {
      case 'capitan':
        return 'Capitán de equipo';
      case 'organizador':
        return 'Organizador de complejo';
      default:
        return 'Jugador';
    }
  }

  String get rolTexto => esAdmin ? 'Administrador de CanchaMatch' : nombreTipo(tipoCuenta);
}
