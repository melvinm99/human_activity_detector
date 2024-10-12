import 'dart:io';

import 'package:flutter/services.dart';

class RingerManager {

  static const platform = MethodChannel('com.activity.detector/ringtone');

  static Future<RingerMode?> getRingerMode() async {
    try {
      final int? ringerMode = await platform.invokeMethod('getRingerMode');
      if (ringerMode == null) {
        return null;
      }
      var result = ringerMode == 2 ? RingerMode.NORMAL :
      ringerMode == 1 ? RingerMode.VIBRATE : RingerMode.SILENT;
      print("Ringer mode: $result");
      return result;
    } on PlatformException catch (e) {
      print("Failed to get Mfcc file path: '${e.message}'.");
      return null;
    }
  }

}

enum RingerMode {
  SILENT,
  VIBRATE,
  NORMAL
}