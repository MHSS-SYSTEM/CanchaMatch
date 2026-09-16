import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// AppColors: paleta tomada del diseno "Cancha Pro" hecho en Stitch (fondo
// casi negro con un tinte verde, acentos en verde lima brillante). Tenerlos
// centralizados aqui evita repetir codigos de color sueltos en cada
// pantalla; cambiar un color aqui cambia toda la app de una vez.
class AppColors {
  static const fondo = Color(0xFF0B0F0C); // fondo principal (casi negro)
  static const fondoOscuro = Color(0xFF070908); // AppBar, barra inferior
  static const tarjeta = Color(0xFF151A16); // fondo de tarjetas/inputs
  static const verdeLima = Color(0xFFB6F03C); // color de acento (botones, iconos activos)
  static const textoClaro = Color(0xFFF5F7F5); // texto principal
  static const textoSecundario = Color(0xFF9AA69C); // texto de menor jerarquia
  static const borde = Color(0xFF2A312B); // bordes de inputs y tarjetas
  static const error = Color(0xFFFF6B6B); // mensajes de error
}

// AppTheme: arma el ThemeData que usa MaterialApp, siguiendo la guia de
// estilo del diseno de Stitch: titulos con la fuente "Anybody" (ancha y
// en mayusculas), texto normal con "Hanken Grotesk", y "JetBrains Mono"
// para datos tipo codigo (como el OTP simulado de HU-01).
class AppTheme {
  // Estilo de titulo grande (pantallas de login/registro, encabezados).
  static TextStyle get tituloGrande => GoogleFonts.anybody(
        color: AppColors.textoClaro,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      );

  // Estilo para mostrar codigos (ej. el OTP simulado de HU-01), en
  // monoespaciado para que se lean claros los digitos.
  static TextStyle get textoCodigo => GoogleFonts.jetBrainsMono(
        color: AppColors.verdeLima,
        fontWeight: FontWeight.w600,
        letterSpacing: 2,
      );

  static ThemeData get tema {
    final textoBase = GoogleFonts.hankenGroteskTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.fondo,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.verdeLima,
        secondary: AppColors.verdeLima,
        surface: AppColors.tarjeta,
        error: AppColors.error,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.fondoOscuro,
        foregroundColor: AppColors.textoClaro,
        elevation: 0,
        titleTextStyle: GoogleFonts.anybody(
          color: AppColors.textoClaro,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
      ),
      // Estilo por defecto para todos los TextField/TextFormField de la app
      // (login, registro, perfil, etc.) para no repetir la decoracion en
      // cada pantalla.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.tarjeta,
        labelStyle: const TextStyle(color: AppColors.textoSecundario),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borde),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.verdeLima, width: 2),
        ),
      ),
      // Botones tipo "pill" (bien redondeados) en verde lima, como en el
      // diseno de Stitch ("INGRESAR", "REGISTRARSE", etc.).
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.verdeLima,
          foregroundColor: AppColors.fondoOscuro,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
      textTheme: textoBase.copyWith(
        bodyLarge: textoBase.bodyLarge?.copyWith(color: AppColors.textoClaro),
        bodyMedium: textoBase.bodyMedium?.copyWith(color: AppColors.textoClaro),
        titleLarge: GoogleFonts.anybody(
          color: AppColors.textoClaro,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardTheme(
        color: AppColors.tarjeta,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borde),
        ),
      ),
    );
  }
}
