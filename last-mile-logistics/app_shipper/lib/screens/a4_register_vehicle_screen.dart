import 'package:flutter/material.dart';

import 'registration_screen.dart';

// Compatibility entry point; registration now uses the connected review flow.
class A4RegisterVehicleScreen extends StatelessWidget {
  const A4RegisterVehicleScreen({super.key});
  @override
  Widget build(BuildContext context) => const RegistrationScreen();
}
