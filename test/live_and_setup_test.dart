// main.dart imports dart:html, so run these with: flutter test --platform chrome
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_ft_event_timer/live_page.dart';
import 'package:flutter_application_ft_event_timer/main.dart';
import 'package:flutter_application_ft_event_timer/setup_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TimerStateModel pausedAt(int seconds) => TimerStateModel.defaults()
    .withTimer(running: false, remainingSeconds: seconds);

Future<void> pumpApp(WidgetTester tester, {TimerStateModel? state}) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    if (state != null) storageKey: jsonEncode(state.toJson()),
  });
  await tester.pumpWidget(const BigInkTimerApp());
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> settle(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 400));

/// Removes the app so its periodic ticker is cancelled before the test ends.
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

Future<Map<String, dynamic>> savedState() async {
  final prefs = await SharedPreferences.getInstance();
  return jsonDecode(prefs.getString(storageKey)!) as Map<String, dynamic>;
}

Future<void> tapUndo(WidgetTester tester) async {
  // Let the snack bar finish sliding in before tapping its action.
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(find.text('Undo'));
  await settle(tester);
}

Widget playerScreenOf(TimerStateModel state) => MaterialApp(
      home: Scaffold(body: PlayerScreen(state: state)),
    );

void main() {
  group('Model', () {
    test('overtime counts from the moment time was called (#23)', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final running = pausedAt(0).copyWith(
        running: true,
        endsAtMillis: now - 65000,
      );
      final called = running.withTimeCalled();
      expect(called.running, isFalse);
      expect(called.calledAtMillis, now - 65000);
      expect(called.overtimeSeconds, inInclusiveRange(65, 66));

      // Adding time ends the overtime.
      expect(called.adjustedBy(60).overtimeSeconds, 0);
    });

    test('display mode, message and note survive JSON (#21, #22)', () {
      final state = pausedAt(60).copyWith(
        displayMode: DisplayMode.black,
        playerMessage: 'Pairings are up',
        timeCalledNote: '+3 turns',
      );
      final copy = TimerStateModel.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );
      expect(copy.displayMode, DisplayMode.black);
      expect(copy.playerMessage, 'Pairings are up');
      expect(copy.timeCalledNote, '+3 turns');
      expect(DisplayMode.parse('nonsense'), DisplayMode.timer);
    });

    test('progress goes from 1 to 0 over the round', () {
      final state = pausedAt(25 * 60).copyWith(roundLengthMinutes: 50);
      expect(state.progress, closeTo(0.5, 0.001));
    });
  });

  group('Table ranges (#25)', () {
    test('parse ranges, lists and reversed ranges', () {
      expect(parseTableRange('1-3,5'), {1, 2, 3, 5});
      expect(parseTableRange(' 9 – 7 '), {7, 8, 9});
      expect(parseTableRange('3,5,7,'), {3, 5, 7});
    });

    test('reject invalid input', () {
      expect(parseTableRange(''), isNull);
      expect(parseTableRange('1-a'), isNull);
      expect(parseTableRange('0'), isNull);
      expect(parseTableRange('1-2-3'), isNull);
    });

    test('format as compact ranges', () {
      expect(formatTableRange({5, 1, 2, 3, 9, 10}), '1-3,5,9-10');
      expect(formatTableRange({4}), '4');
    });
  });

  group('Player window URL (#11)', () {
    test('query parameter and old #player link both work', () {
      expect(isPlayerWindowUrl(Uri.parse('http://x/?view=player')), isTrue);
      expect(isPlayerWindowUrl(Uri.parse('http://x/?view=player#/')), isTrue);
      expect(isPlayerWindowUrl(Uri.parse('http://x/#player')), isTrue);
      expect(isPlayerWindowUrl(Uri.parse('http://x/#/')), isFalse);
    });
  });

  group('Time input (#18)', () {
    test('minutes or minutes:seconds', () {
      expect(parseTimeInput('25'), 1500);
      expect(parseTimeInput('12:30'), 750);
      expect(parseTimeInput(':45'), 45);
      expect(parseTimeInput('12:75'), isNull);
      expect(parseTimeInput('abc'), isNull);
    });
  });

  group('Live page', () {
    testWidgets('primary button starts and pauses (#17)', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Start'));
      await settle(tester);
      expect((await savedState())['running'], isTrue);
      expect(find.text('Pause'), findsOneWidget);

      await tester.tap(find.text('Pause'));
      await settle(tester);
      expect((await savedState())['running'], isFalse);
      await unmountApp(tester);
    });

    testWidgets('−1 / +1 / +5 adjust the time and can be undone (#18, #19)',
        (tester) async {
      await pumpApp(tester, state: pausedAt(600));
      await tester.tap(find.text('+5'));
      await settle(tester);
      expect((await savedState())['remainingSeconds'], 900);

      await tester.tap(find.text('−1'));
      await settle(tester);
      expect((await savedState())['remainingSeconds'], 840);

      await tapUndo(tester);
      expect((await savedState())['remainingSeconds'], 900);
      await unmountApp(tester);
    });

    testWidgets('clicking the time lets you type a new time (#18)',
        (tester) async {
      await pumpApp(tester, state: pausedAt(600));
      // The first match is the Live page timer; the second is the preview.
      await tester.tap(find.text('10:00').first);
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, '12:30');
      await tester.tap(find.text('Set Time'));
      await settle(tester);
      expect((await savedState())['remainingSeconds'], 750);
      await unmountApp(tester);
    });

    testWidgets('Next Round can be undone (#19)', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Next Round'));
      await settle(tester);
      expect((await savedState())['currentRound'], 2);

      await tapUndo(tester);
      expect((await savedState())['currentRound'], 1);
      await unmountApp(tester);
    });

    testWidgets('final round: Finish Event asks for winners (#26)',
        (tester) async {
      await pumpApp(
        tester,
        state: pausedAt(0).copyWith(currentRound: 6, totalRounds: 6),
      );
      // Time is up in the final round, so the big button finishes the event.
      expect(find.widgetWithText(FilledButton, 'Finish Event'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Event'));
      await settle(tester);

      expect(find.text('Finish event'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '1st place'), 'Mira');
      await tester.enterText(find.widgetWithText(TextField, '2nd place'), 'Jonas');
      await tester.tap(find.text('Show Winners'));
      await settle(tester);

      final saved = await savedState();
      expect(saved['eventFinished'], isTrue);
      expect(saved['displayMode'], 'winners');
      expect(saved['firstPlace'], 'Mira');
      expect(saved['thirdPlace'], '');

      await tapUndo(tester);
      expect((await savedState())['eventFinished'], isFalse);
      await unmountApp(tester);
    });

    testWidgets('keyboard shortcuts (#20)', (tester) async {
      await pumpApp(tester, state: pausedAt(600));

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester);
      expect((await savedState())['running'], isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await settle(tester);
      expect((await savedState())['displayMode'], 'black');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await settle(tester);
      expect((await savedState())['displayMode'], 'timer');

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await settle(tester);
      expect((await savedState())['currentRound'], 2);
      await unmountApp(tester);
    });

    testWidgets('shortcuts are ignored while typing (#20)', (tester) async {
      await pumpApp(tester, state: pausedAt(600));
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await settle(tester);
      expect((await savedState())['currentRound'], 1);
      await unmountApp(tester);
    });

    testWidgets('message to players can be shown and hidden (#21)',
        (tester) async {
      await pumpApp(tester);
      await tester.enterText(find.byType(TextField).first, 'Pairings are up');
      await tester.tap(find.text('Show'));
      await settle(tester);
      expect((await savedState())['playerMessage'], 'Pairings are up');
      // The preview shows it, and it becomes a quick pick.
      expect(find.text('Pairings are up'), findsWidgets);

      await tester.tap(find.text('Hide'));
      await settle(tester);
      expect((await savedState())['playerMessage'], '');
      await unmountApp(tester);
    });

    testWidgets('display mode buttons (#22)', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Black'));
      await settle(tester);
      expect((await savedState())['displayMode'], 'black');
      await tester.tap(find.text('Winners'));
      await settle(tester);
      expect((await savedState())['displayMode'], 'winners');
      await unmountApp(tester);
    });
  });

  group('Player screen', () {
    testWidgets('black mode shows nothing (#22)', (tester) async {
      await tester.pumpWidget(
        playerScreenOf(pausedAt(600).copyWith(displayMode: DisplayMode.black)),
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('message replaces the footer text (#21)', (tester) async {
      await tester.pumpWidget(
        playerScreenOf(pausedAt(600).copyWith(playerMessage: 'Break until 8')),
      );
      expect(find.text('Break until 8'), findsOneWidget);
      expect(find.textContaining('Good luck'), findsNothing);
    });

    testWidgets('time called shows note and overtime (#23)', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await tester.pumpWidget(
        playerScreenOf(
          pausedAt(0).copyWith(
            calledAtMillis: now - 75000,
            timeCalledNote: 'Finish the turn + 3 turns',
          ),
        ),
      );
      expect(find.text('TIME CALLED'), findsOneWidget);
      expect(find.text('Finish the turn + 3 turns'), findsOneWidget);
      expect(find.textContaining('Overtime +01:1'), findsOneWidget);
    });

    testWidgets('podium leaves out empty places (#26)', (tester) async {
      await tester.pumpWidget(
        playerScreenOf(
          pausedAt(0).copyWith(
            eventFinished: true,
            firstPlace: 'Mira',
            secondPlace: 'Jonas',
          ),
        ),
      );
      expect(find.text('Mira'), findsOneWidget);
      expect(find.text('2nd Place'), findsOneWidget);
      expect(find.text('3rd Place'), findsNothing);
      expect(find.text('Winner name'), findsNothing);
    });
  });

  group('Setup', () {
    testWidgets('loading a preset from step 1 starts at round 1 (#24)',
        (tester) async {
      await pumpApp(tester, state: pausedAt(100).copyWith(currentRound: 3));
      await tester.tap(find.text('Setup'));
      await settle(tester);
      await tester.tap(find.text('Commander Night'));
      await settle(tester);

      final saved = await savedState();
      expect(saved['eventName'], 'Commander Night');
      expect(saved['currentRound'], 1);
      expect(saved['remainingSeconds'], 3600);
      // The wizard moves on to the details step.
      expect(find.widgetWithText(TextField, 'Event name'), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('clicking tables updates the table range (#25)',
        (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Setup'));
      await settle(tester);
      await tester.tap(find.text('3 · Tables'));
      await settle(tester);

      // Default is 1-12; remove table 12 and add table 14.
      await tester.tap(find.text('12'));
      await settle(tester);
      await tester.tap(find.text('14'));
      await settle(tester);
      expect((await savedState())['tableRange'], '1-11,14');
      await unmountApp(tester);
    });
  });
}
