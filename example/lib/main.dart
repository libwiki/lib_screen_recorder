import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:screen_recording/screen_recording.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const EventChannel _eventChannel = EventChannel('screen_recording_stream');
  StreamSubscription  _subscription;
  List<Uint8List> _videoChunks = [];
  String _outputFilePath = "";
  bool isRecord = false;
  double screenWidth;
  double screenHeight;

  @override
  void initState() {
    super.initState();
    _initOutputFilePath();
    _subscription = _eventChannel.receiveBroadcastStream().listen((dynamic event) {
      setState(() {
        _videoChunks.add(base64Decode(event as String));
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('录屏测试'),
        ),
        body: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          GestureDetector(
              onTap: () async {
                if (!isRecord) {
                  var x = await ScreenRecording.startRecordScreen("test", screenHeight.toInt(), screenWidth.toInt());
                } else {
                  var x = await ScreenRecording.stopRecordScreen;
                }
                setState(() {
                  isRecord = !isRecord;
                });
              },
              child: Text(isRecord ? "录屏中" : "开始录屏")),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("是否开启边录边传"),
              CupertinoSwitch(value: true, onChanged: (value) {}),
            ],
          ),
          Text('Received ${_videoChunks.length} video chunks'),
        ]),
      ),
    );
  }
}
