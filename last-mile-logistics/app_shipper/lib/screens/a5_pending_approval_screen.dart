import 'package:flutter/material.dart';

import 'registration_screen.dart';

// Compatibility entry point; registration now uses the connected review flow.
class A5PendingApprovalScreen extends StatelessWidget {
  const A5PendingApprovalScreen({super.key});
  @override
  Widget build(BuildContext context) => const RegistrationStatusScreen();
}
