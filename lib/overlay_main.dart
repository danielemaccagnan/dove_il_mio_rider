import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FloatingBubbleOverlay extends StatefulWidget {
  const FloatingBubbleOverlay({super.key});

  @override
  State<FloatingBubbleOverlay> createState() => _FloatingBubbleOverlayState();
}

class _FloatingBubbleOverlayState extends State<FloatingBubbleOverlay> {
  bool _isExpanded = false;
  String _status = 'offline';
  StreamSubscription? _listener;
  StreamSubscription? _firestoreListener;

  @override
  void initState() {
    super.initState();
    debugPrint("OVERLAY ENGINE AVVIATO!");
    _init();
    // Aggiornamento istantaneo inviato dall'app via shareData (fast-path).
    _listener = FlutterOverlayWindow.overlayListener.listen((event) {
      String? s;
      if (event is String) {
        s = event;
      } else if (event is Map && event['status'] is String) {
        s = event['status'] as String;
      }
      if (s != null && mounted) {
        setState(() => _status = s!);
      }
    });
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // La bolla è un motore separato: forziamo la rilettura da disco per
      // vedere la configurazione scritta dall'app principale.
      await prefs.reload();
      final s = prefs.getString('rider_status');
      if (s != null && mounted) {
        setState(() => _status = s);
      }

      final name = prefs.getString('rider_name');
      final pizzeriaId = prefs.getString('pizzeria_id');

      // FONTE DI VERITÀ: ascolta direttamente il documento Firestore del rider.
      // Così la bolla riflette SEMPRE lo stato reale, da qualunque parte cambi
      // (app, bolla, o un'altra sessione), senza dipendere dai tempi dei
      // messaggi tra i due motori Flutter.
      if (name != null &&
          name.isNotEmpty &&
          pizzeriaId != null &&
          pizzeriaId.isNotEmpty) {
        _firestoreListener = FirebaseFirestore.instance
            .collection('pizzerie')
            .doc(pizzeriaId)
            .collection('riders')
            .doc(name)
            .snapshots()
            .listen(
          (snap) {
            final serverStatus = snap.data()?['status'] as String?;
            if (serverStatus != null && mounted && serverStatus != _status) {
              debugPrint("OVERLAY: stato da Firestore -> $serverStatus");
              setState(() => _status = serverStatus);
            }
          },
          onError: (e) => debugPrint("OVERLAY: errore listener Firestore: $e"),
        );
      }
    } catch (e) {
      debugPrint("OVERLAY: errore init: $e");
    }
  }

  @override
  void dispose() {
    _listener?.cancel();
    _firestoreListener?.cancel();
    super.dispose();
  }

  Color get _statusColor {
    switch (_status) {
      case 'consegna':
        return Colors.green;
      case 'rientro':
        return Colors.orange;
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Da collassata la bolla assume il colore dello stato; da espansa resta
    // bianca per mostrare bene i pulsanti.
    final Color bubbleColor = _isExpanded ? Colors.white : _statusColor;

    return Material(
      color: Colors.transparent,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: _isExpanded ? 350 : 60,
          height: 60,
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: 3,
              ),
            ],
          ),
          child: _isExpanded ? _buildExpandedView() : _buildCollapsedView(),
        ),
      ),
    );
  }

  Widget _buildCollapsedView() {
    // Icona bianca quando la bolla è colorata (in servizio), blu quando è
    // bianca (offline).
    final Color iconColor = _status == 'offline' ? Colors.blue : Colors.white;
    return InkWell(
      onTap: () => _toggleExpand(true),
      child: Center(
        child: Icon(Icons.delivery_dining, color: iconColor, size: 30),
      ),
    );
  }

  Widget _buildExpandedView() {
    return Row(
      children: [
        const SizedBox(width: 15),
        _buildActionButton(
          icon: Icons.local_pizza,
          color: Colors.green,
          label: "CONSEGNA",
          onTap: () => _updateStatus("consegna"),
        ),
        const Spacer(),
        _buildActionButton(
          icon: Icons.restaurant,
          color: Colors.orange,
          label: "RIENTRO",
          onTap: () => _updateStatus("rientro"),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.grey, size: 20),
          onPressed: () => _toggleExpand(false),
        ),
        const SizedBox(width: 5),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(String status) async {
    debugPrint("OVERLAY: Cambio stato a $status...");

    // Feedback immediato sul colore della bolla.
    if (mounted) {
      setState(() => _status = status);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      // Rilettura da disco: la bolla è un motore separato e altrimenti non
      // vedrebbe la configurazione (nome/pizzeria) salvata dall'app.
      await prefs.reload();
      final name = prefs.getString('rider_name');
      final pizzeriaId = prefs.getString('pizzeria_id');
      await prefs.setString('rider_status', status);

      if (name != null && pizzeriaId != null) {
        await FirebaseFirestore.instance
            .collection('pizzerie')
            .doc(pizzeriaId)
            .collection('riders')
            .doc(name)
            .set({
          'name': name,
          'status': status,
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint("OVERLAY: Firestore aggiornato con successo a $status");
      } else {
        debugPrint("OVERLAY: Configurazione mancante!");
      }
    } catch (e) {
      debugPrint("OVERLAY: Errore aggiornamento diretto: $e");
    }

    // Try sharing data as fallback/notification to main app
    FlutterOverlayWindow.shareData(status).catchError((e) => debugPrint("OVERLAY: Fallback shareData fallito"));
    
    await _toggleExpand(false);
  }

  Future<void> _toggleExpand(bool expand) async {
    if (expand) {
      // Allarghiamo la finestra PRIMA di mostrare il contenuto largo
      await FlutterOverlayWindow.resizeOverlay(1000, 300, true);
    }
    
    if (mounted) {
      setState(() => _isExpanded = expand);
    }

    if (!expand) {
      // Restringiamo la finestra DOPO aver nascosto il contenuto largo
      await Future.delayed(const Duration(milliseconds: 250));
      await FlutterOverlayWindow.resizeOverlay(250, 250, true);
    }
  }
}
