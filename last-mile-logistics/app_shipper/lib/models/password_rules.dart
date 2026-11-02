import 'dart:convert';

class PasswordRules {
  static String? current(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Vui lòng nhập mật khẩu hiện tại.';
    }
    if (utf8.encode(value).length > 72) return 'Mật khẩu quá dài.';
    return null;
  }

  static String? newPassword(String? value, {String? currentPassword}) {
    if (value == null || value.trim().isEmpty) {
      return 'Vui lòng nhập mật khẩu mới.';
    }
    if (value.length < 8) return 'Mật khẩu mới cần ít nhất 8 ký tự.';
    // Match the backend's BCrypt UTF-8 limit, including Vietnamese/emoji input.
    if (value.length > 72 || utf8.encode(value).length > 72) {
      return 'Mật khẩu quá dài. Hãy dùng ít ký tự hơn.';
    }
    if (value == currentPassword) {
      return 'Mật khẩu mới phải khác mật khẩu hiện tại.';
    }
    return null;
  }

  static String? confirm(String? value, String newPassword) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng xác nhận mật khẩu mới.';
    }
    if (value != newPassword) return 'Xác nhận mật khẩu không khớp.';
    return null;
  }

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Vui lòng nhập email đã đăng ký.';
    if (email.length > 150 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Địa chỉ email không hợp lệ.';
    }
    return null;
  }

  static String? recoveryToken(String? value) {
    final token = value?.trim() ?? '';
    if (token.isEmpty) return 'Vui lòng nhập mã khôi phục trong email.';
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      return 'Hãy sao chép đầy đủ mã khôi phục trong email.';
    }
    return null;
  }
}
