import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

// Geometry hints have no street names, junction rules or traffic information.
enum NavigationTurn { left, right, reverse, destination }

class NavigationManeuver {
  final NavigationTurn turn;
  final double atMeters;
  const NavigationManeuver(this.turn, this.atMeters);
  String get label => switch (turn) {
    NavigationTurn.left => 'Rẽ trái theo tuyến',
    NavigationTurn.right => 'Rẽ phải theo tuyến',
    NavigationTurn.reverse => 'Đổi hướng theo tuyến',
    NavigationTurn.destination => 'Đi tiếp đến điểm đến',
  };
}

List<NavigationManeuver> navigationManeuvers(List<LatLng> route) {
  if (route.isEmpty) return const [];
  const distance = Distance();
  final lengths = <double>[0];
  for (var i = 1; i < route.length; i++) {
    lengths.add(lengths.last + distance(route[i - 1], route[i]));
  }
  LatLng sample(double meters) {
    var low = 1, high = lengths.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (lengths[mid] < meters) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    for (var i = low; i < lengths.length; i++) {
      if (lengths[i] > lengths[i - 1]) {
        final f = (meters - lengths[i - 1]) / (lengths[i] - lengths[i - 1]);
        return LatLng(
          route[i - 1].latitude +
              (route[i].latitude - route[i - 1].latitude) * f,
          route[i - 1].longitude +
              (route[i].longitude - route[i - 1].longitude) * f,
        );
      }
    }
    return route.last;
  }

  final result = <NavigationManeuver>[];
  var previousAngle = 0.0;
  for (var i = 1; i < route.length - 1; i++) {
    if (lengths[i] < 12 || lengths.last - lengths[i] < 12) continue;
    final before = sample(math.max(0, lengths[i] - 20));
    final after = sample(math.min(lengths.last, lengths[i] + 20));
    final incoming = distance.bearing(before, route[i]);
    final outgoing = distance.bearing(route[i], after);
    final angle = (outgoing - incoming + 540) % 360 - 180;
    if (angle.abs() < 40) continue;
    final turn = angle.abs() >= 150
        ? NavigationTurn.reverse
        : angle > 0
        ? NavigationTurn.right
        : NavigationTurn.left;
    // Nearby vertices of the same bend produce one hint, not a list of turns.
    if (result.isNotEmpty &&
        lengths[i] - result.last.atMeters < 35 &&
        result.last.turn == turn) {
      if (angle.abs() <= previousAngle) continue;
      result.removeLast();
    }
    result.add(NavigationManeuver(turn, lengths[i]));
    previousAngle = angle.abs();
  }
  result.add(NavigationManeuver(NavigationTurn.destination, lengths.last));
  return List.unmodifiable(result);
}

NavigationManeuver? nextNavigationManeuver(
  List<NavigationManeuver> maneuvers,
  double traveledMeters,
) => maneuvers.where((m) => m.atMeters >= traveledMeters - 5).firstOrNull;

bool isUsableNavigationFix({
  required double latitude,
  required double longitude,
  required double accuracyMeters,
  required DateTime observedAt,
  required DateTime now,
  DateTime? after,
}) {
  if (!latitude.isFinite || !longitude.isFinite) return false;
  if (latitude.abs() > 90 || longitude.abs() > 180) return false;
  if (!accuracyMeters.isFinite || accuracyMeters < 0 || accuracyMeters > 50) {
    return false;
  }
  final ageSeconds = now.difference(observedAt).inSeconds;
  if (ageSeconds < -5 || ageSeconds > 30) return false;
  if (after != null && !observedAt.isAfter(after)) return false;
  return true;
}

class NavigationProgress {
  final double distanceFromRouteMeters;
  final double remainingMeters;
  final double traveledMeters;
  final LatLng matchedPosition;
  final List<LatLng> remainingGeometry;
  final bool arrived;
  const NavigationProgress({
    required this.distanceFromRouteMeters,
    required this.remainingMeters,
    required this.traveledMeters,
    required this.matchedPosition,
    required this.remainingGeometry,
    required this.arrived,
  });
}

// Project onto actual road segments, not only vertices; never replace the GPS fix.
NavigationProgress matchNavigationRoute(
  List<LatLng> route,
  LatLng position,
  LatLng destination, {
  double? previousTraveledMeters,
  double maxAdvanceMeters = double.infinity,
}) {
  if (route.isEmpty) throw ArgumentError('Route must contain a point');
  final distance = Distance();
  var best = double.infinity, bestTraveled = 0.0, total = 0.0, bestIndex = 0;
  var matched = route.first;
  var constrainedBest = double.infinity, constrainedTraveled = 0.0;
  var constrainedIndex = 0;
  var constrainedMatch = route.first;
  for (var i = 0; i < route.length - 1; i++) {
    final a = route[i], b = route[i + 1];
    final scale = math.cos(position.latitude * math.pi / 180);
    final dx = (b.longitude - a.longitude) * scale;
    final dy = b.latitude - a.latitude;
    final px = (position.longitude - a.longitude) * scale;
    final py = position.latitude - a.latitude;
    final denominator = dx * dx + dy * dy;
    final fraction = denominator == 0
        ? 0.0
        : ((px * dx + py * dy) / denominator).clamp(0.0, 1.0);
    final projected = LatLng(
      a.latitude + (b.latitude - a.latitude) * fraction,
      a.longitude + (b.longitude - a.longitude) * fraction,
    );
    final offset = distance(position, projected);
    final length = distance(a, b);
    final along = total + length * fraction;
    if (previousTraveledMeters != null &&
        along >= previousTraveledMeters - 30 &&
        along <= previousTraveledMeters + maxAdvanceMeters &&
        offset < constrainedBest) {
      constrainedBest = offset;
      constrainedTraveled = along;
      constrainedIndex = i;
      constrainedMatch = projected;
    }
    if (offset < best) {
      best = offset;
      matched = projected;
      bestIndex = i;
      bestTraveled = total + length * fraction;
    }
    total += length;
  }
  if (constrainedBest.isFinite) {
    best = constrainedBest;
    bestTraveled = constrainedTraveled;
    bestIndex = constrainedIndex;
    matched = constrainedMatch;
  }
  if (route.length == 1) best = distance(position, route.first);
  final remaining = math.max(0.0, total - bestTraveled);
  return NavigationProgress(
    distanceFromRouteMeters: best,
    remainingMeters: remaining,
    traveledMeters: bestTraveled,
    matchedPosition: matched,
    remainingGeometry: [matched, ...route.skip(bestIndex + 1)],
    arrived: distance(position, destination) <= 30 && remaining <= 45,
  );
}

class NavigationReroutePolicy {
  DateTime? _lastRequest;
  int _offRouteFixes = 0;
  void reset() {
    _lastRequest = null;
    _offRouteFixes = 0;
  }

  void requested(DateTime now) {
    _lastRequest = now;
    _offRouteFixes = 0;
  }

  bool shouldReroute({
    required DateTime now,
    required double offsetMeters,
    required double accuracyMeters,
    required double movedFromRouteOriginMeters,
  }) {
    if (!accuracyMeters.isFinite ||
        accuracyMeters < 0 ||
        accuracyMeters > 50 ||
        offsetMeters <= math.max(45, accuracyMeters * 2)) {
      _offRouteFixes = 0;
      return false;
    }
    _offRouteFixes++;
    if (_offRouteFixes < 2 ||
        movedFromRouteOriginMeters < 30 ||
        _lastRequest != null &&
            now.difference(_lastRequest!) < const Duration(seconds: 15)) {
      return false;
    }
    requested(now);
    return true;
  }
}
