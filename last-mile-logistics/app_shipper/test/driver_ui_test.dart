import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/models/driver_workflow.dart';
import 'package:app_shipper/models/driver_availability.dart';
import 'package:app_shipper/screens/a1_welcome_screen.dart';
import 'package:app_shipper/theme/app_theme.dart';
import 'package:app_shipper/widgets/driver_dashboard.dart';
import 'package:app_shipper/widgets/driver_task_card.dart';

ShipperTaskDto fixture({
double cod = 150000,
String assignment = 'ACCEPTED',
String order = 'ASSIGNED',
String customerName = 'Người nhận có họ tên dài để kiểm tra xuống dòng',
}) => ShipperTaskDto(
assignmentId: 1,
orderId: 1,
orderCode: 'TVD-TEST-00001',
branchName: 'Bưu cục Bình Tân 01',
assignmentStatus: assignment,
orderStatus: order,
customerName: customerName,
customerPhone: '0900000000',
deliveryAddress:
'118 Đường số 5, phường An Lạc, quận Bình Tân, Thành phố Hồ Chí Minh',
codAmount: cod,
shippingFee: 0,
note: 'Gọi người nhận trước khi tới. Kiểm tra kiện hàng khi bàn giao.',
expectedDeliveryAt: DateTime.utc(2035, 1, 1, 10),
);

Widget dashboard({
DriverOverview overview = const DriverOverview(),
List<String> unavailable = const [],
bool statusKnown = true,
ValueChanged<int>? onTasks,
VoidCallback? onHandovers,
VoidCallback? onCod,
}) => DriverDashboard(
driverName: 'Minh An',
employeeCode: 'GH-TEST-01',
workStatus: statusKnown
? DriverAvailability.fromJson({
'shipperId': 1,
'availability': 'AVAILABLE',
'hasActiveWork': false,
'hasDeliveryWork': false,
'canSetAvailable': true,
'canSetOffline': true,
'availableBlockedReason': null,
'stopBlockedReason': null,
})
: null,
changingStatus: false,
loading: false,
overview: overview,
unavailableSections: unavailable,
onRefresh: () async {},
onStatusChanged: (_) {},
onTasks: onTasks ?? (_) {},
onHandovers: onHandovers ?? () {},
onReturns: () {},
onCod: onCod ?? () {},
);

Future<void> mount(
WidgetTester tester,
Widget child, {
double width = 390,
double height = 900,
double textScale = 1,
}) async {
tester.view.physicalSize = Size(width, height);
tester.view.devicePixelRatio = 1;
addTearDown(tester.view.resetPhysicalSize);
addTearDown(tester.view.resetDevicePixelRatio);
final base = AppTheme.lightTheme;
await tester.pumpWidget(
MaterialApp(
theme: base.copyWith(
textTheme: base.textTheme.apply(fontFamily: 'Preview'),
textButtonTheme: TextButtonThemeData(
style: base.textButtonTheme.style?.copyWith(
textStyle: const WidgetStatePropertyAll(
TextStyle(
fontFamily: 'Preview',
fontSize: 14,
fontWeight: FontWeight.w600,
),
),
),
),
),
builder: (context, child) => MediaQuery(
data: MediaQuery.of(context)
.copyWith(textScaler: TextScaler.linear(textScale)),
child: child!,
),
home: Scaffold(body: child),
),
);
await tester.pumpAndSettle();
}

void main() {
TestWidgetsFlutterBinding.ensureInitialized();
setUpAll(() async {
final fontFile = File('C:/Windows/Fonts/segoeui.ttf');
if (fontFile.existsSync()) {
final font = FontLoader('Preview')
..addFont(
Future.value(ByteData.sublistView(await fontFile.readAsBytes())),
);
await font.load();
}
final iconsFile = File(
'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
);
if (iconsFile.existsSync()) {
final icons = FontLoader('MaterialIcons')
..addFont(
Future.value(ByteData.sublistView(await iconsFile.readAsBytes())),
);
await icons.load();
}
});

for (final width in [320.0, 390.0]) {
testWidgets(
'Task card fits $width px and large text without mislabelling zero COD',
(tester) async {
var calls = 0, directions = 0;
await mount(
tester,
SingleChildScrollView(
child: DriverTaskCard(
task: fixture(cod: 0),
actions: const Text(
'Chờ kho xuất hàng, sau đó xác nhận nhận kiện.',
),
onCall: () => calls++,
onDirections: () => directions++,
),
),
width: width,
height: 1400,
textScale: 1.5,
);
final err = tester.takeException();
      expect(err, isNull);
expect(find.text('Không thu COD'), findsOneWidget);
expect(find.text('Đã thanh toán trước'), findsNothing);
expect(find.text('Chờ tài xế nhận kiện'), findsOneWidget);
await tester.tap(find.byTooltip('Gọi người nhận'));
await tester.tap(find.text('Chỉ đường'));
expect(calls, 1);
expect(directions, 1);
},
);
testWidgets('Dashboard fits $width px and preserves unknown data', (
tester,
) async {
await mount(
tester,
dashboard(statusKnown: false, unavailable: ['nhiệm vụ', 'COD']),
width: width,
height: 1600,
textScale: 1.5,
);
      expect(tester.takeException(), isNull);
expect(find.text('Chưa xác nhận trạng thái'), findsOneWidget);
expect(find.text('Đang cập nhật công việc'), findsOneWidget);
expect(find.byType(ChoiceChip), findsNothing);
expect(find.text('Tải lại trạng thái'), findsOneWidget);
expect(
find.textContaining('Chưa tải được nhiệm vụ, COD.'),
findsOneWidget,
);
expect(find.text('0'), findsNothing);
});
}

testWidgets(
'A pending handover takes priority and task metric opens its own stage',
(tester) async {
var handovers = 0;
int? filter;
final overview = DriverOverview(
tasks: [fixture(assignment: 'PENDING')],
handovers: [
ShipperHandoverDto(
handoverId: 1,
handoverCode: 'BG-TEST',
warehouseName: 'Kho kiểm tra',
branchName: 'Bưu cục kiểm tra',
handedOverAt: null,
orderCount: 1,
items: const [],
),
],
cod: const [],
);
await mount(
tester,
dashboard(
overview: overview,
onHandovers: () => handovers++,
onTasks: (value) => filter = value,
),
);
      expect(find.text('Kho đã sẵn sàng bàn giao'), findsOneWidget);
      await tester.ensureVisible(find.text('Nhận hàng từ kho'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhận hàng từ kho'));
      await tester.pumpAndSettle();
      expect(handovers, 1);
      await tester.ensureVisible(find.text('Chờ nhận'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chờ nhận'));
      await tester.pumpAndSettle();
      expect(filter, 0);
},
);

testWidgets('Welcome screen stays usable with large text on a small phone', (
tester,
) async {
await mount(
tester,
const A1WelcomeScreen(),
width: 320,
height: 720,
textScale: 1.5,
);
final err = tester.takeException();
      expect(err, isNull);
expect(find.text('Đăng nhập tài xế'), findsOneWidget);
expect(find.textContaining('180'), findsNothing);
});

}
