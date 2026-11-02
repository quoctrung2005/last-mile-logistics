import 'package:flutter/material.dart';

class PasswordInput extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool newPassword;
  final String? Function(String?) validator;
  final VoidCallback? onSubmitted;

  const PasswordInput({
    super.key,
    required this.controller,
    required this.label,
    required this.validator,
    this.enabled = true,
    this.newPassword = false,
    this.onSubmitted,
  });

  @override
  State<PasswordInput> createState() => _PasswordInputState();
}

class _PasswordInputState extends State<PasswordInput> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    enabled: widget.enabled,
    obscureText: _hidden,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: [
      widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
    ],
    validator: widget.validator,
    textInputAction: widget.onSubmitted == null
        ? TextInputAction.next
        : TextInputAction.done,
    onFieldSubmitted: (_) => widget.enabled ? widget.onSubmitted?.call() : null,
    decoration: InputDecoration(
      labelText: widget.label,
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        tooltip: '${_hidden ? 'Hiện' : 'Ẩn'} ${widget.label.toLowerCase()}',
        onPressed: widget.enabled
            ? () => setState(() => _hidden = !_hidden)
            : null,
        icon: Icon(
          _hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
    ),
  );
}
