import 'package:flutter/material.dart';

import 'dart:async';

import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';
import '../services/realtime_service.dart';
import '../services/session_manager.dart';
import '../models/auth_and_task_models.dart';
import '../models/driver_workflow.dart';
import '../models/task_page.dart';
import '../widgets/driver_task_card.dart';
import '../widgets/canned_sms_sheet.dart';
import 'b4_map_route_screen.dart';
import 'b2_new_task_popup_dialog.dart';
import 'b5_delivery_success_screen.dart';
import 'b6_delivery_failed_screen.dart';
import 'b8_handover_screen.dart';
import 'batch_return_handover_screen.dart';
import '../widgets/proof_of_delivery_dialog.dart';
import '../widgets/quick_barcode_scan_dialog.dart';
import 'c2_return_request_detail_screen.dart';
import 'task_detail_screen.dart';
import 'driver_trips_screen.dart';
import '../widgets/emergency_incident_dialog.dart';

class B3OrderManagementScreen extends StatefulWidget {
  final int initialFilter;
  final bool embedded;
  final Future<TaskPage> Function({
    required String taskGroup,
    required String keyword,
    required int page,
  })?
  loadPage;
  final Stream<void>? updates;
  final bool connectRealtime;
  const B3OrderManagementScreen({
    super.key,
    this.initialFilter = 0,
    this.embedded = false,
    this.loadPage,
    this.updates,
    this.connectRealtime = true,
  }) : assert(initialFilter >= 0 && initialFilter <= 4);

  @override
  State<B3OrderManagementScreen> createState() =>
      _B3OrderManagementScreenState();
}

