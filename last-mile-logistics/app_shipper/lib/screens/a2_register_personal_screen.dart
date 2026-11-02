import 'package:flutter/material.dart';

import 'registration_screen.dart';

// Compatibility entry point; registration now uses the connected review flow.
class A2RegisterPersonalScreen extends StatelessWidget {
  const A2RegisterPersonalScreen({super.key});
  @override
  Widget build(BuildContext context) => const RegistrationScreen();
}
