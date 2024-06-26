import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:screen_recording/screen_recording.dart';
import 'package:path_provider/path_provider.dart';

import 'ScreenRecordingDemo.dart';

void main() {
  runApp(const ScreenRecordingDemo());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const EventChannel _eventChannel = EventChannel('screen_recording_stream');
  StreamSubscription? _subscription;
  List<Uint8List> _videoChunks = [];
  late String _outputFilePath;
  final _screenRecordingPlugin = ScreenRecording();
  final TextEditingController _pathController = TextEditingController();

  // 帧率
  final TextEditingController _frameController = TextEditingController(text: "30");

  // 码率
  final TextEditingController _bitController = TextEditingController(text: "10000000");
  static const platform = MethodChannel('screen_recording');
  String _videoPath = '未录制视频';
  String _md5Hash = '未生成MD5';

  // 帧率默认值
  String _frameRate = "30";

  // 码率默认值
  String _bitRate = "10000000";

  @override
  void initState() {
    super.initState();
    _initOutputFilePath();
    _subscription = _eventChannel.receiveBroadcastStream().listen((dynamic event) {
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
    _outputFilePath = '${appDocDir.path}/recorded_video.mp4';
  }

  Future<void> _saveVideoToFile() async {
    File outputFile = File(_outputFilePath);
    if (!outputFile.existsSync()) {
      outputFile.createSync(recursive: true);
    }
    IOSink sink = outputFile.openWrite();
    for (Uint8List chunk in _videoChunks) {
      sink.add(chunk);
    }
    await sink.close();
    if (kDebugMode) {
      print('Video saved to: $_outputFilePath');
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('视频文件路径:'),
              Text(
                _videoPath,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 20),
              Text('视频文件 MD5:'),
              Text(
                _md5Hash,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              TextField(
                controller: _frameController,
                onChanged: (value) {
                  // 更新帧率的值
                  setState(() {
                    _frameRate = value;
                  });
                },
                decoration: InputDecoration(
                  labelText: '帧率',
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: _bitController,
                onChanged: (value) {
                  // 更新码率的值
                  setState(() {
                    _bitRate = value;
                  });
                },
                decoration: InputDecoration(
                  labelText: '码率',
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: _pathController,
                decoration: InputDecoration(labelText: 'Custom Save Path (optional)'),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _chooseSavePath,
                child: Text('Choose Save Path'),
              ),
              GestureDetector(
                  onTap: () async {
                    _startRecording();
                  },
                  child: const Text("开始录屏")),
              const SizedBox(height: 20),
              GestureDetector(
                  onTap: () async {
                    _stopRecording();
                  },
                  child: const Text("停止录屏")),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("是否开启边录边传"),
                  CupertinoSwitch(value: true, onChanged: (value) {}),
                ],
              ),
              const SizedBox(height: 20),
              Text('Received ${_videoChunks.length} video chunks'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveVideoToFile,
                child: const Text('Save Video'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startRecording() async {
    try {
      await _screenRecordingPlugin.startRecordScreen(
          path: _pathController.text, frameRate: int.parse(_frameRate), bitRate: int.parse(_bitRate));
    } on PlatformException catch (e) {
      print('${e.message}');
    }
  }

  Future<void> _chooseSavePath() async {
    try {
      final String result = await platform.invokeMethod('chooseSavePath');
      _pathController.text = result;
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
