import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'screen_recording_method_channel.dart';

abstract class ScreenRecordingPlatform extends PlatformInterface {
  /// Constructs a ScreenRecordingPlatform.
  ScreenRecordingPlatform() : super(token: _token);

  static final Object _token = Object();

  static ScreenRecordingPlatform _instance = MethodChannelScreenRecording();

  /// The default instance of [ScreenRecordingPlatform] to use.
  ///
  /// Defaults to [MethodChannelScreenRecording].
  static ScreenRecordingPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ScreenRecordingPlatform] when
  /// they register themselves.
  static set instance(ScreenRecordingPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
