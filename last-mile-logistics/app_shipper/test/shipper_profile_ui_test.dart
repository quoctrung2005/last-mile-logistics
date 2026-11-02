import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_shipper/models/shipper_profile.dart';
import 'package:app_shipper/screens/shipper_profile_screen.dart';
import 'package:app_shipper/screens/password_screens.dart';

import 'shipper_profile_test.dart' show profileData;

Future<void> mount(
  WidgetTester tester,
  Future<ShipperProfile> Function() load, {
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: ShipperProfileScreen(loadProfile: load),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 200, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Profile shows live identity and protects CCCD until explicitly revealed',
    (tester) async {
      await mount(tester, () async => ShipperProfile.fromJson(profileData()));
      expect(find.text('Tài xế kiểm thử'), findsOneWidget);
      expect(find.text('Mã nhân viên: QA-25'), findsOneWidget);
      expect(find.text('Sẵn sàng nhận nhiệm vụ'), findsOneWidget);
      await scrollTo(tester, find.byTooltip('Hiện số CCCD'));
      expect(find.text('000000123456'), findsNothing);
      await tester.tap(find.byTooltip('Hiện số CCCD'));
      await tester.pump();
      expect(find.text('000000123456'), findsOneWidget);
      await tester.tap(find.byTooltip('Ẩn số CCCD'));
      await tester.pump();
      expect(find.text('000000123456'), findsNothing);
    },
  );

  testWidgets(
    'Missing vehicle and fields display empty-state guidance instead of demo values',
    (tester) async {
      final data = profileData()
        ..['phone'] = null
        ..['email'] = null
        ..['currentVehicle'] = null
        ..['areas'] = [];
      await mount(tester, () async => ShipperProfile.fromJson(data));
      expect(find.text('Chưa cập nhật'), findsWidgets);
      await scrollTo(tester, find.text('Chưa được phân công phương tiện.'));
      expect(find.text('Chưa được phân công phương tiện.'), findsOneWidget);
      await scrollTo(tester, find.text('Chưa có khu vực được phân công.'));
      expect(find.text('Chưa có khu vực được phân công.'), findsOneWidget);
      expect(find.text('QA-00001'), findsNothing);
    },
  );

  testWidgets(
    'Expired license and maintenance vehicle warnings remain visible',
    (tester) async {
      final data = profileData()
        ..['licenseStatus'] = 'EXPIRED'
        ..['licenseDaysRemaining'] = -1
        ..['licenseExpiresAt'] = '2026-10-29';
      (data['currentVehicle'] as Map<String, dynamic>)['status'] =
          'MAINTENANCE';
      await mount(tester, () async => ShipperProfile.fromJson(data));
      await scrollTo(tester, find.text('Đã hết hạn'));
      expect(
        find.text('Liên hệ quản trị viên để cập nhật giấy phép.'),
        findsOneWidget,
      );
      await scrollTo(tester, find.text('Đang bảo dưỡng'));
      expect(find.text('Đang bảo dưỡng'), findsOneWidget);
      expect(find.text('QA-00001'), findsOneWidget);
    },
  );

  testWidgets(
    'A failed first load offers retry and reloads updated admin data',
    (tester) async {
      var calls = 0;
      await mount(tester, () async {
        if (++calls == 1) throw Exception('Không kết nối được máy chủ.');
        return ShipperProfile.fromJson(
          profileData()..['fullName'] = 'Tên đã được cập nhật',
        );
      });
      expect(find.text('Chưa tải được hồ sơ mới nhất'), findsOneWidget);
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Tên đã được cập nhật'), findsOneWidget);
      expect(find.text('Chưa tải được hồ sơ mới nhất'), findsNothing);
    },
  );

  testWidgets(
    'Failed refresh labels the previous data and does not claim a successful update',
    (tester) async {
      var calls = 0;
      await mount(tester, () async {
        if (++calls > 1) throw Exception('Mất kết nối.');
        return ShipperProfile.fromJson(profileData());
      });
      await tester.tap(find.byTooltip('Làm mới hồ sơ'));
      await tester.pumpAndSettle();
      expect(find.text('Thông tin bên dưới là lần tải trước.'), findsOneWidget);
      expect(find.text('Tài xế kiểm thử'), findsOneWidget);
    },
  );

  testWidgets(
    'Long names and large text fit, and change-password opens from profile',
    (tester) async {
      final data = profileData()
        ..['fullName'] =
            'Tài xế có họ tên dài để kiểm tra hiển thị trên điện thoại';
      await mount(
        tester,
        () async => ShipperProfile.fromJson(data),
        scale: 1.7,
      );
      expect(tester.takeException(), isNull);
      await scrollTo(tester, find.text('Đổi mật khẩu'));
      await tester.tap(find.text('Đổi mật khẩu'));
      await tester.pumpAndSettle();
      expect(find.byType(ChangePasswordScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
