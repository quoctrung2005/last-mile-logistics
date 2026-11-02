import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_shipper/main.dart';

void main() {
  testWidgets('The first frame is visible while local storage is pending', (
    tester,
  ) async {
    final pending = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(home: AuthGate(initialize: () => pending.future)),
    );
    await tester.pump();
    expect(find.text('Đang mở ứng dụng…'), findsOneWidget);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập tài xế'), findsOneWidget);
  });

  testWidgets(
    'A storage failure offers retry without repeating initialization on rebuild',
    (tester) async {
      var attempts = 0;
      Future<bool> initialize() async {
        if (++attempts == 1) throw StateError('Test local storage failure');
        return false;
      }

      await tester.pumpWidget(
        MaterialApp(home: AuthGate(initialize: initialize)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chưa thể mở ứng dụng'), findsOneWidget);
      expect(attempts, 1);
      await tester.pump();
      expect(attempts, 1);
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('Đăng nhập tài xế'), findsOneWidget);
    },
  );

  testWidgets(
    'Unresponsive startup times out instead of waiting indefinitely',
    (tester) async {
      final pending = Completer<bool>();
      await tester.pumpWidget(
        MaterialApp(home: AuthGate(initialize: () => pending.future)),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();
      expect(find.text('Chưa thể mở ứng dụng'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      // A late storage result cannot replace the timeout screen.
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('Chưa thể mở ứng dụng'), findsOneWidget);
    },
  );
}
