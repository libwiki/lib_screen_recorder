import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:screen_recording/screen_recording.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
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
  double screenWidth = 0;
  double screenHeight = 0;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        screenWidth = 375;
        screenHeight = 812;
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
              GestureDetector(
                  onTap: () async {
                    await _screenRecordingPlugin.startRecordScreen("test", screenHeight.toInt(), screenWidth.toInt());
                  },
                  child: const Text("开始录屏")),
              const SizedBox(height: 20),
              GestureDetector(
                  onTap: () async {
                    await _screenRecordingPlugin.stopRecordScreen();
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
}
