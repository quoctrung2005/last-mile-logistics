import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/api_constants.dart';
import 'b1_home_screen.dart';
import 'password_screens.dart';

class LoginScreen extends StatefulWidget {
  final String? message;
  const LoginScreen({super.key, this.message});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _serverUrlCtrl = TextEditingController(text: ApiConstants.baseUrl);
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _openingRecovery = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _serverUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_isLoading || _openingRecovery) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Cập nhật Base URL nếu người dùng đổi cấu hình IP máy chủ
    try {
      await ApiConstants.saveBaseUrl(_serverUrlCtrl.text);
      final response = await ApiService.login(
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đăng nhập thành công: ${response.user.fullName} (${response.user.role})',
          ),
          backgroundColor: AppTheme.tertiary,
        ),
      );

      // Chuyển hướng vào Dashboard B1
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const B1HomeScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;

      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      _passwordCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đăng nhập thất bại: $errorMessage'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openRecovery() async {
    if (_isLoading || _openingRecovery) return;
    setState(() => _openingRecovery = true);
    try {
      await ApiConstants.saveBaseUrl(_serverUrlCtrl.text);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PasswordRecoveryScreen()),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst('FormatException: ', ''),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingRecovery = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        appBar: AppBar(title: const Text('Đăng nhập tài xế')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.message != null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryFixed,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(widget.message!),
                        ),
                      ],
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.two_wheeler_rounded,
                            size: 34,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'TVD LOGISTICS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Chào mừng trở lại',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Đăng nhập để bắt đầu ca giao hàng của bạn.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusXl,
                          ),
                          border: Border.all(color: AppTheme.outlineVariant),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.onSurface.withValues(alpha: 0.04),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Địa chỉ máy chủ',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _serverUrlCtrl,
                              enabled: !_isLoading,
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.next,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'http://10.0.2.2:5038',
                                prefixIcon: Icon(Icons.dns_outlined),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Tên đăng nhập',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _usernameCtrl,
                              enabled: !_isLoading,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Vui lòng nhập tên đăng nhập'
                                  : null,
                              decoration: const InputDecoration(
                                hintText: 'Nhập tên đăng nhập',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Mật khẩu',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _passwordCtrl,
                              enabled: !_isLoading,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) {
                                if (!_isLoading) _handleLogin();
                              },
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? 'Vui lòng nhập mật khẩu'
                                  : null,
                              decoration: InputDecoration(
                                hintText: 'Nhập mật khẩu',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword
                                      ? 'Hiện mật khẩu'
                                      : 'Ẩn mật khẩu',
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _isLoading || _openingRecovery
                                    ? null
                                    : _openRecovery,
                                child: const Text('Quên mật khẩu?'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: _isLoading || _openingRecovery
                                    ? null
                                    : _handleLogin,
                                icon: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.2,
                                        ),
                                      )
                                    : const Icon(Icons.login_rounded),
                                label: Text(
                                  _isLoading ? 'ĐANG ĐĂNG NHẬP' : 'ĐĂNG NHẬP',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 16,
                            color: AppTheme.secondary,
                          ),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Sử dụng tài khoản shipper được cấp bởi quản trị viên.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
