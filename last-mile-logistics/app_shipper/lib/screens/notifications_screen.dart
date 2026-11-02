import 'dart:async';

import 'package:flutter/material.dart';

import '../models/notification_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'task_detail_screen.dart';
import 'incident_chat_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final Future<NotificationPageResult> Function({
    bool unreadOnly,
    int page,
    int pageSize,
  })? loadNotifications;
  final Future<Map<String, dynamic>> Function({
    List<int>? ids,
    bool all,
  })? markRead;

  const NotificationsScreen({
    super.key,
    this.loadNotifications,
    this.markRead,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = false;
  bool _markingAll = false;
  String? _error;
  bool _unreadOnly = false;
  int _unreadCount = 0;
  int _totalItems = 0;
  List<NotificationItem> _items = [];

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final fetcher = widget.loadNotifications ?? ApiService.getNotifications;
      final result = await fetcher(
        unreadOnly: _unreadOnly,
        page: 1,
        pageSize: 50,
      );

      if (!mounted) return;
      setState(() {
        _items = result.items;
        _unreadCount = result.unreadCount;
        _totalItems = result.totalItems;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst(RegExp(r'^(Exception|FormatException):\s*'), '');
      });
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll || _unreadCount == 0) return;
    setState(() => _markingAll = true);

    try {
      final marker = widget.markRead ?? ApiService.markNotificationsRead;
      await marker(all: true);

      if (!mounted) return;
      setState(() {
        _unreadCount = 0;
        _items = _items.map((item) => item.copyWith(isRead: true)).toList();
        if (_unreadOnly) {
          _items.clear();
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã đánh dấu tất cả thông báo là đã đọc.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi đánh dấu: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _markSingleRead(NotificationItem item) async {
    if (item.isRead) return;

    try {
      final marker = widget.markRead ?? ApiService.markNotificationsRead;
      await marker(ids: [item.id]);

      if (!mounted) return;
      setState(() {
        if (_unreadCount > 0) _unreadCount--;
        _items = _items.map((it) {
          if (it.id == item.id) return it.copyWith(isRead: true);
          return it;
        }).toList();

        if (_unreadOnly) {
          _items.removeWhere((it) => it.id == item.id);
        }
      });
    } catch (_) {
      // Ignore background read failure
    }
  }

  void _onNotificationTap(NotificationItem item) {
    if (!item.isRead) {
      _markSingleRead(item);
    }

    if (item.type.toUpperCase() == 'INCIDENT_CHAT' ||
        item.type.toUpperCase() == 'EMERGENCY_INCIDENT' ||
        item.referenceType?.toUpperCase() == 'INCIDENT') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IncidentChatScreen(
            incidentId: item.referenceId,
            initialTitle: item.title,
          ),
        ),
      );
      return;
    }

    if (item.referenceType?.toUpperCase() == 'ORDER' ||
        item.referenceType?.toUpperCase() == 'ASSIGNMENT') {
      if (item.referenceId != null && item.referenceId! > 0) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TaskDetailScreen(assignmentId: item.referenceId!),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text(
          'Trung tâm thông báo',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton.icon(
              onPressed: _markingAll ? null : _markAllRead,
              icon: _markingAll
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Đọc tất cả'),
            ),
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _fetchNotifications(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterTabs(),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ChoiceChip(
            label: Text(
              _totalItems > 0 ? 'Tất cả ($_totalItems)' : 'Tất cả',
              style: TextStyle(
                fontWeight: !_unreadOnly ? FontWeight.w700 : FontWeight.w500,
                color: !_unreadOnly ? AppTheme.primary : AppTheme.onSurfaceVariant,
              ),
            ),
            selected: !_unreadOnly,
            selectedColor: AppTheme.primaryFixed.withValues(alpha: .5),
            onSelected: (val) {
              if (val && _unreadOnly) {
                setState(() => _unreadOnly = false);
                _fetchNotifications();
              }
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Chưa đọc',
                  style: TextStyle(
                    fontWeight: _unreadOnly ? FontWeight.w700 : FontWeight.w500,
                    color: _unreadOnly ? AppTheme.primary : AppTheme.onSurfaceVariant,
                  ),
                ),
                if (_unreadCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            selected: _unreadOnly,
            selectedColor: AppTheme.primaryFixed.withValues(alpha: .5),
            onSelected: (val) {
              if (val && !_unreadOnly) {
                setState(() => _unreadOnly = true);
                _fetchNotifications();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _fetchNotifications(),
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _unreadOnly
                  ? Icons.mark_email_read_outlined
                  : Icons.notifications_none_outlined,
              size: 56,
              color: AppTheme.secondary,
            ),
            const SizedBox(height: 14),
            Text(
              _unreadOnly ? 'Không có thông báo chưa đọc' : 'Chưa có thông báo nào',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _unreadOnly
                  ? 'Bạn đã đọc tất cả thông báo trong hộp thư.'
                  : 'Các cập nhật về đơn hàng, phân công và sự cố sẽ xuất hiện tại đây.',
              style: const TextStyle(fontSize: 13, color: AppTheme.secondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchNotifications(silent: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = _items[index];
          return _buildNotificationCard(item);
        },
      ),
    );
  }

  Widget _buildNotificationCard(NotificationItem item) {
    final unread = !item.isRead;
    final hasReference = (item.referenceType?.toUpperCase() == 'ORDER' ||
            item.referenceType?.toUpperCase() == 'ASSIGNMENT') &&
        item.referenceId != null &&
        item.referenceId! > 0;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: unread ? AppTheme.surfaceContainerLowest : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: unread
              ? AppTheme.primary.withValues(alpha: 0.3)
              : AppTheme.outlineVariant.withValues(alpha: 0.6),
          width: unread ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _onNotificationTap(item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon container
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: item.iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  item.icon,
                  color: item.iconColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                              color: unread ? AppTheme.onSurface : AppTheme.secondary,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.content,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: unread ? AppTheme.onSurface : AppTheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          item.timeFormatted,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.secondary,
                          ),
                        ),
                        if (hasReference)
                          InkWell(
                            onTap: () => _onNotificationTap(item),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Xem chi tiết',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                  SizedBox(width: 2),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 14,
                                    color: AppTheme.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
