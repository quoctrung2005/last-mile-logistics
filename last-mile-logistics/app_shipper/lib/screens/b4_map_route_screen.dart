import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../models/auth_and_task_models.dart';
import '../models/driver_workflow.dart';
import '../models/driver_route.dart';
import '../models/driver_navigation.dart';
import '../models/task_timing.dart';
import '../services/device_service.dart';
import '../services/navigation_location.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pickup_receipt_dialog.dart';
import '../widgets/pickup_issue_dialog.dart';
import '../widgets/emergency_incident_dialog.dart';
import 'b3_order_management_screen.dart';
import 'b8_handover_screen.dart';

enum DriverRouteResult { received }

class B4MapRouteScreen extends StatefulWidget {
  final Stream<Position>? positions;
  final TileProvider? tileProvider;
  final int? assignmentId;
  final int? tripId;
  final ValueChanged<int>? onReceived;
  final Future<Map<String, dynamic>> Function(int, double?, double?)? loadRoute;
  final Future<LatLng> Function()? locate;
  final Future<List<ShipperTaskDto>> Function()? loadTasks;
  final Future<bool> Function(int, String)? receiveTask;
  final Stream<void>? updates;
  final DateTime Function()? navigationClock;
  final Future<bool> Function()? openLocationSettings;
  final Future<bool> Function()? openAppSettings;
  const B4MapRouteScreen({
    super.key,
    this.assignmentId,
    this.tripId,
    this.positions,
    this.tileProvider,
    this.onReceived,
    this.loadRoute,
    this.locate,
    this.loadTasks,
    this.receiveTask,
    this.updates,
    this.navigationClock,
    this.openLocationSettings,
    this.openAppSettings,
  }) : assert(tripId == null || tripId > 0);

  @override
  State<B4MapRouteScreen> createState() => _B4MapRouteScreenState();
}

