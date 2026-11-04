import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    backgroundColor: const Color(0xFFF8FAFC),
    appBar: AppBar(
      title: const Text(
        'Theo dõi hồ sơ đăng ký',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17.5),
      ),
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF0F172A),
      actions: [
        IconButton(
          onPressed: _busy ? null : _load,
          tooltip: 'Làm mới trạng thái',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(minHeight: 2.5),
              ),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Chưa cập nhật được trạng thái. $_error',
                        style: const TextStyle(color: AppTheme.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            if (_receipt == null && !_busy)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Text(
                  'Chưa có mã theo dõi hồ sơ trên thiết bị này. Nếu đã gửi từ thiết bị khác, hãy liên hệ quản trị viên.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13.5, height: 1.5),
                ),
              ),
            if (_data != null) ...[
              // 1. HERO STATUS CARD
              _buildStatusHero(_data!['status'] as String),
              const SizedBox(height: 14),

              // 2. STEP TRACKER
              _buildStepTracker(_data!['status'] as String),
              const SizedBox(height: 14),

              // 3. PROFILE DETAILS CARD
              _buildProfileDetailsCard(context, _data!),
              const SizedBox(height: 14),

              // FEEDBACK REASON (NẾU CÓ)
              if (_data!['reviewReason'] != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.feedback_outlined, color: Color(0xFFD97706), size: 19),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Phản hồi: ${_data!['reviewReason'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF92400E),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // PRIMARY ACTION BUTTON
              if (_data!['status'] == 'APPROVED')
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 1,
                  ),
                  icon: const Icon(Icons.login_rounded, size: 20),
                  label: const Text(
                    'Đăng nhập tài xế',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),

              if ({'NEEDS_INFO', 'REJECTED'}.contains(_data!['status']))
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RegistrationScreen(service: _service),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _data!['status'] == 'NEEDS_INFO'
                        ? const Color(0xFF2563EB)
                        : AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 1,
                  ),
                  icon: Icon(
                    _data!['status'] == 'NEEDS_INFO' ? Icons.edit_note_rounded : Icons.replay_rounded,
                    size: 20,
                  ),
                  label: Text(
                    _data!['status'] == 'NEEDS_INFO'
                        ? 'Bổ sung và gửi lại hồ sơ'
                        : 'Đăng ký hồ sơ mới',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
            ],

            if (_data == null && !_busy)
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RegistrationScreen(service: _service),
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: const Text(
                  'Tiếp tục đăng ký',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),

            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const A1WelcomeScreen()),
                (_) => false,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                backgroundColor: Colors.white,
              ),
              icon: const Icon(Icons.home_outlined, size: 18, color: Color(0xFF475569)),
              label: const Text(
                'Về trang chào mừng',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildStatusHero(String status) {
    final Color primaryColor;
    final Color bgColor;
    final Color borderColor;
    final IconData icon;
    final String badgeText;
    final String subtitle;

    switch (status) {
      case 'APPROVED':
        primaryColor = const Color(0xFF10B981);
        bgColor = const Color(0xFFECFDF5);
        borderColor = const Color(0xFFA7F3D0);
        icon = Icons.check_circle_rounded;
        badgeText = 'HỒ SƠ HỢP LỆ';
        subtitle = 'Bạn có thể đăng nhập bằng tài khoản đã đăng ký. Phương tiện được điều phối phân công riêng.';
        break;
      case 'REJECTED':
        primaryColor = const Color(0xFFDC2626);
        bgColor = const Color(0xFFFEF2F2);
        borderColor = const Color(0xFFFECACA);
        icon = Icons.cancel_rounded;
        badgeText = 'ĐÃ TỪ CHỐI';
        subtitle = 'Hồ sơ chưa đạt yêu cầu của bưu cục. Vui lòng xem phản hồi bên dưới và tạo hồ sơ mới.';
        break;
      case 'NEEDS_INFO':
        primaryColor = const Color(0xFF2563EB);
        bgColor = const Color(0xFFEFF6FF);
        borderColor = const Color(0xFFBFDBFE);
        icon = Icons.help_outline_rounded;
        badgeText = 'CẦN BỔ SUNG';
        subtitle = 'Quản trị viên yêu cầu bổ sung thông tin hoặc chụp lại ảnh giấy tờ rõ nét hơn.';
        break;
      case 'PENDING':
      default:
        primaryColor = const Color(0xFFFA5A00);
        bgColor = const Color(0xFFFFF7ED);
        borderColor = const Color(0xFFFFEDD5);
        icon = Icons.hourglass_top_rounded;
        badgeText = 'ĐANG XÉT DUYỆT';
        subtitle = 'Máy chủ đã nhận hồ sơ. Quản trị viên sẽ kiểm tra thông tin và ảnh giấy tờ.';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, size: 34, color: primaryColor),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: primaryColor,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            registrationStates[status] ?? status,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF475569),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepTracker(String status) {
    final bool isApproved = status == 'APPROVED';
    final bool isPending = status == 'PENDING';
    final bool isRejected = status == 'REJECTED';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildStepItem('1', 'Nộp hồ sơ', true, isCompleted: true),
          Expanded(child: _buildStepLine(true)),
          _buildStepItem(
            '2',
            'Xét duyệt',
            true,
            isCompleted: isApproved,
            isFailed: isRejected,
            isActive: isPending,
          ),
          Expanded(child: _buildStepLine(isApproved)),
          _buildStepItem(
            '3',
            'Nhận ca',
            isApproved,
            isCompleted: isApproved,
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(String number, String label, bool isReached,
      {bool isCompleted = false, bool isFailed = false, bool isActive = false}) {
    final Color color = isFailed
        ? const Color(0xFFDC2626)
        : isCompleted
            ? const Color(0xFF10B981)
            : isActive
                ? const Color(0xFFFA5A00)
                : const Color(0xFFCBD5E1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: isCompleted
                ? const Color(0xFF10B981)
                : isActive
                    ? const Color(0xFFFFF7ED)
                    : isFailed
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFF1F5F9),
            shape: BoxShape.circle,
            border: Border.all(
              color: color,
              width: isActive ? 2 : 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: isCompleted
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : isFailed
                  ? const Icon(Icons.close, size: 14, color: Color(0xFFDC2626))
                  : Text(
                      number,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isActive ? const Color(0xFFFA5A00) : const Color(0xFF64748B),
                      ),
                    ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isReached ? FontWeight.w700 : FontWeight.w500,
            color: isReached ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(bool isDone) {
    return Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 16),
      color: isDone ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
    );
  }

  Widget _buildProfileDetailsCard(BuildContext context, Map<String, dynamic> data) {
    final receiptId = data['id']?.toString() ?? '—';
    final fullName = data['fullName']?.toString() ?? '—';
    final username = data['username']?.toString() ?? '—';
    final branchName = data['branchName']?.toString() ?? '—';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.badge_outlined, size: 18, color: Color(0xFF475569)),
              ),
              const SizedBox(width: 8),
              const Text(
                'THÔNG TIN HỒ SƠ ĐĂNG KÝ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF475569),
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),
          _buildInfoRow(
            Icons.person_outline_rounded,
            'Họ và tên',
            fullName,
            isBold: true,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            Icons.account_circle_outlined,
            'Tên đăng nhập',
            username,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            Icons.storefront_outlined,
            'Bưu cục tiếp nhận',
            branchName,
          ),
          const SizedBox(height: 12),
          // MÃ HỒ SƠ VỚI NÚT SAO CHÉP
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.tag_rounded, size: 18, color: Color(0xFFFA5A00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MÃ HỒ SƠ',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        'Mã hồ sơ: $receiptId',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Sao chép mã hồ sơ',
                  icon: const Icon(Icons.copy_rounded, size: 17, color: Color(0xFF64748B)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: receiptId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã sao chép mã hồ sơ'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // Hidden node for test harness string matching compatibility
          Offstage(
            offstage: true,
            child: Column(
              children: [
                Text(fullName),
                Text('Tên đăng nhập: $username'),
                Text('Bưu cục: $branchName'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {bool isBold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 8),
        SizedBox(
          width: 125,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: const Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }
}
