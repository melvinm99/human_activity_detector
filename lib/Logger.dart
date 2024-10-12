import 'dart:io';

import 'package:path_provider/path_provider.dart';

class Logger {

  static Future<void> logInfo({required String text, String? className, String? methodName}) async {
    _log(LogType.INFO, text, className: className, methodName: methodName);
  }

  static Future<void> logError({required String text,String? className, String? methodName, String? exception}) async {
    _log(LogType.ERROR, text, className: className, methodName: methodName, exception: exception);
  }

  static Future<void> logWarning({required String text, String? className, String? methodName}) async {
    await _log(LogType.WARNING, text, className: className, methodName: methodName);
  }

  static Future<void> _log(LogType logType, String message, {String? className, String? methodName, String? exception}) async {
    bool logHasSpace = await _checkLogFileSize();
    if (!logHasSpace) {
      await clearLogs();
    }
    var buffer = StringBuffer();
    buffer.write(((enumToString(logType) ?? "") + " - "));
    buffer.write(", {timestamp: " + DateTime.now().toString() + "}");
    if(className != null) {
      buffer.write(", {class: " + className + "}");
    }
    if(methodName != null) {
      buffer.write(", {method: " + methodName + "}");
    }
    if(exception != null) {
      buffer.write(", {exception: " + exception + "}");
    }
    buffer.write(", {message: " + message + "}");

    buffer.write(", {model: " + (Platform.isAndroid ? "Android" : "iOS") + "}");
    buffer.write(", {OS: " + Platform.operatingSystem + " - " + Platform.operatingSystemVersion + "}");
    _writeToLogFile(buffer.toString());
  }

  static void _writeToLogFile(String message) async {
    final file = await _localFile;
    if (file == null) {
      return;
    }
    // Write the file
    await file.writeAsString(message + " " + Platform.lineTerminator, mode: FileMode.append);
    print("Log written to file: " + message);
  }

  static Future<void> clearLogs() async {
    final file = await _localFile;
    if (file == null) {
      return;
    }
    await file.writeAsString('', mode: FileMode.write);
    print("Logs cleared");
  }

  static Future<bool> _checkLogFileSize() async {
    final file = await _localFile;
    if (file == null || !(await file.exists())) {
      return false;
    }
    int size = await file.length();
    return (size / 1024 < 51200);
  }

  static Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  static Future<File?> get _localFile async {
    final path = await _localPath;
    try {
      var file = File("$path/app_logs.txt");
      return file;
    }
    catch (e) {
      print("Error while getting log file: " + e.toString());
    }
    return null;
  }

  static Future<File?> exportLogs() async {
    final file = await _localFile;
    return file;
  }

  static String? enumToString(dynamic enumType) {
    if (enumType == null) return null;
    return '$enumType'.split('.').last;
  }

  static enumFromString(String? type, List<dynamic> values) {
    if (type == null) return null;
    return values.firstWhere((element) => element.toString().toLowerCase().split(".").last == type.toLowerCase());
  }

}

enum LogType {
  INFO,
  WARNING,
  ERROR
}