import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
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

    // Cattura gli errori del framework Flutter (es. errori di build/layout)
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      LoggerService().log(
        "FLUTTER ERROR: ${details.exceptionAsString()}\n${details.stack}",
      );
    };

    // Cattura gli errori asincroni non gestiti a livello di piattaforma
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      LoggerService().log("PLATFORM ERROR: $error\n$stack");
      return true;
    };

    try {
      await Firebase.initializeApp();
    } catch (e, stack) {
      await LoggerService().log("Errore inizializzazione Firebase: $e\n$stack");
    }

    runApp(const RiderApp());
  }, (error, stack) {
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
