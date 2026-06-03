import 'dart:async';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'firebase_ios_options.dart';
import 'logger_service.dart';
import 'manager_screen.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await LoggerService().init();

    bool firebaseOk = false;
    try {
      await initFirebaseCrossPlatform();
      firebaseOk = true;
    } catch (e, stack) {
      await LoggerService().log("Errore inizializzazione Firebase: $e\n$stack");
    }

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      if (firebaseOk) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      }
      LoggerService().log(
        "FLUTTER ERROR: ${details.exceptionAsString()}\n${details.stack}",
      );
    };

    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      if (firebaseOk) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
      LoggerService().log("PLATFORM ERROR: $error\n$stack");
      return true;
    };

    runApp(const ManagerApp());
  }, (error, stack) {
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } catch (_) {}
    LoggerService().log("ERRORE GLOBALE MANAGER: $error\n$stack");
  });
}

class ManagerApp extends StatelessWidget {
  const ManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Manager App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF212121),
          primary: const Color(0xFF212121),
          secondary: const Color(0xFFE91E63),
        ),
      ),
      home: const ManagerScreen(),
    );
  }
}
