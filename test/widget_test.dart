import 'package:flutter_test/flutter_test.dart';
import 'package:dove_il_mio_rider/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that our title is present.
    expect(find.text('Dove il mio Rider?'), findsOneWidget);
    expect(find.text('Benvenuto in Dove il mio Rider!'), findsOneWidget);
    expect(find.text('Vai al Tracking'), findsOneWidget);
  });
}
