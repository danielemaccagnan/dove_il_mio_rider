import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'logger_service.dart';
import 'manager_screen.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await LoggerService().init();
    
    try {
      await Firebase.initializeApp();
    } catch (e, stack) {
      await LoggerService().log("Errore inizializzazione Firebase: $e\n$stack");
    }
    
    runApp(const ManagerApp());
  }, (error, stack) {
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
