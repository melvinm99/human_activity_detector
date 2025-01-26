import 'dart:async';

import 'package:flutter/services.dart';
import 'package:human_activity_detector/Logger.dart';

class SleepApiNotifier {

  static const platform = MethodChannel('com.activity.detector/sleep_detector');
  static const receiveChannel = BasicMessageChannel<String>('com.activity.detector/sleep_detector_messages', StringCodec());
  static StreamController<String> receiveStreamController = StreamController.broadcast();
  StreamSubscription<String>? _receiveStreamSubscription;

  Future<void> init() async {
    Logger.logInfo(text:"Start listening messages");
    _receiveStreamSubscription?.cancel();
    _receiveStreamSubscription = receiveStreamController.stream.listen((event) async {
      Logger.logInfo(text: "Received message: $event");
    });
    receiveChannel.setMessageHandler((String? message) async {
      if (message == null) return '';

      Logger.logInfo(text:'Received: $message');
      receiveStreamController.add(message);
      return '';
    });

    try {
      final String result = await platform.invokeMethod('initSleepApi', <String, dynamic>{});
      Logger.logInfo(text:result);
    } on PlatformException catch (e) {
      Logger.logError(text:"Failed to initSdk: '${e.code}'.");
      return;
    }
  }

}