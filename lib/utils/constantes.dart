// Opciones fijas que comparten varias pantallas. Tenerlas en un solo
// lugar evita que el perfil, el formulario de canchas y los filtros de
// busqueda terminen con listas distintas (por ejemplo "Futbol" en una y
// "Fútbol" en otra), lo que haria que los filtros no encuentren nada.

const deportes = ['Futbol', 'Voley', 'Basquet', 'Tenis'];

// Cuantos dias hacia adelante (contando hoy) se pueden buscar y reservar.
// Lo usan la busqueda (HU-06) y el calendario (HU-07), asi ambas pantallas
// muestran siempre el mismo rango de fechas.
const diasReservables = 14;

const distritosCajamarca = [
  'Cajamarca',
  'Baños del Inca',
  'Llacanora',
  'Jesús',
  'Namora',
  'La Encañada',
  'Asunción',
  'Magdalena',
  'San Juan',
  'Chetilla',
  'Cospán',
  'Matara',
];
