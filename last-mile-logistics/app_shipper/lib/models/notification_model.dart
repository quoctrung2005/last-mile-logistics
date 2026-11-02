import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import 'auth_and_task_models.dart';

class NotificationItem {
  final int id;
  final String type;
  final String title;
  final String content;
  final String? referenceType;
  final int? referenceId;
  final bool isRead;
  final DateTime? createdAt;
  final DateTime? readAt;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    this.referenceType,
    this.referenceId,
    required this.isRead,
    this.createdAt,
    this.readAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    int readInt(dynamic value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;

    int? readNullableInt(dynamic value) => value == null
        ? null
        : value is num
        ? value.toInt()
        : int.tryParse(value.toString());

    return NotificationItem(
      id: readInt(json['id']),
      type: (json['type'] ?? 'GENERAL').toString(),
      title: (json['title'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      referenceType: json['referenceType']?.toString(),
      referenceId: readNullableInt(json['referenceId']),
      isRead: json['isRead'] == true,
      createdAt: parseApiDateTime(json['createdAt']),
      readAt: parseApiDateTime(json['readAt']),
    );
  }

  NotificationItem copyWith({
    int? id,
    String? type,
    String? title,
    String? content,
    String? referenceType,
    int? referenceId,
    bool? isRead,
    DateTime? createdAt,
    DateTime? readAt,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      referenceType: referenceType ?? this.referenceType,
      referenceId: referenceId ?? this.referenceId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
    );
  }

  String get timeFormatted {
    if (createdAt == null) return '';
    final local = createdAt!.toLocal();
    final diff = DateTime.now().difference(local);

    if (diff.inSeconds < 60) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return DateFormat('HH:mm · dd/MM/yyyy').format(local);
  }

  IconData get icon {
    final t = type.toUpperCase();
    if (t.contains('ASSIGN') || t.contains('TASK')) {
      return Icons.assignment_outlined;
    }
    if (t.contains('EMERGENCY') || t.contains('INCIDENT') || t.contains('ALERT')) {
      return Icons.warning_amber_rounded;
    }
    if (t.contains('HANDOVER')) {
      return Icons.inventory_2_outlined;
    }
    if (t.contains('RETURN')) {
      return Icons.assignment_return_outlined;
    }
    if (t.contains('COD') || t.contains('PAYMENT')) {
      return Icons.payments_outlined;
    }
    return Icons.notifications_outlined;
  }

  Color get iconColor {
    final t = type.toUpperCase();
    if (t.contains('EMERGENCY') || t.contains('INCIDENT')) {
      return AppTheme.error;
    }
    if (t.contains('ASSIGN') || t.contains('TASK')) {
      return AppTheme.primary;
    }
    if (t.contains('RETURN')) {
      return Colors.orange.shade800;
    }
    if (t.contains('COD')) {
      return Colors.teal;
    }
    return AppTheme.secondary;
  }
}

class NotificationPageResult {
  final int page;
  final int pageSize;
  final int totalItems;
  final int unreadCount;
  final List<NotificationItem> items;

  const NotificationPageResult({
    required this.page,
    required this.pageSize,
    required this.totalItems,
    required this.unreadCount,
    required this.items,
  });

  factory NotificationPageResult.fromJson(Map<String, dynamic> json) {
    int readInt(dynamic value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;

    final rawItems = json['items'];
    final itemsList = <NotificationItem>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          itemsList.add(NotificationItem.fromJson(item));
        }
      }
    }

    return NotificationPageResult(
      page: readInt(json['page']),
      pageSize: readInt(json['pageSize']),
      totalItems: readInt(json['totalItems']),
      unreadCount: readInt(json['unreadCount']),
      items: itemsList,
    );
  }
}
