import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// MediosPagoScreen: explica los medios de pago que acepta CanchaMatch.
class MediosPagoScreen extends StatelessWidget {
  const MediosPagoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Medios de pago')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Medios de pago aceptados',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textoClaro),
          ),
          const SizedBox(height: 20),

          const Text('Yape', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.verdeLima)),
          const SizedBox(height: 4),
          const Text(
            'Yapea al número del complejo y adjunta la captura con el número de operación.',
            style: TextStyle(color: AppColors.textoSecundario),
          ),
          const SizedBox(height: 16),

          const Text('Plin', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.verdeLima)),
          const SizedBox(height: 4),
          const Text(
            'Envía el pago por Plin y adjunta la captura con el número de operación.',
            style: TextStyle(color: AppColors.textoSecundario),
          ),
          const SizedBox(height: 16),

          const Text('Tarjeta', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.verdeLima)),
          const SizedBox(height: 4),
          const Text(
            'Ingresa los 4 últimos dígitos de tu tarjeta y el número de operación.',
            style: TextStyle(color: AppColors.textoSecundario),
          ),
          const SizedBox(height: 32),

          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}