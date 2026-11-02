import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/pickup_issue.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';
import '../services/realtime_service.dart';
import '../theme/app_theme.dart';

class PickupIssueDialog extends StatefulWidget {
  final int assignmentId, orderId;
  final Future<PickupIssuePage> Function()? read;
  final Future<PickupIssueAck> Function(PickupIssueDraft)? send;
  final Future<Uint8List?> Function(bool camera)? pickPhoto;
  final Future<Uint8List> Function(int issueId, int eventId)? loadImage;
  final Stream<void>? updates;
  const PickupIssueDialog({
    super.key,
    required this.assignmentId,
    required this.orderId,
    this.read,
    this.send,
    this.pickPhoto,
    this.loadImage,
    this.updates,
  });
  @override
  State<PickupIssueDialog> createState() => _PickupIssueDialogState();
}

class _PickupIssueDialogState extends State<PickupIssueDialog>
    with WidgetsBindingObserver {
  final _reason = TextEditingController();
  PickupIssuePage? _page;
  PickupIssueDraft? _pending;
  Uint8List? _photo;
  String _kind = 'OTHER';
  String? _error, _success;
  bool _loading = false,
      _sending = false,
      _picking = false,
      _imageLoading = false,
      _foreground = true;
  int _generation = 0;
  bool _lastReadFailed = false;
  Timer? _timer;
  StreamSubscription<void>? _updates;
  DialogRoute<void>? _photoRoute;
  NavigatorState? _photoNavigator;
  bool get _busy => _loading || _sending || _picking;
  PickupIssue? get _supplement {
    for (final issue in _page?.items ?? <PickupIssue>[]) {
      if (issue.canSupplement) return issue;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updates = (widget.updates ?? RealtimeService.instance.handoverReady)
        .listen((_) {
          if (!_busy && _foreground) _load();
        });
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_busy &&
          _foreground &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        _load();
      }
    });
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !_busy) _load();
  }

  void _closePhoto() {
    final route = _photoRoute;
    _photoRoute = null;
    if (route != null && route.isActive) _photoNavigator?.removeRoute(route);
    _photoNavigator = null;
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    _updates?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _closePhoto();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _closePhoto();
    setState(() => _loading = true);
    try {
      final page =
          await (widget.read ??
                  () => ApiService.getPickupIssues(
                    widget.assignmentId,
                    widget.orderId,
                  ))()
              .timeout(const Duration(seconds: 20));
      if (!mounted || generation != _generation) return;
      if (page.assignmentId != widget.assignmentId ||
          page.orderId != widget.orderId) {
        throw const FormatException('Hồ sơ không khớp nhiệm vụ.');
      }
      setState(() {
        if (_lastReadFailed) _error = null;
        _lastReadFailed = false;
        _page = page;
        final found = _pending == null
            ? null
            : page.eventFor(_pending!.requestId);
        if (found != null) {
          _success =
              'Máy chủ đã ghi nhận lúc ${_time(found.recordedAt)}: ${found.notes}';
          _pending = null;
          _photo = null;
          _reason.clear();
          _error = null;
        }
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _page = null;
          _lastReadFailed = true;
          _error = 'Không tải được hồ sơ: $error';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pick(bool camera) async {
    if (_busy || _pending != null) return;
    setState(() => _picking = true);
    try {
      Uint8List? bytes;
      if (widget.pickPhoto != null) {
        bytes = await widget.pickPhoto!(camera);
      } else {
        final file = await (camera
            ? DeviceService.takePhoto()
            : DeviceService.pickImageFromGallery());
        if (file != null) {
          if (await file.length() > 5 * 1024 * 1024) {
            throw const FormatException('Ảnh tối đa 5 MB.');
          }
          bytes = await file.readAsBytes();
        }
      }
      if (bytes != null && (bytes.isEmpty || bytes.length > 5 * 1024 * 1024)) {
        throw const FormatException('Ảnh tối đa 5 MB.');
      }
      if (mounted && bytes != null) {
        setState(() {
          _photo = bytes;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _send({bool retry = false}) async {
    if (_busy) return;
    final issue = _supplement;
    if (!retry &&
        (_page == null ||
            !_page!.available ||
            !_page!.canReport && issue == null)) {
      return;
    }
    final draft = retry
        ? _pending
        : PickupIssueDraft(
            requestId: newPickupIssueRequestId(),
            kind: issue?.kind ?? _kind,
            reason: _reason.text.trim(),
            issueId: issue?.id,
            expectedRevision: issue?.revision,
            evidenceBytes: _photo == null ? null : Uint8List.fromList(_photo!),
          );
    if (draft == null) return;
    try {
      draft.validate();
    } catch (error) {
      setState(() => _error = '$error');
      return;
    }
    setState(() {
      _sending = true;
      _pending = draft;
      _error = null;
      _success = null;
    });
    try {
      final ack =
          await (widget.send ??
                  (draft) => ApiService.sendPickupIssue(
                    widget.assignmentId,
                    widget.orderId,
                    draft,
                  ))(draft)
              .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (ack.assignmentId != widget.assignmentId ||
          ack.orderId != widget.orderId ||
          ack.requestId != draft.requestId) {
        throw const FormatException('Biên nhận không khớp báo cáo.');
      }
      setState(() {
        _pending = null;
        _photo = null;
        _reason.clear();
        _success = 'Đã gửi, máy chủ ghi nhận lúc ${_time(ack.recordedAt)}.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (error is PickupIssueSendException && error.definiteFailure) {
          _pending = null;
        }
        _error = 'Chưa xác nhận được báo cáo: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        await _load();
      }
    }
  }

  Future<void> _showPhoto(PickupIssue issue, PickupIssueEvent event) async {
    if (_imageLoading || _busy) return;
    final generation = _generation;
    setState(() => _imageLoading = true);
    try {
      final bytes =
          await (widget.loadImage ??
              (id, event) => ApiService.getPickupIssueEvidence(
                widget.orderId,
                id,
                event,
              ))(issue.id, event.id);
      if (!mounted || generation != _generation) return;
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = DialogRoute<void>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(title: const Text('Ảnh sự cố nhận kiện')),
            body: Center(
              child: InteractiveViewer(
                child: Image.memory(
                  bytes,
                  errorBuilder: (_, _, _) =>
                      const Text('Không hiển thị được ảnh.'),
                ),
              ),
            ),
          ),
        ),
      );
      _photoNavigator = navigator;
      _photoRoute = route;
      await navigator.push(route);
      if (identical(_photoRoute, route)) {
        _photoRoute = null;
        _photoNavigator = null;
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Không mở được ảnh: $error');
      }
    } finally {
      if (mounted) setState(() => _imageLoading = false);
    }
  }

  String _time(DateTime time) =>
      DateFormat('HH:mm · dd/MM/yyyy').format(time.toLocal());
  @override
  Widget build(BuildContext context) {
    final supplement = _supplement,
        canWrite =
            _page?.available == true &&
            (_page?.canReport == true || supplement != null);
    return PopScope(
      canPop: !_sending,
      child: AlertDialog(
        title: const Text('Sự cố nhận kiện / Phản hồi'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loading) const LinearProgressIndicator(),
                const Text(
                  'Báo sự cố chưa xuất kho hoặc ghi nhận bạn đã nhận kiện. Chờ kho/điều phối xử lý trước khi nhận.',
                ),
                if (_page?.pickupBlocked == true)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Đang tạm chặn nhận/xuất kiện vì còn hồ sơ sự cố mở.',
                      style: TextStyle(color: AppTheme.error),
                    ),
                  ),
                if (_success != null)
                  Text(_success!, style: const TextStyle(color: Colors.green)),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: AppTheme.error)),
                if (_page?.available == false)
                  const Text(
                    'Chưa bật hồ sơ sự cố. Cần cập nhật SQL trên hệ thống quản lý.',
                  ),
                if (_pending != null) ...[
                  const Text(
                    'Chưa xác định kết quả gửi. Kiểm tra biên nhận trước khi gửi lại; gửi lại giữ nguyên nội dung và mã yêu cầu.',
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _send(retry: true),
                    child: const Text('Gửi lại đúng yêu cầu này'),
                  ),
                ],
                if (canWrite && _pending == null) ...[
                  const Divider(),
                  Text(
                    supplement == null
                        ? 'Báo sự cố mới'
                        : 'Bổ sung cho hồ sơ #${supplement.id}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (supplement == null)
                    DropdownButtonFormField<String>(
                      initialValue: _kind,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Loại sự cố',
                      ),
                      items: pickupIssueKinds.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _kind = value!),
                    ),
                  TextField(
                    controller: _reason,
                    enabled: !_busy,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: supplement == null
                          ? 'Mô tả sự cố'
                          : 'Thông tin bổ sung',
                    ),
                  ),
                  const Text(
                    'Hàng hỏng/sai nhãn cần ảnh khi báo lần đầu. Giữ nguyên hiện trạng; không nhận kiện nếu không an toàn.',
                  ),
                  Wrap(
                    children: [
                      TextButton.icon(
                        onPressed: _busy ? null : () => _pick(true),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Chụp ảnh minh chứng'),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : () => _pick(false),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Chọn ảnh minh chứng'),
                      ),
                    ],
                  ),
                  if (_photo != null) ...[
                    Image.memory(
                      _photo!,
                      height: 120,
                      errorBuilder: (_, _, _) => const Text(
                        'Không xem trước được ảnh; máy chủ sẽ kiểm tra khi gửi.',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _photo = null),
                      child: const Text('Xóa ảnh minh chứng'),
                    ),
                  ],
                  const Text(
                    'Một ảnh JPEG/PNG tối đa 5 MB. Ảnh được gửi riêng theo quyền xem hồ sơ.',
                    style: TextStyle(fontSize: 12),
                  ),
                  FilledButton(
                    onPressed: _busy || _reason.text.trim().length < 3
                        ? null
                        : () => _send(),
                    child: Text(
                      _sending
                          ? 'Đang gửi…'
                          : supplement == null
                          ? 'Gửi sự cố'
                          : 'Gửi bổ sung',
                    ),
                  ),
                ],
                if (_page != null && _page!.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Chưa có hồ sơ sự cố trong nhiệm vụ này.'),
                  ),
                for (final issue in _page?.items ?? <PickupIssue>[]) ...[
                  const Divider(),
                  Text(
                    '#${issue.id} · ${pickupIssueKinds[issue.kind]}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(pickupIssueStatuses[issue.status]!),
                  Text(
                    'Kho: ${issue.warehouseName} · Báo lúc ${_time(issue.reportedAt)}',
                  ),
                  for (final event in issue.events)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${pickupIssueActions[event.eventType]} · ${event.authorName} · ${_time(event.recordedAt)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          Text(event.notes),
                          if (event.hasEvidence)
                            TextButton.icon(
                              onPressed: _imageLoading || _busy
                                  ? null
                                  : () => _showPhoto(issue, event),
                              icon: const Icon(Icons.photo),
                              label: const Text('Xem ảnh sự cố'),
                            ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _sending ? null : () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Kiểm tra / làm mới'),
          ),
        ],
      ),
    );
  }
}
