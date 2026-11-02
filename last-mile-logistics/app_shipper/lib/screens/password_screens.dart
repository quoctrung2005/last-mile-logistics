import 'dart:async';

import 'package:flutter/material.dart';

import '../models/password_rules.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';
import '../theme/app_theme.dart';
import '../widgets/password_input.dart';
import 'login_screen.dart';

String _error(Object error) => error.toString().replaceFirst(
  RegExp(r'^(Exception|FormatException):\s*'),
  '',
);

Future<void> _returnToLogin(BuildContext context, String message) async {
  // The root session listener normally performs this navigation. This fallback
  // also supports screens opened in their own Navigator without that listener.
  if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
  await RealtimeService.instance.disconnect();
  if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => LoginScreen(message: message)),
    (_) => false,
  );
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await ApiService.changePassword(
        currentPassword: _current.text,
        newPassword: _new.text,
        confirmPassword: _confirm.text,
      );
      if (!mounted) return;
      _current.clear();
      _new.clear();
      _confirm.clear();
      await _returnToLogin(context, message);
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _PasswordPage(
    title: 'Đổi mật khẩu',
    formKey: _form,
    busy: _busy,
    children: [
      const Text(
        'Bảo vệ tài khoản của bạn',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      const Text(
        'Sau khi đổi mật khẩu, bạn cần đăng nhập lại trên các thiết bị đang sử dụng tài khoản này.',
      ),
      const SizedBox(height: 24),
      PasswordInput(
        key: const ValueKey('current-password'),
        controller: _current,
        label: 'Mật khẩu hiện tại',
        validator: PasswordRules.current,
        enabled: !_busy,
      ),
      const SizedBox(height: 18),
      PasswordInput(
        key: const ValueKey('new-password'),
        controller: _new,
        label: 'Mật khẩu mới',
        newPassword: true,
        enabled: !_busy,
        validator: (value) =>
            PasswordRules.newPassword(value, currentPassword: _current.text),
      ),
      const SizedBox(height: 8),
      const Text(
        'Ít nhất 8 ký tự và khác mật khẩu hiện tại.',
        style: TextStyle(color: AppTheme.secondary),
      ),
      const SizedBox(height: 18),
      PasswordInput(
        key: const ValueKey('confirm-password'),
        controller: _confirm,
        label: 'Xác nhận mật khẩu mới',
        newPassword: true,
        enabled: !_busy,
        validator: (value) => PasswordRules.confirm(value, _new.text),
        onSubmitted: _submit,
      ),
      if (_message != null) _Feedback(_message!, error: true),
      const SizedBox(height: 24),
      _SubmitButton(busy: _busy, label: 'Đổi mật khẩu', onPressed: _submit),
    ],
  );
}

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _emailForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _token = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _resetStep = false, _busy = false;
  String? _message, _requestNotice;
  DateTime? _resendAt;
  Timer? _timer;

  int get _seconds {
    final milliseconds =
        _resendAt?.difference(DateTime.now()).inMilliseconds ?? 0;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _token.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _cooldown() {
    _resendAt = DateTime.now().add(const Duration(seconds: 60));
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_seconds == 0) _timer?.cancel();
      setState(() {});
    });
  }

  Future<void> _request() async {
    if (_busy || _seconds > 0 || !_emailForm.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final notice = await ApiService.requestPasswordRecovery(_email.text);
      if (!mounted) return;
      _cooldown();
      setState(() {
        _resetStep = true;
        _requestNotice = notice;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy || !_resetForm.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await ApiService.resetPassword(
        recoveryToken: _token.text,
        newPassword: _new.text,
        confirmPassword: _confirm.text,
      );
      if (!mounted) return;
      _timer?.cancel();
      _token.clear();
      _new.clear();
      _confirm.clear();
      await _returnToLogin(context, message);
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _PasswordPage(
    title: _resetStep ? 'Đặt lại mật khẩu' : 'Quên mật khẩu',
    formKey: _resetStep ? _resetForm : _emailForm,
    busy: _busy,
    children: _resetStep ? _resetFields() : _emailFields(),
  );

  List<Widget> _emailFields() => [
    const Icon(
      Icons.mark_email_read_outlined,
      size: 48,
      color: AppTheme.primary,
    ),
    const SizedBox(height: 20),
    const Text(
      'Khôi phục tài khoản',
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
    ),
    const SizedBox(height: 10),
    const Text(
      'Nhập email đã đăng ký với đơn vị quản lý. Mã khôi phục trong email có hiệu lực 15 phút và chỉ dùng một lần.',
    ),
    const SizedBox(height: 24),
    TextFormField(
      key: const ValueKey('recovery-email'),
      controller: _email,
      enabled: !_busy,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      autofillHints: const [AutofillHints.email],
      validator: PasswordRules.email,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _request(),
      decoration: const InputDecoration(
        labelText: 'Email đã đăng ký',
        prefixIcon: Icon(Icons.email_outlined),
      ),
    ),
    if (_message != null) _Feedback(_message!, error: true),
    const SizedBox(height: 24),
    _SubmitButton(
      busy: _busy,
      label: _seconds > 0 ? 'Gửi lại sau ${_seconds}s' : 'Gửi mã khôi phục',
      onPressed: _seconds > 0 ? null : _request,
    ),
    const SizedBox(height: 8),
    TextButton(
      onPressed: _busy
          ? null
          : () => setState(() {
              _resetStep = true;
              _message = null;
            }),
      child: const Text('Tôi đã có mã khôi phục'),
    ),
    const SizedBox(height: 16),
    const Text(
      'Nếu chưa đăng ký email hoặc email không còn sử dụng, hãy liên hệ quản trị viên để được hỗ trợ.',
      style: TextStyle(color: AppTheme.secondary),
    ),
  ];

  List<Widget> _resetFields() => [
    const Text(
      'Tạo mật khẩu mới',
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
    ),
    if (_requestNotice != null) _Feedback(_requestNotice!),
    const SizedBox(height: 12),
    const Text(
      'Sao chép đầy đủ mã khôi phục trong email. Hãy kiểm tra cả thư mục spam nếu chưa thấy thư.',
    ),
    const SizedBox(height: 24),
    TextFormField(
      key: const ValueKey('recovery-token'),
      controller: _token,
      enabled: !_busy,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      validator: PasswordRules.recoveryToken,
      decoration: const InputDecoration(
        labelText: 'Mã khôi phục',
        prefixIcon: Icon(Icons.key_outlined),
      ),
    ),
    const SizedBox(height: 18),
    PasswordInput(
      key: const ValueKey('new-password'),
      controller: _new,
      label: 'Mật khẩu mới',
      newPassword: true,
      enabled: !_busy,
      validator: PasswordRules.newPassword,
    ),
    const SizedBox(height: 8),
    const Text(
      'Mật khẩu mới cần ít nhất 8 ký tự.',
      style: TextStyle(color: AppTheme.secondary),
    ),
    const SizedBox(height: 18),
    PasswordInput(
      key: const ValueKey('confirm-password'),
      controller: _confirm,
      label: 'Xác nhận mật khẩu mới',
      newPassword: true,
      enabled: !_busy,
      validator: (value) => PasswordRules.confirm(value, _new.text),
      onSubmitted: _reset,
    ),
    if (_message != null) _Feedback(_message!, error: true),
    const SizedBox(height: 24),
    _SubmitButton(busy: _busy, label: 'Đặt lại mật khẩu', onPressed: _reset),
    TextButton(
      onPressed: _busy
          ? null
          : () => setState(() {
              _resetStep = false;
              _message = null;
            }),
      child: Text(
        _seconds > 0
            ? 'Đổi email / gửi lại sau ${_seconds}s'
            : 'Đổi email hoặc yêu cầu mã mới',
      ),
    ),
  ];
}

class _PasswordPage extends StatelessWidget {
  final String title;
  final GlobalKey<FormState> formKey;
  final bool busy;
  final List<Widget> children;
  const _PasswordPage({
    required this.title,
    required this.formKey,
    required this.busy,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: AutofillGroup(
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Feedback extends StatelessWidget {
  final String message;
  final bool error;
  const _Feedback(this.message, {this.error = false});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: error ? AppTheme.errorContainer : AppTheme.primaryFixed,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(
          color: error ? AppTheme.onErrorContainer : AppTheme.onSurface,
        ),
      ),
    ),
  );
}

class _SubmitButton extends StatelessWidget {
  final bool busy;
  final String label;
  final VoidCallback? onPressed;
  const _SubmitButton({
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: busy ? null : onPressed,
    icon: busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.lock_reset),
    label: Text(busy ? 'Đang xử lý…' : label),
  );
}
