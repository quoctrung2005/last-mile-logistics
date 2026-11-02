import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/password_rules.dart';
import '../services/registration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/password_input.dart';
import 'a1_welcome_screen.dart';
import 'login_screen.dart';

const registrationStates = {
  'PENDING': 'Chờ xét duyệt',
  'NEEDS_INFO': 'Cần bổ sung',
  'APPROVED': 'Đã được duyệt',
  'REJECTED': 'Đã từ chối',
};
const registrationDocuments = {
  'IDENTITY_FRONT': 'CCCD mặt trước',
  'IDENTITY_BACK': 'CCCD mặt sau',
  'LICENSE': 'Giấy phép lái xe',
  'PORTRAIT': 'Ảnh chân dung',
};

class RegistrationScreen extends StatefulWidget {
  final RegistrationService? service;
  final Future<XFile?> Function(String kind)? pickPhoto;
  const RegistrationScreen({super.key, this.service, this.pickPhoto});
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  RegistrationService get _service =>
      widget.service ?? RegistrationService.instance;
  final _forms = List.generate(4, (_) => GlobalKey<FormState>());
  final _fields = {
    for (final name in [
      'FullName',
      'Phone',
      'Email',
      'IdentityNumber',
      'Username',
      'Password',
      'ConfirmPassword',
      'LicenseNumber',
      'LicensePlate',
    ])
      name: TextEditingController(),
  };
  final Map<String, Uint8List> _photos = {};
  List<Map<String, dynamic>> _branches = [];
  RegistrationReceipt? _receipt;
  String? _version, _error;
  DateTime? _birth, _expires;
  int? _branch, _area;
  String _vehicle = 'MOTORBIKE';
  int _step = 0;
  bool _loading = true, _busy = false, _consent = false;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _branches = await _service.catalogs();
      if (_branches.isEmpty) {
        throw const RegistrationException(
          'Chưa có bưu cục tiếp nhận đăng ký. Vui lòng thử lại sau.',
        );
      }
      final saved = await _service.savedReceipt();
      Map<String, dynamic>? old;
      if (saved != null) {
        try {
          old = await _service.status(saved);
        } on RegistrationException catch (e) {
          if (e.status != 404) rethrow;
        }
      }
      if (!mounted) return;
      if (old != null && {'PENDING', 'APPROVED'}.contains(old['status'])) {
        _openStatus(saved!);
        return;
      }
      _receipt = old?['status'] == 'REJECTED'
          ? RegistrationReceipt.create()
          : saved ?? RegistrationReceipt.create();
      if (old?['status'] == 'NEEDS_INFO') {
        _version = old!['version'] as String;
        for (final entry in {
          'FullName': 'fullName',
          'Phone': 'phone',
          'Email': 'email',
          'IdentityNumber': 'identityNumber',
          'Username': 'username',
          'LicenseNumber': 'licenseNumber',
          'LicensePlate': 'licensePlate',
        }.entries) {
          _fields[entry.key]!.text = old[entry.value]?.toString() ?? '';
        }
        _birth = DateTime.tryParse(old['birthDate']?.toString() ?? '');
        _expires = DateTime.tryParse(old['licenseExpiresAt']?.toString() ?? '');
        _vehicle = old['vehicleType'] as String;
        _branch = (old['branchId'] as num).toInt();
        _area = (old['areaId'] as num).toInt();
        if (!_branches.any((b) => b['id'] == _branch)) {
          _branch = null;
          _area = null;
        }
        if (!_areas.any((a) => a['id'] == _area)) _area = null;
      }
    } catch (e) {
      if (mounted) _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _areas {
    final branch = _branches.where((b) => b['id'] == _branch).firstOrNull;
    return ((branch?['areas'] ?? []) as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  void _openStatus(RegistrationReceipt receipt) {
    _fields['Password']!.clear();
    _fields['ConfirmPassword']!.clear();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) =>
            RegistrationStatusScreen(service: _service, receipt: receipt),
      ),
      (_) => false,
    );
  }

  Future<void> _photo(String kind) async {
    if (_busy) return;
    try {
      XFile? photo;
      if (widget.pickPhoto != null) {
        photo = await widget.pickPhoto!(kind);
      } else {
        final source = await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Chụp ảnh'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Chọn từ thư viện'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
        if (source == null) return;
        photo = await ImagePicker().pickImage(
          source: source,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
          preferredCameraDevice: kind == 'PORTRAIT'
              ? CameraDevice.front
              : CameraDevice.rear,
        );
      }
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
        throw const RegistrationException('Ảnh phải lớn hơn 0 và tối đa 5 MB.');
      }
      if (mounted) {
        setState(() {
          _photos[kind] = bytes;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Chưa chọn được ảnh. $e');
    }
  }

  Future<void> _date(bool license) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final value = await showDatePicker(
      context: context,
      confirmText: 'Chọn',
      cancelText: 'Hủy',
      initialDate: license
          ? (_expires != null && !_expires!.isBefore(today)
                ? _expires!
                : today.add(const Duration(days: 365)))
          : (_birth ?? DateTime(today.year - 20)),
      firstDate: license ? today : DateTime(1900),
      lastDate: license
          ? DateTime(today.year + 50)
          : today.subtract(const Duration(days: 1)),
    );
    if (value != null && mounted) {
      setState(() {
        if (license) {
          _expires = value;
        } else {
          _birth = value;
        }
      });
    }
  }

  Future<void> _next() async {
    if (_busy || !_forms[_step].currentState!.validate()) return;
    if (_step == 1 && (_photos.length != 4 || _expires == null)) {
      setState(() => _error = 'Chọn đủ 4 ảnh và ngày hết hạn giấy phép.');
      return;
    }
    if (_step < 3) {
      setState(() {
        _step++;
        _error = null;
      });
      return;
    }
    if (!_consent) {
      setState(() => _error = 'Hãy xác nhận thông tin trước khi gửi.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final receipt = _receipt!;
    try {
      final fields = {
        for (final e in _fields.entries)
          e.key: e.key.contains('Password')
              ? e.value.text
              : e.value.text.trim(),
        'LicenseExpiresAt': DateFormat('yyyy-MM-dd').format(_expires!),
        'BranchId': '$_branch',
        'AreaId': '$_area',
        'VehicleType': _vehicle,
        if (_birth != null)
          'BirthDate': DateFormat('yyyy-MM-dd').format(_birth!),
        'ExpectedVersion': ?_version,
      };
      await _service.submit(
        receipt,
        fields,
        _photos,
        resubmit: _version != null,
      );
      if (mounted) _openStatus(receipt);
    } catch (e) {
      try {
        final state = await _service.status(receipt);
        if (mounted && state['status'] != 'NEEDS_INFO') {
          _openStatus(receipt);
          return;
        }
      } catch (_) {
        /* Keep the receipt for an explicit status check or retry. */
      }
      if (mounted) {
        setState(() => _error = 'Chưa xác nhận gửi hồ sơ thành công. $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _input(
    String name,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(name),
      controller: _fields[name],
      enabled: !_busy,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
      validator:
          validator ??
          (v) => v == null || v.trim().isEmpty ? 'Vui lòng nhập $label.' : null,
    ),
  );
  List<Widget> _content() => switch (_step) {
    0 => [
      _input(
        'FullName',
        'Họ và tên',
        validator: (v) => v == null || v.trim().isEmpty || v.length > 150
            ? 'Nhập họ tên tối đa 150 ký tự.'
            : null,
      ),
      _input(
        'Phone',
        'Số điện thoại',
        keyboard: TextInputType.phone,
        validator: (v) => RegExp(r'^\+?[0-9]{9,15}$').hasMatch(v?.trim() ?? '')
            ? null
            : 'Số điện thoại cần 9–15 chữ số.',
      ),
      _input(
        'Email',
        'Email',
        keyboard: TextInputType.emailAddress,
        validator: PasswordRules.email,
      ),
      _input(
        'IdentityNumber',
        'Số CCCD',
        keyboard: TextInputType.number,
        validator: (v) => RegExp(r'^[0-9]{12}$').hasMatch(v ?? '')
            ? null
            : 'CCCD cần đủ 12 chữ số.',
      ),
      TextButton.icon(
        onPressed: () => _date(false),
        icon: const Icon(Icons.calendar_today_outlined),
        label: Text(
          _birth == null
              ? 'Ngày sinh (không bắt buộc)'
              : DateFormat('dd/MM/yyyy').format(_birth!),
        ),
      ),
      _input(
        'Username',
        'Tên đăng nhập',
        validator: (v) =>
            RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{2,99}$')
                .hasMatch(v?.trim() ?? '')
            ? null
            : 'Tên đăng nhập từ 3–100 ký tự: chữ Latin, số, . _ -',
      ),
      PasswordInput(
        key: const ValueKey('registration-password'),
        controller: _fields['Password']!,
        label: 'Mật khẩu',
        newPassword: true,
        enabled: !_busy,
        validator: PasswordRules.newPassword,
      ),
      const SizedBox(height: 16),
      PasswordInput(
        controller: _fields['ConfirmPassword']!,
        label: 'Xác nhận mật khẩu',
        newPassword: true,
        enabled: !_busy,
        validator: (v) => PasswordRules.confirm(v, _fields['Password']!.text),
      ),
    ],
    1 => [
      const Text(
        'Ảnh được quản trị viên kiểm tra thủ công. Đây chưa phải xác minh eKYC tự động.',
      ),
      if (_version != null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Hồ sơ bổ sung cần nhập lại mật khẩu và chọn đầy đủ ảnh.',
          ),
        ),
      for (final e in registrationDocuments.entries)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  e.value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (_photos[e.key] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Image.memory(
                      _photos[e.key]!,
                      height: 100,
                      errorBuilder: (_, _, _) => const Text(
                        'Chưa xem được ảnh; hãy chọn ảnh JPEG hoặc PNG khác.',
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  key: ValueKey(e.key),
                  onPressed: _busy ? null : () => _photo(e.key),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(
                    _photos[e.key] == null ? 'Chọn ảnh' : 'Chọn lại ảnh',
                  ),
                ),
              ],
            ),
          ),
        ),
      _input(
        'LicenseNumber',
        'Số giấy phép lái xe',
        validator: (v) =>
            RegExp(r'^[A-Za-z0-9 -]{1,50}$').hasMatch(v?.trim() ?? '')
            ? null
            : 'Nhập số giấy phép hợp lệ, tối đa 50 ký tự.',
      ),
      TextButton.icon(
        onPressed: () => _date(true),
        icon: const Icon(Icons.calendar_today_outlined),
        label: Text(
          _expires == null
              ? 'Chọn hạn giấy phép'
              : 'Hạn giấy phép: ${DateFormat('dd/MM/yyyy').format(_expires!)}',
        ),
      ),
    ],
    2 => [
      DropdownButtonFormField<String>(
        initialValue: _vehicle,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Phương tiện đề xuất'),
        items: const [
          DropdownMenuItem(value: 'MOTORBIKE', child: Text('Xe máy')),
          DropdownMenuItem(value: 'VAN', child: Text('Xe van')),
          DropdownMenuItem(value: 'TRUCK', child: Text('Xe tải')),
        ],
        onChanged: (v) => setState(() => _vehicle = v!),
      ),
      const SizedBox(height: 16),
      _input(
        'LicensePlate',
        'Biển số xe',
        validator: (v) =>
            RegExp(r'^[A-Za-z0-9. -]{3,20}$').hasMatch(v?.trim() ?? '')
            ? null
            : 'Nhập biển số từ 3–20 ký tự.',
      ),
      DropdownButtonFormField<int>(
        initialValue: _branch,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Bưu cục muốn hoạt động'),
        items: _branches
            .map(
              (b) => DropdownMenuItem(
                value: (b['id'] as num).toInt(),
                child: Text(b['name'] as String),
              ),
            )
            .toList(),
        validator: (v) => v == null ? 'Chọn bưu cục.' : null,
        onChanged: (v) => setState(() {
          _branch = v;
          _area = null;
        }),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<int>(
        key: ValueKey(_branch),
        initialValue: _area,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Khu vực chính'),
        items: _areas
            .map(
              (a) => DropdownMenuItem(
                value: (a['id'] as num).toInt(),
                child: Text(a['name'] as String),
              ),
            )
            .toList(),
        validator: (v) => v == null ? 'Chọn khu vực thuộc bưu cục.' : null,
        onChanged: (v) => setState(() => _area = v),
      ),
      const SizedBox(height: 16),
      const Text(
        'Phương tiện sẽ được quản trị viên kiểm tra và phân công sau khi hồ sơ được duyệt.',
      ),
    ],
    _ => [
      for (final key in [
        'FullName',
        'Username',
        'Phone',
        'Email',
        'LicensePlate',
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(_fields[key]!.text),
        ),
      Text('Đã chọn ${_photos.length}/4 ảnh giấy tờ.'),
      const SizedBox(height: 16),
      const Text(
        'Tài khoản chỉ được kích hoạt sau khi quản trị viên duyệt hồ sơ.',
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _consent,
        onChanged: _busy ? null : (v) => setState(() => _consent = v ?? false),
        title: const Text(
          'Tôi xác nhận thông tin và ảnh giấy tờ là của tôi, đồng ý gửi để quản trị viên xét duyệt.',
        ),
      ),
    ],
  };
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(_version == null ? 'Đăng ký tài xế' : 'Bổ sung hồ sơ'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _receipt == null
                      ? Column(
                          children: [
                            Text(_error ?? 'Chưa có bưu cục tiếp nhận.'),
                            TextButton(
                              onPressed: _initialize,
                              child: const Text('Thử lại'),
                            ),
                          ],
                        )
                      : Form(
                          key: _forms[_step],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              LinearProgressIndicator(value: (_step + 1) / 4),
                              const SizedBox(height: 16),
                              Text(
                                'Bước ${_step + 1}/4 · ${['Thông tin cá nhân', 'Ảnh giấy tờ', 'Phương tiện và bưu cục', 'Kiểm tra và gửi'][_step]}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 20),
                              ..._content(),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: AppTheme.error,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _busy ? null : _next,
                                child: Text(
                                  _busy
                                      ? 'Đang gửi hồ sơ…'
                                      : _step == 3
                                      ? 'Gửi hồ sơ xét duyệt'
                                      : 'Tiếp tục',
                                ),
                              ),
                              if (_step > 0)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                          _step--;
                                          _error = null;
                                        }),
                                  child: const Text('Quay lại bước trước'),
                                ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
    ),
  );
}

class RegistrationStatusScreen extends StatefulWidget {
  final RegistrationReceipt? receipt;
  final RegistrationService? service;
  const RegistrationStatusScreen({super.key, this.receipt, this.service});
  @override
  State<RegistrationStatusScreen> createState() =>
      _RegistrationStatusScreenState();
}

class _RegistrationStatusScreenState extends State<RegistrationStatusScreen>
    with WidgetsBindingObserver {
  RegistrationService get _service =>
      widget.service ?? RegistrationService.instance;
  Map<String, dynamic>? _data;
  RegistrationReceipt? _receipt;
  String? _error;
  bool _busy = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (ModalRoute.of(context)?.isCurrent ?? false) _load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _receipt = widget.receipt ?? await _service.savedReceipt();
      if (_receipt != null) {
        final data = await _service.status(_receipt!);
        if (mounted) setState(() => _data = data);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Theo dõi hồ sơ đăng ký'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _load,
          tooltip: 'Làm mới trạng thái',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Chưa cập nhật được trạng thái. $_error',
                  style: const TextStyle(color: AppTheme.error),
                ),
              ),
            if (_receipt == null && !_busy)
              const Text(
                'Chưa có mã theo dõi hồ sơ trên thiết bị này. Nếu đã gửi từ thiết bị khác, hãy liên hệ quản trị viên.',
              ),
            if (_data != null) ...[
              Text(
                registrationStates[_data!['status']]!,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(_data!['fullName'] as String),
              Text('Tên đăng nhập: ${_data!['username']}'),
              Text('Bưu cục: ${_data!['branchName']}'),
              const SizedBox(height: 12),
              SelectableText('Mã hồ sơ: ${_data!['id']}'),
              if (_data!['reviewReason'] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('Phản hồi: ${_data!['reviewReason']}'),
                ),
              if (_data!['status'] == 'PENDING')
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Máy chủ đã nhận hồ sơ. Quản trị viên sẽ kiểm tra thông tin và ảnh giấy tờ.',
                  ),
                ),
              if (_data!['status'] == 'APPROVED') ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Bạn có thể đăng nhập bằng tài khoản đã đăng ký. Phương tiện được điều phối phân công riêng.',
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false,
                  ),
                  child: const Text('Đăng nhập tài xế'),
                ),
              ],
              if ({'NEEDS_INFO', 'REJECTED'}.contains(_data!['status']))
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RegistrationScreen(service: _service),
                    ),
                  ),
                  child: Text(
                    _data!['status'] == 'NEEDS_INFO'
                        ? 'Bổ sung và gửi lại hồ sơ'
                        : 'Đăng ký hồ sơ mới',
                  ),
                ),
            ],
            if (_data == null && !_busy)
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RegistrationScreen(service: _service),
                  ),
                ),
                child: const Text('Tiếp tục đăng ký'),
              ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const A1WelcomeScreen()),
                (_) => false,
              ),
              child: const Text('Về trang chào mừng'),
            ),
          ],
        ),
      ),
    ),
  );
}
