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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE91E63), // Pinkish/Red for food apps
          primary: const Color(0xFFE91E63),
          secondary: const Color(0xFF212121),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
          bodyLarge: TextStyle(fontSize: 16, color: Colors.black54),
        ),
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
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Decorative background element
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 60),
                  const Text(
                    'Dove il mio\nRider?',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      color: Color(0xFF2D3436),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Gestione consegne in tempo reale per il tuo ristorante.',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 60),
                  _buildMenuCard(
                    context,
                    title: 'SONO UN RIDER',
                    subtitle: 'Attiva il GPS e inizia le consegne',
                    icon: Icons.delivery_dining_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const RiderScreen()),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildMenuCard(
                    context,
                    title: 'SONO IL MANAGER',
                    subtitle: 'Monitora la flotta sulla mappa live',
                    icon: Icons.restaurant_menu_rounded,
                    color: Theme.of(context).colorScheme.secondary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ManagerScreen()),
                    ),
                  ),
                  const Spacer(),
                  Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        String logs = await LoggerService().getLogs();
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => _LogsScreen(logs: logs),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.bug_report_outlined, size: 18),
                      label: const Text('DEBUG LOGS'),
                      style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: Colors.white, size: 32),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogsScreen extends StatelessWidget {
  final String logs;
  const _LogsScreen({required this.logs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Log Errori"),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: logs));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Log copiati!')),
                );
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(logs, style: const TextStyle(fontFamily: 'monospace')),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.delete),
        onPressed: () async {
          await LoggerService().clearLogs();
          if (context.mounted) Navigator.pop(context);
        },
      ),
    );
  }
}
