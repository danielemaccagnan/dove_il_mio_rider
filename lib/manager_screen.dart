import 'dart:async';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  GoogleMapController? _mapController;
  final TextEditingController _pizzeriaController = TextEditingController();
  final Map<String, BitmapDescriptor> _descriptorCache = {};
  final Map<String, String> _riderStatusCache = {}; // riderId -> "name_status"
  final ValueNotifier<Set<Marker>> _markersNotifier = ValueNotifier({});
  StreamSubscription? _riderSubscription;
  String? _pizzeriaId;
  bool _isConfigured = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  Future<void> _loadConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPizzeria = prefs.getString('pizzeria_id');

    setState(() {
      if (savedPizzeria != null && savedPizzeria.isNotEmpty) {
        _pizzeriaId = savedPizzeria;
        _isConfigured = true;
        _startRiderListener(savedPizzeria);
      }
      _isLoading = false;
    });
  }

  void _startRiderListener(String pizzeriaId) {
    _riderSubscription?.cancel();
    _riderSubscription = FirebaseFirestore.instance
        .collection('pizzerie')
        .doc(pizzeriaId)
        .collection('riders')
        .where('status', isNotEqualTo: 'offline')
        .snapshots()
        .listen((snapshot) {
          _updateMarkers(snapshot.docs);
        });
  }

  Future<void> _updateMarkers(List<QueryDocumentSnapshot> docs) async {
    final Set<Marker> newMarkers = {};

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final String name = data['name'] ?? 'Sconosciuto';
      final String status = data['status'] ?? 'unknown';
      final double? lat = (data['lat'] as num?)?.toDouble();
      final double? lng = (data['lng'] as num?)?.toDouble();

      if (lat != null && lng != null) {
        final Color color = status == 'consegna' ? Colors.green : Colors.orange;

        // Cache key includes status to detect changes
        final String statusKey = '${name}_$status';

        BitmapDescriptor icon;
        // Only regenerate descriptor if name or status changed
        if (_riderStatusCache[doc.id] != statusKey ||
            !_descriptorCache.containsKey(statusKey)) {
          icon = await _createCustomMarker(name, color);
          _riderStatusCache[doc.id] = statusKey;
          _descriptorCache[statusKey] = icon;
        } else {
          icon = _descriptorCache[statusKey]!;
        }

        newMarkers.add(
          Marker(
            markerId: MarkerId(doc.id),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(
              title: name,
              snippet: 'Stato: ${status.toUpperCase()}',
            ),
            icon: icon,
            anchor: const Offset(0.5, 1.0), // Better positioning
          ),
        );
      }
    }

    if (mounted) {
      _markersNotifier.value = newMarkers;
    }
  }

  Future<void> _saveConfiguration() async {
    final pizzeriaId = _pizzeriaController.text.trim().toLowerCase();

    if (pizzeriaId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci un codice pizzeria valido!')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pizzeria_id', pizzeriaId);

    setState(() {
      _pizzeriaId = pizzeriaId;
      _isConfigured = true;
    });
    _startRiderListener(pizzeriaId);
  }

  Future<void> _resetConfiguration() async {
    _riderSubscription?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pizzeria_id');
    setState(() {
      _pizzeriaId = null;
      _isConfigured = false;
      _pizzeriaController.clear();
      _descriptorCache.clear();
      _riderStatusCache.clear();
      _markersNotifier.value = {};
    });
  }

  Future<BitmapDescriptor> _createCustomMarker(String name, Color color) async {
    final String cacheKey = '${name}_${color.toARGB32()}';
    if (_descriptorCache.containsKey(cacheKey)) {
      return _descriptorCache[cacheKey]!;
    }

    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    const double width = 200.0;
    const double height = 80.0;
    const double radius = 20.0;

    // Draw Bubble background
    final Paint paint = Paint()..color = color;
    final RRect rRect = RRect.fromLTRBR(
      0,
      0,
      width,
      height - 20,
      const Radius.circular(radius),
    );
    canvas.drawRRect(rRect, paint);

    // Draw Triangle pointer
    final Path path = Path()
      ..moveTo(width / 2 - 15, height - 20)
      ..lineTo(width / 2 + 15, height - 20)
      ..lineTo(width / 2, height)
      ..close();
    canvas.drawPath(path, paint);

    // Draw Text
    final TextPainter tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '...',
    );
    tp.text = TextSpan(
      text: name,
      style: const TextStyle(
        fontSize: 35,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
    tp.layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, Offset(0, (height - 20 - tp.height) / 2));

    final ui.Image image = await pictureRecorder.endRecording().toImage(
      width.toInt(),
      height.toInt(),
    );
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final Uint8List uint8List = byteData!.buffer.asUint8List();

    final BitmapDescriptor descriptor = BitmapDescriptor.bytes(uint8List);
    _descriptorCache[cacheKey] = descriptor;
    return descriptor;
  }

  @override
  void dispose() {
    _riderSubscription?.cancel();
    _pizzeriaController.dispose();
    _markersNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isConfigured) {
      return _buildSetupScreen();
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Area Manager ($_pizzeriaId)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white.withValues(alpha: 0.9),
        elevation: 0,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Cambia Pizzeria'),
                  content: const Text('Vuoi resettare il codice pizzeria?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('ANNULLA'),
                    ),
                    TextButton(
                      onPressed: () {
                        _resetConfiguration();
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'RESET',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          ValueListenableBuilder<Set<Marker>>(
            valueListenable: _markersNotifier,
            builder: (context, markers, _) {
              return Stack(
                children: [
                  GoogleMap(
                    key: const ValueKey('manager_google_map'),
                    initialCameraPosition: _comoPosition,
                    markers: markers,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      LoggerService().log(
                        'Google Map creata per pizzeria $_pizzeriaId',
                      );
                    },
                  ),

                  // Se non ci sono rider online, mostriamo un piccolo avviso
                  if (markers.isEmpty)
                    Positioned(
                      top: 100,
                      left: 20,
                      right: 20,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Nessun rider online al momento',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

          // Legend / Summary overlay
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Zoom context buttons
                FloatingActionButton.small(
                  heroTag: 'zoomIn',
                  onPressed: () =>
                      _mapController?.animateCamera(CameraUpdate.zoomIn()),
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.add, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoomOut',
                  onPressed: () =>
                      _mapController?.animateCamera(CameraUpdate.zoomOut()),
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.remove, color: Colors.black87),
                ),
                const SizedBox(height: 16),

                // Summary Panel
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Legenda Stato',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildLegendItem(Colors.green, 'In Consegna'),
                          const SizedBox(width: 16),
                          _buildLegendItem(Colors.orange, 'In Rientro'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupScreen() {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.storefront, size: 64, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                'Accesso Manager',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Inserisci il codice della tua pizzeria per iniziare a monitorare i tuoi rider.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 48),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _pizzeriaController,
                  decoration: InputDecoration(
                    labelText: 'Codice Pizzeria',
                    hintText: 'es. pizzeria_napoli',
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: _saveConfiguration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'ACCEDI ALLA MAPPA',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
      ],
    );
  }
}
