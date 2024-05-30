import 'package:flutter_test/flutter_test.dart';
import 'package:screen_recording/screen_recording.dart';
import 'package:screen_recording/screen_recording_platform_interface.dart';
import 'package:screen_recording/screen_recording_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockScreenRecordingPlatform
    with MockPlatformInterfaceMixin
    implements ScreenRecordingPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ScreenRecordingPlatform initialPlatform = ScreenRecordingPlatform.instance;

  test('$MethodChannelScreenRecording is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelScreenRecording>());
  });

  test('getPlatformVersion', () async {
    ScreenRecording screenRecordingPlugin = ScreenRecording();
    MockScreenRecordingPlatform fakePlatform = MockScreenRecordingPlatform();
    ScreenRecordingPlatform.instance = fakePlatform;

    expect(await screenRecordingPlugin.platformVersion, '42');
  });
}
