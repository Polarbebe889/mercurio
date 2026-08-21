import 'package:flutter_test/flutter_test.dart';

import 'package:el_bunker/main.dart';

void main() {
  testWidgets('la app arranca en la pantalla de registro sin sesión',
      (tester) async {
    app.token = null;
    await tester.pumpWidget(const ElBunkerApp(arrancandoConSesion: false));
    expect(find.text('EL BUNKER'), findsOneWidget);
  });
}