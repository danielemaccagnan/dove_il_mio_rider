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

  @override
  void initState() {
    super.initState();
    debugPrint("OVERLAY ENGINE AVVIATO!");
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: _isExpanded ? 350 : 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
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
    return InkWell(
      onTap: () => _toggleExpand(true),
      child: const Center(
        child: Icon(Icons.delivery_dining, color: Colors.blue, size: 30),
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
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('rider_name');
      final pizzeriaId = prefs.getString('pizzeria_id');

      if (name != null && pizzeriaId != null) {
        await FirebaseFirestore.instance
            .collection('pizzerie')
            .doc(pizzeriaId)
            .collection('riders')
            .doc(name)
            .update({
          'status': status,
          'timestamp': FieldValue.serverTimestamp(),
        });
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
