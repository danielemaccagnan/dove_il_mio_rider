import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'delivery_log.dart';

/// Storico e statistiche delle consegne per il manager.
/// Mostra una classifica dei rider (n. consegne, tempo medio, km) con filtro
/// Oggi / Tutto e un pulsante per esportare lo storico in CSV.
class StatsScreen extends StatefulWidget {
  final String pizzeriaId;
  const StatsScreen({super.key, required this.pizzeriaId});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _loading = true;
  bool _todayOnly = true;
  List<DeliveryRecord> _all = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final records = await fetchDeliveries(widget.pizzeriaId);
      if (mounted) setState(() => _all = records);
    } catch (_) {
      // lasciamo la lista vuota: lo schermo mostra "nessuna consegna"
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DeliveryRecord> get _filtered {
    if (!_todayOnly) return _all;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    return _all.where((r) => r.startedAt.isAfter(startOfDay)).toList();
  }

  Future<void> _exportCsv() async {
    final records = _filtered;
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna consegna da esportare.')),
      );
      return;
    }
    try {
      final csv = buildDeliveriesCsv(records);
      final dir = await getTemporaryDirectory();
      final suffix = _todayOnly ? 'oggi' : 'tutto';
      final file = File('${dir.path}/consegne_${widget.pizzeriaId}_$suffix.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Storico consegne ${widget.pizzeriaId}',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore export: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final stats = aggregateByRider(filtered);
    final totalDeliveries = filtered.length;
    final totalKm = filtered.fold<double>(0, (s, r) => s + r.distanceMeters) / 1000;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiche consegne'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aggiorna',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Esporta CSV',
            onPressed: _exportCsv,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Oggi')),
                      ButtonSegment(value: false, label: Text('Tutto')),
                    ],
                    selected: {_todayOnly},
                    onSelectionChanged: (s) =>
                        setState(() => _todayOnly = s.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _summaryCard('Consegne', '$totalDeliveries',
                          Icons.delivery_dining, Colors.green),
                      const SizedBox(width: 12),
                      _summaryCard('Km totali', totalKm.toStringAsFixed(1),
                          Icons.route, Colors.blue),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: stats.isEmpty
                      ? Center(
                          child: Text(
                            _todayOnly
                                ? 'Nessuna consegna oggi.'
                                : 'Nessuna consegna registrata.',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        )
                      : ListView.builder(
                          itemCount: stats.length,
                          itemBuilder: (context, i) {
                            final s = stats[i];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _rankColor(i),
                                child: Text('${i + 1}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                              ),
                              title: Text(s.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                '${s.deliveries} consegne · '
                                'media ${s.avgDurationMin.toStringAsFixed(0)} min · '
                                '${s.totalKm.toStringAsFixed(1)} km',
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Color _rankColor(int i) {
    switch (i) {
      case 0:
        return Colors.amber[700]!;
      case 1:
        return Colors.blueGrey;
      case 2:
        return Colors.brown;
      default:
        return Colors.grey;
    }
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
