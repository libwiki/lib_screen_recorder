
import 'dart:async';

import 'package:flutter/services.dart';

class ScreenRecording {
  static const MethodChannel _channel =
      const MethodChannel('screen_recording');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  static Future<bool> startRecordScreen(
      String name, int height, int width) async {
    final bool start = await _channel.invokeMethod('startRecordScreen',
        {"name": name, "audio": false, "height": height, "width": width});
    return start;
  }

  static Future<bool> startRecordScreenAndAudio(
      String name, int height, int width) async {
    final bool start = await _channel.invokeMethod('startRecordScreen',
        {"name": name, "audio": true, "height": height, "width": width});
    return start;
  }

  static Future<String> get stopRecordScreen async {
    final String path = await _channel.invokeMethod('stopRecordScreen');
    return path;
  }
}