class _B3OrderManagementScreenState extends State<B3OrderManagementScreen>
    with WidgetsBindingObserver {
  int _selectedFilter = 0;
  final _searchCtrl = TextEditingController();
  Timer? _refreshTimer, _searchTimer;
  StreamSubscription<void>? _changeSubscription;
  int _page = 0;
  int? _total;
  bool _hasMore = false,
      _loadingMore = false,
      _dataCurrent = false,
      _searchPending = false;
  String? _moreError;
  StreamSubscription<Map<String, dynamic>>? _assignmentSubscription;
  bool _isLoading = false;
  bool _isActing = false;
  int _loadGeneration = 0;
  String? _errorMessage;
  double? _vehicleMaxWeight;
  List<ShipperTaskDto> _tasks = [];

  final _currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedFilter = widget.initialFilter;
    SessionManager.getVehicleMaxWeight().then((w) {
      if (mounted) setState(() => _vehicleMaxWeight = w);
    });
    _fetchTasks();
    if (widget.connectRealtime) RealtimeService.instance.connect();
    if (widget.connectRealtime) {
      _assignmentSubscription = RealtimeService.instance.taskAssigned.listen((
        _,
      ) {
        DeviceService.vibrateAlert();
        _fetchTasks(showLoading: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bạn vừa nhận được nhiệm vụ mới.')),
          );
        }
      });
    }
    _changeSubscription =
        (widget.updates ??
                (widget.connectRealtime
                    ? RealtimeService.instance.handoverReady
                    : const Stream<void>.empty()))
            .listen((_) => _fetchTasks(showLoading: false));
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_page <= 1 &&
          !_isLoading &&
          !_loadingMore &&
          !_isActing &&
          !_searchPending &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        _fetchTasks(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchTimer?.cancel();
    _changeSubscription?.cancel();
    _searchCtrl.dispose();
    _refreshTimer?.cancel();
    _assignmentSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isActing) {
      _fetchTasks(showLoading: false);
    }
  }

  void _searchChanged(String _) {
    _searchTimer?.cancel();
    ++_loadGeneration;
    setState(() {
      _searchPending = true;
      _dataCurrent = false;
      _isLoading = false;
      _loadingMore = false;
    });
    _searchTimer = Timer(const Duration(milliseconds: 350), _fetchTasks);
  }

  Future<TaskPage> _readPage(String group, String keyword, int page) =>
      widget.loadPage != null
      ? widget.loadPage!(taskGroup: group, keyword: keyword, page: page)
      : ApiService.getMyTaskPage(
          taskGroup: group,
          keyword: keyword,
          page: page,
          activeOnly: group != 'DONE',
        );

  Future<void> _fetchTasks({bool showLoading = true, bool more = false}) async {
    if (!mounted ||
        more && (_loadingMore || _isLoading || !_hasMore || !_dataCurrent)) {
      return;
    }
    _searchTimer?.cancel();
    final generation = ++_loadGeneration;
    final filter = _selectedFilter, keyword = _searchCtrl.text.trim();
    final nextPage = more ? _page + 1 : 1;
    setState(() {
      _searchPending = false;
      if (more) {
        _loadingMore = true;
        _moreError = null;
      } else {
        _isLoading = true;
        _loadingMore = false;
        _moreError = null;
        _errorMessage = null;
        if (showLoading) {
          _tasks = [];
          _total = null;
          _page = 0;
          _hasMore = false;
        }
      }
    });
    try {
      final result = await _readPage(
        TaskPage.groups[filter],
        keyword,
        nextPage,
      );
      if (!mounted || generation != _loadGeneration) return;
      _vehicleMaxWeight ??= await SessionManager.getVehicleMaxWeight();
      // An khoi trang shipper neu don hang vuot qua tai trong xe shipper
      final suitableItems = result.items.where((t) {
        if (_vehicleMaxWeight == null || t.weightKg == null) return true;
        if (t.stage == DriverTaskStage.done || t.stage == DriverTaskStage.inactive) return true;
        return t.weightKg! <= _vehicleMaxWeight!;
      }).toList(growable: false);

      setState(() {
        if (more) {
          final merged = {for (final item in _tasks) item.assignmentId: item};
          for (final item in suitableItems) {
            merged[item.assignmentId] = item;
          }
          _tasks = merged.values.toList(growable: false);
        } else {
          _tasks = suitableItems;
        }
        _page = result.page;
        _total = result.totalItems;
        _hasMore = result.hasMore;
        _dataCurrent = true;
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          if (more) {
            _moreError = error.toString();
          } else {
            _errorMessage = error.toString();
            _dataCurrent = false;
          }
        });
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isLoading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
        title: const Text(
          'Nhiệm vụ giao hàng',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Chuyến giao của tôi',
            icon: const Icon(Icons.local_shipping_outlined),
            onPressed: _isActing
                ? null
                : () async {
                    final result = await Navigator.push<DriverRouteResult>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DriverTripsScreen(),
                      ),
                    );
                    if (!mounted) return;
                    if (result == DriverRouteResult.received) {
                      setState(() => _selectedFilter = 2);
                    }
                    await _fetchTasks();
                  },
          ),
          IconButton(
            tooltip: 'Làm mới nhiệm vụ',
            onPressed: _isLoading || _isActing ? null : _fetchTasks,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Mở lộ trình',
            icon: const Icon(Icons.map_outlined),
            onPressed: () async {
              final result = await Navigator.push<DriverRouteResult>(
                context,
                MaterialPageRoute(builder: (_) => const B4MapRouteScreen()),
              );
              if (!mounted) return;
              if (result == DriverRouteResult.received) {
                setState(() => _selectedFilter = 2);
              }
              await _fetchTasks();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Scanner Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppTheme.surfaceContainerLowest,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: _searchChanged,
                          onSubmitted: (_) => _fetchTasks(),
                          maxLength: 100,
                          decoration: InputDecoration(
                            counterText: '',
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_searchCtrl.text.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Xóa tìm kiếm',
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _fetchTasks();
                                    },
                                  ),
                                IconButton(
                                  tooltip: 'Quét mã vạch kiện hàng',
                                  icon: const Icon(
                                    Icons.qr_code_scanner_rounded,
                                    color: AppTheme.primary,
                                  ),
                                  onPressed: _openBarcodeScanner,
                                ),
                              ],
                            ),
                            hintText: 'Mã đơn, người nhận, số điện thoại',
                            prefixIcon: Icon(
                              Icons.search,
                              color: AppTheme.secondary,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Status Tabs
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTabItem(0, 'Chờ tiếp nhận'),
                      _buildTabItem(1, 'Lấy tại kho'),
                      _buildTabItem(2, 'Đang giao'),
                      _buildTabItem(3, 'Sự cố & Hoàn'),
                      _buildTabItem(4, 'Lịch sử'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_searchPending) const LinearProgressIndicator(minHeight: 2),
          if (_total != null && !_isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${TaskPage.labels[_selectedFilter]} · ${_tasks.length}/$_total nhiệm vụ',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.secondary,
                  ),
                ),
              ),
            ),
                    if (_selectedFilter == 3 &&
              !_isLoading &&
              _tasks.any((t) =>
                  t.orderStatus.toUpperCase() == 'RETURNING' ||
                  t.stage == DriverTaskStage.returning))
            _buildBatchReturnBanner(),
          if (_selectedFilter == 0 &&
              !_isLoading &&
              _tasks.isNotEmpty)
            _buildBatchAcceptOfferBanner(),
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.errorContainer.withValues(alpha: 0.5),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: AppTheme.error,
                    size: 16,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Chưa cập nhật được danh sách. Tải lại trước khi thao tác. $_errorMessage',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.error,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Orders List with Pull-to-refresh
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetchTasks,
                    child: _tasks.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 72),
                              Icon(
                                _errorMessage == null
                                    ? Icons.inbox_outlined
                                    : Icons.cloud_off_outlined,
                                size: 48,
                                color: AppTheme.secondary,
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: Text(
                                  _errorMessage == null
                                      ? (_searchCtrl.text.trim().isEmpty
                                            ? 'Chưa có nhiệm vụ trong mục này'
                                            : 'Không có nhiệm vụ khớp tìm kiếm')
                                      : 'Chưa thể tải danh sách đơn hàng',
                                  style: const TextStyle(
                                    color: AppTheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 12),
                                Center(
                                  child: TextButton.icon(
                                    onPressed: _fetchTasks,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Thử lại'),
                                  ),
                                ),
                              ],
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _tasks.length + 1,
                            itemBuilder: (context, index) {
                              if (index == _tasks.length) {
                                return _pagingFooter();
                              }
                              final task = _tasks[index];
                              return _buildTaskCard(task);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchAcceptOfferBanner() {
    final offerTasks = _tasks.where((t) => t.stage == DriverTaskStage.offer).toList();
    final count = offerTasks.isNotEmpty ? offerTasks.length : _tasks.length;
    final branchName = _tasks.isNotEmpty ? _tasks.first.branchName : 'Bưu cục';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDBEAFE), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.alt_route_rounded, color: Color(0xFF2563EB), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chuyến giao được phân công từ Điều phối',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1E40AF)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Điều phối viên $branchName đã gán $count đơn vào tuyến của bạn',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF3B82F6), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isActing ? null : _acceptAllTasksInBatch,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(
                _isActing ? 'Đang tiếp nhận chuyến…' : 'Chấp nhận toàn bộ chuyến ($count đơn)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptAllTasksInBatch() async {
    if (_isActing || _tasks.isEmpty) return;
    setState(() => _isActing = true);
    int successCount = 0;
    try {
      final offers = _tasks.where((t) => t.stage == DriverTaskStage.offer).toList();
      final toAccept = offers.isNotEmpty ? offers : _tasks;
      for (final task in toAccept) {
        try {
          final ok = await ApiService.acceptTask(task.assignmentId);
          if (ok) successCount++;
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã tiếp nhận chuyến thành công ($successCount/${toAccept.length} đơn). Chuyển sang lấy kiện tại kho.'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
        setState(() => _selectedFilter = 1);
        await _fetchTasks(showLoading: true);
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Widget _buildBatchReturnBanner() {
    final returningTasks = _tasks
        .where((t) =>
            t.orderStatus.toUpperCase() == 'RETURNING' ||
            t.stage == DriverTaskStage.returning)
        .toList();
    final count = returningTasks.length;
    final branchName = returningTasks.isNotEmpty ? returningTasks.first.branchName : 'Bưu cục';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFEDD5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.assignment_return_rounded, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bàn giao hàng hoàn về kho cuối ca',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF9A3412)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Có $count kiện cần nộp trả $branchName (Gom 1 lần)',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFFC2410C), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isActing
                  ? null
                  : () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BatchReturnHandoverScreen(returningTasks: returningTasks),
                        ),
                      );
                      if (result == true) {
                        _fetchTasks();
                      }
                    },
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: Text(
                'Tạo phiếu nộp kho ($count kiện)',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

    Future<void> _openBarcodeScanner() async {
    final code = await QuickBarcodeScanDialog.show(context);
    if (code != null && code.isNotEmpty && mounted) {
      _searchCtrl.text = code;
      _fetchTasks();
    }
  }

  Widget _buildTabItem(int index, String title) {
    final isSelected = _selectedFilter == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        onTap: () {
          setState(() => _selectedFilter = index);
          _fetchTasks();
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : AppTheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected ? Colors.white : AppTheme.secondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _pagingFooter() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        if (_moreError != null)
          Text(
            'Chưa tải được trang tiếp theo. $_moreError',
            style: const TextStyle(color: AppTheme.error),
          ),
        if (_loadingMore)
          const CircularProgressIndicator()
        else if (_hasMore)
          OutlinedButton.icon(
            onPressed: _isActing ? null : () => _fetchTasks(more: true),
            icon: const Icon(Icons.expand_more),
            label: const Text('Tải thêm nhiệm vụ'),
          ),
        if (_errorMessage != null)
          TextButton(
            onPressed: _fetchTasks,
            child: const Text('Tải lại danh sách'),
          ),
      ],
    ),
  );

  Widget _buildTaskCard(ShipperTaskDto task) {
    return DriverTaskCard(
      task: task,
      onTap: () async {
        final result = await Navigator.push<DriverRouteResult>(
          context,
          MaterialPageRoute(
            builder: (_) => TaskDetailScreen(assignmentId: task.assignmentId),
          ),
        );
        if (!mounted) return;
        if (result == DriverRouteResult.received) {
          setState(() => _selectedFilter = 2);
        }
        await _fetchTasks(showLoading: false);
      },
      actions: _buildTaskActions(task, task.codAmount > 0),
      onCall:
          !_dataCurrent || _searchPending || task.customerPhone.trim().isEmpty
          ? null
          : () => DeviceService.makePhoneCall(task.customerPhone),
      onSms:
          !_dataCurrent || _searchPending || task.customerPhone.trim().isEmpty
          ? null
          : () => CannedSmsSheet.show(
                context,
                customerName: task.customerName,
                customerPhone: task.customerPhone,
                orderCode: task.orderCode,
                codAmount: task.codAmount,
              ),
      onDirections:
          !_dataCurrent || _searchPending || task.stage == DriverTaskStage.offer
          ? null
          : () => _openPickupRoute(task),
    );
  }

  Future<void> _runTaskAction(
    ShipperTaskDto task,
    Future<bool> Function() action,
    String fallback,
  ) async {
    if (_isActing) return;
    setState(() => _isActing = true);
    try {
      await action();
      await _fetchTasks(showLoading: false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$fallback: ${task.orderCode}')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$fallback thất bại: $error'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _reviewOffer(ShipperTaskDto task) async {
    if (_isActing) return;
    setState(() => _isActing = true);
    try {
      final response = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            B2NewTaskPopupDialog(assignment: {'id': task.assignmentId}),
      );
      if (!mounted) return;
      if (response == 'accepted') {
        setState(() => _selectedFilter = 1);
        await _openPickupRoute(task);
      } else {
        await _fetchTasks(showLoading: false);
        if (mounted && response == 'rejected') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Đã từ chối. Đơn trở về hàng đợi để điều phối phân công lại.',
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _openPickupRoute(ShipperTaskDto task) async {
    final result = await Navigator.push<DriverRouteResult>(
      context,
      MaterialPageRoute(
        builder: (_) => B4MapRouteScreen(assignmentId: task.assignmentId),
      ),
    );
    if (!mounted) return;
    if (result == DriverRouteResult.received) {
      setState(() => _selectedFilter = 2);
    }
    await _fetchTasks();
  }

  Widget _buildTaskActions(ShipperTaskDto task, bool hasCod) {
    if (!_dataCurrent || _searchPending || _isLoading) {
      return const Text(
        'Tải lại danh sách trước khi thao tác.',
        style: TextStyle(color: AppTheme.secondary),
      );
    }
    final order = task.orderStatus.toUpperCase();
    if (task.needsResolution) {
      if (order == 'RETURNING' || task.stage == DriverTaskStage.returning) {
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _isActing ? null : () => _openPickupRoute(task),
                    icon: const Icon(Icons.navigation_outlined, size: 16),
                    label: const Text(
                      'Về bưu cục',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _isActing
                        ? null
                        : () async {
                            final allReturning = _tasks
                                .where((t) =>
                                    t.orderStatus.toUpperCase() == 'RETURNING' ||
                                    t.stage == DriverTaskStage.returning)
                                .toList();
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BatchReturnHandoverScreen(
                                  returningTasks: allReturning.isNotEmpty
                                      ? allReturning
                                      : [task],
                                ),
                              ),
                            );
                            if (result == true) {
                              _fetchTasks();
                            }
                          },
                    icon: const Icon(Icons.qr_code_rounded, size: 16),
                    label: const Text(
                      'Nộp trả kho',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _isActing
                    ? null
                    : () async {
                        final changed = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => C2ReturnRequestDetailScreen(task: task),
                          ),
                        );
                        if (mounted && changed == true) {
                          setState(() => _selectedFilter = 3);
                          _fetchTasks();
                        }
                      },
                icon: const Icon(Icons.tune, size: 14, color: AppTheme.secondary),
                label: const Text(
                  'Xem chi tiết xử lý đơn hoàn',
                  style: TextStyle(fontSize: 12, color: AppTheme.secondary),
                ),
              ),
            ),
          ],
        );
      }
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _isActing
              ? null
              : () async {
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => C2ReturnRequestDetailScreen(task: task),
                    ),
                  );
                  if (mounted && changed == true) {
                    setState(() => _selectedFilter = 3);
                    _fetchTasks();
                  }
                },
          icon: const Icon(Icons.tune),
          label: const Text('Xem hướng xử lý'),
        ),
      );
    }
    if (task.stage == DriverTaskStage.offer) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _isActing ? null : () => _reviewOffer(task),
          icon: const Icon(Icons.assignment_turned_in_outlined),
          label: const Text('Tiếp nhận đơn phân công'),
        ),
      );
    }
    if (task.stage == DriverTaskStage.warehouse) {
      if (order == 'HANDED_OVER') {
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isActing
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const B8HandoverScreen(),
                      ),
                    );
                    if (mounted) await _fetchTasks(showLoading: false);
                  },
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Kho đã xuất · Ký nhận kiện'),
          ),
        );
      }
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _isActing ? null : () => _openPickupRoute(task),
          icon: const Icon(Icons.hourglass_top_outlined),
          label: const Text('Chờ kho quét xuất · Xem vị trí'),
        ),
      );
    }
    if (task.stage == DriverTaskStage.ready) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _isActing
              ? null
              : () => _runTaskAction(
                  task,
                  () => ApiService.startDelivery(task.assignmentId),
                  'Đã bắt đầu giao',
                ),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Bắt đầu giao hàng'),
        ),
      );
    }
    if (task.stage == DriverTaskStage.done) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Giao thành công · Đã tất toán vào ví',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF047857),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF047857),
                side: const BorderSide(color: Color(0xFF10B981)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => ProofOfDeliveryDialog.show(context, task: task),
              icon: const Icon(Icons.verified_rounded, size: 16),
              label: const Text(
                'Xem bằng chứng giao hàng (POD)',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      );
    }
    if (task.stage != DriverTaskStage.delivering) {
      return const Text(
        'Nhiệm vụ hiện không có thao tác giao hàng khả dụng.',
        style: TextStyle(color: AppTheme.onSurfaceVariant),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: const BorderSide(color: AppTheme.error),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isActing
                    ? null
                    : () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => B6DeliveryFailedScreen(
                              orderId: task.orderId,
                              orderCode: task.orderCode,
                              customerName: task.customerName,
                              address: task.deliveryAddress,
                            ),
                          ),
                        );
                        if (mounted && result == true) {
                          setState(() => _selectedFilter = 3);
                          _fetchTasks();
                        }
                      },
                child: const Text('Báo thất bại'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isActing
                    ? null
                    : () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => B5DeliverySuccessScreen(
                              assignmentId: task.assignmentId,
                              orderId: task.orderId,
                              orderCode: task.orderCode,
                              customerName: task.customerName,
                              address: task.deliveryAddress,
                              codAmountNumber: task.codAmount,
                              codAmount: hasCod
                                  ? _currencyFormat.format(task.codAmount)
                                  : 'Không thu COD',
                            ),
                          ),
                        );
                        if (mounted && result == true) {
                          setState(() => _selectedFilter = 4);
                          _fetchTasks();
                        }
                      },
                child: const Text('Giao thành công'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: _isActing
                ? null
                : () async {
                    final reported = await EmergencyIncidentDialog.show(
                      context,
                      assignmentId: task.assignmentId,
                      orderId: task.orderId,
                      orderCode: task.orderCode,
                      tripId: task.tripId,
                    );
                    if (reported == true) {
                      await _fetchTasks(showLoading: false);
                    }
                  },
            icon: const Icon(
              Icons.warning_amber_rounded,
              color: AppTheme.error,
              size: 18,
            ),
            label: const Text(
              'Báo sự cố khẩn cấp (Hỏng xe / Tai nạn / Hư hàng)',
              style: TextStyle(
                color: AppTheme.error,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
