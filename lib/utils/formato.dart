// Funciones pequeñas para mostrar horas, dias y fechas en pantalla.
// Se hacen a mano (sin el paquete intl) porque solo se necesitan unos
// pocos formatos simples y en español.

// Nombres cortos de los dias, en el mismo orden que DateTime.weekday
// (1 = lunes ... 7 = domingo).
const diasCortos = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
const diasNombres = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
const mesesCortos = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

// horaTexto(8) -> "08:00"
String horaTexto(int hora) => '${hora.toString().padLeft(2, '0')}:00';

// rangoHora(8) -> "08:00 - 09:00" (cada horario dura una hora)
String rangoHora(int hora) => '${horaTexto(hora)} - ${horaTexto(hora + 1)}';

// fechaClave: convierte una fecha al formato "2026-10-05". Se usa como
// parte del id de las reservas y para buscar por fecha en Firestore.
String fechaClave(DateTime fecha) {
  final mes = fecha.month.toString().padLeft(2, '0');
  final dia = fecha.day.toString().padLeft(2, '0');
  return '${fecha.year}-$mes-$dia';
}

// fechaDesdeClave: hace lo contrario ("2026-10-05" -> DateTime).
// Si el texto estuviera vacio o mal escrito (por ejemplo, un dato editado
// a mano en Firestore), devuelve el 1 de enero de 1970 en vez de hacer
// caer la pantalla.
DateTime fechaDesdeClave(String clave) {
  final partes = clave.split('-');
  if (partes.length == 3) {
    final anio = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final dia = int.tryParse(partes[2]);
    if (anio != null && mes != null && dia != null) return DateTime(anio, mes, dia);
  }
  return DateTime(1970);
}

// fechaTexto -> "Lunes 5 oct"
String fechaTexto(DateTime fecha) =>
    '${diasNombres[fecha.weekday - 1]} ${fecha.day} ${mesesCortos[fecha.month - 1]}';

// soloFecha: quita la hora de un DateTime (deja las 00:00 de ese dia).
DateTime soloFecha(DateTime fecha) => DateTime(fecha.year, fecha.month, fecha.day);
