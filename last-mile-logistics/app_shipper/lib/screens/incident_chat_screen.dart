import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/incident_chat.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';
import '../theme/app_theme.dart';

class IncidentChatScreen extends StatefulWidget {
  final int? incidentId;
  final int? orderId;
  final String? orderCode;
  final int? tripId;
  final String? tripCode;
  final String? initialTitle;

  const IncidentChatScreen({
    super.key,
    this.incidentId,
    this.orderId,
    this.orderCode,
    this.tripId,
    this.tripCode,
    this.initialTitle,
  });

  static Future<void> open(
    BuildContext context, {
    int? incidentId,
    int? orderId,
    String? orderCode,
    int? tripId,
    String? tripCode,
    String? initialTitle,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IncidentChatScreen(
          incidentId: incidentId,
          orderId: orderId,
          orderCode: orderCode,
          tripId: tripId,
          tripCode: tripCode,
          initialTitle: initialTitle,
        ),
      ),
    );
  }

  @override
  State<IncidentChatScreen> createState() => _IncidentChatScreenState();
}

class _IncidentChatScreenState extends State<IncidentChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  IncidentChatThread? _thread;
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;
  Timer? _pollingTimer;
  StreamSubscription<void>? _realtimeSub;

  final List<String> _quickSuggestions = [
    '⚡ Tôi đang ở vị trí sự cố',
    '🛠️ Xe hỏng, cần hỗ trợ cứu hộ gấp',
    '📞 Khách không nghe máy, đã gọi 3 lần',
    '📍 Địa chỉ sai / không tìm thấy số nhà',
    '⏳ Đang đợi người nhận khoảng 5-10 phút',
    '✅ Đã giải quyết xong, tiếp tục di chuyển',
  ];

  @override
  void initState() {
    super.initState();
    _loadMessages();

    // Tự động kiểm tra tin nhắn mới mỗi 4 giây
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_isLoading && !_isSending) {
        _pollNewMessages();
      }
    });

    // Lắng nghe cập nhật realtime
    _realtimeSub = RealtimeService.instance.handoverReady.listen((_) {
      if (mounted) _pollNewMessages();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _realtimeSub?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final thread = await ApiService.getIncidentChat(
        incidentId: widget.incidentId,
        orderId: widget.orderId,
        tripId: widget.tripId,
      );

      if (!mounted) return;
      setState(() {
        _thread = thread;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _pollNewMessages() async {
    final currentThread = _thread;
    final lastId = currentThread != null && currentThread.messages.isNotEmpty
        ? currentThread.messages.last.id
        : null;

    try {
      final updated = await ApiService.getIncidentChat(
        incidentId: _thread?.incidentId ?? widget.incidentId,
        orderId: _thread?.orderId ?? widget.orderId,
        tripId: _thread?.tripId ?? widget.tripId,
        afterId: lastId,
      );

      if (!mounted) return;
      if (updated.messages.isNotEmpty) {
        final existingIds = (currentThread?.messages ?? []).map((m) => m.id).toSet();
        final brandNew = updated.messages.where((m) => !existingIds.contains(m.id)).toList();

        if (brandNew.isNotEmpty) {
          setState(() {
            _thread = IncidentChatThread(
              incidentId: updated.incidentId ?? currentThread?.incidentId,
              orderId: updated.orderId ?? currentThread?.orderId,
              orderCode: updated.orderCode ?? currentThread?.orderCode,
              tripId: updated.tripId ?? currentThread?.tripId,
              tripCode: updated.tripCode ?? currentThread?.tripCode,
              title: updated.title,
              category: updated.category,
              severity: updated.severity,
              status: updated.status,
              messages: [...(currentThread?.messages ?? []), ...brandNew],
            );
          });
          _scrollToBottom();
        }
      }
    } catch (_) {
      // Bỏ qua lỗi polling nền
    }
  }

  Future<void> _sendMessage([String? presetText]) async {
    final text = (presetText ?? _textCtrl.text).trim();
    if (text.isEmpty || _isSending) return;

    if (presetText == null) {
      _textCtrl.clear();
    }

    setState(() => _isSending = true);

    try {
      final newMsg = await ApiService.sendIncidentChatMessage(
        incidentId: _thread?.incidentId ?? widget.incidentId,
        orderId: _thread?.orderId ?? widget.orderId,
        tripId: _thread?.tripId ?? widget.tripId,
        content: text,
      );

      if (!mounted) return;
      final currentMessages = _thread?.messages ?? [];
      final exists = currentMessages.any((m) => m.id == newMsg.id);

      setState(() {
        _isSending = false;
        if (!exists) {
          _thread = IncidentChatThread(
            incidentId: newMsg.incidentId ?? _thread?.incidentId ?? widget.incidentId,
            orderId: _thread?.orderId ?? widget.orderId,
            orderCode: _thread?.orderCode ?? widget.orderCode,
            tripId: _thread?.tripId ?? widget.tripId,
            tripCode: _thread?.tripCode ?? widget.tripCode,
            title: _thread?.title ?? 'Chat xử lý sự cố',
            category: _thread?.category ?? 'Sự cố',
            severity: _thread?.severity ?? 'CRITICAL',
            status: _thread?.status == 'RESOLVED' ? 'RESOLVED' : 'IN_PROGRESS',
            messages: [...currentMessages, newMsg],
          );
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không gửi được: ${e.toString().replaceAll("Exception: ", "")}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _confirmResolveIncident() async {
    final incidentId = _thread?.incidentId ?? widget.incidentId;
    if (incidentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có mã sự cố cụ thể để giải quyết.')),
      );
      return;
    }

    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('Hoàn tất xử lý sự cố', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bạn xác nhận sự cố này đã được giải quyết hoặc đã khắc phục xong?',
              style: TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Ghi chú hướng giải quyết (tùy chọn)',
                hintText: 'Ví dụ: Đã thay lốp xong, tiếp tục giao đơn',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận hoàn tất'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService.resolveIncident(
          incidentId: incidentId,
          note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã đánh dấu sự cố giải quyết thành công!'),
            backgroundColor: Color(0xFF059669),
          ),
        );
        _loadMessages();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Widget _buildStatusChip(String status) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status) {
      case 'RESOLVED':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF15803D);
        label = 'Đã giải quyết';
        icon = Icons.check_circle_rounded;
        break;
      case 'IN_PROGRESS':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1D4ED8);
        label = 'Đang xử lý';
        icon = Icons.sync_rounded;
        break;
      default:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        label = 'Chờ tiếp nhận';
        icon = Icons.hourglass_top_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(IncidentChatMessage msg) {
    if (msg.senderRole == 'SYSTEM') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                msg.content,
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF475569),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    final isMe = msg.isMe;
    final timeStr = DateFormat('HH:mm').format(msg.sentAt.toLocal());
    final isDispatcher = msg.senderRole == 'DISPATCHER' || msg.senderRole == 'ADMIN';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: isDispatcher ? const Color(0xFF2563EB) : const Color(0xFF64748B),
              child: Icon(
                isDispatcher ? Icons.support_agent_rounded : Icons.person_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? AppTheme.primary
                    : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          msg.senderName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDispatcher
                                ? const Color(0xFF1D4ED8)
                                : AppTheme.onSurface,
                          ),
                        ),
                        if (isDispatcher) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ĐIỀU PHỐI',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E40AF),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    msg.content,
                    style: TextStyle(
                      fontSize: 14,
                      color: isMe ? Colors.white : const Color(0xFF1E293B),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.75)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thread = _thread;
    final title = thread?.title ?? widget.initialTitle ?? 'Chat xử lý sự cố';
    final status = thread?.status ?? 'OPEN';
    final isResolved = status == 'RESOLVED';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                _buildStatusChip(status),
                if (thread?.category != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '· ${thread!.category}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ],
            ),
          ],
        ),
        actions: [
          if (!isResolved)
            IconButton(
              tooltip: 'Giải quyết xong sự cố',
              icon: const Icon(Icons.check_circle_outline),
              onPressed: _confirmResolveIncident,
            ),
          IconButton(
            tooltip: 'Làm mới tin nhắn',
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Banner tóm tắt ngữ cảnh sự cố
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white,
              child: Row(
                children: [
                  const Icon(Icons.headset_mic_rounded,
                      size: 20, color: Color(0xFF0284C7)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Kênh liên lạc trực tiếp với Điều phối viên kho. Tin nhắn được lưu vào biên bản sự cố.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Danh sách tin nhắn
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline,
                                    size: 40, color: AppTheme.error),
                                const SizedBox(height: 10),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: AppTheme.error),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: _loadMessages,
                                  child: const Text('Thử lại'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : (thread?.messages.isEmpty ?? true)
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      size: 56,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Chưa có tin nhắn nào',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Hãy gửi tin nhắn mô tả sự cố hoặc yêu cầu hỗ trợ điều phối.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 13, color: Color(0xFF94A3B8)),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              itemCount: thread!.messages.length,
                              itemBuilder: (ctx, i) =>
                                  _buildMessageBubble(thread.messages[i]),
                            ),
            ),

            // Gợi ý tin nhắn nhanh
            if (!isResolved)
              Container(
                height: 40,
                color: Colors.white,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: _quickSuggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (ctx, idx) {
                    final sug = _quickSuggestions[idx];
                    return ActionChip(
                      label: Text(
                        sug,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                      onPressed: _isSending ? null : () => _sendMessage(sug),
                    );
                  },
                ),
              ),

            // Ô nhập tin nhắn
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !_isSending && !isResolved,
                      decoration: InputDecoration(
                        hintText: isResolved
                            ? 'Sự cố đã được giải quyết'
                            : 'Nhập tin nhắn trao đổi với điều phối…',
                        hintStyle: TextStyle(
                          fontSize: 13.5,
                          color: Colors.grey.shade400,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        filled: true,
                        fillColor: isResolved
                            ? Colors.grey.shade100
                            : const Color(0xFFF8FAFC),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending || isResolved ? null : () => _sendMessage(),
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
