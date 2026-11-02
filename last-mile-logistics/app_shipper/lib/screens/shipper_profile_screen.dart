import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/shipper_profile.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';
import '../theme/app_theme.dart';
import 'password_screens.dart';
import 'driver_earnings_screen.dart';

class ShipperProfileScreen extends StatefulWidget {
  final Future<ShipperProfile> Function()? loadProfile;
  const ShipperProfileScreen({super.key, this.loadProfile});

  @override
  State<ShipperProfileScreen> createState() => _ShipperProfileScreenState();
}

class _ShipperProfileScreenState extends State<ShipperProfileScreen>
    with WidgetsBindingObserver {
  ShipperProfile? _profile;
  bool _loading = false, _showIdentity = false;
  String? _error;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await (widget.loadProfile ?? ApiService.getMyProfile)()
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loadedAt = DateTime.now();
        _showIdentity = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.toString().replaceFirst(
          RegExp(r'^(Exception|FormatException):\s*'),
          '',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _value(String value) => value.isEmpty ? 'Chưa cập nhật' : value;
  String _date(DateTime? date) =>
      date == null ? 'Chưa cập nhật' : DateFormat('dd/MM/yyyy').format(date);

  Future<void> _requestVehicleChange(BuildContext context, String? currentPlate) async {
    final plateCtrl = TextEditingController(text: currentPlate ?? '');
    String vehicleType = 'MOTORBIKE';
    final reasonCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.two_wheeler_outlined, color: AppTheme.primary, size: 24),
                  SizedBox(width: 10),
                  Text('Yêu cầu đổi / cập nhật phương tiện', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 6),
              const Text('Yêu cầu sẽ được chuyển đến Điều phối viên để kiểm tra và duyệt xe mới.', style: TextStyle(fontSize: 12, color: AppTheme.secondary)),
              const SizedBox(height: 16),
              TextField(
                controller: plateCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Biển số xe mới *',
                  hintText: 'VD: 59-X1 123.45',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.tag_rounded),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: vehicleType,
                decoration: const InputDecoration(
                  labelText: 'Loại phương tiện',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'MOTORBIKE', child: Text('Xe máy (Tải trọng ≤ 30 - 50 kg)')),
                  DropdownMenuItem(value: 'VAN', child: Text('Xe van / Ba gác (Tải trọng ≤ 500 kg)')),
                  DropdownMenuItem(value: 'TRUCK_500KG', child: Text('Xe tải nhỏ (Tải trọng ≤ 1.000 kg)')),
                  DropdownMenuItem(value: 'TRUCK_2T', child: Text('Xe tải trung (Tải trọng 1.5 - 2.5 tấn)')),
                ],
                onChanged: (v) => setSheetState(() => vehicleType = v ?? 'MOTORBIKE'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Lý do đổi xe (không bắt buộc)',
                  hintText: 'VD: Xe cũ hỏng đang sửa, đổi xe mới...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final plate = plateCtrl.text.trim();
                  if (plate.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Vui lòng nhập biển số xe mới!'), backgroundColor: AppTheme.error),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Đã gửi yêu cầu đổi sang xe biển số $plate đến Điều phối!'),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                },
                child: const Text('Gửi yêu cầu đổi xe', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Hồ sơ tài xế'),
      actions: [
        if (_profile != null)
          IconButton(
            tooltip: 'Sửa thông tin',
            onPressed: _loading ? null : () => _editProfile(_profile!),
            icon: const Icon(Icons.edit_outlined),
          ),
        IconButton(
          tooltip: 'Làm mới hồ sơ',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: _profile == null && _loading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Đang tải hồ sơ…'),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (_loading) const LinearProgressIndicator(),
                    if (_error != null) _errorPanel(),
                    if (_profile != null) ..._details(_profile!),
                  ],
                ),
              ),
      ),
    ),
  );

  Widget _errorPanel() => Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: AppTheme.errorContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Chưa tải được hồ sơ mới nhất',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(_error!),
        if (_profile != null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Thông tin bên dưới là lần tải trước.'),
          ),
        TextButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Thử lại'),
        ),
      ],
    ),
  );

  List<Widget> _details(ShipperProfile profile) {
    final names = profile.fullName.split(RegExp(r'\s+'));
    final initials = names.length == 1
        ? names.first.characters.first
        : '${names.first.characters.first}${names.last.characters.first}';
    final vehicle = profile.currentVehicle;
    final formatNumber = NumberFormat('#,##0.###', 'vi_VN');
    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.primaryFixed,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppTheme.primary,
              child: Text(
                initials.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              profile.fullName,
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text('Mã nhân viên: ${profile.employeeCode}'),
            const SizedBox(height: 12),
            _badge(profile.availabilityLabel),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Thông tin do quản trị viên quản lý. Nếu cần sửa hồ sơ, hãy liên hệ quản trị viên.',
        style: TextStyle(color: AppTheme.secondary, height: 1.5),
      ),
      _section('Thông tin cá nhân', Icons.person_outline, [
        _row('Tên đăng nhập', profile.username),
        _row('Số điện thoại', _value(profile.phone)),
        _row('Email', _value(profile.email)),
        _row(
          'CCCD',
          _identity(profile.identityNumber),
          trailing: profile.identityNumber.isEmpty
              ? null
              : IconButton(
                  tooltip: _showIdentity ? 'Ẩn số CCCD' : 'Hiện số CCCD',
                  onPressed: () =>
                      setState(() => _showIdentity = !_showIdentity),
                  icon: Icon(
                    _showIdentity
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
        ),
      ],
      action: TextButton.icon(
        onPressed: _loading ? null : () => _editProfile(profile),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Sửa'),
      )),
      _section('Giấy phép lái xe', Icons.badge_outlined, [
        _row('Số giấy phép', _value(profile.licenseNumber)),
        _row('Ngày hết hạn', _date(profile.licenseExpiresAt)),
        const SizedBox(height: 8),
        _badge(
          profile.licenseLabel,
          warning:
              profile.licenseStatus == 'EXPIRED' ||
              profile.licenseStatus == 'EXPIRING',
        ),
        if (profile.licenseStatus == 'EXPIRED' ||
            profile.licenseStatus == 'EXPIRING')
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Liên hệ quản trị viên để cập nhật giấy phép.',
              style: TextStyle(color: AppTheme.error),
            ),
          ),
      ]),
      _section('Bưu cục quản lý', Icons.store_outlined, [
        _row('Bưu cục', profile.branch.name),
        _row('Mã bưu cục', profile.branch.code),
        _row('Địa chỉ', profile.branch.address),
        _row('Điện thoại', _value(profile.branch.phone)),
        _row('Email bưu cục', _value(profile.branch.email)),
        if (profile.branch.phone.isNotEmpty)
          TextButton.icon(
            onPressed: () async {
              try {
                await DeviceService.makePhoneCall(profile.branch.phone);
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Chưa mở được cuộc gọi. Vui lòng thử lại.'),
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.phone_outlined),
            label: const Text('Gọi bưu cục'),
          ),
      ]),
      _section(
        'Phương tiện được phân công',
        Icons.two_wheeler_outlined,
        [
          if (vehicle == null) ...[
            const Text('Chưa được phân công phương tiện.'),
            const SizedBox(height: 8),
            const Text(
              'Liên hệ điều phối để kiểm tra phân công.',
              style: TextStyle(color: AppTheme.secondary),
            ),
          ] else ...[
            _row('Biển số', vehicle.licensePlate),
            _row('Mã phương tiện', vehicle.code),
            _row('Loại phương tiện', vehicle.typeLabel),
            _row(
              'Tải trọng tối đa',
              '${formatNumber.format(vehicle.maxWeightKg)} kg',
            ),
            _row(
              'Thể tích tối đa',
              vehicle.maxVolumeM3 == null
                  ? 'Chưa cập nhật'
                  : '${formatNumber.format(vehicle.maxVolumeM3)} m³',
            ),
            _row(
              'Ngày phân công',
              DateFormat('dd/MM/yyyy HH:mm')
                  .format(vehicle.assignedAt.toLocal()),
            ),
            const SizedBox(height: 8),
            _badge(
              vehicle.statusLabel,
              warning:
                  !vehicle.isActive ||
                  {'MAINTENANCE', 'INACTIVE'}.contains(vehicle.status),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _requestVehicleChange(context, vehicle?.licensePlate),
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Yêu cầu đổi / cập nhật phương tiện'),
            ),
          ),
        ],
      ),
      _section(
        'Khu vực phụ trách',
        Icons.location_on_outlined,
        profile.areas.isEmpty
            ? [const Text('Chưa có khu vực được phân công.')]
            : profile.areas
                  .map(
                    (area) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            area.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            area.code,
                            style: const TextStyle(color: AppTheme.secondary),
                          ),
                          if (area.isPrimary || !area.isActive)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (area.isPrimary) _badge('Khu vực chính'),
                                  if (!area.isActive)
                                    _badge('Ngừng hoạt động', warning: true),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
      ),
      const SizedBox(height: 20),
      FilledButton.tonalIcon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DriverEarningsScreen()),
        ),
        icon: const Icon(Icons.monetization_on_outlined),
        label: const Text('Ví thu nhập & Bảng tính thù lao'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen()),
        ),
        icon: const Icon(Icons.lock_outline),
        label: const Text('Đổi mật khẩu'),
      ),
      if (_loadedAt != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'Tải hồ sơ lúc ${DateFormat('HH:mm dd/MM/yyyy').format(_loadedAt!)}',
            style: const TextStyle(fontSize: 12, color: AppTheme.secondary),
          ),
        ),
    ];
  }

  Future<void> _editProfile(ShipperProfile profile) async {
    final nameController = TextEditingController(text: profile.fullName);
    final phoneController = TextEditingController(text: profile.phone);
    final emailController = TextEditingController(text: profile.email);
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    String? dialogError;

    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.edit_outlined, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        const Text(
                          'Sửa thông tin cá nhân',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: saving ? null : () => Navigator.pop(bottomSheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (dialogError != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          dialogError!,
                          style: const TextStyle(color: AppTheme.onErrorContainer),
                        ),
                      ),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Họ và tên *',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().length < 2) {
                          return 'Họ tên phải từ 2 ký tự trở lên';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value != null && value.trim().isNotEmpty) {
                          if (!RegExp(r'^\+?[0-9]{9,15}$').hasMatch(value.trim())) {
                            return 'Số điện thoại phải từ 9 đến 15 chữ số';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value != null && value.trim().isNotEmpty) {
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                            return 'Email không đúng định dạng';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: saving
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) return;
                              setSheetState(() {
                                saving = true;
                                dialogError = null;
                              });
                              try {
                                await ApiService.updateMyProfile(
                                  fullName: nameController.text,
                                  phone: phoneController.text,
                                  email: emailController.text,
                                );
                                if (!context.mounted) return;
                                Navigator.pop(bottomSheetContext, true);
                              } catch (e) {
                                setSheetState(() {
                                  saving = false;
                                  dialogError = e.toString().replaceFirst(
                                    RegExp(r'^(Exception|FormatException):\s*'),
                                    '',
                                  );
                                });
                              }
                            },
                      child: saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Lưu thay đổi',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã cập nhật thông tin cá nhân.')),
      );
      _load();
    }
  }

  String _identity(String value) => value.isEmpty
      ? 'Chưa cập nhật'
      : _showIdentity
      ? value
      : '${List.filled(value.length > 4 ? value.length - 4 : value.length, '•').join()}${value.length > 4 ? value.substring(value.length - 4) : ''}';

  Widget _section(String title, IconData icon, List<Widget> children, {Widget? action}) =>
      Container(
        margin: const EdgeInsets.only(top: 20),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );

  Widget _row(String title, String value, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12, color: AppTheme.secondary),
              ),
              const SizedBox(height: 5),
              SelectableText(value, style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _badge(String label, {bool warning = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: warning ? AppTheme.errorContainer : AppTheme.surfaceContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: warning ? AppTheme.onErrorContainer : AppTheme.onSurface,
      ),
    ),
  );
}
