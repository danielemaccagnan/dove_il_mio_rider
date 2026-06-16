import 'package:cloud_firestore/cloud_firestore.dart';

/// Una consegna completata, registrata quando un rider termina una sessione di
/// "consegna" (passa a rientro / pausa / fine turno). Da questi record nascono
/// lo storico, le statistiche e l'export CSV.
class DeliveryRecord {
  final String riderName;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSec;
  final double distanceMeters;

  DeliveryRecord({
    required this.riderName,
    required this.startedAt,
    required this.endedAt,
    required this.durationSec,
    required this.distanceMeters,
  });

  /// Chiave giorno YYYY-MM-DD, comoda per filtrare "oggi".
  String get dateKey {
    final d = startedAt;
    final m = d.month.toString().padLeft(2, '0');
    final g = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$g';
  }

  Map<String, dynamic> toMap() => {
        'riderName': riderName,
        'startedAt': Timestamp.fromDate(startedAt),
        'endedAt': Timestamp.fromDate(endedAt),
        'durationSec': durationSec,
        'distanceMeters': distanceMeters,
        'dateKey': dateKey,
      };

  static DeliveryRecord? fromDoc(Map<String, dynamic> d) {
    final name = d['riderName'] as String?;
    final start = d['startedAt'];
    final end = d['endedAt'];
    if (name == null || start is! Timestamp || end is! Timestamp) return null;
    return DeliveryRecord(
      riderName: name,
      startedAt: start.toDate(),
      endedAt: end.toDate(),
      durationSec: (d['durationSec'] as num?)?.toInt() ?? 0,
      distanceMeters: (d['distanceMeters'] as num?)?.toDouble() ?? 0,
    );
  }
}

CollectionReference<Map<String, dynamic>> _consegneCol(String code) =>
    FirebaseFirestore.instance
        .collection('pizzerie')
        .doc(code)
        .collection('consegne');

/// Registra una consegna completata. È "best effort": se fallisce (offline) non
/// deve mai bloccare il rider — Firestore la sincronizza appena torna la rete.
Future<void> logDelivery(String code, DeliveryRecord record) async {
  try {
    await _consegneCol(code).add(record.toMap());
  } catch (_) {
    // ignorata di proposito: la consegna non è dato critico per il rider
  }
}

/// Scarica le consegne (opzionalmente solo da [since] in poi).
Future<List<DeliveryRecord>> fetchDeliveries(String code, {DateTime? since}) async {
  Query<Map<String, dynamic>> q =
      _consegneCol(code).orderBy('startedAt', descending: true);
  if (since != null) {
    q = q.where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since));
  }
  final snap = await q.get();
  return snap.docs
      .map((d) => DeliveryRecord.fromDoc(d.data()))
      .whereType<DeliveryRecord>()
      .toList();
}

/// Statistiche aggregate per un singolo rider.
class RiderStats {
  final String name;
  int deliveries = 0;
  int totalDurationSec = 0;
  double totalDistanceMeters = 0;

  RiderStats(this.name);

  double get avgDurationMin =>
      deliveries == 0 ? 0 : (totalDurationSec / deliveries) / 60.0;
  double get totalKm => totalDistanceMeters / 1000.0;
}

/// Aggrega le consegne per rider e le ordina per numero di consegne (classifica).
List<RiderStats> aggregateByRider(List<DeliveryRecord> records) {
  final map = <String, RiderStats>{};
  for (final r in records) {
    final s = map.putIfAbsent(r.riderName, () => RiderStats(r.riderName));
    s.deliveries++;
    s.totalDurationSec += r.durationSec;
    s.totalDistanceMeters += r.distanceMeters;
  }
  final list = map.values.toList();
  list.sort((a, b) => b.deliveries.compareTo(a.deliveries));
  return list;
}

/// Costruisce un CSV (apribile in Excel) con una riga per consegna.
String buildDeliveriesCsv(List<DeliveryRecord> records) {
  String two(int n) => n.toString().padLeft(2, '0');
  String fmt(DateTime d) =>
      '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  final buffer = StringBuffer();
  buffer.writeln('Rider,Data,Ora inizio,Ora fine,Durata (min),Distanza (km)');
  for (final r in records) {
    final durMin = (r.durationSec / 60).toStringAsFixed(1);
    final km = (r.distanceMeters / 1000).toStringAsFixed(2);
    // Virgolette sul nome per non rompere il CSV se contiene una virgola.
    buffer.writeln(
      '"${r.riderName}",${r.dateKey},${fmt(r.startedAt).split(' ')[1]},'
      '${fmt(r.endedAt).split(' ')[1]},$durMin,$km',
    );
  }
  return buffer.toString();
}
