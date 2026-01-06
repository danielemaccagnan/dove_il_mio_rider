import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'logger_service.dart';
import 'manager_screen.dart';
import 'rider_screen.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await LoggerService().init();
    await LoggerService().log("App avviata");
    
    try {
      await Firebase.initializeApp();
      await LoggerService().log("Firebase inizializzato correttamente");
    } catch (e, stack) {
      await LoggerService().log("Errore inizializzazione Firebase: $e\n$stack");
    }
    
    runApp(const MyApp());
  }, (error, stack) {
     LoggerService().log("ERRORE GLOBALE: $error\n$stack");
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dove il mio Rider',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dove il mio Rider'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 250,
              height: 80,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RiderScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 20),
                ),
                child: const Text('SONO UN RIDER 🛵'),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: 250,
              height: 80,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ManagerScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 20),
                ),
                child: const Text('SONO IL MANAGER 🍕'),
              ),
            ),
            const SizedBox(height: 30),
             TextButton.icon(
              onPressed: () async {
                String logs = await LoggerService().getLogs();
                if (context.mounted) {
                   Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        appBar: AppBar(
                          title: const Text("Log Errori"),
                          actions: [
                            IconButton(
                              icon: const Icon(Icons.copy),
                              tooltip: 'Copia Log',
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: logs));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Log copiati negli appunti!')),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        body: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(logs),
                        ),
                        floatingActionButton: FloatingActionButton(
                          child: const Icon(Icons.delete),
                          onPressed: () async {
                              await LoggerService().clearLogs();
                              if(context.mounted) Navigator.pop(context);
                          },
                        ),
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.bug_report),
              label: const Text('Visualizza Log Errori'),
            ),
          ],
        ),
      ),
    );
  }
}
