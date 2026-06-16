import 'package:cloud_firestore/cloud_firestore.dart';

/// Zona di consegna / posizione della pizzeria.
///
/// È il cerchio che il manager disegna sulla mappa intorno al locale. Serve a
/// due cose:
///  - mostrare a colpo d'occhio l'area coperta dai rider;
///  - far scattare il "rientro automatico" del rider e l'avviso di rientro al
///    manager quando un rider rientrante entra nel cerchio.
class DeliveryZone {
  final double lat;
  final double lng;
  final double radius; // in metri

  const DeliveryZone({
    required this.lat,
    required this.lng,
    required this.radius,
  });

  Map<String, dynamic> toMap() => {
        'zoneLat': lat,
        'zoneLng': lng,
        'zoneRadius': radius,
      };

  static DeliveryZone? fromData(Map<String, dynamic>? data) {
    if (data == null) return null;
    final lat = (data['zoneLat'] as num?)?.toDouble();
    final lng = (data['zoneLng'] as num?)?.toDouble();
    final radius = (data['zoneRadius'] as num?)?.toDouble();
    if (lat == null || lng == null || radius == null) return null;
    return DeliveryZone(lat: lat, lng: lng, radius: radius);
  }
}

DocumentReference<Map<String, dynamic>> _pizzeriaDoc(String code) =>
    FirebaseFirestore.instance.collection('pizzerie').doc(code);

/// Legge una volta la zona di consegna della pizzeria (null se non impostata).
Future<DeliveryZone?> loadDeliveryZone(String code) async {
  try {
    final doc = await _pizzeriaDoc(code).get();
    return DeliveryZone.fromData(doc.data());
  } catch (_) {
    return null;
  }
}

/// Salva/aggiorna la zona di consegna (impostata dal manager).
Future<void> saveDeliveryZone(String code, DeliveryZone zone) async {
  await _pizzeriaDoc(code).set(zone.toMap(), SetOptions(merge: true));
}

/// Stream in tempo reale della zona: il rider la riceve appena il manager la
/// imposta o la cambia, senza riavviare l'app.
Stream<DeliveryZone?> deliveryZoneStream(String code) {
  return _pizzeriaDoc(code)
      .snapshots()
      .map((snap) => DeliveryZone.fromData(snap.data()));
}
