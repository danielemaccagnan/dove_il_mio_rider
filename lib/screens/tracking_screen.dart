import 'package:flutter/material.dart';

class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracking Ordine'),
      ),
      body: const Center(
        child: Text(
          'Mappa del Rider qui',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
