import 'dart:io';

import 'package:flutter/services.dart';

class AudioManager {

  static const platform = MethodChannel('com.activity.detector/audio_processing');

  static Future<bool> startAudioRecording() async {
    if(!Platform.isAndroid) {
      print("Audio recording is only supported on Android");
      return false;
    }
    try {
      final bool started = await platform.invokeMethod('startAudioRecording');
      return started;
    } on PlatformException catch (e) {
      print("Failed to start recording: '${e.message}'.");
      return false;
    }
  }

  static Future<bool> stopAudioRecording() async {
    try {
      final bool stopped = await platform.invokeMethod('stopAudioRecording'); //stops recording and computes MFCC features
      if(stopped) {
        clearAudioRecordingData();
      }
      return stopped;
    } on PlatformException catch (e) {
      print("Failed to stop recording: '${e.message}'.");
      return false;
    }
  }

  static Future<bool> clearAudioRecordingData() async {
    try {
      final bool cleared = await platform.invokeMethod('clearAudioRecordingData'); //stops recording and computes MFCC features
      return cleared;
    } on PlatformException catch (e) {
      print("Failed to clear audio data: '${e.message}'.");
      return false;
    }
  }

  static Future<bool> computeMfccFeatures() async {
    try {
      final bool computed = await platform.invokeMethod('computeMfccFeatures');
      return computed;
    } on PlatformException catch (e) {
      print("Failed to compute Mfcc features: '${e.message}'.");
      return false;
    }
  }

  static Future<File?> getMfccFile() async {
    try {
      final String? filePath = await platform.invokeMethod('getMfccFilePath');
      if (filePath == null) {
        return null;
      }
      return File(filePath);
    } on PlatformException catch (e) {
      print("Failed to get Mfcc file path: '${e.message}'.");
      return null;
    }
  }

}