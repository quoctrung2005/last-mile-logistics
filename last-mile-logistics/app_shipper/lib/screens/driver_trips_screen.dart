import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/driver_trip.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';
import '../theme/app_theme.dart';
import 'b4_map_route_screen.dart';
import 'task_detail_screen.dart';

String _time(DateTime? value) => value == null
    ? 'Chưa ghi nhận'
    : DateFormat('HH:mm · dd/MM/yyyy').format(value.toLocal());

class DriverTripsScreen extends StatefulWidget {
  final Future<DriverTripPage> Function(String group, String keyword, int page)?
  loadPage;
  final Future<DriverRouteResult?> Function(int tripId)? openTrip;
  final Stream<void>? updates;
  const DriverTripsScreen({
    super.key,
    this.loadPage,
    this.openTrip,
    this.updates,
  });
  @override
  State<DriverTripsScreen> createState() => _DriverTripsScreenState();
}

class _DriverTripsScreenState extends State<DriverTripsScreen>
    with WidgetsBindingObserver {
  final _keyword = TextEditingController();
  String _group = 'ACTIVE';
  DateTime? _selectedDate;
  DateTime? _fromDate;
  DateTime? _toDate;
  String _datePreset = 'ALL'; // 'ALL', 'TODAY', 'YESTERDAY', 'LAST_7_DAYS', 'CUSTOM'
  int _page = 1, _generation = 0;
  DriverTripPage? _data;
  String? _error;
  bool _loading = false, _opening = false;
  Timer? _timer, _search;
  StreamSubscription<void>? _updates;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _updates = (widget.updates ?? RealtimeService.instance.handoverReady)
        .listen((_) {
          if (mounted &&
              !_loading &&
              !_opening &&
              (ModalRoute.of(context)?.isCurrent ?? false)) {
            _load();
          }
        });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          !_loading &&
          !_opening &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    _search?.cancel();
    _updates?.cancel();
    _keyword.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_opening &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    _search?.cancel();
    final generation = ++_generation,
        requestedPage = _page,
        group = _group,
        keyword = _keyword.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await (widget.loadPage != null
              ? widget.loadPage!(group, keyword, requestedPage)
              : ApiService.getMyTrips(
                  group: group,
                  keyword: keyword,
                  page: requestedPage,
                  date: group == 'HISTORY' ? _selectedDate : null,
                  fromDate: group == 'HISTORY' ? _fromDate : null,
                  toDate: group == 'HISTORY' ? _toDate : null,
                )).timeout(const Duration(seconds: 20));
      if (!mounted || generation != _generation) return;
      if (data.group != group || data.page != requestedPage) {
        throw const FormatException('Danh sách chuyến không khớp bộ lọc.');
      }
      final last = ((data.totalItems + data.pageSize - 1) ~/ data.pageSize)
          .clamp(1, 100000);
      if (requestedPage > last) {
        _page = last;
        await _load();
        return;
      }
      setState(() => _data = data);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _data = null;
          _error = '$error';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _changeGroup(String group) {
    if (group == _group) return;
    setState(() {
      _group = group;
      _page = 1;
      _data = null;
    });
    _load();
  }

  void _setDatePreset(String preset) {
    if (preset == _datePreset && preset != 'CUSTOM') return;
    setState(() {
      _datePreset = preset;
      _page = 1;
      _data = null;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (preset == 'ALL') {
        _selectedDate = null;
        _fromDate = null;
        _toDate = null;
      } else if (preset == 'TODAY') {
        _selectedDate = today;
        _fromDate = null;
        _toDate = null;
      } else if (preset == 'YESTERDAY') {
        _selectedDate = today.subtract(const Duration(days: 1));
        _fromDate = null;
        _toDate = null;
      } else if (preset == 'LAST_7_DAYS') {
        _selectedDate = null;
        _fromDate = today.subtract(const Duration(days: 6));
        _toDate = today.add(const Duration(days: 1));
      }
    });
    _load();
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(2025, 1, 1),
      lastDate: now,
      helpText: 'CHỌN NGÀY XEM CHUYẾN GIAO',
      cancelText: 'HỦY',
      confirmText: 'CHỌN',
    );
    if (picked != null) {
      setState(() {
        _datePreset = 'CUSTOM';
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
        _fromDate = null;
        _toDate = null;
        _page = 1;
        _data = null;
      });
      _load();
    }
  }

  Widget _buildDateFilterToolbar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Tất cả ngày'),
            selected: _datePreset == 'ALL',
            onSelected: (val) {
              if (val) _setDatePreset('ALL');
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Hôm nay'),
            selected: _datePreset == 'TODAY',
            onSelected: (val) {
              if (val) _setDatePreset('TODAY');
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Hôm qua'),
            selected: _datePreset == 'YESTERDAY',
            onSelected: (val) {
              if (val) _setDatePreset('YESTERDAY');
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('7 ngày qua'),
            selected: _datePreset == 'LAST_7_DAYS',
            onSelected: (val) {
              if (val) _setDatePreset('LAST_7_DAYS');
            },
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.calendar_month_outlined, size: 16),
            label: Text(
              _datePreset == 'CUSTOM' && _selectedDate != null
                  ? DateFormat('dd/MM/yyyy').format(_selectedDate!)
                  : 'Chọn ngày...',
            ),
            backgroundColor: _datePreset == 'CUSTOM'
                ? AppTheme.primary.withValues(alpha: 0.12)
                : null,
            side: _datePreset == 'CUSTOM'
                ? const BorderSide(color: AppTheme.primary, width: 1.5)
                : null,
            onPressed: _pickCustomDate,
          ),
        ],
      ),
    );
  }

  void _searchChanged(String value) {
    ++_generation;
    _search?.cancel();
    setState(() {
      _page = 1;
      _loading = true;
      _data = null;
      _error = null;
    });
    _search = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _open(int id) async {
    if (_loading || _opening) return;
    setState(() => _opening = true);
    try {
      final result = await (widget.openTrip != null
          ? widget.openTrip!(id)
          : Navigator.push<DriverRouteResult>(
              context,
              MaterialPageRoute(
                builder: (_) => DriverTripDetailScreen(tripId: id),
              ),
            ));
      if (!mounted) return;
      if (result == DriverRouteResult.received) {
        Navigator.pop(context, result);
      } else {
        await _load();
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Widget _buildHistorySummaryBanner(DriverTripPage data) {
    final summary = data.historySummary;
    final totalTrips = summary?.totalTrips ?? data.totalItems;
    final totalKm = summary != null
        ? summary.totalDistanceKm
        : data.items.fold<double>(0.0, (s, t) => s + (t.plannedDistanceKm ?? 0.0));
    final totalOrders = summary?.totalOrders ??
        data.items.fold<int>(0, (s, t) => s + t.stopCount);
    final deliveredOrders = summary?.totalDelivered ??
        data.items.fold<int>(0, (s, t) => s + t.deliveredCount);
    final durationMin = summary?.totalDurationMinutes ??
        data.items.fold<int>(0, (s, t) => s + (t.plannedDurationMinutes?.toInt() ?? 0));

    String filterTitle = 'Tổng kết tất cả chuyến lịch sử';
    if (_datePreset == 'TODAY') {
      filterTitle = 'Tổng kết chuyến hôm nay (${DateFormat("dd/MM/yyyy").format(DateTime.now())})';
    } else if (_datePreset == 'YESTERDAY') {
      final y = DateTime.now().subtract(const Duration(days: 1));
      filterTitle = 'Tổng kết chuyến hôm qua (${DateFormat("dd/MM/yyyy").format(y)})';
    } else if (_datePreset == 'LAST_7_DAYS') {
      filterTitle = 'Tổng kết chuyến 7 ngày qua';
    } else if (_datePreset == 'CUSTOM' && _selectedDate != null) {
      filterTitle = 'Tổng kết chuyến ngày ${DateFormat("dd/MM/yyyy").format(_selectedDate!)}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history_rounded, color: Color(0xFF059669), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      filterTitle,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF065F46)),
                    ),
                    const Text(
                      'Các chuyến xe đã hoàn tất và kết thúc trong ngày',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF047857)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildKpiBox(
                  label: 'TỔNG CHUYẾN',
                  value: '$totalTrips',
                  color: const Color(0xFF065F46),
                  icon: Icons.alt_route_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiBox(
                  label: 'QUÃNG ĐƯỜNG',
                  value: '${totalKm.toStringAsFixed(1)} km',
                  color: const Color(0xFF2563EB),
                  icon: Icons.straighten_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildKpiBox(
                  label: 'ĐƠN HOÀN THÀNH',
                  value: '$deliveredOrders / $totalOrders',
                  color: const Color(0xFF059669),
                  icon: Icons.check_circle_outline_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiBox(
                  label: 'THỜI GIAN CHẠY',
                  value: durationMin > 0 ? '${durationMin ~/ 60}h ${durationMin % 60}p' : '0 phút',
                  color: const Color(0xFFD97706),
                  icon: Icons.schedule_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiBox({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCFCE7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Chuyến giao của tôi'),
        actions: [
          IconButton(
            tooltip: 'Làm mới chuyến',
            onPressed: _loading || _opening ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _keyword,
              maxLength: 100,
              onChanged: _searchChanged,
              decoration: const InputDecoration(
                labelText: 'Tìm mã chuyến, kho hoặc biển số',
                prefixIcon: Icon(Icons.search),
                counterText: '',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    avatar: const Icon(Icons.local_shipping_outlined, size: 18),
                    label: const Center(child: Text('Đang thực hiện')),
                    selected: _group == 'ACTIVE',
                    onSelected: _opening ? null : (_) => _changeGroup('ACTIVE'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChoiceChip(
                    avatar: const Icon(Icons.history_rounded, size: 18),
                    label: const Center(child: Text('Lịch sử chuyến')),
                    selected: _group == 'HISTORY',
                    onSelected: _opening ? null : (_) => _changeGroup('HISTORY'),
                  ),
                ),
              ],
            ),
          ),
          if (_group == 'HISTORY') _buildDateFilterToolbar(),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_error != null) ...[
                    Text(
                      'Không tải được chuyến: $_error',
                      style: const TextStyle(color: AppTheme.error),
                    ),
                    TextButton(
                      onPressed: _loading ? null : _load,
                      child: const Text('Thử lại'),
                    ),
                  ],
                  if (data != null) ...[
                    if (_group == 'HISTORY') _buildHistorySummaryBanner(data),
                    Text(
                      'Cập nhật ${_time(data.readAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondary,
                      ),
                    ),
                    if (data.unplannedTaskCount > 0)
                      Text(
                        '${data.unplannedTaskCount} nhiệm vụ đơn lẻ/chưa gắn chuyến vẫn xem trong tab Nhiệm vụ.',
                      ),
                    if (data.heldReturnCount > 0)
                      Text(
                        'Còn ${data.heldReturnCount} kiện chờ trả kho cuối ca. Kiểm tra mục Giao lại / hoàn.',
                        style: const TextStyle(color: AppTheme.primary),
                      ),
                    if (data.items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _keyword.text.trim().isNotEmpty
                              ? 'Không có chuyến phù hợp tìm kiếm.'
                              : _group == 'ACTIVE'
                              ? 'Chưa có chuyến đang thực hiện.'
                              : 'Chưa có lịch sử chuyến.',
                        ),
                      ),
                    for (final trip in data.items)
                      Card(
                        child: InkWell(
                          onTap: _loading || _opening
                              ? null
                              : () => _open(trip.id),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TripOverview(trip: trip),
                                const SizedBox(height: 10),
                                OutlinedButton(
                                  onPressed: _loading || _opening
                                      ? null
                                      : () => _open(trip.id),
                                  child: const Text('Xem chuyến / thứ tự điểm'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        Text(
                          '${data.totalItems} chuyến · Trang ${data.page} / ${((data.totalItems + data.pageSize - 1) ~/ data.pageSize).clamp(1, 100000)}',
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: _loading || _opening || _page <= 1
                                  ? null
                                  : () {
                                      _page--;
                                      _load();
                                    },
                              child: const Text('Trước'),
                            ),
                            TextButton(
                              onPressed: _loading || _opening || !data.hasMore
                                  ? null
                                  : () {
                                      _page++;
                                      _load();
                                    },
                              child: const Text('Sau'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TripOverview extends StatelessWidget {
  final DriverTripSummary trip;
  const TripOverview({super.key, required this.trip});

  Widget _statusChip(String status) {
    Color bg;
    Color fg;
    IconData icon;
    switch (status) {
      case 'COMPLETED':
        bg = AppTheme.tertiaryContainer;
        fg = AppTheme.onTertiaryContainer;
        icon = Icons.check_circle_outline;
        break;
      case 'CANCELLED':
        bg = AppTheme.errorContainer;
        fg = AppTheme.onErrorContainer;
        icon = Icons.cancel_outlined;
        break;
      case 'IN_PROGRESS':
        bg = const Color(0xFFD6E4FF);
        fg = const Color(0xFF003A8C);
        icon = Icons.local_shipping_outlined;
        break;
      case 'ACCEPTED':
      case 'ASSIGNED':
        bg = const Color(0xFFFFF1B8);
        fg = const Color(0xFF874D00);
        icon = Icons.assignment_outlined;
        break;
      default:
        bg = AppTheme.surfaceContainer;
        fg = AppTheme.onSurface;
        icon = Icons.schedule;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      constraints: const BoxConstraints(maxWidth: 130),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              driverTripStatuses[status] ?? status,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.tripCode,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${trip.warehouseName} · ${trip.licensePlate ?? "Chưa gán xe"}${trip.plannedDistanceKm != null ? " · ${trip.plannedDistanceKm!.toStringAsFixed(1)} km" : ""}',
                  style: const TextStyle(
                    color: AppTheme.secondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _statusChip(trip.status),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Tiến độ: ${trip.handledCount}/${trip.stopCount} điểm',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(trip.progress * 100).toInt()}%',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: trip.progress,
          backgroundColor: AppTheme.surfaceContainerHigh,
          color: trip.status == 'COMPLETED' ? AppTheme.tertiary : AppTheme.primary,
          minHeight: 6,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '${trip.deliveredCount} giao thành công · ${trip.pickupCount} chờ lấy · ${trip.deliveringCount} đang giao · ${trip.offerCount} chờ nhận',
        style: const TextStyle(fontSize: 12, color: AppTheme.onSurfaceVariant),
      ),
      if (trip.attentionCount > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${trip.attentionCount} điểm cần xử lý',
            style: const TextStyle(
              color: AppTheme.error,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      if (trip.pendingReturnCount > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${trip.pendingReturnCount} kiện chờ trả kho cuối ca.',
            style: const TextStyle(
              color: AppTheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      const SizedBox(height: 6),
      if (trip.status == 'COMPLETED' && trip.endedAt != null)
        Text(
          'Hoàn thành lúc: ${_time(trip.endedAt)}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.tertiary,
          ),
        )
      else if (trip.status == 'CANCELLED' && trip.endedAt != null)
        Text(
          'Hủy lúc: ${_time(trip.endedAt)}',
          style: const TextStyle(fontSize: 12, color: AppTheme.error),
        )
      else if (trip.startedAt != null)
        Text(
          'Xuất phát lúc: ${_time(trip.startedAt)}',
          style: const TextStyle(fontSize: 12),
        )
      else
        Text(
          'Dự kiến xuất phát: ${_time(trip.plannedStartAt)}',
          style: const TextStyle(fontSize: 12),
        ),
    ],
  );
}

class DriverTripDetailScreen extends StatefulWidget {
  final int tripId;
  final Future<DriverTripDetail> Function(int)? load;
  final Future<DriverRouteResult?> Function(DriverTripDetail, DriverTripStop)?
  openRoute;
  final Future<DriverRouteResult?> Function(int)? openTask;
  final Stream<void>? updates;
  const DriverTripDetailScreen({
    super.key,
    required this.tripId,
    this.load,
    this.openRoute,
    this.openTask,
    this.updates,
  });
  @override
  State<DriverTripDetailScreen> createState() => _DriverTripDetailScreenState();
}

class _DriverTripDetailScreenState extends State<DriverTripDetailScreen>
    with WidgetsBindingObserver {
  DriverTripDetail? _data;
  String? _error;
  bool _loading = false, _acting = false;
  int _generation = 0;
  Timer? _timer;
  StreamSubscription<void>? _updates;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _updates = (widget.updates ?? RealtimeService.instance.handoverReady)
        .listen((_) {
          if (mounted &&
              !_acting &&
              (ModalRoute.of(context)?.isCurrent ?? false)) {
            _load();
          }
        });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          !_loading &&
          !_acting &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    _updates?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DriverTripDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tripId != widget.tripId) {
      _data = null;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_acting &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await (widget.load ?? ApiService.getMyTrip)(widget.tripId)
          .timeout(const Duration(seconds: 20));
      if (!mounted || generation != _generation) return;
      if (data.trip.id != widget.tripId) {
        throw const FormatException('Chi tiết chuyến không khớp.');
      }
      setState(() => _data = data);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _data = null;
          _error = '$error';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(DriverTripStop stop, {required bool route}) async {
    final data = _data;
    if (data == null ||
        _loading ||
        _acting ||
        !stop.canOpenTask ||
        route && !stop.canNavigate) {
      return;
    }
    setState(() => _acting = true);
    try {
      final DriverRouteResult? result;
      if (route) {
        result = await (widget.openRoute != null
            ? widget.openRoute!(data, stop)
            : Navigator.push<DriverRouteResult>(
                context,
                MaterialPageRoute(
                  builder: (_) => B4MapRouteScreen(
                    assignmentId: stop.assignmentId,
                    tripId: data.trip.id,
                  ),
                ),
              ));
      } else {
        result = await (widget.openTask != null
            ? widget.openTask!(stop.assignmentId!)
            : Navigator.push<DriverRouteResult>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      TaskDetailScreen(assignmentId: stop.assignmentId!),
                ),
              ));
      }
      if (!mounted) return;
      if (result == DriverRouteResult.received) {
        Navigator.pop(context, result);
      } else {
        await _load();
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data, trip = data?.trip;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Chi tiết chuyến giao'),
        actions: [
          IconButton(
            tooltip: 'Làm mới chi tiết chuyến',
            onPressed: _loading || _acting ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(
                'Không tải được chuyến: $_error',
                style: const TextStyle(color: AppTheme.error),
              ),
              TextButton(
                onPressed: _loading ? null : _load,
                child: const Text('Thử lại'),
              ),
            ],
            if (data != null && trip != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TripOverview(trip: trip),
                      const Divider(),
                      Text('Bắt đầu thực tế: ${_time(trip.startedAt)}'),
                      Text('Kết thúc chuyến giao: ${_time(trip.endedAt)}'),
                      Text(
                        'Quãng đường kế hoạch: ${trip.plannedDistanceKm == null ? 'Chưa có' : '${trip.plannedDistanceKm!.toStringAsFixed(1)} km'}',
                      ),
                      Text(
                        'Thời gian kế hoạch: ${trip.plannedDurationMinutes == null ? 'Chưa có' : '${trip.plannedDurationMinutes!.ceil()} phút'}',
                      ),
                      Text(
                        'Cập nhật: ${_time(data.readAt)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const Text(
                        'Tiến độ đã xử lý điểm gồm cả điểm đã thu hồi hoặc chuyển hoàn. Số giao thành công được thống kê riêng.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.secondary,
                        ),
                      ),
                      if (data.firstNavigable != null)
                        FilledButton.icon(
                          onPressed: _loading || _acting
                              ? null
                              : () => _open(data.firstNavigable!, route: true),
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Xem lộ trình chuyến'),
                        ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Thứ tự điểm do admin điều phối. Chọn điểm xem không sắp lại chuyến.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (data.stops.isEmpty) const Text('Chuyến chưa có điểm giao.'),
              for (final stop in data.stops)
                Card(
                  key: ValueKey('trip-stop-${stop.sequence}'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Điểm ${stop.sequence} · ${stop.orderCode}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(driverTripStages[stop.stage]!),
                        if (stop.pickupBlocked)
                          const Text(
                            'Chờ kho/điều phối xử lý sự cố nhận kiện.',
                            style: TextStyle(color: AppTheme.error),
                          ),
                        if (stop.receiverName != null) Text(stop.receiverName!),
                        if (stop.deliveryAddress != null)
                          Text(stop.deliveryAddress!),
                        if (!stop.canOpenTask)
                          const Text(
                            'Điểm chưa có nhiệm vụ khả dụng của bạn. Thông tin liên hệ được ẩn.',
                          ),
                        Text(
                          'Đến dự kiến: ${_time(stop.plannedArrivalAt)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (stop.lastAttemptAt != null)
                          Text(
                            '${stop.lastAttemptResult == 'SUCCESS' ? 'Giao thành công' : 'Giao thất bại'} lúc ${_time(stop.lastAttemptAt)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (stop.canOpenTask)
                              OutlinedButton(
                                onPressed: _loading || _acting
                                    ? null
                                    : () => _open(stop, route: false),
                                child: const Text('Xem nhiệm vụ'),
                              ),
                            if (stop.canNavigate)
                              TextButton.icon(
                                onPressed: _loading || _acting
                                    ? null
                                    : () => _open(stop, route: true),
                                icon: const Icon(Icons.route),
                                label: const Text('Xem tuyến đến điểm này'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
