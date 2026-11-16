import 'package:flutter/services.dart';

class CameraPermissionService {
  static const MethodChannel _channel =
      MethodChannel('com.taha.yoloncnn/permission');

  static Future<bool> checkPermission() async {
    try {
      final bool? res =
          await _channel.invokeMethod<bool>('checkCameraPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    try {
      final bool? res =
          await _channel.invokeMethod<bool>('requestCameraPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod('openAppSettings');
    } catch (_) {}
  }
}
