import 'auth_and_task_models.dart';

class TaskPage {
  static const groups = ['OFFERS', 'WAREHOUSE', 'DELIVERING', 'ISSUES', 'DONE'];
  static const labels = [
    'Chờ tiếp nhận',
    'Lấy tại kho',
    'Đang giao',
    'Sự cố & Hoàn',
    'Lịch sử',
  ];
  final int page, pageSize, totalItems;
  final List<ShipperTaskDto> items;
  const TaskPage({
    required this.page,
    required this.pageSize,
    required this.totalItems,
    required this.items,
  });
  bool get hasMore => items.isNotEmpty && page * pageSize < totalItems;

  factory TaskPage.fromJson(
    Object? json, {
    required int expectedPage,
    required int expectedSize,
    String? expectedGroup,
  }) {
    const invalid = FormatException(
      'Danh sách nhiệm vụ trả về không hợp lệ. Hãy tải lại hoặc cập nhật máy chủ.',
    );
    if (json is! Map<String, dynamic> ||
        json['items'] is! List ||
        json['page'] != expectedPage ||
        json['pageSize'] != expectedSize ||
        json['totalItems'] is! int ||
        json['totalItems'] < 0 ||
        json['shipperId'] is! int ||
        json['shipperId'] <= 0 ||
        expectedGroup != null && json['taskGroup'] != expectedGroup) {
      throw invalid;
    }
    final rows = json['items'] as List;
    if (rows.length > expectedSize || rows.length > json['totalItems']) {
      throw invalid;
    }
    final ids = <int>{};
    final items = <ShipperTaskDto>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic> ||
          row['id'] is! int ||
          row['id'] <= 0 ||
          row['orderId'] is! int ||
          row['orderId'] <= 0 ||
          row['assignmentStatus'] is! String ||
          row['orderStatus'] is! String ||
          !ids.add(row['id']) ||
          expectedGroup != null && row['taskGroup'] != expectedGroup) {
        throw invalid;
      }
      items.add(ShipperTaskDto.fromJson(row));
    }
    return TaskPage(
      page: expectedPage,
      pageSize: expectedSize,
      totalItems: json['totalItems'],
      items: List.unmodifiable(items),
    );
  }
}
