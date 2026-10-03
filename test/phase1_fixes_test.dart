// main.dart imports dart:html, so run these with: flutter test --platform chrome
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_application_ft_event_timer/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TimerStateModel pausedAt(int seconds) =>
    TimerStateModel.defaults().withTimer(running: false, remainingSeconds: seconds);

Future<void> pumpApp(WidgetTester tester, {Map<String, Object>? saved}) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(saved ?? {});
  await tester.pumpWidget(const BigInkTimerApp());
  await tester.pump(const Duration(milliseconds: 100));
}

/// Removes the app so its periodic ticker is cancelled before the test ends.
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

Finder field(String label) => find.widgetWithText(TextField, label);

Future<Map<String, dynamic>> savedState() async {
  final prefs = await SharedPreferences.getInstance();
  return jsonDecode(prefs.getString(storageKey)!) as Map<String, dynamic>;
}

void main() {
  group('TimerStateModel (#8)', () {
    test('a running timer counts down from a fixed end time', () {
      final running = pausedAt(600).withTimer(running: true, remainingSeconds: 600);
      expect(running.remainingNow, 600);
      expect(
        running.endsAtMillis,
        closeTo(DateTime.now().millisecondsSinceEpoch + 600000, 50),
      );
    });

    test('remainingNow rounds up partial seconds', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final state = pausedAt(0).copyWith(running: true, endsAtMillis: now + 1500);
      expect(state.remainingNow, 2);
    });

    test('adjustedBy keeps the sub-second position of a running timer', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final state = pausedAt(0).copyWith(running: true, endsAtMillis: now + 10400);
      final later = state.adjustedBy(300);
      expect(later.endsAtMillis, state.endsAtMillis + 300000);
      expect(later.running, isTrue);
    });

    test('adjustedBy on a paused or called timer stays paused', () {
      expect(pausedAt(0).adjustedBy(300).remainingNow, 300);
      expect(pausedAt(0).adjustedBy(300).running, isFalse);
      expect(pausedAt(100).adjustedBy(-300).remainingNow, 0);
    });

    test('old saved data without endsAtMillis keeps counting correctly', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final json = pausedAt(0).toJson()
        ..remove('endsAtMillis')
        ..['running'] = true
        ..['remainingSeconds'] = 120
        ..['lastUpdateMillis'] = now - 20000;
      final state = TimerStateModel.fromJson(json);
      expect(state.remainingNow, inInclusiveRange(99, 100));
    });

    test('toJson and fromJson round-trip a running timer', () {
      final running = pausedAt(900).withTimer(running: true, remainingSeconds: 900);
      final restored = TimerStateModel.fromJson(
        jsonDecode(jsonEncode(running.toJson())) as Map<String, dynamic>,
      );
      expect(restored.endsAtMillis, running.endsAtMillis);
      expect(restored.remainingNow, running.remainingNow);
    });
  });

  group('Game names (#9)', () {
    test('unknown saved game falls back to Random', () {
      final json = pausedAt(60).toJson()..['game'] = 'Flesh and Blood';
      expect(TimerStateModel.fromJson(json).game, 'Random');
      expect(normalizeGame('Pokémon'), 'Pokémon');
    });

    testWidgets('timer page renders with an unknown saved game', (tester) async {
      final json = pausedAt(60).toJson()..['game'] = 'Flesh and Blood';
      await pumpApp(tester, saved: {storageKey: jsonEncode(json)});
      expect(tester.takeException(), isNull);
      expect(find.text('Random'), findsWidgets);
      await unmountApp(tester);
    });
  });

  group('Presets (#5, #10)', () {
    test('presets keep their id through JSON and old ones get one', () {
      final preset = EventPreset('Test', 'Pokémon', 'BO1', 30, 3, '1-4');
      final copy = EventPreset.fromJson(preset.toJson());
      expect(copy.id, preset.id);

      final legacy = EventPreset.fromJson(preset.toJson()..remove('id'));
      expect(legacy.id, isNotEmpty);
      expect(legacy.id, isNot(preset.id));
    });

    test('missingDefaults skips defaults already present by id or name', () {
      final defaults = EventPreset.defaultPresets();
      expect(EventPreset.missingDefaults(defaults), isEmpty);

      final legacyCopies = defaults
          .map((p) => EventPreset.fromJson(p.toJson()..remove('id')))
          .toList();
      expect(EventPreset.missingDefaults(legacyCopies), isEmpty);

      expect(EventPreset.missingDefaults([defaults.first]).length, 2);
    });
  });

  group('Control panel (#3, #4, #5, #10, dialogs)', () {
    testWidgets('typed winner names survive Next Round', (tester) async {
      await pumpApp(tester);

      await tester.enterText(field('1st place'), 'Mira K.');
      // Press Next Round before the autosave delay has passed.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Next Round'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Mira K.'), findsOneWidget);
      expect((await savedState())['firstPlace'], 'Mira K.');
      expect((await savedState())['currentRound'], 2);
      await unmountApp(tester);
    });

    testWidgets('field edits save automatically without touching the timer',
        (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 100));
      final endsAt = (await savedState())['endsAtMillis'];

      await tester.enterText(field('Event name'), 'Friday Cup');
      await tester.pump(const Duration(milliseconds: 600));

      final saved = await savedState();
      expect(saved['eventName'], 'Friday Cup');
      expect(saved['running'], isTrue);
      expect(saved['endsAtMillis'], endsAt);
      await unmountApp(tester);
    });

    testWidgets('Next Round in the final round shows the info dialog',
        (tester) async {
      final json = pausedAt(60).copyWith(currentRound: 6, totalRounds: 6).toJson();
      await pumpApp(tester, saved: {storageKey: jsonEncode(json)});

      await tester.tap(find.text('Next Round'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Final round reached'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pump(const Duration(milliseconds: 300));
      await unmountApp(tester);
    });

    testWidgets('deleting a preset can be undone', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Presets'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Commander Night'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Commander Night'), findsNothing);

      // Let the snack bar finish sliding in before tapping its action.
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Undo'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Commander Night'), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('editing survives deleting another preset', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Presets'));
      await tester.pump(const Duration(milliseconds: 300));

      // Edit the last preset, then delete the first one.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit').last);
      await tester.pump();
      await tester.enterText(field('Preset name'), 'Commander Night XL');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Save Edited Preset'));
      await tester.pump(const Duration(milliseconds: 300));

      final prefs = await SharedPreferences.getInstance();
      final names = (jsonDecode(prefs.getString(presetsStorageKey)!) as List)
          .map((p) => (p as Map)['name'])
          .toList();
      expect(names, ['Pokémon Casual Night', 'Commander Night XL']);
      await unmountApp(tester);
    });

    testWidgets('Add Default Presets does not duplicate', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Presets'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Add Default Presets'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Commander Night'), findsOneWidget);
      expect(find.text('All default presets are already in your list.'),
          findsOneWidget);
      await unmountApp(tester);
    });
  });
}
