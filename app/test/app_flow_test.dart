import 'package:blackwake_isles/app.dart';
import 'package:blackwake_isles/core/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// End-to-end through the UI in offline demo mode: log in, see the haven,
// build a lumber camp, and watch it get built.
void main() {
  testWidgets('a captain can log in and build a lumber camp', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // portrait phone
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: const BlackwakeApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Login screen (demo mode: just a name).
    expect(find.text('Offline demo'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('captain-name')), 'Calico');
    await tester.tap(find.text('Set sail'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // The haven, with the Captain's Quarters and seven empty plots.
    expect(find.text('Calico\'s Haven'), findsOneWidget);
    expect(find.text('Captain\'s Quarters'), findsOneWidget);
    expect(find.text('Build'), findsNWidgets(7));
    expect(find.text('300'), findsOneWidget); // starting timber

    // Build a lumber camp on the first empty plot.
    await tester.tap(find.text('Build').first);
    await tester.pump(); // open the sheet
    await tester.pump(const Duration(milliseconds: 600)); // let it slide in
    expect(find.text('Build on plot 2'), findsOneWidget);

    final buildButton = find.widgetWithText(FilledButton, 'Build').first;
    await tester.ensureVisible(buildButton);
    await tester.tap(buildButton);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Lumber Camp'), findsOneWidget);
    expect(find.textContaining('Lumber Camp → level 1'), findsOneWidget);
    expect(find.text('240'), findsOneWidget); // 300 − 60 timber

    // Leave the widget tree so periodic timers stop.
    await tester.pumpWidget(const SizedBox());
  });
}
