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
