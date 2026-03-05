import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger_service.dart';

class RiderScreen extends StatefulWidget {
  const RiderScreen({super.key});

  @override
  State<RiderScreen> createState() => _RiderScreenState();
}

class _RiderScreenState extends State<RiderScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _pizzeriaController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  bool _isConfigured = false;
  String _currentStatus = 'offline';
  StreamSubscription<Position>? _positionStream;
  StreamSubscription? _overlayListener;

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
    _initOverlayListener();
  }

  void _initOverlayListener() {
    _overlayListener = FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is String && _isConfigured) {
        // Prevent infinite loop by checking if it's already in that status
        if (_currentStatus != event) {
          _toggleTracking(event);
        }
      }
    });
  }

  Future<void> _loadConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('rider_name');
    final savedPizzeria = prefs.getString('pizzeria_id');
    
    if (savedName != null && savedName.isNotEmpty && savedPizzeria != null && savedPizzeria.isNotEmpty) {
      setState(() {
        _nameController.text = savedName;
        _pizzeriaController.text = savedPizzeria;
        _isConfigured = true;
      });
    }
  }

  Future<void> _saveConfiguration() async {
    final name = _nameController.text.trim();
    final pizzeriaId = _pizzeriaController.text.trim().toLowerCase();
    
    if (name.isEmpty || pizzeriaId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci nome e codice pizzeria!')),
      );
      return;
    }

    // Check overlay permission
    final bool status = await FlutterOverlayWindow.isPermissionGranted();
    if (!status) {
      final bool? granted = await FlutterOverlayWindow.requestPermission();
      if (granted != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permesso "Spostamento sopra altre app" necessario per la bolla!')),
        );
      }
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rider_name', name);
    await prefs.setString('pizzeria_id', pizzeriaId);
    
    setState(() {
      _isConfigured = true;
    });
  }

  Future<void> _resetConfiguration() async {
    await _stopTracking();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('rider_name');
    await prefs.remove('pizzeria_id');
    setState(() {
      _isConfigured = false;
      _nameController.clear();
      _pizzeriaController.clear();
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _overlayListener?.cancel();
    _nameController.dispose();
    _pizzeriaController.dispose();
    FlutterOverlayWindow.closeOverlay();
    super.dispose();
  }

  Future<void> _toggleTracking(String status) async {
    if (!_isConfigured) return;

    final String name = _nameController.text.trim();
    final String pizzeriaId = _pizzeriaController.text.trim();

    if (_currentStatus == status) {
      await _stopTracking();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      LoggerService().log('Avvio tracking per: $status');
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        LoggerService().log('Richiedo permessi GPS...');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permessi GPS negati');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Permessi GPS negati permanentemente. Abilitali dalle impostazioni.');
      }

      LoggerService().log('Fermo tracking precedente...');
      await _stopTracking();

      late final LocationSettings locationSettings;
      
      if (Theme.of(context).platform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 30,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "Il tracking della tua posizione è attivo per la pizzeria.",
            notificationTitle: "Dove Rider: In Servizio",
            enableWakeLock: true,
          ),
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 30,
        );
      }

      LoggerService().log('Avvio stream GPS...');
      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (Position position) {
          _updateFirestorePosition(pizzeriaId, name, status, position);
        },
        onError: (e) {
          LoggerService().log('Errore Stream GPS: $e');
        },
      );

      LoggerService().log('Ottengo posizione iniziale...');
      Position initialPosition;
      try {
        initialPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
        ).timeout(const Duration(seconds: 5), onTimeout: () {
          LoggerService().log('TIMEOUT GPS! Uso ultima nota.');
          return Geolocator.getLastKnownPosition().then((val) => val ?? Position(latitude: 0, longitude: 0, timestamp: DateTime.now(), accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0));
        });
      } catch (e) {
        LoggerService().log('Errore GPS iniziale: $e');
        initialPosition = await Geolocator.getLastKnownPosition() ?? 
            Position(latitude: 0, longitude: 0, timestamp: DateTime.now(), accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0);
      }
      
      LoggerService().log('Aggiorno Firestore iniziale...');
      await _updateFirestorePosition(pizzeriaId, name, status, initialPosition);

      /* Temporaneamente disabilitato per debug hang
      LoggerService().log('Controllo permessi Overlay...');
      if (await FlutterOverlayWindow.isPermissionGranted()) {
        LoggerService().log('Mostro Overlay...');
        await FlutterOverlayWindow.showOverlay(
          enableDrag: true,
          overlayTitle: "Dove Rider Status",
          overlayContent: "Bolla per cambio stato rapido",
          flag: OverlayFlag.defaultFlag,
          visibility: NotificationVisibility.visibilityPublic,
          height: 150, 
          width: 150, 
        );
      }
      */

      setState(() {
        _currentStatus = status;
      });
      LoggerService().log('Tracking attivato con successo');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tracking attivato: $status'),
            backgroundColor: status == 'consegna' ? Colors.green : Colors.blue,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _stopTracking() async {
    LoggerService().log('Eseguo _stopTracking...');
    try {
      await _positionStream?.cancel();
      _positionStream = null;
    } catch (e) {
      LoggerService().log('Errore cancellazione stream: $e');
    }

    try {
      // Chiudiamo l'overlay in modo asincrono senza attenderlo se rischia di bloccare
      FlutterOverlayWindow.closeOverlay().catchError((e) => LoggerService().log('Errore chiusura overlay: $e'));
    } catch (e) {
      LoggerService().log('Eccezione chiusura overlay: $e');
    }
    
    final String name = _nameController.text.trim();
    final String pizzeriaId = _pizzeriaController.text.trim();
    
    if (name.isNotEmpty && pizzeriaId.isNotEmpty && _currentStatus != 'offline') {
      LoggerService().log('Aggiorno Firestore a offline...');
      try {
        await _firestore
            .collection('pizzerie')
            .doc(pizzeriaId)
            .collection('riders')
            .doc(name)
            .update({
          'status': 'offline',
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        LoggerService().log('Errore aggiornamento Firestore offline: $e');
      }
    }

    if (mounted) {
      setState(() {
        _currentStatus = 'offline';
      });
    }
    LoggerService().log('_stopTracking completato.');
  }

  Future<void> _updateFirestorePosition(String pizzeriaId, String name, String status, Position position) async {
    try {
      await _firestore
          .collection('pizzerie')
          .doc(pizzeriaId)
          .collection('riders')
          .doc(name)
          .set({
        'name': name,
        'status': status,
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      LoggerService().log('Posizione aggiornata ($pizzeriaId - $name): ${position.latitude}, ${position.longitude}');
    } catch (e) {
      LoggerService().log('Errore aggiornamento Firestore ($pizzeriaId): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isTracking = _currentStatus != 'offline';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Area Rider', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        centerTitle: true,
        actions: [
          if (_isConfigured && !isTracking)
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Cambia Pizzeria/Nome',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Configurazione'),
                    content: const Text('Vuoi resettare il nome e il codice pizzeria?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANNULLA')),
                      TextButton(
                        onPressed: () {
                          _resetConfiguration();
                          Navigator.pop(context);
                        },
                        child: const Text('RESET', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                _isConfigured ? 'Ciao, ${_nameController.text}!' : 'Benvenuto!',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
              ),
              Text(
                _isConfigured 
                  ? 'Pizzeria: ${_pizzeriaController.text}'
                  : 'Configura l\'app per iniziare.',
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 40),
              
              if (!_isConfigured) _buildConfigurationInput() else _buildTrackingControls(isTracking),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigurationInput() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildInputField(
            controller: _pizzeriaController,
            label: 'Codice Pizzeria',
            icon: Icons.storefront,
            hint: 'es. pizzeria_napoli',
          ),
          const SizedBox(height: 20),
          _buildInputField(
            controller: _nameController,
            label: 'Il tuo nome',
            icon: Icons.person_outline,
            hint: 'es. Marco',
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: _saveConfiguration,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 2,
              ),
              child: const Text('CONFERMA CONFIGURAZIONE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTrackingControls(bool isTracking) {
    if (_isLoading) return const Expanded(child: Center(child: CircularProgressIndicator()));
    
    return Expanded(
      child: Column(
        children: [
          _buildStatusCard(
            title: 'PARTITO PER CONSEGNA',
            subtitle: 'Inizia il viaggio verso il cliente',
            icon: Icons.delivery_dining,
            color: Colors.green,
            active: _currentStatus == 'consegna',
            onTap: () => _toggleTracking('consegna'),
          ),
          const SizedBox(height: 20),
          _buildStatusCard(
            title: 'STO RIENTRANDRO',
            subtitle: 'Torna al ristorante per il prossimo ordine',
            icon: Icons.storefront,
            color: Colors.orange,
            active: _currentStatus == 'rientro',
            onTap: () => _toggleTracking('rientro'),
          ),
          const Spacer(),
          if (isTracking)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: TextButton.icon(
                  onPressed: _stopTracking,
                  icon: const Icon(Icons.stop_circle, color: Colors.red),
                  label: const Text(
                    'TERMINA TURNO',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: active ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? color : Colors.grey.withOpacity(0.2),
            width: 2,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: active ? Colors.white.withOpacity(0.2) : color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: active ? Colors.white : color,
                size: 32,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: active ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: active ? Colors.white.withOpacity(0.8) : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            if (active)
              const Icon(Icons.check_circle, color: Colors.white)
            else
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
