import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/auth_and_task_models.dart';
import 'navigation_location.dart';

class DeviceService {
  static final ImagePicker _picker = ImagePicker();

  /// Rung phản hồi khi nhận đơn mới hoặc có sự kiện quan trọng
  static Future<void> vibrateAlert() async {
    try {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  static Future<Position> getCurrentPosition() async {
    await NavigationLocationService.ensureAccess();

    // Uu tien vi tri gan nhat neu con moi de tranh dung may/cho GPS lau tren may ao
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null &&
          DateTime.now().difference(lastKnown.timestamp) <
              const Duration(minutes: 5) &&
          lastKnown.accuracy <= 150) {
        return lastKnown;
      }
    } catch (_) {}

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 5),
          forceLocationManager: true,
        ),
      );
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return last;
      } catch (_) {}
      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 6),
        ),
      );
    }
  }

  // Foreground-only navigation; the caller stops this stream on pause/dispose.
  static Stream<Position> watchNavigationPosition() =>
      Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          forceLocationManager: true,
        ),
      );

  static Future<void> openDirections({
    required List<ShipperTaskDto> stops,
    Position? origin,
  }) async {
    if (stops.isEmpty) {
      throw Exception('Không có đơn hàng để mở chỉ đường.');
    }
    final limitedStops = stops.take(10).toList();

    String destination(ShipperTaskDto task) {
      if (task.latitude != null && task.longitude != null) {
        return '${task.latitude},${task.longitude}';
      }
      if (task.deliveryAddress.trim().isEmpty) {
        throw Exception('Đơn ${task.orderCode} chưa có địa chỉ giao hàng.');
      }
      return task.deliveryAddress;
    }

    final parameters = <String, String>{
      'api': '1',
      'destination': destination(limitedStops.last),
      'travelmode': 'driving',
    };
    if (origin != null) {
      parameters['origin'] = '${origin.latitude},${origin.longitude}';
    }
    if (limitedStops.length > 1) {
      parameters['waypoints'] = limitedStops
          .take(limitedStops.length - 1)
          .map(destination)
          .join('|');
    }

    final uri = Uri.https('www.google.com', '/maps/dir/', parameters);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Không thể mở ứng dụng bản đồ trên thiết bị.');
    }
  }

  /// Thực hiện cuộc gọi điện thoại tới số của khách hàng
  /// Mở ứng dụng SMS gửi tin nhắn kèm nội dung mẫu
  static Future<bool> sendSms(String rawPhoneNumber, {String? body}) async {
    final cleanNumber = rawPhoneNumber.replaceAll(
      RegExp(r'[\\s\\.\\-\\(\\)]'),
      '',
    );
    if (cleanNumber.isEmpty) return false;

    final query = body != null && body.isNotEmpty
        ? '?body=${Uri.encodeComponent(body)}'
        : '';
    final uri = Uri.parse('sms:$cleanNumber$query');
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Không thể mở ứng dụng SMS: $e');
      return false;
    }
  }

  static Future<bool> makePhoneCall(String rawPhoneNumber) async {
    final cleanNumber = rawPhoneNumber.replaceAll(RegExp(r'[\s\.\-\(\)]'), '');
    if (cleanNumber.isEmpty) return false;

    final uri = Uri.parse('tel:$cleanNumber');
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Không thể thực hiện cuộc gọi: $e');
      return false;
    }
  }

  /// Chụp ảnh bằng Camera
  static Future<XFile?> takePhoto() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      return photo;
    } catch (e) {
      debugPrint('Lỗi khi mở camera: $e');
      return null;
    }
  }

  /// Chọn ảnh từ Thư viện ảnh (Gallery)
  static Future<XFile?> pickImageFromGallery() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      return photo;
    } catch (e) {
      debugPrint('Lỗi khi mở thư viện ảnh: $e');
      return null;
    }
  }
}
