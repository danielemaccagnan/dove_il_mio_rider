import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SimulatorApp());
}

class SimulatorApp extends StatelessWidget {
  const SimulatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Rider Simulator')),
        body: const SimulatorControl(),
      ),
    );
  }
}

class SimulatorControl extends StatefulWidget {
  const SimulatorControl({super.key});

  @override
  State<SimulatorControl> createState() => _SimulatorControlState();
}

class _SimulatorControlState extends State<SimulatorControl> {
  final String _pizzeriaId = 'dani';
  final List<Map<String, dynamic>> _riders = [
    {'id': 'sim_1', 'name': 'Rider Alpha', 'color': 'consegna', 'lat': 45.8081, 'lng': 9.0852},
    {'id': 'sim_2', 'name': 'Rider Beta', 'color': 'rientro', 'lat': 45.8000, 'lng': 9.0900},
    {'id': 'sim_3', 'name': 'Rider Gamma', 'color': 'consegna', 'lat': 45.8150, 'lng': 9.0700},
    {'id': 'sim_4', 'name': 'Rider Delta', 'color': 'rientro', 'lat': 45.8200, 'lng': 9.1000},
    {'id': 'sim_5', 'name': 'Rider Epsilon', 'color': 'consegna', 'lat': 45.7950, 'lng': 9.0600},
  ];
  
  Timer? _timer;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    // Auto-start simulation after a short delay for Firebase initialization
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _startSimulation();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startSimulation() {
    setState(() => _isRunning = true);
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _moveRiders();
    });
  }

  void _stopSimulation() {
    _timer?.cancel();
    setState(() => _isRunning = false);
    _clearRiders();
  }

  void _moveRiders() async {
    final Random random = Random();
    final firestore = FirebaseFirestore.instance;

    for (var rider in _riders) {
      // Small random movement
      rider['lat'] += (random.nextDouble() - 0.5) * 0.001;
      rider['lng'] += (random.nextDouble() - 0.5) * 0.001;
      
      // Occasionally change status
      if (random.nextDouble() < 0.1) {
        rider['color'] = rider['color'] == 'consegna' ? 'rientro' : 'consegna';
      }

      await firestore
          .collection('pizzerie')
          .doc(_pizzeriaId)
          .collection('riders')
          .doc(rider['id'])
          .set({
        'name': rider['name'],
        'status': rider['color'],
        'lat': rider['lat'],
        'lng': rider['lng'],
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  void _clearRiders() async {
    final firestore = FirebaseFirestore.instance;
    for (var rider in _riders) {
      await firestore
          .collection('pizzerie')
          .doc(_pizzeriaId)
          .collection('riders')
          .doc(rider['id'])
          .update({'status': 'offline'});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Pizzeria: $_pizzeriaId', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Text(_isRunning ? 'Simulazione in corso...' : 'Pronto per la simulazione'),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _isRunning ? null : _startSimulation,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('AVVIA SIMULAZIONE (5 RIDER)'),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: !_isRunning ? null : _stopSimulation,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('STOP E PULISCI'),
          ),
        ],
      ),
    );
  }
}
