import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:app_shipper/models/driver_navigation.dart';

void main() {
  test('GPS noise beside a parallel return road cannot skip ahead to the end of a loop', () {
    final loop = [
      const LatLng(10, 106),
      const LatLng(10.01, 106),
      const LatLng(10.01, 106.00005),
      const LatLng(10, 106.00005),
    ];
    final progress = matchNavigationRoute(
      loop,
      const LatLng(10.004, 106.00004),
      loop.last,
      previousTraveledMeters: 400,
      maxAdvanceMeters: 100,
    );
    expect(progress.traveledMeters, inInclusiveRange(440, 450));
    expect(progress.remainingMeters, greaterThan(1700));
    expect(progress.arrived, isFalse);
  });
  test('Geometry guidance identifies right, left and reverse without inventing street names', () {
    for (final item in [
      (const LatLng(10.001, 106.001), NavigationTurn.right),
      (const LatLng(10.001, 105.999), NavigationTurn.left),
      (const LatLng(10, 106), NavigationTurn.reverse),
    ]) {
      final hints = navigationManeuvers([
        const LatLng(10, 106),
        const LatLng(10.001, 106),
        item.$1,
      ]);
      expect(hints.first.turn, item.$2);
      expect(hints.first.atMeters, inInclusiveRange(110, 112));
      expect(hints.last.turn, NavigationTurn.destination);
    }
  });
  test('Straight roads and repeated vertices do not generate fake turns', () {
    final hints = navigationManeuvers([
      const LatLng(10, 106),
      const LatLng(10.001, 106),
      const LatLng(10.001, 106),
      const LatLng(10.002, 106),
    ]);
    expect(hints.map((h) => h.turn), [NavigationTurn.destination]);
    expect(navigationManeuvers([]), isEmpty);
    expect(navigationManeuvers([const LatLng(10, 106)]).single.atMeters, 0);
  });
  test('Passing a bend moves guidance to the next maneuver without reordering stops', () {
    final hints = navigationManeuvers([
      const LatLng(10, 106),
      const LatLng(10.001, 106),
      const LatLng(10.001, 106.001),
    ]);
    expect(nextNavigationManeuver(hints, 60)!.turn, NavigationTurn.right);
    expect(
      nextNavigationManeuver(hints, 125)!.turn,
      NavigationTurn.destination,
    );
  });
  test('Fresh GPS validation rejects old, future, invalid, inaccurate and out-of-order fixes', () {
    final now = DateTime.utc(2035, 1, 1);
    bool valid({
      int age = 0,
      double accuracy = 5,
      double lat = 10,
      double lng = 106,
      DateTime? after,
    }) => isUsableNavigationFix(
      latitude: lat,
      longitude: lng,
      accuracyMeters: accuracy,
      observedAt: now.subtract(Duration(seconds: age)),
      now: now,
      after: after,
    );
    expect(valid(), isTrue);
    expect(valid(age: 30, accuracy: 50), isTrue);
    expect(valid(age: 31), isFalse);
    expect(valid(age: -6), isFalse);
    expect(valid(accuracy: -1), isFalse);
    expect(valid(accuracy: double.nan), isFalse);
    expect(valid(accuracy: 51), isFalse);
    expect(valid(lat: double.infinity), isFalse);
    expect(valid(lng: 181), isFalse);
    expect(valid(after: now), isFalse);
    expect(valid(age: 1, after: now), isFalse);
  });
  final route = [
    const LatLng(10, 106),
    const LatLng(10.01, 106),
    const LatLng(10.01, 106.01),
  ];
  test(
    'progress projects onto a road segment and reduces remaining distance',
    () {
      final initial = matchNavigationRoute(route, route.first, route.last);
      final halfway = matchNavigationRoute(
        route,
        const LatLng(10.005, 106),
        route.last,
      );
      expect(halfway.distanceFromRouteMeters, lessThan(2));
      expect(halfway.traveledMeters, inInclusiveRange(550, 560));
      expect(halfway.remainingMeters, lessThan(initial.remainingMeters));
      expect(
        halfway.remainingGeometry.first.latitude,
        closeTo(10.005, 0.00001),
      );
      expect(halfway.arrived, isFalse);
    },
  );
  test('arrival requires the actual destination, not just the snapped final road node', () {
    expect(matchNavigationRoute(route, route.last, route.last).arrived, isTrue);
    final collapsed = matchNavigationRoute(
      [route.first],
      const LatLng(10.001, 106),
      route.first,
    );
    expect(collapsed.remainingMeters, 0);
    expect(collapsed.arrived, isFalse);
    expect(collapsed.distanceFromRouteMeters, greaterThan(100));
  });
  test(
    'off-route fixes are measured against the path rather than the destination',
    () {
      final fix = matchNavigationRoute(
        route,
        const LatLng(10.005, 106.001),
        route.last,
      );
      expect(fix.distanceFromRouteMeters, greaterThan(100));
      expect(fix.arrived, isFalse);
    },
  );
  test(
    'rerouting needs two reliable fixes and respects the request cooldown',
    () {
      final policy = NavigationReroutePolicy();
      final now = DateTime(2030, 1, 1);
      policy.requested(now);
      bool fix(
        int seconds, {
        double offset = 100,
        double accuracy = 5,
        double moved = 60,
      }) => policy.shouldReroute(
        now: now.add(Duration(seconds: seconds)),
        offsetMeters: offset,
        accuracyMeters: accuracy,
        movedFromRouteOriginMeters: moved,
      );
      expect(fix(1), isFalse);
      expect(fix(2), isFalse);
      expect(fix(16), isTrue);
      expect(fix(17), isFalse);
      expect(fix(18), isFalse);
      expect(fix(32), isTrue);
      expect(fix(50, accuracy: 200), isFalse);
      expect(fix(51), isFalse);
      expect(fix(52, offset: 10), isFalse);
      expect(fix(53), isFalse);
      expect(fix(54), isTrue);
    },
  );
  test(
    'a stationary GPS fix outside the road snap does not cause reroute loops',
    () {
      final policy = NavigationReroutePolicy();
      final now = DateTime(2030, 1, 1);
      for (var i = 0; i < 20; i++) {
        expect(
          policy.shouldReroute(
            now: now.add(Duration(seconds: i * 20)),
            offsetMeters: 150,
            accuracyMeters: 5,
            movedFromRouteOriginMeters: 0,
          ),
          isFalse,
        );
      }
    },
  );
}
