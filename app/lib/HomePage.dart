import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:human_activity_detector/AudioManager.dart';
import 'package:human_activity_detector/Logger.dart';
import 'package:human_activity_detector/SensorsManager.dart';
import 'package:human_activity_detector/SleepApiNotifier.dart';
import 'package:share_plus/share_plus.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static AppLifecycleState appState = AppLifecycleState.resumed;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  StreamSubscription<Activity>? _activityStreamSubscription;
  List<Activity> _events = [];

  final _controller = ScrollController();

  bool _systemStarted = false;

  void _handleError(dynamic error) {
    Logger.logError(text: 'Catch Error >> $error');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    HomePage.appState = state;
    super.didChangeAppLifecycleState(state);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
          appBar: AppBar(title: const Text('Human Activity Detector'), centerTitle: true),
          floatingActionButton: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FloatingActionButton(
                  child: const Icon(Icons.save_alt_rounded),
                  onPressed: () async {
                    await Logger.logInfo(text: "Exporting logs...");
                    var file = await Logger.exportLogs();
                    if (file == null) {
                      return;
                    }
                    var xFile = XFile(file.path);
                    await Share.shareXFiles([xFile]);
                    print("File exported: ${file.path}");
                  }),
              const SizedBox(width: 10),
              FloatingActionButton(
                  child: const Icon(Icons.audio_file_outlined),
                  onPressed: () async {
                    await Logger.logInfo(text: "Exporting audio mfcc file...");
                    var file = await AudioManager.getMfccFile();
                    if (file == null) {
                      return;
                    }
                    var xFile = XFile(file.path);
                    await Share.shareXFiles([xFile]);
                    print("File exported: ${file.path}");
                  }),
              const SizedBox(width: 10),
              FloatingActionButton(
                  child: Icon(_systemStarted ? Icons.stop_circle : Icons.not_started),
                  onPressed: () async {
                    if(_systemStarted) {
                      _stopSystem();
                    } else {
                      _startSystem();
                    }
                  }),
            ],
          ),
          body: _buildContentView()),
    );
  }

  @override
  void dispose() {
    //_activityStreamController.close();
    WidgetsBinding.instance.removeObserver(this);
    _activityStreamSubscription?.cancel();
    super.dispose();
  }

  Widget _buildContentView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 20.0),
          Text('Prediction', style: TextStyle(fontSize: 30.0, fontWeight: FontWeight.bold)),
          StreamBuilder<PredictionEntity>(
              stream: SensorsManager.predictionStream.stream,
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data == null) {
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No prediction available'),
                      ]);
                }
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Prediction: ${data.prediction}'),
                      SizedBox(height: 10.0),
                      Text('Updated at: ${data.timestamp}'),
                    ]);
              }),
          SizedBox(height: 10.0),
          Text('Sleep Detection', style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold)),
          SizedBox(height: 10.0),
          StreamBuilder<String>(
              stream: SleepApiNotifier.receiveStreamController.stream,
              builder: (context, snapshot) {
                final updatedDateTime = DateTime.now();
                //val messageWithSemiColon = "sleepSegment;$startTime;$endTime;$duration;$status"
                //val messageWithSemiColon = "sleepClassify;$timestamp;$confidence;$light;$motion"
                final message = snapshot.data ?? '';
                final contentParts = message.split(';');
                if (contentParts[0] != null) {
                  final eventType = contentParts[0];
                  if (eventType == "sleepInitSuccess") {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sleep API status: STARTED OK'),
                          SizedBox(height: 10.0),
                          Text('Updated at: $updatedDateTime'),
                        ]);
                  } else if (eventType == "sleepInitError") {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Last Sleep API status: NOT STARTED ERROR'),
                          SizedBox(height: 10.0),
                          Text('Updated at: $updatedDateTime'),
                        ]);
                  } else if (eventType == "StopInitSuccess") {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Last Sleep API status: STOPPED OK'),
                          SizedBox(height: 10.0),
                          Text('Updated at: $updatedDateTime'),
                        ]);
                  } else if (eventType == "StopInitError") {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Last Sleep API status: NOT STOPPED ERROR'),
                          SizedBox(height: 10.0),
                          Text('Updated at: $updatedDateTime'),
                        ]);
                  }
                  Logger.logInfo(text: 'Sleep API Event Detected >> $eventType');
                }
                return SizedBox();
              }),
          SizedBox(height: 10.0),
          StreamBuilder<String>(
              stream: SleepApiNotifier.receiveStreamController.stream,
              builder: (context, snapshot) {
                final updatedDateTime = DateTime.now();
                //val messageWithSemiColon = "sleepSegment;$startTime;$endTime;$duration;$status"
                //val messageWithSemiColon = "sleepClassify;$timestamp;$confidence;$light;$motion"
                final message = snapshot.data ?? '';
                final contentParts = message.split(';');
                if (contentParts[0] != null) {
                  Logger.logInfo(text: 'Sleep API Event Detected >> $contentParts');
                  final eventType = contentParts[0];
                  if (eventType == "sleepSegment") {
                    _sendSleepSegmentToBackend(contentParts);
                    final startTime = contentParts[1];
                    final endTime = contentParts[2];
                    final duration = contentParts[3];
                    final status = contentParts[4];
                    return Column(children: [
                      Text('Last Sleep API event detected (updated: $updatedDateTime)'),
                      SizedBox(height: 10.0),
                      Text('Sleep Segment status: $status'),
                      SizedBox(height: 5.0),
                      Text('Sleep Segment starttime: $startTime'),
                      SizedBox(height: 5.0),
                      Text('Sleep Segment endtime: $endTime'),
                      SizedBox(height: 5.0),
                      Text('Sleep Segment duration: $duration'),
                    ]);
                  } else if (eventType == "sleepClassify") {
                    _sendSleepClassifyToBackend(contentParts);
                    final timestamp = contentParts[1];
                    final confidence = contentParts[2];
                    final light = contentParts[3];
                    final motion = contentParts[4];
                    return Column(children: [
                      Text('Last Sleep API event detected (updated: $updatedDateTime)'),
                      SizedBox(height: 10.0),
                      Text('Sleep Classify confidence: $confidence'),
                      SizedBox(height: 5.0),
                      Text('Sleep Classify light: $light'),
                      SizedBox(height: 5.0),
                      Text('Sleep Classify motion: $motion'),
                      SizedBox(height: 5.0),
                    ]);
                  }
                }
                return SizedBox();
              }),
          SizedBox(height: 30.0),
          Text('Activity Detection', style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold)),
          SizedBox(height: 10.0),
          _events.isEmpty
              ? Text('No activity detected')
              :
          Flexible(
            child: ListView.builder(
                itemCount: _events.length,
                reverse: true,
                shrinkWrap: true,
                controller: _controller,
                physics: ClampingScrollPhysics(),
                itemBuilder: (_, int idx) {
                  final activity = _events[idx];
                  return ListTile(
                    leading: _activityIcon(activity.type),
                    title: Text(
                        '${activity.type.toString().split('.').last}'),
                    trailing: Text(activity.confidence.name
                    ),
                  );
                }),
          ),
          /*StreamBuilder<Activity>(
              stream: _activityStreamController.stream,
              builder: (context, snapshot) {
                final updatedDateTime = DateTime.now();
                final content = snapshot.data;
                if(content == null) {
                  return Column(children: [
                    Text('No activity detected'),
                  ]);
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Last activity detected', style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold)),
                  SizedBox(height: 10.0),
                  Text('Updated at: $updatedDateTime'),
                  const SizedBox(height: 10.0),
                  Text("Activity type: " + content!.type.name),
                  const SizedBox(height: 10.0),
                  Text("Activity confidence: ${content.confidence.name}"),
                ]);
              }),*/

        ],
      ),
    );
  }

  void _sendSleepSegmentToBackend(List<String> contentParts) async {
    Dio dio = Dio();

    BaseOptions options = BaseOptions(
        connectTimeout: const Duration(milliseconds: 30000),
        receiveTimeout: const Duration(milliseconds: 30000),
        headers: {
          "Content-Type": "application/json",
        },
        contentType: ContentType.json.value,
        responseType: ResponseType.json);
    dio.options = options;
    Response res;

    final startTime = contentParts[1];
    final endTime = contentParts[2];
    final duration = contentParts[3];
    final status = contentParts[4];

    try {
      res = await dio.post("https://tesibe.swipeapp.studio/sample/tesi", data: {
        "startTime": startTime,
        "endTime": endTime,
        "duration": duration,
        "status": status,
      });
    } on DioError {
      return null;
    }
    return res.data["isTrackable"];
  }

  void _sendSleepClassifyToBackend(List<String> contentParts) async {
    Dio dio = Dio();

    BaseOptions options = BaseOptions(
        connectTimeout: const Duration(milliseconds: 30000),
        receiveTimeout: const Duration(milliseconds: 30000),
        headers: {
          "Content-Type": "application/json",
        },
        contentType: ContentType.json.value,
        responseType: ResponseType.json);
    dio.options = options;
    Response res;

    final timestamp = contentParts[1];
    final confidence = contentParts[2];
    final light = contentParts[3];
    final motion = contentParts[4];

    try {
      res = await dio.post("https://tesibe.swipeapp.studio/sample/tesi", data: {
        "timestamp": timestamp,
        "confidence": confidence,
        "light": light,
        "motion": motion,
      });
    } on DioError {
      return null;
    }
    return res.data["isTrackable"];
  }

  void onData(Activity activityEvent) {
    print(activityEvent);
    setState(() {
      _events.add(activityEvent);
    });
    if(_controller.hasClients && _events.isNotEmpty) {
      _controller.animateTo(_controller.position.maxScrollExtent, duration: Duration(milliseconds: 300), curve: Curves.easeIn);
    }
  }

  void onError(Object error) {
    print('ERROR - $error');
  }

  Icon _activityIcon(ActivityType type) {
    switch (type) {
      case ActivityType.WALKING:
        return Icon(Icons.directions_walk);
      case ActivityType.IN_VEHICLE:
        return Icon(Icons.car_rental);
      case ActivityType.ON_BICYCLE:
        return Icon(Icons.pedal_bike);
      case ActivityType.RUNNING:
        return Icon(Icons.run_circle);
      case ActivityType.STILL:
        return Icon(Icons.cancel_outlined);
      case ActivityType.UNKNOWN:
        return Icon(Icons.device_unknown);
      default:
        return Icon(Icons.device_unknown);
    }
  }

  void _startSystem() async {
    setState(() {
      _systemStarted = true;
    });
    final activityRecognition = FlutterActivityRecognition.instance;

    // Check if the user has granted permission. If not, request permission.
    ActivityPermission reqResult;
    reqResult = await activityRecognition.checkPermission();
    if (reqResult == ActivityPermission.PERMANENTLY_DENIED) {
      print('Permission is permanently denied.');
      return;
    } else if (reqResult == ActivityPermission.DENIED) {
      reqResult = await activityRecognition.requestPermission();
      if (reqResult != ActivityPermission.GRANTED) {
        print('Permission is denied.');
        return;
      }
    }

    // Subscribe to activity recognition stream.
    _activityStreamSubscription = SensorsManager.activityStream.stream.listen(onData, onError: onError);

    //subscribe to the sleep api stream
    if(Platform.isAndroid) {
      SleepApiNotifier().init();
    }
    SensorsManager.init();
  }

  void _stopSystem() {
    SensorsManager.stop();
    _activityStreamSubscription?.cancel();
    _activityStreamSubscription = null;
    setState(() {
      _systemStarted = false;
    });
  }
}
