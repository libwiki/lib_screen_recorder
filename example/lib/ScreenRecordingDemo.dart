import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_recording/screen_recording.dart';

class ScreenRecordingDemo extends StatefulWidget {
  const ScreenRecordingDemo({super.key});

  @override
  State<ScreenRecordingDemo> createState() => _ScreenRecordingDemoState();
}

class _ScreenRecordingDemoState extends State<ScreenRecordingDemo> {
  static const EventChannel _eventChannel =
      EventChannel('screen_recording_stream');
  StreamSubscription? _subscription;
  List<Uint8List> _videoChunks = [];
  String _outputFilePath = "";
  final _screenRecordingPlugin = ScreenRecording();
  final TextEditingController _pathController = TextEditingController();

  // 帧率
  final TextEditingController _frameController =
      TextEditingController(text: "30");

  // 码率
  final TextEditingController _bitController =
      TextEditingController(text: "10000000");
  static const platform = MethodChannel('screen_recording');
  String _videoPath = '未录制视频';
  String _md5Hash = '未生成MD5';
  String _md5Hash2 = '...';

  // 帧率默认值
  String _frameRate = "30";

  // 码率默认值
  String _bitRate = "10000000";

  @override
  void initState() {
    super.initState();
    _initOutputFilePath();
    _subscription =
        _eventChannel.receiveBroadcastStream().listen((dynamic event) {
      setState(() {
        _videoChunks.add(base64Decode(event as String));
        // Example: Print the length of received video chunks to console
        print('Received video chunk, length: ${_videoChunks.last.length}');
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _initOutputFilePath() async {
    Directory appDocDir = await getApplicationDocumentsDirectory();
    setState(() {
      _outputFilePath = '${appDocDir.path}/recorded_video.mp4';
    });
  }

  _checkMd5() async {
    try {
      final file = File(_videoPath);
      print(_videoPath);
      if (!file.existsSync()) {
        showToast("文件不存在");
        return;
      }
      final res = await _screenRecordingPlugin.queryMd5(_videoPath);
      setState(() {
        _md5Hash2 = res;
      });
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text('传入的路径:'),
                Text(
                  _outputFilePath,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('视频文件路径:'),
                Text(
                  _videoPath,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('原始 MD5:'),
                Text(
                  _md5Hash,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('校验 MD5:'),
                Text(
                  _md5Hash2,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                ElevatedButton(
                  onPressed: _checkMd5,
                  child: const Text('校验md5'),
                ),
                TextField(
                  controller: _pathController,
                  decoration: const InputDecoration(
                    labelText: 'Custom Save Path (optional)',
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    _startRecording();
                  },
                  child: const Text("开始录屏"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    _stopRecording();
                  },
                  child: const Text("停止录屏"),
                ),
                // ElevatedButton(
                //   onPressed: _saveVideoToFile,
                //   child: const Text('Save Video'),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startRecording() async {
    try {
      await _screenRecordingPlugin.startRecordScreen(
          path: _outputFilePath, // ../../demo.mp4
          frameRate: int.parse(_frameRate),
          bitRate: int.parse(_bitRate));
    } on PlatformException catch (e) {
      print('${e.message}');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final result = await _screenRecordingPlugin.stopRecordScreen();
      setState(() {
        _videoPath = result['path'];
        _md5Hash = result['md5'];
      });
    } on PlatformException catch (e) {
      print("Failed to stop recording: '${e.message}'.");
    }
  }
}
