import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_ios_options.dart';
import 'logger_service.dart';
import 'rider_screen.dart';
import 'overlay_main.dart';

@pragma("vm:entry-point")
Future<void> overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("ERRORE FIREBASE IN OVERLAY: $e");
  }
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: FloatingBubbleOverlay(),
  ));
}

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

    // Errori del framework Flutter -> Crashlytics + log locale.
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      if (firebaseOk) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      }
      LoggerService().log(
        "FLUTTER ERROR: ${details.exceptionAsString()}\n${details.stack}",
      );
    };

    // Errori asincroni non gestiti -> Crashlytics + log locale.
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      if (firebaseOk) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
      LoggerService().log("PLATFORM ERROR: $error\n$stack");
      return true;
    };

    runApp(const RiderApp());
  }, (error, stack) {
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } catch (_) {}
    LoggerService().log("ERRORE GLOBALE RIDER: $error\n$stack");
  });
}

class RiderApp extends StatelessWidget {
  const RiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rider App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE91E63),
          primary: const Color(0xFFE91E63),
        ),
      ),
      home: const RiderScreen(),
    );
  }
}
