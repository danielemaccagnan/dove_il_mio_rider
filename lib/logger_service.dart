import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();

  factory LoggerService() {
    return _instance;
  }

  LoggerService._internal();

  File? _logFile;

  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    _logFile = File('${directory.path}/app_logs.txt');
  }

  Future<void> log(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] $message\n';
    debugPrint(logMessage); // Stampa anche in console per debug immediato
    
    if (_logFile != null) {
      try {
        await _logFile!.writeAsString(logMessage, mode: FileMode.append);
      } catch (e) {
        debugPrint("Errore durante la scrittura del log: $e");
      }
    }
  }

  Future<String> getLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      return await _logFile!.readAsString();
    }
    return "Nessun log presente.";
  }

  Future<void> clearLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }
  }
  
  String? get filePath => _logFile?.path;
}
