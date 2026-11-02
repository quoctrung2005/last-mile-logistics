enum ParcelLabelStatus { empty, invalid, multiple, mismatch, matched }

class ParcelLabelResult {
  final ParcelLabelStatus status;
  final String? code;
  const ParcelLabelResult(this.status, [this.code]);
  String get message => switch (status) {
    ParcelLabelStatus.empty => 'Đưa một mã vận đơn trên kiện vào camera.',
    ParcelLabelStatus.invalid =>
      'Mã đọc được không hợp lệ. Hãy quét mã vận đơn trên nhãn kiện.',
    ParcelLabelStatus.multiple =>
      'Đang thấy nhiều mã khác nhau. Chỉ đưa một mã vận đơn vào camera.',
    ParcelLabelStatus.mismatch =>
      'Mã này không thuộc nhiệm vụ đang nhận. Hãy kiểm tra lại kiện.',
    ParcelLabelStatus.matched => 'Đã khớp mã kiện',
  };
}

// Tracking identifiers use ASCII case folding; do not turn Unicode lookalikes
// such as ß into a different label (SS).
String _labelKey(String value) =>
    value.replaceAllMapped(RegExp('[a-z]'), (m) => m[0]!.toUpperCase());

/// Accept only the full label value. Never extract a code from a URL/JSON or
/// remove prefixes, punctuation or leading zeroes to make another label match.
ParcelLabelResult checkParcelLabels(
  Iterable<String?> values,
  Iterable<String> expected,
) {
  final labels = <String, String>{};
  for (final raw in values) {
    if (raw == null || raw.trim().isEmpty) continue;
    final value = raw.trim();
    if (value.length > 50 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(raw)) {
      return const ParcelLabelResult(ParcelLabelStatus.invalid);
    }
    labels.putIfAbsent(_labelKey(value), () => value);
  }
  if (labels.isEmpty) return const ParcelLabelResult(ParcelLabelStatus.empty);
  if (labels.length > 1) {
    return const ParcelLabelResult(ParcelLabelStatus.multiple);
  }
  for (final canonical in expected) {
    final value = canonical.trim();
    if (value.isNotEmpty &&
        value.length <= 50 &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) &&
        labels.containsKey(_labelKey(value))) {
      return ParcelLabelResult(ParcelLabelStatus.matched, value);
    }
  }
  return const ParcelLabelResult(ParcelLabelStatus.mismatch);
}
