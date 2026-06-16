import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Guida in-app per impedire al telefono di "uccidere" l'app a schermo spento.
///
/// Molti telefoni (soprattutto Xiaomi/MIUI, Honor/Huawei, Samsung, OPPO) hanno
/// un risparmio energetico aggressivo che ferma il GPS quando lo schermo è
/// spento. Questa schermata spiega, marca per marca, come disattivarlo.
class BatteryGuideScreen extends StatelessWidget {
  const BatteryGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracking sempre attivo'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Se la posizione si blocca quando metti il telefono in tasca o con '
              'lo schermo spento, è il risparmio energetico del telefono che '
              'ferma l\'app. Segui i passi qui sotto per la tua marca: bastano '
              'una volta sola.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => openAppSettings(),
              icon: const Icon(Icons.settings),
              label: const Text('APRI IMPOSTAZIONI APP'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _brand(
            'Xiaomi / Redmi / POCO (MIUI / HyperOS)',
            const [
              'Impostazioni → App → Gestisci app → "Dov\'è il mio Rider".',
              'Risparmio energia → imposta "Nessuna restrizione".',
              'Avvio automatico → ATTIVALO.',
              'Nelle app recenti, tieni premuta l\'app e tocca il lucchetto per '
                  'bloccarla (non viene chiusa pulendo la memoria).',
            ],
          ),
          _brand(
            'Honor / Huawei (EMUI / MagicOS)',
            const [
              'Impostazioni → Batteria → Avvio app.',
              'Trova "Dov\'è il mio Rider" e DISATTIVA "Gestione automatica".',
              'Attiva manualmente: Avvio automatico, Avvio secondario, '
                  'Esecuzione in background.',
            ],
          ),
          _brand(
            'Samsung (One UI)',
            const [
              'Impostazioni → Batteria → Limiti uso in background.',
              'Aggiungi l\'app a "App che non verranno mai sospese".',
              'Impostazioni → App → l\'app → Batteria → "Senza restrizioni".',
            ],
          ),
          _brand(
            'OPPO / Realme / OnePlus (ColorOS)',
            const [
              'Impostazioni → Batteria → consumo energetico in background.',
              'Consenti attività in background per l\'app.',
              'Avvio automatico → ATTIVALO.',
            ],
          ),
          _brand(
            'Android "puro" (Pixel, Motorola, ecc.)',
            const [
              'Impostazioni → App → l\'app → Batteria.',
              'Imposta "Senza restrizioni" / "Non ottimizzata".',
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Suggerimento: tieni anche la batteria sopra il 15% — sotto, alcuni '
            'telefoni spengono tutto a prescindere.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _brand(String title, List<String> steps) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.phone_android),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (int i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${i + 1}. ',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(child: Text(steps[i], style: const TextStyle(height: 1.3))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
