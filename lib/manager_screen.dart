import 'dart:async';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger_service.dart';
import 'pizzeria_access.dart';

class ManagerScreen extends StatefulWidget {
  const ManagerScreen({super.key});

  @override
  State<ManagerScreen> createState() => _ManagerScreenState();
}

class _ManagerScreenState extends State<ManagerScreen>
    with SingleTickerProviderStateMixin {
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
  StreamSubscription? _authSubscription;
  String? _pizzeriaId;
  bool _isConfigured = false;
  bool _isLoading = true;

  // --- Animazione marker ---
  // Ogni rider mantiene posizione mostrata + posizione obiettivo (da Firestore).
  // Un Ticker (60fps) interpola la posizione mostrata verso l'obiettivo, così
  // il pallino "scivola" in modo lineare invece di saltare ad ogni update.
  final Map<String, _RiderMarker> _riders = {};
  late final Ticker _ticker;
  // Durata dell'animazione = circa l'intervallo con cui il rider scrive (5s),
  // così il movimento è continuo e quasi lineare.
  static const Duration _animDuration = Duration(seconds: 5);
  // Limita gli aggiornamenti dei marker sulla mappa a ~30fps (basta e avanza,
  // e alleggerisce il canale nativo di Google Maps).
  Duration _lastRebuild = Duration.zero;

  // --- Lista rider + stima rientro ---
  // Posizione del manager = posizione del locale (GPS del telefono manager).
  Position? _managerPosition;
  // Bump quando cambiano i dati dei rider (da Firestore o quando arriva la
  // posizione del manager): la lista in basso si aggiorna senza ridisegnare a
  // 30fps come i marker.
  final ValueNotifier<int> _ridersVersion = ValueNotifier(0);
  // Parametri per la stima del tempo di rientro (linea d'aria -> stima strada).
  static const double _avgSpeedKmh = 25; // velocità media realistica in città
  static const double _roadFactor = 1.4; // le strade non sono in linea d'aria

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _loadConfiguration();
  }

  /// Chiamato ad ogni frame mentre almeno un rider si sta muovendo.
  void _onTick(Duration elapsed) {
    bool anyMoving = false;
    for (final r in _riders.values) {
      r.updateInterpolated();
      if (r.isMoving) anyMoving = true;
    }
    // Throttle a ~30fps per non sovraccaricare la mappa nativa.
    if (elapsed - _lastRebuild >= const Duration(milliseconds: 33) || !anyMoving) {
      _lastRebuild = elapsed;
      _rebuildMarkers();
    }
    if (!anyMoving) {
      _ticker.stop();
    }
  }

  /// Costruisce il set di marker dalle posizioni interpolate correnti.
  void _rebuildMarkers() {
    if (!mounted) return;
    final markers = <Marker>{};
    _riders.forEach((id, r) {
      markers.add(
        Marker(
          markerId: MarkerId(id),
          position: r.currentPos,
          infoWindow: InfoWindow(
            title: r.name,
            snippet: 'Stato: ${r.status.toUpperCase()}',
          ),
          icon: r.icon,
          anchor: const Offset(0.5, 1.0),
        ),
      );
    });
    _markersNotifier.value = markers;
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
    if (_isConfigured && savedPizzeria != null) {
      _startAuthListener(savedPizzeria);
      _loadManagerPosition();
    }
  }

  /// Ottiene la posizione del manager (= posizione del locale) per stimare il
  /// tempo di rientro dei rider. Se il permesso manca, l'app funziona comunque
  /// (semplicemente non mostra la stima in minuti).
  Future<void> _loadManagerPosition() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 8));
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos != null && mounted) {
        setState(() => _managerPosition = pos);
        _ridersVersion.value++; // aggiorna la lista se è aperta
      }
    } catch (e) {
      LoggerService().log('Manager: posizione non disponibile: $e');
    }
  }

  /// Stima i minuti di rientro dal punto [riderPos] alla posizione del manager.
  /// Usa la distanza in linea d'aria moltiplicata per un fattore "strada",
  /// divisa per una velocità media. Approssimazione, non navigazione reale.
  int? _etaMinutes(LatLng riderPos) {
    final m = _managerPosition;
    if (m == null) return null;
    final double straight = Geolocator.distanceBetween(
      riderPos.latitude,
      riderPos.longitude,
      m.latitude,
      m.longitude,
    );
    final double roadMeters = straight * _roadFactor;
    final double metersPerMinute = _avgSpeedKmh * 1000 / 60;
    final int mins = (roadMeters / metersPerMinute).ceil();
    return mins < 1 ? 1 : mins;
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
    final Set<String> seenIds = {};
    bool needsTicker = false;

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final String name = data['name'] ?? 'Sconosciuto';
      final String status = data['status'] ?? 'unknown';
      final double? lat = (data['lat'] as num?)?.toDouble();
      final double? lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      seenIds.add(doc.id);
      final LatLng target = LatLng(lat, lng);
      final Color color = status == 'consegna' ? Colors.green : Colors.orange;

      // Icona: la rigeneriamo solo se nome o stato sono cambiati.
      final String statusKey = '${name}_$status';
      BitmapDescriptor icon;
      if (_riderStatusCache[doc.id] != statusKey ||
          !_descriptorCache.containsKey(statusKey)) {
        icon = await _createCustomMarker(name, color);
        _riderStatusCache[doc.id] = statusKey;
        _descriptorCache[statusKey] = icon;
      } else {
        icon = _descriptorCache[statusKey]!;
      }

      final existing = _riders[doc.id];
      if (existing == null) {
        // Nuovo rider: appare subito nella sua posizione (senza animazione).
        _riders[doc.id] = _RiderMarker(
          name: name,
          status: status,
          icon: icon,
          position: target,
        );
      } else {
        existing.name = name;
        existing.status = status;
        existing.icon = icon;
        // Anima dalla posizione mostrata ora verso la nuova posizione.
        existing.animateTo(target, _animDuration);
        needsTicker = true;
      }
    }

    // Rimuovi i rider non più presenti (andati offline).
    _riders.removeWhere((id, _) => !seenIds.contains(id));

    _rebuildMarkers(); // riflette subito nuovi rider / rimozioni
    _ridersVersion.value++; // aggiorna la lista in basso
    if (needsTicker && !_ticker.isActive) {
      _lastRebuild = Duration.zero;
      _ticker.start();
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

    // Verifica che il codice pizzeria sia autorizzato (cliente attivo).
    final access = await checkPizzeriaAccess(pizzeriaId);
    if (access == PizzeriaAccess.notAuthorized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Codice pizzeria non valido o non attivo.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (access == PizzeriaAccess.networkError) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Connessione assente: impossibile verificare il codice. Riprova.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pizzeria_id', pizzeriaId);

    setState(() {
      _pizzeriaId = pizzeriaId;
      _isConfigured = true;
    });
    _startRiderListener(pizzeriaId);
    _startAuthListener(pizzeriaId);
    _loadManagerPosition();
  }

  /// Logout automatico se l'autorizzazione della pizzeria viene revocata.
  void _startAuthListener(String pizzeriaId) {
    _authSubscription?.cancel();
    _authSubscription = pizzeriaAuthorizationStream(pizzeriaId).listen((ok) {
      if (!ok && mounted && _isConfigured) {
        LoggerService().log('Accesso pizzeria revocato: logout automatico.');
        _resetConfiguration();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Accesso non più autorizzato. Contatta l\'amministratore.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    });
  }

  Future<void> _resetConfiguration() async {
    _riderSubscription?.cancel();
    _authSubscription?.cancel();
    if (_ticker.isActive) _ticker.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pizzeria_id');
    setState(() {
      _pizzeriaId = null;
      _isConfigured = false;
      _pizzeriaController.clear();
      _descriptorCache.clear();
      _riderStatusCache.clear();
      _riders.clear();
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

  /// Apre la lista dei rider divisa per stato, con stima di rientro.
  void _showRidersList() {
    // Aggiorna la posizione del locale all'apertura (il manager potrebbe
    // essersi spostato), poi la lista si aggiorna da sola.
    _loadManagerPosition();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return ValueListenableBuilder<int>(
          valueListenable: _ridersVersion,
          builder: (context, _, _) {
            final consegna =
                _riders.values.where((r) => r.status == 'consegna').toList()
                  ..sort((a, b) => a.name.compareTo(b.name));
            final rientro =
                _riders.values.where((r) => r.status == 'rientro').toList();
            // I rientranti ordinati per ETA crescente (prima chi arriva prima).
            rientro.sort((a, b) {
              final ea = _etaMinutes(a.targetPos) ?? 9999;
              final eb = _etaMinutes(b.targetPos) ?? 9999;
              return ea.compareTo(eb);
            });

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      'Rider attivi',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (_managerPosition == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Posizione locale non disponibile: concedi il permesso GPS per la stima di rientro.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[800],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildRiderSection(
                              'In consegna',
                              Colors.green,
                              Icons.delivery_dining,
                              consegna,
                              showEta: false,
                            ),
                            const SizedBox(height: 20),
                            _buildRiderSection(
                              'In rientro',
                              Colors.orange,
                              Icons.keyboard_return,
                              rientro,
                              showEta: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRiderSection(
    String title,
    Color color,
    IconData icon,
    List<_RiderMarker> riders, {
    required bool showEta,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              '$title (${riders.length})',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (riders.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 28, bottom: 4),
            child: Text(
              'Nessuno',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          )
        else
          ...riders.map((r) {
            final eta = showEta ? _etaMinutes(r.targetPos) : null;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 28, right: 12),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (showEta)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        eta == null ? '— min' : '~$eta min',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _riderSubscription?.cancel();
    _authSubscription?.cancel();
    _pizzeriaController.dispose();
    _markersNotifier.dispose();
    _ridersVersion.dispose();
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
            icon: const Icon(Icons.format_list_bulleted_rounded),
            tooltip: 'Lista rider',
            onPressed: _showRidersList,
          ),
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

/// Stato di un rider sulla mappa, con animazione fluida tra una posizione e
/// l'altra. `currentPos` è la posizione MOSTRATA (interpolata), `targetPos` è
/// l'ultima posizione ricevuta da Firestore.
class _RiderMarker {
  String name;
  String status;
  BitmapDescriptor icon;
  LatLng startPos; // da dove parte l'animazione corrente
  LatLng targetPos; // dove deve arrivare (ultima posizione reale)
  LatLng currentPos; // posizione mostrata ora
  DateTime _animStart;
  Duration _animDuration;

  _RiderMarker({
    required this.name,
    required this.status,
    required this.icon,
    required LatLng position,
  })  : startPos = position,
        targetPos = position,
        currentPos = position,
        _animStart = DateTime.now(),
        _animDuration = const Duration(milliseconds: 1);

  /// Avvia una nuova animazione: dalla posizione mostrata ora verso [newTarget].
  void animateTo(LatLng newTarget, Duration duration) {
    startPos = currentPos;
    targetPos = newTarget;
    _animStart = DateTime.now();
    _animDuration = duration;
  }

  /// Vero finché l'animazione non è arrivata a destinazione.
  bool get isMoving {
    final elapsed = DateTime.now().difference(_animStart).inMilliseconds;
    return elapsed < _animDuration.inMilliseconds;
  }

  /// Ricalcola `currentPos` interpolando linearmente start -> target nel tempo.
  void updateInterpolated() {
    final elapsedMs = DateTime.now().difference(_animStart).inMilliseconds;
    final durMs = _animDuration.inMilliseconds;
    final double t = durMs <= 0 ? 1.0 : (elapsedMs / durMs).clamp(0.0, 1.0);
    currentPos = LatLng(
      startPos.latitude + (targetPos.latitude - startPos.latitude) * t,
      startPos.longitude + (targetPos.longitude - startPos.longitude) * t,
    );
  }
}
