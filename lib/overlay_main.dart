import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class FloatingBubbleOverlay extends StatefulWidget {
  const FloatingBubbleOverlay({super.key});

  @override
  State<FloatingBubbleOverlay> createState() => _FloatingBubbleOverlayState();
}

class _FloatingBubbleOverlayState extends State<FloatingBubbleOverlay> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: _isExpanded ? 240 : 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 2,
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
      onTap: () => setState(() => _isExpanded = true),
      child: const Center(
        child: Icon(Icons.delivery_dining, color: Colors.blue, size: 30),
      ),
    );
  }

  Widget _buildExpandedView() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildActionButton(
          icon: Icons.local_pizza,
          color: Colors.green,
          label: "CONSEGNA",
          onTap: () => _updateStatus("consegna"),
        ),
        _buildActionButton(
          icon: Icons.restaurant,
          color: Colors.orange,
          label: "RIENTRO",
          onTap: () => _updateStatus("rientro"),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.grey),
          onPressed: () => setState(() => _isExpanded = false),
        ),
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
    );
  }

  void _updateStatus(String status) {
    // Send message to main app to update Firestore
    FlutterOverlayWindow.shareData(status);
    setState(() => _isExpanded = false);
  }
}
