import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger_service.dart';

class RiderScreen extends StatefulWidget {
  const RiderScreen({super.key});

  @override
  State<RiderScreen> createState() => _RiderScreenState();
}

class _RiderScreenState extends State<RiderScreen>
    with WidgetsBindingObserver {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _pizzeriaController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  bool _isConfigured = false;
  String _currentStatus = 'offline';
  StreamSubscription<Position>? _positionStream;
  StreamSubscription? _overlayListener;
  StreamSubscription? _statusSubscription;
  bool _isInternalChange = false;

  // Token di generazione: ogni operazione di avvio tracking ne prende uno.
  // Se parte un'altra operazione (stop, reset, altro toggle) il token cambia
  // e l'operazione "vecchia" si annulla invece di re-impostare lo stato.
  // Risolve la race tra _toggleTracking (lungo) e stop/reset.
  int _opGeneration = 0;

  // La bolla galleggiante (flutter_overlay_window) esiste SOLO su Android:
  // iOS non permette finestre sopra altre app. Su iOS saltiamo tutte le
  // chiamate all'overlay, che altrimenti lancerebbero MissingPluginException.
  bool get _overlaySupported => defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConfiguration();
    _initOverlayListener();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Quando l'utente torna nell'app (es. dopo aver concesso il permesso
    // overlay dalle impostazioni di sistema), riproviamo a mostrare la bolla.
    if (state == AppLifecycleState.resumed && _isConfigured) {
      _ensureOverlayIsShown();
    }
  }

  void _initStatusListener(String pizzeriaId, String name) {
    _statusSubscription?.cancel();
    _statusSubscription = _firestore
        .collection('pizzerie')
        .doc(pizzeriaId)
        .collection('riders')
        .doc(name)
        .snapshots()
        .listen((snapshot) {
          if (_isInternalChange) {
            LoggerService().log('Ignoro update Firestore (cambio interno)');
            return;
          }

          final data = snapshot.data();
          final serverStatus = data?['status'] as String?;
          if (serverStatus != null && serverStatus != _currentStatus) {
            LoggerService().log('Sync Firestore -> Local: $serverStatus');
            // If we are offline on Firestore but local is not, we might need to stop tracking
            // But usually this listener is for moving from consegna <-> rientro
            if (serverStatus == 'offline' && _currentStatus != 'offline') {
              _stopTracking(keepOverlay: true);
            } else if (serverStatus != 'offline' &&
                _currentStatus != serverStatus) {
              // If we are switching active statuses
              if (_isConfigured) {
                _toggleTracking(serverStatus);
              }
            }
          }
        });
  }

  void _initOverlayListener() {
    if (!_overlaySupported) return; // iOS: nessuna bolla
    LoggerService().log('Inizializzazione Listener Overlay...');
    _overlayListener = FlutterOverlayWindow.overlayListener.listen((event) {
      LoggerService().log(
        'MESSAGGIO RICEVUTO DALL\'OVERLAY: "$event" (tipo: ${event.runtimeType})',
      );

      String? newStatus;
      if (event is String) {
        newStatus = event;
      } else if (event is Map && event.containsKey('status')) {
        newStatus = event['status'];
      }

      if (newStatus != null) {
        if (!_isConfigured) {
          LoggerService().log(
            'Attenzione: App non ancora configurata, ignoro messaggio.',
          );
          return;
        }

        if (_currentStatus != newStatus) {
          LoggerService().log('ESEGUO CAMBIO STATO DA OVERLAY: $newStatus');
          _toggleTracking(newStatus);
        } else {
          LoggerService().log('Stato già impostato a $newStatus, ignoro.');
        }
      } else {
        LoggerService().log('Ricevuto evento non riconosciuto: $event');
      }
    });
  }

  Future<void> _loadConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('rider_name');
    final savedPizzeria = prefs.getString('pizzeria_id');

    if (savedName != null &&
        savedName.isNotEmpty &&
        savedPizzeria != null &&
        savedPizzeria.isNotEmpty) {
      setState(() {
        _nameController.text = savedName;
        _pizzeriaController.text = savedPizzeria;
        _isConfigured = true;
      });
      _initStatusListener(savedPizzeria, savedName);
      _ensureOverlayIsShown();
    }
  }

  Future<void> _ensureOverlayIsShown() async {
    if (!_overlaySupported) return; // iOS: nessuna bolla
    LoggerService().log('Controllo se mostrare la bolla persistente...');
    try {
      if (await FlutterOverlayWindow.isPermissionGranted()) {
        if (!await FlutterOverlayWindow.isActive()) {
          LoggerService().log('Avvio bolla persistente...');
          await FlutterOverlayWindow.showOverlay(
            enableDrag: true,
            overlayTitle: "Dove Rider Status",
            overlayContent: "Bolla per cambio stato rapido",
            flag: OverlayFlag.defaultFlag,
            visibility: NotificationVisibility.visibilityPublic,
            height: 250,
            width: 250,
          );
        }
      } else {
        LoggerService().log(
          'Permesso overlay mancante per la bolla persistente.',
        );
      }
    } catch (e) {
      LoggerService().log('Errore avvio bolla persistente: $e');
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

    // Permesso GPS richiesto SUBITO, in primo piano. Fondamentale: così quando
    // poi avvii il tracking dalla bolla (con l'app in background) il permesso è
    // già concesso e non serve mostrare alcun dialog — cosa che Android non
    // permette di fare a un'app in background.
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if ((perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permesso posizione necessario: abilitalo per usare il tracking.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }

    // Permesso bolla (solo Android: su iOS la bolla non esiste).
    if (_overlaySupported) {
      final bool status = await FlutterOverlayWindow.isPermissionGranted();
      if (!status) {
        final bool? granted = await FlutterOverlayWindow.requestPermission();
        if (granted != true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Permesso "Spostamento sopra altre app" necessario per la bolla!',
              ),
            ),
          );
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rider_name', name);
    await prefs.setString('pizzeria_id', pizzeriaId);

    setState(() {
      _isConfigured = true;
    });
    _initStatusListener(pizzeriaId, name);
    _ensureOverlayIsShown();
  }

  Future<void> _resetConfiguration() async {
    LoggerService().log('Avvio reset configurazione...');
    _opGeneration++; // annulla qualsiasi operazione di tracking in corso

    // Catturiamo i dati PRIMA di pulire, servono per l'ultimo update Firestore.
    final String name = _nameController.text.trim();
    final String pizzeriaId = _pizzeriaController.text.trim();
    final bool wasActive = _currentStatus != 'offline';

    // 1) Cambiamo SUBITO schermata, prima di qualunque cleanup lento. Così la
    //    UI torna SEMPRE alla configurazione, anche se la pulizia di
    //    GPS/overlay/Firestore è lenta o si blocca (capita su MIUI).
    if (mounted) {
      setState(() {
        _isConfigured = false;
        _currentStatus = 'offline';
        _isLoading = false;
        _nameController.clear();
        _pizzeriaController.clear();
      });
    }
    LoggerService().log('Tornato alla schermata di configurazione.');

    // 2) Cleanup "best effort": non deve mai bloccare il ritorno alla schermata.
    try {
      await _positionStream?.cancel().timeout(const Duration(seconds: 2));
    } catch (e) {
      LoggerService().log('Errore cancel GPS durante reset: $e');
    }
    _positionStream = null;

    try {
      await _statusSubscription?.cancel();
    } catch (e) {
      LoggerService().log('Errore cancel listener durante reset: $e');
    }
    _statusSubscription = null;

    if (_overlaySupported) {
      try {
        await FlutterOverlayWindow.closeOverlay().timeout(
          const Duration(seconds: 2),
        );
      } catch (e) {
        LoggerService().log('Errore closeOverlay durante reset: $e');
      }
    }
    _notifyOverlayStatus('offline');

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('rider_name');
      await prefs.remove('pizzeria_id');
      await prefs.setString('rider_status', 'offline');
    } catch (e) {
      LoggerService().log('Errore rimozione prefs durante reset: $e');
    }

    // Ultimo update a Firestore: il rider risulta offline sulla mappa.
    if (name.isNotEmpty && pizzeriaId.isNotEmpty && wasActive) {
      try {
        await _firestore
            .collection('pizzerie')
            .doc(pizzeriaId)
            .collection('riders')
            .doc(name)
            .set({
              'status': 'offline',
              'timestamp': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        LoggerService().log('Errore Firestore offline durante reset: $e');
      }
    }

    LoggerService().log('Reset completato.');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _overlayListener?.cancel();
    _nameController.dispose();
    _pizzeriaController.dispose();
    if (_overlaySupported) FlutterOverlayWindow.closeOverlay();
    _statusSubscription?.cancel();
    super.dispose();
  }

  /// Stop richiesto dall'utente (pulsante TERMINA TURNO o tap sullo stato
  /// attivo). Incrementa il token così un eventuale _toggleTracking in corso
  /// viene annullato e non riattiva il tracking.
  Future<void> _userStopTracking() async {
    _opGeneration++;
    await _stopTracking();
  }

  Future<void> _toggleTracking(String status) async {
    if (!_isConfigured) return;

    // Premere lo stato già attivo = ferma il turno.
    if (_currentStatus == status) {
      await _userStopTracking();
      return;
    }

    final int myGen = ++_opGeneration;
    final String name = _nameController.text.trim();
    final String pizzeriaId = _pizzeriaController.text.trim();

    _isInternalChange = true;
    if (mounted) setState(() => _isLoading = true);

    StreamSubscription<Position>? newStream;
    try {
      LoggerService().log('Avvio tracking per: $status (gen $myGen)');
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        LoggerService().log('Richiedo permessi GPS...');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permessi GPS negati');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Permessi GPS negati permanentemente. Abilitali dalle impostazioni.',
        );
      }

      if (myGen != _opGeneration) {
        LoggerService().log('Toggle $status annullato (operazione superata).');
        return;
      }

      LoggerService().log('Fermo tracking precedente...');
      await _stopTracking(keepOverlay: true);

      if (myGen != _opGeneration) {
        LoggerService().log('Toggle $status annullato dopo stop precedente.');
        return;
      }

      final LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 30,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText:
                "Il tracking della tua posizione è attivo per la pizzeria.",
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

      LoggerService().log('Ottengo posizione iniziale...');
      final Position initialPosition = await _getInitialPosition();

      // Ultimo controllo prima di "committare": se nel frattempo l'utente ha
      // fermato o resettato, non attiviamo nulla.
      if (myGen != _opGeneration || !mounted) {
        LoggerService().log('Toggle $status annullato prima dell\'attivazione.');
        return;
      }

      LoggerService().log('Avvio stream GPS...');
      newStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          _updateFirestorePosition(pizzeriaId, name, status, position);
        },
        onError: (e) {
          LoggerService().log('Errore Stream GPS: $e');
        },
      );
      _positionStream = newStream;

      setState(() => _currentStatus = status);
      await _persistStatus(status);
      _notifyOverlayStatus(status);
      await _updateFirestorePosition(pizzeriaId, name, status, initialPosition);

      LoggerService().log('Tracking attivato con successo: $status');
    } catch (e) {
      LoggerService().log('Errore _toggleTracking: $e');
      await newStream?.cancel();
      if (identical(newStream, _positionStream)) _positionStream = null;
      if (mounted && myGen == _opGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _isInternalChange = false;
      // Se l'operazione è stata superata da uno stop/reset, non lasciare uno
      // stream "fantasma" attivo che continuerebbe a scrivere su Firestore.
      if (myGen != _opGeneration && newStream != null) {
        await newStream.cancel();
        if (identical(newStream, _positionStream)) _positionStream = null;
      }
      if (mounted && myGen == _opGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Ottiene una posizione iniziale velocemente, con timeout e fallback
  /// all'ultima posizione nota (o 0,0 se nulla è disponibile).
  Future<Position> _getInitialPosition() async {
    Position fallback() => Position(
          latitude: 0,
          longitude: 0,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () async {
          LoggerService().log('TIMEOUT GPS! Uso ultima nota.');
          return await Geolocator.getLastKnownPosition() ?? fallback();
        },
      );
    } catch (e) {
      LoggerService().log('Errore GPS iniziale: $e');
      return await Geolocator.getLastKnownPosition() ?? fallback();
    }
  }

  /// Salva lo stato corrente nelle preferenze (usato anche dalla bolla per
  /// conoscere il colore iniziale).
  Future<void> _persistStatus(String status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rider_status', status);
    } catch (e) {
      LoggerService().log('Errore salvataggio stato: $e');
    }
  }

  /// Notifica la bolla (engine separato) del nuovo stato, così ne aggiorna
  /// il colore (verde = consegna, arancione = rientro).
  void _notifyOverlayStatus(String status) {
    if (!_overlaySupported) return; // iOS: nessuna bolla
    FlutterOverlayWindow.shareData(status).catchError(
      (e) => LoggerService().log('Errore invio stato a overlay: $e'),
    );
  }

  Future<void> _stopTracking({bool keepOverlay = false}) async {
    final bool prevInternalChange = _isInternalChange;
    _isInternalChange = true;
    LoggerService().log('Eseguo _stopTracking (keepOverlay: $keepOverlay)...');
    try {
      final bool wasActive = _currentStatus != 'offline';

      // PRIMA aggiorniamo lo stato locale (la UI esce subito dal tracking e
      // l'icona di reset riappare), POI facciamo il cleanup lento che su alcuni
      // device potrebbe bloccarsi.
      if (mounted && _currentStatus != 'offline') {
        setState(() => _currentStatus = 'offline');
      } else {
        _currentStatus = 'offline';
      }
      _notifyOverlayStatus('offline');

      try {
        await _positionStream?.cancel().timeout(const Duration(seconds: 2));
      } catch (e) {
        LoggerService().log('Errore cancel GPS: $e');
      }
      _positionStream = null;

      if (!keepOverlay && _overlaySupported) {
        try {
          await FlutterOverlayWindow.closeOverlay().timeout(
            const Duration(seconds: 2),
          );
        } catch (e) {
          LoggerService().log('Errore chiusura overlay: $e');
        }
      }

      await _persistStatus('offline');

      final String name = _nameController.text.trim();
      final String pizzeriaId = _pizzeriaController.text.trim();

      if (name.isNotEmpty && pizzeriaId.isNotEmpty && wasActive) {
        LoggerService().log('Aggiorno Firestore a offline...');
        try {
          await _firestore
              .collection('pizzerie')
              .doc(pizzeriaId)
              .collection('riders')
              .doc(name)
              .set({
                'status': 'offline',
                'timestamp': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true))
              .timeout(const Duration(seconds: 3));
        } catch (e) {
          LoggerService().log('Errore aggiornamento Firestore offline: $e');
        }
      }
    } finally {
      // Ripristina il valore precedente invece di forzarlo a false: se questo
      // _stopTracking è stato invocato DENTRO _toggleTracking, il guard deve
      // restare attivo per tutta la durata del toggle. Altrimenti il listener
      // Firestore vede lo stato scritto dalla bolla e re-innesca un toggle
      // concorrente che annulla il primo (la bolla cambiava colore ma il
      // tracking GPS non partiva mai).
      _isInternalChange = prevInternalChange;
      LoggerService().log('_stopTracking completato.');
    }
  }

  Future<void> _updateFirestorePosition(
    String pizzeriaId,
    String name,
    String status,
    Position position,
  ) async {
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
      LoggerService().log(
        'Posizione aggiornata ($pizzeriaId - $name): ${position.latitude}, ${position.longitude}',
      );
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
        title: const Text(
          'Area Rider',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Log di debug',
            onPressed: () async {
              final logs = await LoggerService().getLogs();
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => _RiderLogsScreen(logs: logs),
                  ),
                );
              }
            },
          ),
          if (_isConfigured)
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Cambia Pizzeria/Nome',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Configurazione'),
                    content: const Text(
                      'Vuoi resettare il nome e il codice pizzeria?',
                    ),
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

              if (!_isConfigured)
                _buildConfigurationInput()
              else
                _buildTrackingControls(isTracking),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 2,
              ),
              child: const Text(
                'CONFERMA CONFIGURAZIONE',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
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
            color: Colors.black.withValues(alpha: 0.05),
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
    if (_isLoading) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }

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
                  onPressed: _resetConfiguration,
                  icon: const Icon(Icons.stop_circle, color: Colors.red),
                  label: const Text(
                    'TERMINA TURNO',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
            color: active ? color : Colors.grey.withValues(alpha: 0.2),
            width: 2,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withValues(alpha: 0.2)
                    : color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: active ? Colors.white : color, size: 32),
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
                      color: active
                          ? Colors.white.withValues(alpha: 0.8)
                          : Colors.black54,
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

/// Schermata di debug per leggere/copiare/svuotare i log dell'app.
class _RiderLogsScreen extends StatelessWidget {
  final String logs;
  const _RiderLogsScreen({required this.logs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log di Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copia tutti i log',
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
        child: SelectableText(
          logs.isEmpty ? 'Nessun log presente.' : logs,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.delete),
        label: const Text('Svuota'),
        onPressed: () async {
          await LoggerService().clearLogs();
          if (context.mounted) Navigator.pop(context);
        },
      ),
    );
  }
}
