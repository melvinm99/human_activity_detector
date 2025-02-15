import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:human_activity_detector/AudioManager.dart';
import 'package:human_activity_detector/Logger.dart';
import 'package:human_activity_detector/SensorsManager.dart';
import 'package:human_activity_detector/SleepApiNotifier.dart';
import 'package:human_activity_detector/configuration.dart';
import 'package:human_activity_detector/rounded_button.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

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

  bool systemStarted = false;

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
    return Scaffold(
        backgroundColor: Color(0xfff9f9f9ff),
        body: _buildContentView());
  }

  @override
  void dispose() {
    //_activityStreamController.close();
    WidgetsBinding.instance.removeObserver(this);
    _activityStreamSubscription?.cancel();
    super.dispose();
  }

  Widget _buildContentView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 20.0),
                Text(
                  'Human Activity Detector',
                  style: TextStyle(fontSize: 30.0, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20.0),
                //Text('Prediction', style: TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold)),
                Container(
                  padding: EdgeInsets.all(20.0),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10.0)),
                  child: StreamBuilder<PredictionEntity>(
                      stream: SensorsManager.predictionStream.stream,
                      builder: (context, snapshot) {
                        final data = snapshot.data;
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Model Prediction', style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold)),
                          SizedBox(height: 10.0),
                          if (data == null)
                            Text('No prediction available')
                          else
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                              decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(20.0)),
                              child: Text(data.prediction, style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold)),
                            ),
                          SizedBox(height: 10.0),
                          if (data != null)
                            Text('Last update: ${DateFormat("dd/MM/yyyy HH:mm").format(data.timestamp)}'),
                        ]);
                      }),
                ),
                /*SizedBox(height: 10.0),
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
                    }),*/
                SizedBox(height: 30.0),
                Text('Native Activity Detection History', style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold)),
                //Text('For debugging purpose', style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.normal)),
                SizedBox(height: 10.0),
                if (_events.isEmpty) Text('No activity detected') else Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 80.0),
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
                                  title: Text(activity.type.toString().split('.').last),
                                  trailing: Text(activity.confidence.name),
                                );
                              }),
                        ),
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
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                    const SizedBox(width: 20),
                    Flexible(
                      child: RoundedButton(
                          label: systemStarted ? 'Stop' : 'Start',
                          onTap: () {
                            if (systemStarted) {
                              _stopSystem();
                            } else {
                              _startSystem();
                            }
                          }),
                    ),
                    const SizedBox(width: 20),
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
                  ],
                ),
              ),
            ),
          ],
        ),
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
      res = await dio.post("${Configuration.BASE_URL}sample", data: {
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
      res = await dio.post("${Configuration.BASE_URL}sample", data: {
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
    if (_controller.hasClients && _events.isNotEmpty) {
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
      systemStarted = true;
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
    if (Platform.isAndroid) {
      SleepApiNotifier().init();
    }
    SensorsManager.init();
  }

  void _stopSystem() {
    SensorsManager.stop();
    _activityStreamSubscription?.cancel();
    _activityStreamSubscription = null;
    setState(() {
      systemStarted = false;
    });
  }
}
