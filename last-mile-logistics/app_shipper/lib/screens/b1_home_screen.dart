import 'dart:async';

import 'package:flutter/material.dart';

import '../models/auth_and_task_models.dart';
import '../models/driver_workflow.dart';
import '../models/driver_availability.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';
import '../services/realtime_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/driver_dashboard.dart';
import 'a1_welcome_screen.dart';
import 'b2_new_task_popup_dialog.dart';
import 'b3_order_management_screen.dart';
import 'b4_map_route_screen.dart';
import 'b7_cod_wallet_screen.dart';
import 'b8_handover_screen.dart';
import 'c1_return_orders_screen.dart';
import 'password_screens.dart';
import 'shipper_profile_screen.dart';
import 'driver_trips_screen.dart';
import 'notifications_screen.dart';
import 'driver_earnings_screen.dart';
import '../models/driver_earnings_models.dart';

class B1HomeScreen extends StatefulWidget {
  const B1HomeScreen({super.key});
  @override
  State<B1HomeScreen> createState() => _B1HomeScreenState();
}

class _B1HomeScreenState extends State<B1HomeScreen>
    with WidgetsBindingObserver {
  DriverAvailability? _workStatus;
  bool _isUpdatingStatus = false, _offerDialogOpen = false;
  bool _loading = false, _loggingOut = false;
  double? _vehicleMaxWeight;
  int _currentTabIndex = 0, _taskFilter = 0, _profileGeneration = 0;
  String _driverName = 'Tài xế', _employeeCode = '';
  DriverOverview _overview = const DriverOverview();
  List<String> _unavailable = [];
  final List<Map<String, dynamic>> _pendingOffers = [];
  final Set<int> _seenOfferIds = {};
  StreamSubscription<Map<String, dynamic>>? _assignmentSubscription;
  StreamSubscription<void>? _handoverSubscription;
  Timer? _refreshTimer;
  int _unreadNotificationCount = 0;
  final Set<int> _activatedTabs = {0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
    RealtimeService.instance.connect();
    _assignmentSubscription = RealtimeService.instance.taskAssigned.listen(
      _handleTaskAssigned,
    );
    _handoverSubscription = RealtimeService.instance.handoverReady.listen(
      (_) => _refreshDashboard(),
    );
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          _currentTabIndex == 0 &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        _refreshAll();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _assignmentSubscription?.cancel();
    _handoverSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loggingOut) {
      _refreshAll();
      _showPendingOffers();
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadProfile(), _refreshDashboard(), _loadUnreadNotifications()]);
  }

  Future<void> _loadUnreadNotifications() async {
    if (_loggingOut) return;
    try {
      final res = await ApiService.getNotifications(unreadOnly: true, pageSize: 1);
      if (mounted && !_loggingOut) {
        setState(() => _unreadNotificationCount = res.unreadCount);
      }
    } catch (_) {}
  }

  Future<T?> _read<T>(
    String label,
    Future<T> Function() request,
    List<String> unavailable,
  ) async {
    try {
      return await request().timeout(const Duration(seconds: 15));
    } catch (_) {
      unavailable.add(label);
      return null;
    }
  }

  Future<void> _refreshDashboard() async {
    if (!mounted || _loading || _loggingOut) return;
    setState(() => _loading = true);
    final unavailable = <String>[];
    final results = await Future.wait<Object?>([
      _read(
        'nhiệm vụ',
        () => ApiService.getAllMyTasks(activeOnly: true),
        unavailable,
      ),
      _read('phiếu bàn giao', ApiService.getMyPendingHandovers, unavailable),
      _read(
        'COD',
        () => ApiService.getAllCodCollections(outstandingOnly: true),
        unavailable,
      ),
      ApiService.getMyEarnings().catchError((_) => const DriverEarningsSummary(
        shipperId: 0,
        shipperName: '',
        today: 0,
        pending: 0,
        approved: 0,
        paid: 0,
        total: 0,
        deliverySuccessRate: 15000,
        retryBonusRate: 5000,
        returnCompletedRate: 8000,
        todayCount: 0,
        totalCount: 0,
        successCount: 0,
        retryCount: 0,
        returnCount: 0,
      )),
    ]);
    if (!mounted || _loggingOut) return;
    final maxWeight = _vehicleMaxWeight ?? await SessionManager.getVehicleMaxWeight();
    var tasks = results[0] as List<ShipperTaskDto>?;
    if (tasks != null && maxWeight != null) {
      tasks = tasks.where((t) => t.weightKg == null || t.weightKg! <= maxWeight).toList();
    }
    setState(() {
      _overview = DriverOverview(
        tasks: tasks,
        handovers: results[1] as List<ShipperHandoverDto>?,
        cod: results[2] as List<CodCollectionDto>?,
        earnings: results.length > 3 ? results[3] as DriverEarningsSummary? : null,
      );
      _unavailable = unavailable;
      _loading = false;
    });
  }

  bool get _canShowOffer =>
      mounted &&
      !_loggingOut &&
      _currentTabIndex == 0 &&
      (ModalRoute.of(context)?.isCurrent ?? false) &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> _handleTaskAssigned(Map<String, dynamic> assignment) async {
    DeviceService.vibrateAlert();
    final raw = assignment['id'] ?? assignment['assignmentId'];
    final id = raw is int ? raw : int.tryParse('$raw');
    if (!mounted ||
        _loggingOut ||
        id == null ||
        id <= 0 ||
        !_seenOfferIds.add(id)) {
      return;
    }
    _pendingOffers.add({'id': id});
    _refreshDashboard();
    await _showPendingOffers();
  }

  Future<void> _showPendingOffers() async {
    if (_offerDialogOpen || !_canShowOffer) return;
    _offerDialogOpen = true;
    try {
      while (_canShowOffer && _pendingOffers.isNotEmpty) {
        if (!mounted) return;
        final offer = _pendingOffers.removeAt(0);
        final offerId = offer['id'] is int ? offer['id'] as int : int.tryParse('') ?? 0;
        final maxWeight = _vehicleMaxWeight ?? await SessionManager.getVehicleMaxWeight();
        if (maxWeight != null && offerId > 0) {
          try {
            final taskDetail = await ApiService.getMyTaskDetail(offerId);
            if (taskDetail.weightKg != null && taskDetail.weightKg! > maxWeight) {
              try {
                await ApiService.rejectTask(
                  offerId,
                  reason: 'Quá tải trọng phương tiện ( kg >  kg)',
                );
              } catch (_) {}
              continue;
            }
          } catch (_) {}
        }
        if (!mounted) return;
        final response = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => B2NewTaskPopupDialog(assignment: offer),
        );
        if (!mounted || _loggingOut) return;
        _refreshAll();
        if (response == 'accepted') {
          await _openSecondary(
            B4MapRouteScreen(assignmentId: offer['id'] as int),
          );
        } else if (response == 'rejected') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Đã từ chối. Đơn trở về chờ điều phối phân công lại.',
              ),
            ),
          );
        } else if (response == 'later') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Mở mục Chờ nhận để kiểm tra và phản hồi nhiệm vụ.',
              ),
              action: SnackBarAction(
                label: 'Mở nhiệm vụ',
                onPressed: () => _openTasks(0),
              ),
            ),
          );
        }
      }
    } finally {
      _offerDialogOpen = false;
    }
  }

  Future<void> _loadProfile() async {
    if (_isUpdatingStatus || _loggingOut) return;
    final generation = ++_profileGeneration;
    final name = await SessionManager.getFullName();
    final cachedCode = await SessionManager.getEmployeeCode();
    if (!mounted || generation != _profileGeneration) return;
    setState(() {
      if (name?.isNotEmpty == true) _driverName = name!;
      if (cachedCode?.isNotEmpty == true) _employeeCode = cachedCode!;
    });
    final vehicleMax = await SessionManager.getVehicleMaxWeight();
    if (mounted && generation == _profileGeneration) {
      _vehicleMaxWeight = vehicleMax;
    }
    try {
      final profile = await ApiService.getMyProfile().timeout(const Duration(seconds: 15));
      if (mounted && generation == _profileGeneration) {
        _vehicleMaxWeight = profile.currentVehicle?.maxWeightKg;
      }
    } catch (_) {}
    try {
      final status = await ApiService.getWorkStatus().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted || generation != _profileGeneration) return;
      setState(() {
        _workStatus = status;
      });
    } catch (_) {
      if (mounted && generation == _profileGeneration) {
        setState(() => _workStatus = null);
      }
    }
  }

  Future<void> _handleStatusChanged(String target) async {
    final previous = _workStatus;
    if (_isUpdatingStatus ||
        previous == null ||
        !previous.canSet(target) ||
        target == previous.availability ||
        _loggingOut) {
      return;
    }
    ++_profileGeneration;
    setState(() => _isUpdatingStatus = true);
    try {
      double? latitude, longitude, accuracy;
      var locationUnavailable = false;
      if (target == 'AVAILABLE') {
        try {
          final position = await DeviceService.getCurrentPosition().timeout(
            const Duration(seconds: 15),
          );
          latitude = position.latitude;
          longitude = position.longitude;
          accuracy = position.accuracy;
        } catch (_) {
          locationUnavailable = true;
        }
      }
      if (!mounted || _loggingOut) return;
      final updated = await ApiService.updateShipperStatus(
        availability: target,
        expectedAvailability: previous.availability,
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: accuracy,
      );
      if (!mounted || _loggingOut) return;
      setState(() => _workStatus = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${DriverAvailability.labels[updated.availability]}.${locationUnavailable ? ' Chưa lấy được GPS; vị trí cũ chưa được cập nhật.' : ''}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted || _loggingOut) return;
      // A timeout may follow a committed write. Read back; never send it again.
      setState(() => _workStatus = null);
      try {
        final actual = await ApiService.getWorkStatus().timeout(
          const Duration(seconds: 15),
        );
        if (mounted && !_loggingOut) setState(() => _workStatus = actual);
      } catch (_) {
        /* Keep controls unavailable until a successful read. */
      }
      if (mounted && !_loggingOut) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Chưa xác nhận được thay đổi: $error. ${_workStatus == null ? 'Hãy tải lại trạng thái.' : 'Đã tải lại trạng thái hiện tại từ máy chủ.'}',
            ),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đăng xuất tài khoản'),
        content: const Text(
          'Bạn muốn kết thúc phiên làm việc trên thiết bị này?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Ở lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _loggingOut = true);
    var serverConfirmed = true;
    try {
      await ApiService.logout();
    } catch (_) {
      serverConfirmed = false;
    }
    await RealtimeService.instance.disconnect();
    if (!mounted) return;
    if (!serverConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đã đăng xuất trên thiết bị. Chưa xác nhận thu hồi phiên với máy chủ do lỗi kết nối.',
          ),
        ),
      );
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const A1WelcomeScreen()),
      (_) => false,
    );
  }

  void _openTasks(int filter) => setState(() {
    _taskFilter = filter;
    _activatedTabs.add(1);
    _currentTabIndex = 1;
  });

  void _openTab(int index) {
    if (index == _currentTabIndex) return;
    setState(() {
      _activatedTabs.add(index);
      _currentTabIndex = index;
    });
    if (index == 0) {
      _refreshAll();
      _showPendingOffers();
    }
  }

  Future<void> _openSecondary(Widget screen) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    if (!mounted) return;
    if (result == DriverRouteResult.received) _openTasks(2);
    _refreshAll();
    _showPendingOffers();
  }

  @override
  Widget build(BuildContext context) {
    final content = IndexedStack(
      index: _currentTabIndex,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: DriverDashboard(
              driverName: _driverName,
              employeeCode: _employeeCode,
              workStatus: _workStatus,
              changingStatus: _isUpdatingStatus,
              loading: _loading,
              overview: _overview,
              unavailableSections: _unavailable,
              onRefresh: _refreshAll,
              onStatusChanged: _handleStatusChanged,
              onTasks: _openTasks,
              onHandovers: () => _openSecondary(const B8HandoverScreen()),
              onReturns: () => _openSecondary(const C1ReturnOrdersScreen()),
              onCod: () => _openTab(3),
              onEarnings: () => _openSecondary(const DriverEarningsScreen()),
            ),
          ),
        ),
        _activatedTabs.contains(1)
            ? B3OrderManagementScreen(
                key: ValueKey(_taskFilter),
                initialFilter: _taskFilter,
                embedded: true,
              )
            : const SizedBox.shrink(),
        (_activatedTabs.contains(2) && _currentTabIndex == 2)
            ? B4MapRouteScreen(onReceived: (_) => _openTasks(2))
            : const SizedBox.shrink(),
        _activatedTabs.contains(3)
            ? const B7CodWalletScreen()
            : const SizedBox.shrink(),
        _activatedTabs.contains(4)
            ? const ShipperProfileScreen()
            : const SizedBox.shrink(),
      ],
    );    return PopScope(
      canPop: _currentTabIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentTabIndex != 0) _openTab(0);
      },
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        appBar: _currentTabIndex == 0
            ? AppBar(
                titleSpacing: 20,
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.local_shipping_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TVD Logistics',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                            ),
                          ),
                          Text(
                            'Ứng dụng tài xế',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: 'Thông báo',
                    onPressed: () async {
                      await _openSecondary(const NotificationsScreen());
                      _loadUnreadNotifications();
                    },
                    icon: Badge(
                      isLabelVisible: _unreadNotificationCount > 0,
                      label: Text(
                        '$_unreadNotificationCount',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      child: const Icon(Icons.notifications_outlined),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ví thu nhập tài xế',
                    onPressed: () => _openSecondary(const DriverEarningsScreen()),
                    icon: const Icon(Icons.monetization_on_outlined),
                  ),
                  IconButton(
                    tooltip: 'Chuyến giao & lịch sử',
                    onPressed: () => _openSecondary(const DriverTripsScreen()),
                    icon: const Icon(Icons.alt_route_rounded),
                  ),
                  IconButton(
                    tooltip: 'Làm mới công việc',
                    onPressed: _loading ? null : _refreshAll,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Tài khoản tài xế',
                    onSelected: (value) {
                      if (_loggingOut) return;
                      if (value == 'logout') _confirmLogout();
                      if (value == 'notifications') {
                        _openSecondary(const NotificationsScreen());
                        _loadUnreadNotifications();
                      }
                      if (value == 'earnings') {
                        _openSecondary(const DriverEarningsScreen());
                      }
                      if (value == 'trips') {
                        _openSecondary(const DriverTripsScreen());
                      }
                      if (value == 'profile') {
                        _openSecondary(const ShipperProfileScreen());
                      }
                      if (value == 'change-password') {
                        _openSecondary(const ChangePasswordScreen());
                      }
                    },
                    icon: CircleAvatar(
                      radius: 17,
                      backgroundColor: AppTheme.primaryFixed,
                      child: Text(
                        _driverName.characters.first.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    itemBuilder: (_) => [
                      PopupMenuItem(enabled: false, child: Text(_driverName)),
                      const PopupMenuItem(
                        value: 'earnings',
                        child: Text('Ví thu nhập tài xế'),
                      ),
                      const PopupMenuItem(
                        value: 'trips',
                        child: Text('Chuyến giao & lịch sử'),
                      ),
                      const PopupMenuItem(
                        value: 'profile',
                        child: Text('Hồ sơ tài xế'),
                      ),
                      const PopupMenuItem(
                        value: 'change-password',
                        child: Text('Đổi mật khẩu'),
                      ),
                      const PopupMenuItem(
                        value: 'notifications',
                        child: Text('Thông báo'),

                      ),
                      const PopupMenuItem(
                        value: 'logout',
                        child: Text('Đăng xuất'),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                ],
              )
            : null,
        body: Stack(
          children: [
            Positioned.fill(child: content),
            if (_loggingOut)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.white70,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Đang đăng xuất…'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentTabIndex,
          onDestinationSelected: _loggingOut ? null : _openTab,
          backgroundColor: Colors.white,
          indicatorColor: AppTheme.primaryFixed.withValues(alpha: .6),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Trang chủ',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_shipping_outlined),
              selectedIcon: Icon(Icons.local_shipping_rounded),
              label: 'Đơn hàng',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded),
              label: 'Lộ trình',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Ví tiền',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Cá nhân',
            ),
          ],
        ),
      ),
    );
  }
}
