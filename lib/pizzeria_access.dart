import 'package:cloud_firestore/cloud_firestore.dart';

/// Esito della verifica di un codice pizzeria.
enum PizzeriaAccess {
  authorized, // codice presente e attivo
  notAuthorized, // codice assente o disattivato
  networkError, // impossibile verificare (offline / errore)
}

/// Controlla se un codice pizzeria è autorizzato.
///
/// La fonte di verità è la collezione Firestore `pizzerie_autorizzate`:
/// il titolare gestisce la lista dalla console Firebase. Un documento con
/// id = codice pizzeria autorizza l'accesso; rimuoverlo (o impostare il campo
/// `active` a `false`) revoca l'accesso.
Future<PizzeriaAccess> checkPizzeriaAccess(String code) async {
  if (code.isEmpty) return PizzeriaAccess.notAuthorized;
  try {
    final doc = await FirebaseFirestore.instance
        .collection('pizzerie_autorizzate')
        .doc(code)
        .get();
    if (!doc.exists) return PizzeriaAccess.notAuthorized;
    // Autorizzata se esiste e `active` non è esplicitamente false.
    if (doc.data()?['active'] == false) return PizzeriaAccess.notAuthorized;
    return PizzeriaAccess.authorized;
  } catch (e) {
    return PizzeriaAccess.networkError;
  }
}

/// Esito del controllo "c'è posto per un altro rider online?".
enum RiderSlotResult {
  available, // c'è uno slot libero (o il rider è già online)
  full, // limite del piano raggiunto
  error, // impossibile verificare (offline): il chiamante decide
}

/// Numero massimo di rider che possono essere online contemporaneamente per
/// questa pizzeria, in base al piano di abbonamento.
///
/// La fonte è il campo `maxRiders` del documento `pizzerie_autorizzate/{code}`
/// (lo imposti tu dalla console Firebase: Base = 3, Pro = 5, ecc.).
/// Se il campo è assente si considera ILLIMITATO, così i clienti già esistenti
/// non vengono limitati a sorpresa.
Future<int> getMaxRiders(String code) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('pizzerie_autorizzate')
        .doc(code)
        .get();
    final v = doc.data()?['maxRiders'];
    if (v is num) return v.toInt();
  } catch (_) {}
  return 9999; // nessun limite impostato
}

/// Controlla se [riderName] può andare online rispettando il limite del piano.
///
/// Conta i rider attualmente non offline: se [riderName] è già tra questi (sta
/// solo cambiando stato, es. consegna -> rientro) è sempre permesso; altrimenti
/// è permesso solo se il numero di attivi è sotto il massimo del piano.
Future<RiderSlotResult> checkRiderSlot(String code, String riderName) async {
  try {
    final max = await getMaxRiders(code);
    if (max >= 9999) return RiderSlotResult.available; // illimitato
    final snap = await FirebaseFirestore.instance
        .collection('pizzerie')
        .doc(code)
        .collection('riders')
        .where('status', isNotEqualTo: 'offline')
        .get();
    final activeNames = snap.docs.map((d) => d.id).toSet();
    if (activeNames.contains(riderName)) return RiderSlotResult.available;
    if (activeNames.length >= max) return RiderSlotResult.full;
    return RiderSlotResult.available;
  } catch (_) {
    return RiderSlotResult.error;
  }
}

/// Stream che segnala se il codice pizzeria è ancora autorizzato in tempo reale.
/// Emette `false` quando l'accesso viene revocato (documento rimosso o
/// `active: false`) confermato dal server. Usato per fare il logout automatico.
Stream<bool> pizzeriaAuthorizationStream(String code) {
  return FirebaseFirestore.instance
      .collection('pizzerie_autorizzate')
      .doc(code)
      .snapshots()
      .map((snap) {
    // Ignoriamo gli aggiornamenti da cache (offline) per non sloggare per
    // un semplice calo di rete: agiamo solo su conferme dal server.
    if (snap.metadata.isFromCache) return true;
    if (!snap.exists) return false;
    if (snap.data()?['active'] == false) return false;
    return true;
  });
}