class _B4MapRouteScreenState extends State<B4MapRouteScreen>
    with WidgetsBindingObserver {
  List<ShipperTaskDto> _tasks = [];
  int? _selectedAssignmentId, _scopeTripId;
  bool _loading = true, _working = false;
  String? _error;
  int _generation = 0;
  final MapController _mapController = MapController();
  List<LatLng> _geometry = [];
  LatLng? _position;
  String? _routeError, _routeSource, _gpsWarning;
  double? _distanceKm, _minutes;
  bool _routing = false, _mapReady = false;
  int _routeGeneration = 0;
  String? _routeKey;
  bool _navigating = false, _following = true;
  ShipperTaskDto? _routeTask;
  LatLng? _routeOrigin;
  NavigationProgress? _progress;
  LatLng? _progressPosition;
  final _reroutePolicy = NavigationReroutePolicy();
  List<NavigationManeuver> _maneuvers = [];
  DateTime? _lastFixAt;
  double _lastAccuracy = 5;
  int _fixRevision = 0;
  Future<Position>? _locationRequest;
  bool _locating = false, _retryLocationOnResume = false;
  NavigationLocationException? _locationIssue;
  StreamSubscription<Position>? _gps;
  double? _geometryLengthMeters;
  Timer? _timer, _gpsTimer;
  StreamSubscription<void>? _updates;
  DateTime get _now => widget.navigationClock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedAssignmentId = widget.assignmentId;
    _scopeTripId = widget.tripId;
    _loadTasks();
    _gpsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted &&
          _navigating &&
          _lastFixAt != null &&
          _now.difference(_lastFixAt!) > const Duration(seconds: 30)) {
        setState(() => _gpsWarning = 'Vị trí đã cũ. Đang chờ GPS cập nhật.');
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_working &&
          !_loading &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        _loadTasks(silent: true);
      }
    });
    _updates = (widget.updates ?? RealtimeService.instance.handoverReady)
        .listen((_) {
          if (!mounted) return;
          if (!_working && (ModalRoute.of(context)?.isCurrent ?? false)) {
            _loadTasks(silent: true);
          }
        });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gps?.cancel();
    _routeGeneration++;
    _mapController.dispose();
    _timer?.cancel();
    _gpsTimer?.cancel();
    _updates?.cancel();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation({bool moveTo = false}) async {
    try {
      final p = await _readLocation();
      if (!mounted) return;
      final point = LatLng(p.latitude, p.longitude);
      setState(() {
        _position = point;
        ++_fixRevision;
        _locationIssue = null;
      });
      if (_mapReady && (moveTo || _tasks.isEmpty)) {
        _mapController.move(point, 15);
      }
      final selected = selectedDriverRoute(_tasks, _selectedAssignmentId);
      if (selected != null && !_working && _error == null && !_navigating) {
        _stopNavigation();
        await _loadRoadRoute(selected, origin: point);
      }
    } catch (error) {
      if (!mounted) return;
      final issue = error is NavigationLocationException
          ? error
          : const NavigationLocationException(
              NavigationLocationProblem.unavailable,
            );
      setState(() {
        _locationIssue = issue;
        _routeError = issue.message;
      });
    }
  }

  Future<Position> _readLocation() {
    if (_locationRequest != null) return _locationRequest!;
    setState(() => _locating = true);
    late Future<Position> request;
    request =
        Future<Position>.sync(() async {
          if (widget.locate == null) {
            return NavigationLocationService.getPosition();
          }
          final point = await widget.locate!();
          if (!point.latitude.isFinite ||
              !point.longitude.isFinite ||
              point.latitude.abs() > 90 ||
              point.longitude.abs() > 180) {
            throw const FormatException(
              'GPS trả tọa độ không hợp lệ. Hãy lấy lại vị trí.',
            );
          }
          return Position(
            latitude: point.latitude,
            longitude: point.longitude,
            timestamp: _now,
            accuracy: 5,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        }).whenComplete(() {
          if (identical(_locationRequest, request)) {
            _locationRequest = null;
            if (mounted) setState(() => _locating = false);
          }
        });
    return _locationRequest = request;
  }

  Future<void> _openGpsSettings({required bool app}) async {
    setState(_stopNavigation);
    _retryLocationOnResume = true;
    try {
      final opened = await (app
          ? (widget.openAppSettings ?? Geolocator.openAppSettings)()
          : (widget.openLocationSettings ?? Geolocator.openLocationSettings)());
      if (!mounted) return;
      if (!opened) {
        _retryLocationOnResume = false;
        setState(
          () => _routeError = 'Không mở được cài đặt. Mở Cài đặt thiết bị → Vị trí, rồi bấm Lấy lại GPS.',
        );
      }
    } catch (_) {
      if (!mounted) return;
      _retryLocationOnResume = false;
      setState(
        () =>
            _routeError = 'Mở Cài đặt thiết bị → Vị trí, rồi bấm Lấy lại GPS.',
      );
    }
  }

  Widget _locationRecovery() {
    final app =
        _locationIssue?.problem == NavigationLocationProblem.denied ||
        _locationIssue?.problem == NavigationLocationProblem.deniedForever ||
        _locationIssue?.problem == NavigationLocationProblem.inaccurate;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _locating || _routing || _working
                ? null
                : () => _fetchCurrentLocation(moveTo: true),
            icon: const Icon(Icons.my_location),
            label: const Text('Lấy lại GPS'),
          ),
          TextButton(
            onPressed: _locating || _routing || _working
                ? null
                : () => _openGpsSettings(app: app),
            child: Text(app ? 'Cấp quyền vị trí' : 'Bật vị trí'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadTasks({bool silent = false}) async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      final tasks =
          await (widget.loadTasks?.call() ??
                  ApiService.getAllMyTasks(activeOnly: true))
              .timeout(const Duration(seconds: 20));
      if (!mounted || generation != _generation) return;
      final focus = tasks
          .where((t) => t.assignmentId == widget.assignmentId)
          .firstOrNull;
      if (widget.tripId != null &&
          focus != null &&
          focus.tripId != widget.tripId) {
        throw const FormatException(
          'Nhiệm vụ đã đổi chuyến. Hãy mở lại chuyến từ danh sách.',
        );
      }
      if (widget.assignmentId != null && focus != null) {
        _scopeTripId = widget.tripId ?? focus.tripId;
      }
      final scoped = driverRouteScope(
        tasks,
        assignmentId: widget.assignmentId,
        tripId: _scopeTripId,
      );
      final selected = selectedDriverRoute(scoped, _selectedAssignmentId);
      setState(() {
        _tasks = scoped;
        _selectedAssignmentId = selected?.assignmentId;
      });
      if (_tasks.isNotEmpty) {
        final t = selected!;
        final key =
            '${t.assignmentId}:${t.orderStatus}:${t.tripId}:${t.routeLatitude}:${t.routeLongitude}:${t.stopSequence}';
        if (_routeKey != key) {
          if (_navigating) _stopNavigation();
          _routeKey = key;
          _geometry = [];
          _routeSource = null;
          _distanceKm = null;
          _minutes = null;
          unawaited(_loadRoadRoute(t));
        }
      } else {
        _invalidateRoute();
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        _invalidateRoute();
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _invalidateRoute() {
    _stopNavigation();
    ++_routeGeneration;
    _geometry = [];
    _routeTask = null;
    _routeKey = null;
    _routeSource = null;
    _routeError = null;
    _distanceKm = null;
    _minutes = null;
    _routing = false;
  }

  @override
  void didUpdateWidget(covariant B4MapRouteScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assignmentId != widget.assignmentId ||
        oldWidget.tripId != widget.tripId) {
      _scopeTripId = widget.tripId;
      _selectedAssignmentId = widget.assignmentId;
      _tasks = [];
      _invalidateRoute();
      _loadTasks();
    }
  }

  Future<void> _loadRoadRoute(
    ShipperTaskDto task, {
    bool live = false,
    LatLng? origin,
  }) async {
    final generation = ++_routeGeneration;
    final fixRevision = _fixRevision;
    setState(() {
      _routing = true;
      _routeError = null;
      if (!live) {
        _geometry = [];
        _routeSource = null;
        _distanceKm = null;
        _minutes = null;
      }
    });
    try {
      if (task.routeLatitude == null || task.routeLongitude == null) {
        throw Exception(
          'Điểm đến chưa có tọa độ. Hãy nhờ điều phối cập nhật vị trí trên trang quản lý.',
        );
      }
      String? locationError;
      NavigationLocationException? locationIssue;
      DateTime? observedAt;
      LatLng? position = origin;
      try {
        if (position == null) {
          final p = await _readLocation();
          if (!isUsableNavigationFix(
            latitude: p.latitude,
            longitude: p.longitude,
            accuracyMeters: p.accuracy,
            observedAt: p.timestamp,
            now: _now,
          )) {
            throw Exception(
              'GPS đã cũ hoặc chưa đủ chính xác. Hãy lấy lại vị trí.',
            );
          }
          position = LatLng(p.latitude, p.longitude);
          observedAt = p.timestamp;
        }
      } catch (error) {
        locationIssue = error is NavigationLocationException ? error : null;
        locationError = error.toString().replaceFirst(
          RegExp(r'^(Exception|FormatException):\s*'),
          '',
        );
      }
      if (!mounted || generation != _routeGeneration) return;
      setState(() => _locationIssue = locationIssue);
      if (position != null &&
          (!position.latitude.isFinite ||
              !position.longitude.isFinite ||
              position.latitude.abs() > 90 ||
              position.longitude.abs() > 180)) {
        position = null;
        locationError = 'GPS trả tọa độ không hợp lệ. Hãy lấy lại vị trí.';
      }
      if (live && position == null) {
        throw Exception(
          locationError ?? 'Cần vị trí GPS để bắt đầu chỉ đường.',
        );
      }
      if (fixRevision == _fixRevision) {
        _position = position;
        if (live && observedAt != null) _lastFixAt = observedAt;
      }
      if (position == null && task.stage == DriverTaskStage.warehouse) {
        throw Exception(
          locationError ??
              'Chưa nhận được GPS để xem đường đến kho. Bấm Lấy lại GPS.',
        );
      }
      final route =
          await (widget.loadRoute != null
                  ? widget.loadRoute!(
                      task.assignmentId,
                      position?.latitude,
                      position?.longitude,
                    )
                  : ApiService.getTaskRoute(
                      task.assignmentId,
                      navigation: live || _position != null,
                      expectedOrderId: task.orderId,
                      expectedStage: task.stage == DriverTaskStage.warehouse
                          ? 'PICKUP'
                          : 'DELIVERY',
                      latitude: position?.latitude,
                      longitude: position?.longitude,
                    ))
              .timeout(const Duration(seconds: 20));
      if (!mounted || generation != _routeGeneration) return;
      if (route.containsKey('assignmentId') &&
              route['assignmentId'] != task.assignmentId ||
          route.containsKey('orderId') && route['orderId'] != task.orderId ||
          route.containsKey('stopSequence') &&
              route['stopSequence'] != task.stopSequence ||
          route.containsKey('stage') &&
              route['stage'] !=
                  (task.stage == DriverTaskStage.warehouse
                      ? 'PICKUP'
                      : 'DELIVERY') ||
          live && route['source'] == 'ADMIN_PLAN') {
        throw Exception(
          'Lộ trình hoặc thứ tự đã thay đổi. Hãy tải lại nhiệm vụ.',
        );
      }
      final leg = route['leg'] as Map<String, dynamic>;
      final distanceMeters = leg['distanceMeters'],
          travelSeconds = leg['travelSeconds'];
      if (distanceMeters is! num ||
          !distanceMeters.isFinite ||
          distanceMeters < 0 ||
          travelSeconds is! num ||
          !travelSeconds.isFinite ||
          travelSeconds < 0) {
        throw Exception('Khoảng cách hoặc thời gian tuyến không hợp lệ.');
      }
      final geometry = (leg['geometry'] as List)
          .map(
            (p) => LatLng(
              (p['latitude'] as num).toDouble(),
              (p['longitude'] as num).toDouble(),
            ),
          )
          .toList();
      if (geometry.isEmpty ||
          geometry.any(
            (p) =>
                !p.latitude.isFinite ||
                !p.longitude.isFinite ||
                p.latitude.abs() > 90 ||
                p.longitude.abs() > 180,
          )) {
        throw Exception('Máy chủ chưa trả được đường đi hợp lệ.');
      }
      setState(() {
        _geometry = geometry;
        _maneuvers = navigationManeuvers(geometry);
        _routeTask = task;
        _routeOrigin = position;
        _progress = null;
        _progressPosition = null;
        _geometryLengthMeters = 0;
        for (var i = 1; i < geometry.length; i++) {
          _geometryLengthMeters =
              _geometryLengthMeters! + Distance()(geometry[i - 1], geometry[i]);
        }
        _routeSource = route['source']?.toString();
        _distanceKm = (leg['distanceMeters'] as num).toDouble() / 1000;
        _minutes = (leg['travelSeconds'] as num).toDouble() / 60;
        _routeError = locationError;
        if (_navigating &&
            _lastFixAt != null &&
            _now.difference(_lastFixAt!) > const Duration(seconds: 30)) {
          _gpsWarning = 'Vị trí đã cũ. Đang chờ GPS cập nhật.';
        }
      });
      if (_navigating && _position != null) {
        _updateProgress(_position!);
        _followPosition();
      } else {
        _fitMap();
      }
    } catch (error) {
      if (mounted && generation == _routeGeneration) {
        setState(() {
          _routeError = error.toString().replaceFirst(
            RegExp(r'^(Exception|FormatException):\s*'),
            '',
          );
          if (!live) _geometry = [];
        });
      }
    } finally {
      if (mounted && generation == _routeGeneration) {
        setState(() => _routing = false);
      }
    }
  }

  List<LatLng> get _cameraPoints => [
    ..._geometry,
    ?_position,
    ..._tasks
        .where(
          (t) => _geometry.isEmpty || t.assignmentId == _selectedAssignmentId,
        )
        .where(
          (t) =>
              t.routeLatitude != null &&
              t.routeLongitude != null &&
              t.routeLatitude!.isFinite &&
              t.routeLongitude!.isFinite &&
              t.routeLatitude!.abs() <= 90 &&
              t.routeLongitude!.abs() <= 180,
        )
        .map((t) => LatLng(t.routeLatitude!, t.routeLongitude!)),
  ];

  void _fitMap() {
    if (!_mapReady || _cameraPoints.isEmpty) return;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(_cameraPoints),
        padding: EdgeInsets.fromLTRB(28, 28, 28, _navigating ? 80 : 200),
        maxZoom: 16,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_working &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      if (_retryLocationOnResume) {
        _retryLocationOnResume = false;
        _routeKey = null;
      }
      _loadTasks(silent: true);
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_navigating) {
        _stopNavigation();
        if (mounted) {
          setState(
            () => _routeError = 'Chỉ đường đã tạm dừng khi bạn rời ứng dụng.',
          );
        }
      }
    }
  }

  void _stopNavigation() {
    ++_routeGeneration;
    _routing = false;
    _gps?.cancel();
    _gps = null;
    _navigating = false;
    _progress = null;
    _progressPosition = null;
    _gpsWarning = null;
    _lastFixAt = null;
    _reroutePolicy.reset();
  }

  Future<void> _directions(ShipperTaskDto task) async {
    if (_working ||
        _error != null ||
        !_tasks.any((t) => t.assignmentId == task.assignmentId)) {
      return;
    }
    _stopNavigation();
    _routeKey =
        '${task.assignmentId}:${task.orderStatus}:${task.tripId}:${task.routeLatitude}:${task.routeLongitude}:${task.stopSequence}';
    setState(() => _selectedAssignmentId = task.assignmentId);
    await _loadRoadRoute(task);
    if (mounted) _fitMap();
  }

  Future<void> _startNavigation(ShipperTaskDto task) async {
    if (_routing || _working || _error != null) return;
    _stopNavigation();
    setState(() {
      _navigating = true;
      _following = true;
    });
    final generation = _routeGeneration + 1;
    await _loadRoadRoute(task, live: true);
    if (!mounted || !_navigating || generation != _routeGeneration) return;
    if (_routeError != null ||
        _geometry.isEmpty ||
        _position == null ||
        _routeTask?.assignmentId != task.assignmentId) {
      setState(() => _navigating = false);
      return;
    }
    if (_geometry.length == 1 && _progress?.arrived != true) {
      setState(() {
        _navigating = false;
        _routeError = 'Hai điểm cùng nút đường nhưng chưa đến nơi. Cần cập nhật tọa độ điểm đến để chỉ đường chính xác.';
      });
      return;
    }
    _lastFixAt = DateTime.now();
    _gpsWarning = null;
    if (_position != null) {
      _updateProgress(_position!);
      _followPosition();
    }
    _reroutePolicy.requested(_now);
    _gps = (widget.positions ?? DeviceService.watchNavigationPosition()).listen(
      _onPosition,
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _routeError =
              'Mất cập nhật GPS. Hãy bật vị trí và bắt đầu lại chỉ đường.';
          _stopNavigation();
        });
      },
      onDone: () {
        if (!mounted || !_navigating) return;
        setState(() {
          _routeError = 'Đã dừng cập nhật GPS. Bấm bắt đầu để nối lại.';
          _stopNavigation();
        });
      },
    );
  }

  void _updateProgress(LatLng position) {
    final task = _routeTask;
    if (task == null ||
        _geometry.isEmpty ||
        task.routeLatitude == null ||
        task.routeLongitude == null) {
      return;
    }
    _progress = matchNavigationRoute(
      _geometry,
      position,
      LatLng(task.routeLatitude!, task.routeLongitude!),
      previousTraveledMeters: _progress?.traveledMeters,
      maxAdvanceMeters: _progressPosition == null
          ? double.infinity
          : Distance()(_progressPosition!, position) * 2 + 40,
    );
    _progressPosition = position;
  }

  void _followPosition() {
    if (!_mapReady || !_following || _position == null) return;
    _mapController.move(_position!, math.max(16, _mapController.camera.zoom));
  }

  void _onPosition(Position fix) {
    if (!mounted ||
        !_navigating ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    if (_lastFixAt != null && !fix.timestamp.isAfter(_lastFixAt!)) return;
    if (!isUsableNavigationFix(
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracyMeters: fix.accuracy,
      observedAt: fix.timestamp,
      now: _now,
    )) {
      setState(
        () => _gpsWarning = 'GPS chưa đủ chính xác. Đang chờ vị trí tốt hơn.',
      );
      return;
    }
    final point = LatLng(fix.latitude, fix.longitude);
    setState(() {
      ++_fixRevision;
      _lastFixAt = fix.timestamp;
      _lastAccuracy = fix.accuracy;
      _position = point;
      _gpsWarning = null;
      _updateProgress(point);
    });
    _followPosition();
    final progress = _progress, task = _routeTask;
    if (progress == null || task == null || _routing || progress.arrived) {
      return;
    }
    if (_reroutePolicy.shouldReroute(
      now: _now,
      offsetMeters: progress.distanceFromRouteMeters,
      accuracyMeters: fix.accuracy,
      movedFromRouteOriginMeters: _routeOrigin == null
          ? 0
          : Distance()(_routeOrigin!, point),
    )) {
      unawaited(_loadRoadRoute(task, live: true, origin: point));
    }
  }

  Widget _navigationPanel() {
    final arrived = _progress?.arrived == true;
    final joiningRoad =
        _position != null &&
        _geometry.isNotEmpty &&
        (_progress?.traveledMeters ?? 0) <= 15 &&
        Distance()(_position!, _geometry.first) > 45;
    final offRoute =
        (_progress?.distanceFromRouteMeters ?? 0) >
        math.max(45, _lastAccuracy * 2);
    final reliable =
        !_routing && _routeError == null && _gpsWarning == null && !offRoute;
    final maneuver = nextNavigationManeuver(
      _maneuvers,
      _progress?.traveledMeters ?? 0,
    );
    final untilTurn = math.max(
      0.0,
      (maneuver?.atMeters ?? 0) - (_progress?.traveledMeters ?? 0),
    );
    String meters(double value) => value < 1000
        ? '${value.round()} m'
        : '${(value / 1000).toStringAsFixed(1)} km';
    final remaining = _progress?.remainingMeters ?? ((_distanceKm ?? 0) * 1000);
    final total = _geometryLengthMeters ?? 0;
    final minutes = total <= 0
        ? (_minutes ?? 0)
        : (_minutes ?? 0) * (remaining / total).clamp(0, 1);
    return Card(
      color: AppTheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _gpsWarning != null
                  ? 'Đang chờ vị trí GPS tin cậy'
                  : _routing
                  ? 'Đang tính lại đường…'
                  : _routeError != null
                  ? 'Chưa có tuyến chỉ đường mới'
                  : joiningRoad
                  ? 'Đến điểm bắt đầu tuyến'
                  : offRoute
                  ? 'Bạn đang lệch tuyến'
                  : arrived
                  ? 'Đã ở gần điểm đến'
                  : maneuver?.label ?? 'Đi theo tuyến màu cam',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (reliable && !arrived && maneuver != null)
              Text(
                'Sau ${meters(untilTurn)}',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            if (reliable && !arrived)
              Text(
                'Còn ${remaining < 1000 ? "${remaining.round()} m" : "${(remaining / 1000).toStringAsFixed(1)} km"} · ước tính ${minutes < 1 ? "dưới 1" : minutes.ceil()} phút',
                style: const TextStyle(color: Colors.white),
              ),
            if (reliable && arrived)
              const Text(
                'Kiểm tra điểm đến và cập nhật nhận/giao hàng bên dưới.',
                style: TextStyle(color: Colors.white),
              ),
            if (reliable && !arrived)
              const Text(
                'Hướng rẽ ước lượng theo hình tuyến; quan sát biển báo thực tế.',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            if (_routeTask != null)
              Text(
                _routeTask!.orderCode,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            if (joiningRoad &&
                _routeError == null &&
                _gpsWarning == null &&
                !_routing)
              Text(
                'Điểm vào đường cách GPS khoảng ${meters(Distance()(_position!, _geometry.first))}. Kiểm tra lối tiếp cận thực tế; bản đồ không vẽ đường nối qua khu vực chưa có dữ liệu.',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            if (_gpsWarning != null || _routeError != null)
              Text(
                _gpsWarning ?? _routeError!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            if (!_routing &&
                (_routeError != null || offRoute) &&
                _position != null &&
                _gpsWarning == null)
              TextButton(
                onPressed: () {
                  final task = _routeTask;
                  if (task != null) {
                    _reroutePolicy.requested(_now);
                    unawaited(
                      _loadRoadRoute(task, live: true, origin: _position),
                    );
                  }
                },
                child: const Text(
                  'Thử lại tuyến từ vị trí hiện tại',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            TextButton(
              onPressed: () {
                setState(_stopNavigation);
                _fitMap();
              },
              child: const Text(
                'Dừng chỉ đường',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finishReceipt(int assignmentId) async {
    if (!mounted) return;
    _stopNavigation();
    if (widget.onReceived != null) {
      widget.onReceived!(assignmentId);
    } else if (Navigator.of(context).canPop()) {
      Navigator.pop(context, DriverRouteResult.received);
    } else {
      await _loadTasks(silent: true);
    }
  }

  Future<ShipperTaskDto> _readPickupTask(int id) async {
    if (widget.loadTasks == null) return ApiService.getMyTaskDetail(id);
    final tasks = await widget.loadTasks!();
    return tasks.firstWhere(
      (task) => task.assignmentId == id,
      orElse: () =>
          throw Exception('Nhiệm vụ không còn trong danh sách hiện tại.'),
    );
  }

  Future<void> _pickup(ShipperTaskDto task) async {
    if (_working || _error != null) return;
    setState(() {
      _working = true;
      _stopNavigation();
    });
    try {
      final result = await showDialog<PickupReceiptResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PickupReceiptDialog(
          assignmentId: task.assignmentId,
          readCurrent: () => _readPickupTask(task.assignmentId),
          receiveWithCondition: widget.receiveTask != null
              ? null
              : (code, notes, details) => ApiService.pickupTask(
                  task.assignmentId,
                  code,
                  notes: notes,
                  parcelCondition: details.parcelCondition,
                  evidenceBytes: details.evidenceBytes,
                  latitude: details.latitude,
                  longitude: details.longitude,
                  accuracyMeters: details.accuracyMeters,
                ),
          receive: (code, notes) => widget.receiveTask != null
              ? widget.receiveTask!(task.assignmentId, code)
              : ApiService.pickupTask(task.assignmentId, code, notes: notes),
        ),
      );
      if (!mounted) return;
      if (result == PickupReceiptResult.received) {
        await _finishReceipt(task.assignmentId);
      } else if (result == PickupReceiptResult.issue) {
        await _reportIssue(task);
      }
      if (mounted && result != PickupReceiptResult.received) {
        await _loadTasks(silent: true);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _reportIssue(ShipperTaskDto task) async {
    setState(_stopNavigation);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PickupIssueDialog(
        assignmentId: task.assignmentId,
        orderId: task.orderId,
      ),
    );
    if (mounted) await _loadTasks(silent: true);
  }

  void _showWaitingWarehouseDialog(ShipperTaskDto task) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warehouse_outlined, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('Chờ Thủ kho xuất kho', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đơn hàng ${task.orderCode} (${task.trackingNumber}) đang ở trạng thái CHỜ XUẤT KHO.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quy trình kiểm soát thực tế tại kho:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  SizedBox(height: 6),
                  Text('1. Shipper gom kiện đến quầy bàn giao/cổng xuất.'),
                  Text('2. Thủ kho dùng súng barcode quét đối chiếu.'),
                  Text('3. Thủ kho bấm "Xác nhận xuất kho" trên hệ thống.'),
                  Text('4. Khi có thông báo, Shipper mở phiếu để bấm xác nhận nhận kiện chuyển giao trách nhiệm.'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đã hiểu'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await _loadTasks();
              final refreshed = _tasks.where((t) => t.assignmentId == task.assignmentId).firstOrNull;
              if (refreshed != null && refreshed.orderStatus.toUpperCase() == 'HANDED_OVER' && mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const B8HandoverScreen()),
                ).then((_) => _loadTasks());
              }
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Kiểm tra lại'),
          ),
        ],
      ),
    );
  }

  Widget _card(ShipperTaskDto task, int index) {
    final pickup = task.stage == DriverTaskStage.warehouse;
    final selected = _selectedAssignmentId == task.assignmentId;
    final isRouteLoaded =
        _routeTask?.assignmentId == task.assignmentId && _geometry.isNotEmpty;

    return Semantics(
      key: ValueKey('route-stop-${task.assignmentId}'),
      selected: selected,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primary : const Color(0xFFE2E8F0),
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Row 1: Header (Mã đơn + Tag trạng thái)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: pickup
                          ? const Color(0xFFEFF6FF)
                          : const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      task.tripId == null
                          ? 'Đơn lẻ'
                          : 'Điểm ${task.stopSequence ?? index + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: pickup
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF059669),
                      ),
                    ),
                  ),
                  Text(
                    task.orderCode,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppTheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: pickup
                          ? AppTheme.primaryFixed.withValues(alpha: 0.4)
                          : const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      pickup ? 'Lấy tại kho' : 'Giao khách',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: pickup
                            ? AppTheme.primary
                            : const Color(0xFF166534),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Row 2: Khung địa chỉ điểm đến
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      pickup
                          ? Icons.warehouse_outlined
                          : Icons.location_on_outlined,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pickup
                                ? task.pickupWarehouseName
                                : task.customerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pickup
                                ? (task.pickupAddress.isEmpty
                                      ? 'Kho chưa có địa chỉ'
                                      : task.pickupAddress)
                                : task.deliveryAddress,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.secondary,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (pickup && task.pickupDueAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: AppTheme.secondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Hạn đến: ${DateFormat('HH:mm · dd/MM').format(task.pickupDueAt!.toLocal())} (${pickupDeadlineLabel(task, DateTime.now())})',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 10),

              // Row 3: Action Buttons (GỌN GÀNG, KHÔNG ĐÈ LÊN NHAU)
              if (isRouteLoaded) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: ValueKey('route-start-${task.assignmentId}'),
                        onPressed:
                            _navigating ||
                                _routing ||
                                _working ||
                                _error != null
                            ? null
                            : () => _startNavigation(task),
                        icon: const Icon(Icons.navigation_rounded, size: 16),
                        label: const Text(
                          'Dẫn đường',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: AppTheme.primary),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        key: ValueKey('route-result-${task.assignmentId}'),
                        onPressed: _working || _error != null
                            ? null
                            : () {
                                setState(_stopNavigation);
                                if (pickup) {
                                  if (widget.receiveTask != null) {
                                    _pickup(task);
                                  } else if (task.orderStatus.toUpperCase() ==
                                      'ASSIGNED') {
                                    _showWaitingWarehouseDialog(task);
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const B8HandoverScreen(),
                                      ),
                                    ).then((_) => _loadTasks());
                                  }
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const B3OrderManagementScreen(
                                            initialFilter: 2,
                                          ),
                                    ),
                                  ).then((_) => _loadTasks());
                                }
                              },
                        icon: Icon(
                          pickup
                              ? (task.orderStatus.toUpperCase() == 'HANDED_OVER'
                                  ? Icons.fact_check_outlined
                                  : Icons.hourglass_top_outlined)
                              : Icons.check_circle_outline,
                          size: 16,
                        ),
                        label: Text(
                          pickup
                              ? (widget.receiveTask != null
                                  ? (_working ? 'Đang nhận…' : 'Đã nhận kiện hàng')
                                  : (task.orderStatus.toUpperCase() == 'HANDED_OVER'
                                      ? (_working ? 'Đang tải…' : 'Ký nhận bàn giao')
                                      : 'Chờ kho quét xuất'))
                              : 'Giao hàng',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  key: ValueKey('route-preview-${task.assignmentId}'),
                  onPressed: _routing || _working || _error != null
                      ? null
                      : () => _directions(task),
                  icon: const Icon(Icons.alt_route_rounded, size: 16),
                  label: const Text('Xem lại tuyến'),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: ValueKey('route-preview-${task.assignmentId}'),
                        onPressed: _routing || _error != null || _working
                            ? null
                            : () => _directions(task),
                        icon: const Icon(Icons.alt_route_rounded, size: 16),
                        label: Text(
                          _routing
                              ? 'Đang tìm tuyến…'
                              : (pickup
                                    ? 'Xem tuyến đến kho'
                                    : 'Xem tuyến giao đã xếp'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    if (pickup) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _working || _error != null
                              ? null
                              : () {
                                  if (widget.receiveTask != null) {
                                    _pickup(task);
                                  } else if (task.orderStatus.toUpperCase() ==
                                      'ASSIGNED') {
                                    _showWaitingWarehouseDialog(task);
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const B8HandoverScreen(),
                                      ),
                                    ).then((_) => _loadTasks());
                                  }
                                },
                          icon: Icon(
                            task.orderStatus.toUpperCase() == 'HANDED_OVER'
                                ? Icons.fact_check_outlined
                                : Icons.hourglass_top_outlined,
                            size: 16,
                          ),
                          label: Text(
                            widget.receiveTask != null
                                ? (_working ? 'Đang nhận…' : 'Đã nhận kiện hàng')
                                : (task.orderStatus.toUpperCase() == 'HANDED_OVER'
                                    ? (_working ? 'Đang tải…' : 'Ký nhận bàn giao')
                                    : 'Chờ kho quét xuất'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              // Row 4: Báo sự cố
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: _working || _error != null
                        ? null
                        : () {
                            if (pickup) {
                              _reportIssue(task);
                            } else {
                              EmergencyIncidentDialog.show(
                                context,
                                assignmentId: task.assignmentId,
                                orderId: task.orderId,
                                orderCode: task.orderCode,
                                tripId: task.tripId,
                              ).then((reported) {
                                if (reported == true) _loadTasks();
                              });
                            }
                          },
                    icon: const Icon(
                      Icons.report_problem_outlined,
                      size: 14,
                      color: AppTheme.secondary,
                    ),
                    label: Text(
                      pickup ? 'Báo sự cố nhận kiện' : 'Báo sự cố giao hàng',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondary,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _map() {
    final points = _tasks
        .where(
          (t) =>
              t.routeLatitude != null &&
              t.routeLongitude != null &&
              t.routeLatitude!.abs() <= 90 &&
              t.routeLongitude!.abs() <= 180,
        )
        .toList();
    const defaultCenter = LatLng(10.7769, 106.7009);
    final initialPos = _cameraPoints.isNotEmpty
        ? _cameraPoints.first
        : (_position ?? defaultCenter);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialPos,
        initialZoom: 14,
        onPositionChanged: (_, hasGesture) {
          if (hasGesture && _navigating && _following) {
            setState(() => _following = false);
          }
        },
        onMapReady: () {
          _mapReady = true;
          if (_position != null && _tasks.isEmpty) {
            _mapController.move(_position!, 15);
          } else {
            _fitMap();
          }
        },
      ),
      children: [
        TileLayer(
          tileProvider: widget.tileProvider,
          urlTemplate:
              'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}&hl=vi',
          subdomains: const ['0', '1', '2', '3'],
          panBuffer: 2,
          keepBuffer: 4,
          maxNativeZoom: 19,
          maxZoom: 20,
          tileDisplay: const TileDisplay.fadeIn(
            duration: Duration(milliseconds: 120),
          ),
          userAgentPackageName: 'com.tvdlogistics.shipper',
        ),
        if (_geometry.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points:
                    _navigating &&
                        _progress != null &&
                        _progress!.distanceFromRouteMeters <= 45
                    ? _progress!.remainingGeometry
                    : _geometry,
                strokeWidth: 6,
                color: const Color(0xFF1A73E8),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (_navigating && _geometry.isNotEmpty)
              Marker(
                point: _geometry.first,
                width: 32,
                height: 32,
                child: const Tooltip(
                  message: 'Điểm bắt đầu đường đã tìm được',
                  child: Icon(Icons.flag_circle, color: Colors.green, size: 30),
                ),
              ),
            if (_position != null)
              Marker(
                point: _position!,
                width: 28,
                height: 28,
                child: const Icon(
                  Icons.my_location,
                  color: Colors.blue,
                  size: 26,
                ),
              ),
            ...points.map(
              (t) => Marker(
                point: LatLng(t.routeLatitude!, t.routeLongitude!),
                width: 42,
                height: 42,
                child: GestureDetector(
                  onTap: _routing || _working || _error != null
                      ? null
                      : () => _directions(t),
                  child: Tooltip(
                    message: t.stage == DriverTaskStage.warehouse
                        ? t.pickupWarehouseName
                        : t.orderCode,
                    child: CircleAvatar(
                      backgroundColor: AppTheme.primary,
                      child: t.stage == DriverTaskStage.warehouse
                          ? const Icon(Icons.warehouse, color: Colors.white)
                          : Text(
                              '${t.stopSequence ?? _tasks.indexOf(t) + 1}',
                              style: const TextStyle(color: Colors.white),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.topRight,
          child: ColoredBox(
            color: Colors.white,
            child: TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://www.openstreetmap.org/copyright'),
              ),
              child: const Text(
                '© OpenStreetMap',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.assignmentId == null
              ? 'Lộ trình điều phối'
              : _tasks.isNotEmpty &&
                    selectedDriverRoute(_tasks, _selectedAssignmentId)?.stage !=
                        DriverTaskStage.warehouse
              ? 'Đi giao theo lộ trình'
              : 'Đến kho nhận hàng',
        ),
        actions: [
          IconButton(
            tooltip: 'Báo sự cố khẩn cấp trên đường',
            icon: const Icon(
              Icons.warning_amber_rounded,
              color: AppTheme.error,
            ),
            onPressed: () async {
              final activeTask = selectedDriverRoute(
                _tasks,
                _selectedAssignmentId,
              );
              final reported = await EmergencyIncidentDialog.show(
                context,
                assignmentId: activeTask?.assignmentId,
                orderId: activeTask?.orderId,
                orderCode: activeTask?.orderCode,
                tripId: activeTask?.tripId,
              );
              if (reported == true) {
                await _loadTasks();
              }
            },
          ),
          IconButton(
            tooltip: 'Bản đồ © OpenStreetMap',
            icon: const Icon(Icons.info_outline),
            onPressed: () => launchUrl(
              Uri.parse('https://www.openstreetmap.org/copyright'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          IconButton(
            onPressed: _loading || _working
                ? null
                : () async {
                    _routeKey = null;
                    await _loadTasks();
                  },
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_navigating) _navigationPanel(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      Positioned.fill(child: _map()),
                      Positioned(
                        top: _navigating ? 52 : 12,
                        right: 12,
                        child: FloatingActionButton.small(
                          heroTag: 'my-location-fab',
                          tooltip: _navigating
                              ? 'Theo vị trí của tôi'
                              : 'Vị trí hiện tại',
                          backgroundColor: Colors.white,
                          foregroundColor: AppTheme.primary,
                          elevation: 3,
                          onPressed:
                              !_navigating &&
                                  (_locating || _routing || _working)
                              ? null
                              : () {
                                  if (_navigating) {
                                    setState(() => _following = true);
                                    _followPosition();
                                  } else {
                                    _fetchCurrentLocation(moveTo: true);
                                  }
                                },
                          child: _locating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _navigating
                                      ? (_following
                                            ? Icons.gps_fixed
                                            : Icons.gps_not_fixed)
                                      : Icons.my_location,
                                ),
                        ),
                      ),
                      if (_routing || _locating)
                        Positioned(
                          top: 10,
                          left: 12,
                          child: Chip(
                            label: Text(
                              _locating
                                  ? 'Đang lấy vị trí…'
                                  : 'Đang tải tuyến đường…',
                            ),
                          ),
                        ),
                      DraggableScrollableSheet(
                        initialChildSize: 0.48,
                        minChildSize: 0.25,
                        maxChildSize: 0.86,
                        builder: (context, scrollController) => Material(
                          elevation: 8,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                            children: [
                              Center(
                                child: Container(
                                  key: const ValueKey('route-sheet-handle'),
                                  width: 42,
                                  height: 4,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade400,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  const Text(
                                    'Lộ trình điều phối',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.onSurface,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Text(
                                      '${_tasks.where((t) => t.stage == DriverTaskStage.warehouse).length} lấy kho · ${_tasks.where((t) => t.stage != DriverTaskStage.warehouse).length} đi giao',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.secondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_error != null)
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.errorContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Không tải được dữ liệu mới: ${_error!.replaceFirst(RegExp(r"^(Exception|FormatException):\s*"), "")}',
                                    style: const TextStyle(
                                      color: AppTheme.error,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              if (_routeSource != null && !_navigating)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFBFDBFE),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.near_me_rounded,
                                        size: 16,
                                        color: Color(0xFF2563EB),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          driverRouteSummary(
                                            distanceKm: _distanceKm ?? 0,
                                            minutes: _minutes ?? 0,
                                            savedPlan:
                                                _routeSource == 'ADMIN_PLAN',
                                            atDestination:
                                                _position != null &&
                                                _routeTask != null &&
                                                _routeTask!.routeLatitude !=
                                                    null &&
                                                _routeTask!.routeLongitude !=
                                                    null &&
                                                Distance()(
                                                      _position!,
                                                      LatLng(
                                                        _routeTask!
                                                            .routeLatitude!,
                                                        _routeTask!
                                                            .routeLongitude!,
                                                      ),
                                                    ) <=
                                                    30,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1E40AF),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_gpsWarning != null && !_navigating)
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(_gpsWarning!),
                                ),
                              if (_routeError != null && !_navigating)
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFFDE68A),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.info_outline,
                                        size: 16,
                                        color: Color(0xFFD97706),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _routeError!,
                                          style: const TextStyle(
                                            color: Color(0xFF92400E),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_locationIssue != null && !_navigating)
                                _locationRecovery(),
                              if (_tasks.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'Không còn nhiệm vụ lấy/giao hàng đang xử lý.',
                                  ),
                                ),
                              ..._tasks.asMap().entries.map(
                                (e) => _card(e.value, e.key),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
