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

  // 不设置path参数，默认就是保存到相册中
  Future<bool> startRecordScreen(
      {String? path, int frameRate = 30, int bitRate = 10000000}) async {
    final bool start = await _channel.invokeMethod('startRecordScreen',
        {"path": path, "frameRate": frameRate, "bitRate": bitRate});
    return start;
  }

  Future<bool> startRecordScreenAndAudio(
      String name, int height, int width) async {
    final bool start = await _channel.invokeMethod('startRecordScreen',
        {"name": name, "audio": true, "height": height, "width": width});
    return start;
  }

  Future<String> get videoPath async {
    final String path = await _channel.invokeMethod('stopRecordScreen');
    return path;
  }

  // 发起查询视频文件md5的请求
  // 参数: 文件的地址
  Future<String> queryMd5(String path) async {
    final String md5 = await _channel.invokeMethod('queryMd5', {"path": path});
    return md5;
  }

  Future<Map<dynamic, dynamic>> stopRecordScreen() async {
    final Map<dynamic, dynamic> results =
        await _channel.invokeMethod('stopRecordScreen');
    return results;
  }

  Future<bool> isCaptured() async {
    final bool start = await _channel.invokeMethod('isCaptured');
    return start;
  }
}
