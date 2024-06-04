import 'package:flutter/services.dart';

import 'screen_recording_platform_interface.dart';

class ScreenRecording {
  static const MethodChannel _channel = MethodChannel('screen_recording');

  static Future<String> getPlatformVersion() async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  Future<bool> startRecordScreen(String name, int height, int width) async {
    final bool start = await _channel
        .invokeMethod('startRecordScreen', {"name": name, "audio": false, "height": height, "width": width});
    return start;
  }

  Future<bool> startRecordScreenAndAudio(String name, int height, int width) async {
    final bool start = await _channel
        .invokeMethod('startRecordScreen', {"name": name, "audio": true, "height": height, "width": width});
    return start;
  }

  Future<String> get videoPath async {
    final String path = await _channel.invokeMethod('stopRecordScreen');
    return path;
  }

  Future<Map<String, dynamic>> stopRecordScreen() async {
    final Map<String, dynamic> results = await _channel.invokeMethod('stopRecordScreen');
    return results;
  }
}
