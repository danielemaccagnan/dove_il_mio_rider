import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'logger_service.dart';
import 'rider_screen.dart';
import 'overlay_main.dart'; 

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: FloatingBubbleOverlay(),
  ));
}

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await LoggerService().init();
    
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
