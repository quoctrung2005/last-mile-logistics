import 'dart:typed_data';

import 'auth_and_task_models.dart';

class DeliverySuccessSubmission {
  final int assignmentId, orderId;
  final String receiverName, notes;
  final double actualCodAmount;
  final double? latitude, longitude;
  final Uint8List? evidence;
  const DeliverySuccessSubmission({
    required this.assignmentId,
    required this.orderId,
    required this.receiverName,
    required this.actualCodAmount,
    this.notes = '',
    this.latitude,
    this.longitude,
    this.evidence,
  });
}

class DeliverySuccessReceipt {
  final int assignmentId, orderId, shipperId, attemptId, evidenceId;
  final String receiverName, evidenceType, codStatus;
  final double actualCodAmount;
  final DateTime deliveredAt;
  final bool hasEvidence, alreadyDelivered;
  DeliverySuccessReceipt._(Map<String, dynamic> d)
    : assignmentId = d['assignmentId'],
      orderId = d['orderId'],
      shipperId = d['shipperId'],
      attemptId = d['deliveryAttemptId'],
      evidenceId = d['evidenceId'],
      receiverName = d['receiverName'],
      evidenceType = d['evidenceType'],
      codStatus = d['codStatus'],
      actualCodAmount = (d['actualCodAmount'] as num).toDouble(),
      deliveredAt = parseApiDateTime(d['deliveredAt'])!,
      hasEvidence = d['hasEvidence'],
      alreadyDelivered = d['alreadyDelivered'];
  factory DeliverySuccessReceipt.fromJson(
    Map<String, dynamic> d, {
    required int assignmentId,
    required int orderId,
    double? expectedCod,
  }) {
    const bad = FormatException(
      'Biên nhận giao hàng thiếu hoặc sai dữ liệu. Hãy kiểm tra lại trên máy chủ.',
    );
    for (final key in [
      'assignmentId',
      'orderId',
      'shipperId',
      'deliveryAttemptId',
      'evidenceId',
    ]) {
      if (d[key] is! int || d[key] <= 0) throw bad;
    }
    final cod = d['actualCodAmount'];
    if (d['assignmentId'] != assignmentId ||
        d['orderId'] != orderId ||
        d['orderStatus'] != 'DELIVERED' ||
        d['assignmentStatus'] != 'COMPLETED' ||
        d['receiverName'] is! String ||
        (d['receiverName'] as String).trim().isEmpty ||
        cod is! num ||
        !cod.isFinite ||
        cod < 0 ||
        expectedCod != null && cod != expectedCod ||
        parseApiDateTime(d['deliveredAt']) == null ||
        d['hasEvidence'] is! bool ||
        d['alreadyDelivered'] is! bool ||
        !{'PHOTO', 'RECEIVER_CONFIRMATION'}.contains(d['evidenceType']) ||
        (d['hasEvidence'] == true) != (d['evidenceType'] == 'PHOTO') ||
        d['codStatus'] != (cod > 0 ? 'COLLECTED' : 'NOT_REQUIRED')) {
      throw bad;
    }
    return DeliverySuccessReceipt._(d);
  }
}
