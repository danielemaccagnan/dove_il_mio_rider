import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'logger_service.dart';

class ManagerScreen extends StatefulWidget {
  const ManagerScreen({super.key});

  @override
  State<ManagerScreen> createState() => _ManagerScreenState();
}

class _ManagerScreenState extends State<ManagerScreen> {
  // Como, Italy coordinates
  static const CameraPosition _comoPosition = CameraPosition(
    target: LatLng(45.8081, 9.0852),
    zoom: 13,
  );

  @override
  void initState() {
    super.initState();
    LoggerService().log('ManagerScreen init');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mappa Rider 🍕')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('riders').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
             LoggerService().log('Errore Stream Firestore: ${snapshot.error}');
            return Center(child: Text('Errore: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final Set<Marker> markers = {};
          
          if (snapshot.hasData) {
            try {
              for (var doc in snapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final String name = data['name'] ?? 'Sconosciuto';
                final String status = data['status'] ?? 'unknown';
                // Handle both double and int types safely for coordinates
                final double? lat = (data['lat'] as num?)?.toDouble();
                final double? lng = (data['lng'] as num?)?.toDouble();

                if (lat != null && lng != null) {
                  // Determine marker color based on status
                  final double hue = status == 'consegna'
                      ? BitmapDescriptor.hueRed
                      : (status == 'rientro'
                          ? BitmapDescriptor.hueGreen
                          : BitmapDescriptor.hueAzure);

                  markers.add(
                    Marker(
                      markerId: MarkerId(name),
                      position: LatLng(lat, lng),
                      infoWindow: InfoWindow(
                        title: name,
                        snippet: 'Stato: $status',
                      ),
                      icon: BitmapDescriptor.defaultMarkerWithHue(hue),
                    ),
                  );
                }
              }
            } catch (e, s) {
              LoggerService().log('Errore parsing dati markers: $e\n$s');
            }
          }

          return GoogleMap(
            initialCameraPosition: _comoPosition,
            markers: markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onMapCreated: (controller) => LoggerService().log('Google Map creata'),
          );
        },
      ),
    );
  }
}
