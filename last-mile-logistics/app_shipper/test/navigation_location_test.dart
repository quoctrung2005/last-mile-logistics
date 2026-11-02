import 'dart:async';

import 'package:app_shipper/services/device_service.dart';
import 'package:app_shipper/services/navigation_location.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Position gpsFix({
  int ageSeconds = 0,
  double accuracy = 5,
  double latitude = 10.7769,
}) => Position(
  latitude: latitude,
  longitude: 106.7009,
  timestamp: DateTime.now().subtract(Duration(seconds: ageSeconds)),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class FakeGpsPlatform extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  Position? cached;
  int permissionRequests = 0,
      currentCalls = 0,
      locationSettingsCalls = 0,
      appSettingsCalls = 0;
  Completer<LocationPermission>? permissionReply;
  Future<Position> Function(LocationSettings?)? read;
  final settings = <LocationSettings?>[];
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return permission =
        await (permissionReply?.future ?? Future.value(requestedPermission));
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => cached;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    currentCalls++;
    settings.add(locationSettings);
    return read?.call(locationSettings) ?? Future.value(gpsFix());
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsCalls++;
    return true;
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsCalls++;
    return true;
  }
}

Matcher locationProblem(NavigationLocationProblem problem) => throwsA(
  isA<NavigationLocationException>().having(
    (e) => e.problem,
    'problem',
    problem,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GeolocatorPlatform original;
  late FakeGpsPlatform fake;
  setUp(() {
    original = GeolocatorPlatform.instance;
    fake = FakeGpsPlatform();
    GeolocatorPlatform.instance = fake;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    GeolocatorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });
  test('GPS service disabled is distinct from missing app permission and never reads coordinates', () async {
    fake.enabled = false;
    await expectLater(
      NavigationLocationService.getPosition(),
      locationProblem(NavigationLocationProblem.disabled),
    );
    expect(fake.currentCalls, 0);
    expect(fake.permissionRequests, 0);
  });
  test('Denied and permanently denied permission retain distinct recoverable messages', () async {
    fake.permission = LocationPermission.denied;
    fake.requestedPermission = LocationPermission.denied;
    await expectLater(
      NavigationLocationService.getPosition(),
      locationProblem(NavigationLocationProblem.denied),
    );
    expect(fake.permissionRequests, 1);
    fake.permission = LocationPermission.deniedForever;
    await expectLater(
      NavigationLocationService.getPosition(),
      locationProblem(NavigationLocationProblem.deniedForever),
    );
    expect(fake.permissionRequests, 1);
    expect(fake.currentCalls, 0);
  });
  test(
    'Home and concurrent map requests share one OS permission dialog',
    () async {
      fake.permission = LocationPermission.denied;
      fake.permissionReply = Completer<LocationPermission>();
      fake.cached = gpsFix();
      final first = NavigationLocationService.getPosition(),
          second = NavigationLocationService.getPosition();
      final home = DeviceService.getCurrentPosition();
      await Future<void>.delayed(Duration.zero);
      expect(identical(first, second), isTrue);
      expect(fake.permissionRequests, 1);
      fake.permissionReply!.complete(LocationPermission.whileInUse);
      final positions = await Future.wait([first, second, home]);
      expect(positions.every((p) => identical(p, fake.cached)), isTrue);
      expect(fake.currentCalls, 0);
    },
  );
  test(
    'Stale or approximate cached GPS is replaced by a fresh high accuracy fix',
    () async {
      fake.cached = gpsFix(ageSeconds: 240, accuracy: 150);
      final fix = await NavigationLocationService.getPosition();
      expect(fix.accuracy, 5);
      expect(fake.currentCalls, 1);
      expect(fake.settings.single!.accuracy, LocationAccuracy.high);
    },
  );
  test(
    'Android provider timeout retries once through LocationManager',
    () async {
      fake.read = (_) async {
        if (fake.currentCalls == 1) throw TimeoutException('no fused fix');
        return gpsFix();
      };
      await NavigationLocationService.getPosition();
      expect(fake.currentCalls, 2);
      expect(
        (fake.settings.first as AndroidSettings).forceLocationManager,
        isFalse,
      );
      expect(
        (fake.settings.last as AndroidSettings).forceLocationManager,
        isTrue,
      );
    },
  );
  test('A failed GPS read can be retried after service recovery, with no poisoned pending request', () async {
    fake.read = (_) async => throw TimeoutException('no fix');
    await expectLater(
      NavigationLocationService.getPosition(),
      locationProblem(NavigationLocationProblem.unavailable),
    );
    fake.read = (_) async => gpsFix();
    await expectLater(NavigationLocationService.getPosition(), completes);
    expect(fake.currentCalls, 3);
  });
  test('Old, future and inaccurate fixes never become an accepted navigation origin', () async {
    for (final fix in [
      gpsFix(ageSeconds: 90),
      gpsFix(ageSeconds: -60),
      gpsFix(accuracy: 150),
      gpsFix(latitude: double.nan),
    ]) {
      fake.cached = fix;
      fake.read = (_) async => fix;
      await expectLater(
        NavigationLocationService.getPosition(),
        locationProblem(NavigationLocationProblem.inaccurate),
      );
    }
  });
  test('Service switched off mid-request reports the setting problem and avoids another provider read', () async {
    fake.read = (_) async {
      fake.enabled = false;
      throw TimeoutException('disabled');
    };
    await expectLater(
      NavigationLocationService.getPosition(),
      locationProblem(NavigationLocationProblem.disabled),
    );
    expect(fake.currentCalls, 1);
  });
}
