import 'auth_and_task_models.dart' show parseApiDateTime;

class IncidentChatMessage {
  final int id;
  final int? incidentId;
  final int senderAccountId;
  final String senderRole;
  final String senderName;
  final bool isMe;
  final String content;
  final String? imageUrl;
  final DateTime sentAt;
  final bool isRead;

  const IncidentChatMessage({
    required this.id,
    this.incidentId,
    required this.senderAccountId,
    required this.senderRole,
    required this.senderName,
    required this.isMe,
    required this.content,
    this.imageUrl,
    required this.sentAt,
    this.isRead = false,
  });

  factory IncidentChatMessage.fromJson(Map<String, dynamic> json) {
    return IncidentChatMessage(
      id: json['id'] as int? ?? 0,
      incidentId: json['incidentId'] as int?,
      senderAccountId: json['senderAccountId'] as int? ?? 0,
      senderRole: (json['senderRole'] as String?) ?? 'USER',
      senderName: (json['senderName'] as String?) ?? 'Người dùng',
      isMe: json['isMe'] == true || json['isMe'] == 1,
      content: (json['content'] as String?) ?? '',
      imageUrl: json['imageUrl'] as String?,
      sentAt: json['sentAt'] is String
          ? (parseApiDateTime(json['sentAt'] as String) ?? DateTime.now())
          : DateTime.now(),
      isRead: json['isRead'] == true || json['isRead'] == 1,
    );
  }
}

class IncidentChatThread {
  final int? incidentId;
  final int? orderId;
  final String? orderCode;
  final int? tripId;
  final String? tripCode;
  final String title;
  final String category;
  final String severity;
  final String status;
  final List<IncidentChatMessage> messages;

  const IncidentChatThread({
    this.incidentId,
    this.orderId,
    this.orderCode,
    this.tripId,
    this.tripCode,
    required this.title,
    required this.category,
    required this.severity,
    required this.status,
    required this.messages,
  });

  factory IncidentChatThread.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List? ?? [];
    return IncidentChatThread(
      incidentId: json['incidentId'] as int?,
      orderId: json['orderId'] as int?,
      orderCode: json['orderCode'] as String?,
      tripId: json['tripId'] as int?,
      tripCode: json['tripCode'] as String?,
      title: (json['title'] as String?) ?? 'Chat xử lý sự cố',
      category: (json['category'] as String?) ?? 'Sự cố',
      severity: (json['severity'] as String?) ?? 'CRITICAL',
      status: (json['status'] as String?) ?? 'OPEN',
      messages: rawMessages
          .whereType<Map<String, dynamic>>()
          .map(IncidentChatMessage.fromJson)
          .toList(),
    );
  }
}

class IncidentConversationSummary {
  final int incidentId;
  final int? orderId;
  final String? orderCode;
  final int? tripId;
  final String? tripCode;
  final String incidentType;
  final String severity;
  final String status;
  final String category;
  final String title;
  final String? lastMessage;
  final String? lastSenderName;
  final DateTime? lastMessageAt;
  final int unreadCount;

  const IncidentConversationSummary({
    required this.incidentId,
    this.orderId,
    this.orderCode,
    this.tripId,
    this.tripCode,
    required this.incidentType,
    required this.severity,
    required this.status,
    required this.category,
    required this.title,
    this.lastMessage,
    this.lastSenderName,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  factory IncidentConversationSummary.fromJson(Map<String, dynamic> json) {
    return IncidentConversationSummary(
      incidentId: json['incidentId'] as int? ?? 0,
      orderId: json['orderId'] as int?,
      orderCode: json['orderCode'] as String?,
      tripId: json['tripId'] as int?,
      tripCode: json['tripCode'] as String?,
      incidentType: (json['incidentType'] as String?) ?? 'OTHER',
      severity: (json['severity'] as String?) ?? 'CRITICAL',
      status: (json['status'] as String?) ?? 'OPEN',
      category: (json['category'] as String?) ?? 'Sự cố',
      title: (json['title'] as String?) ?? 'Sự cố',
      lastMessage: json['lastMessage'] as String?,
      lastSenderName: json['lastSenderName'] as String?,
      lastMessageAt: json['lastMessageAt'] is String
          ? parseApiDateTime(json['lastMessageAt'] as String)
          : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }
}
