import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const storageKey = 'big_ink_tcg_timer_v1';
const presetsStorageKey = 'big_ink_tcg_timer_presets_v1';
const appVersion = 'V1.2.3 Alena';

void main() => runApp(const BigInkTimerApp());

class BigInkTimerApp extends StatefulWidget {
  const BigInkTimerApp({super.key});

  @override
  State<BigInkTimerApp> createState() => _BigInkTimerAppState();
}

class _BigInkTimerAppState extends State<BigInkTimerApp> {
  TimerStateModel state = TimerStateModel.defaults();
  List<EventPreset> presets = EventPreset.defaultPresets();
  SharedPreferences? prefs;
  Timer? ticker;
  StreamSubscription<html.Event>? fullscreenSubscription;
  final FocusNode keyboardFocusNode = FocusNode();

  int page = 0;
  late final bool playerOnly;

  final eventName = TextEditingController();
  final roundLength = TextEditingController();
  final currentRound = TextEditingController();
  final totalRounds = TextEditingController();
  final tableRange = TextEditingController();
  final tableCount = TextEditingController();
  final firstPlace = TextEditingController();
  final secondPlace = TextEditingController();
  final thirdPlace = TextEditingController();

  @override
  void initState() {
    super.initState();
    playerOnly = Uri.base.fragment.toLowerCase().contains('player');
    _syncTextFields();
    _load();

    fullscreenSubscription = html.document.onFullscreenChange.listen((_) {
      if (!playerOnly && page == 1 && html.document.fullscreenElement == null) {
        setState(() => page = 0);
      }
    });

    ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (playerOnly) await _reloadForPlayerScreen();

      if (state.running && state.remainingNow <= 0) {
        await _setStateModel(
          state.snapshot().copyWith(running: false, remainingSeconds: 0),
        );
      }

      if (mounted) setState(() {});
    });
  }

  void openPlayerScreenFullscreen() {
    setState(() => page = 1);

    // This works for Flutter Web in Chrome/Edge.
    // Browsers allow fullscreen only directly after a user action,
    // so we call it immediately when the Player Screen navigation item is pressed.
    html.document.documentElement?.requestFullscreen();

    keyboardFocusNode.requestFocus();
  }

  Future<void> exitPlayerScreenToSetup() async {
    if (html.document.fullscreenElement != null) {
      html.document.exitFullscreen();
    }

    if (!playerOnly && mounted) {
      setState(() => page = 0);
    }
  }

  KeyEventResult handleKeyboard(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (!playerOnly && page == 1) {
        exitPlayerScreenToSetup();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    ticker?.cancel();
    fullscreenSubscription?.cancel();
    keyboardFocusNode.dispose();
    eventName.dispose();
    roundLength.dispose();
    currentRound.dispose();
    totalRounds.dispose();
    tableRange.dispose();
    tableCount.dispose();
    firstPlace.dispose();
    secondPlace.dispose();
    thirdPlace.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    prefs = await SharedPreferences.getInstance();

    final raw = prefs!.getString(storageKey);
    if (raw == null) {
      await _save();
    } else {
      try {
        state =
            TimerStateModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        state = TimerStateModel.defaults();
      }
    }

    await _loadPresets();
    _syncTextFields();
    if (mounted) setState(() {});
  }

  Future<void> _loadPresets() async {
    prefs ??= await SharedPreferences.getInstance();
    final raw = prefs!.getString(presetsStorageKey);

    if (raw == null) {
      presets = EventPreset.defaultPresets();
      await _savePresets();
      return;
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      presets = decoded
          .map((item) => EventPreset.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      presets = EventPreset.defaultPresets();
      await _savePresets();
    }
  }

  Future<void> _reloadForPlayerScreen() async {
    prefs ??= await SharedPreferences.getInstance();
    await prefs!.reload();
    final raw = prefs!.getString(storageKey);
    if (raw == null) return;

    try {
      state = TimerStateModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Keep current state if saved data is broken.
    }
  }

  Future<void> _save() async {
    prefs ??= await SharedPreferences.getInstance();
    await prefs!.setString(storageKey, jsonEncode(state.toJson()));
  }

  Future<void> _savePresets() async {
    prefs ??= await SharedPreferences.getInstance();
    final encoded =
        jsonEncode(presets.map((preset) => preset.toJson()).toList());
    await prefs!.setString(presetsStorageKey, encoded);
  }

  Future<void> _setPresets(List<EventPreset> next) async {
    setState(() => presets = next);
    await _savePresets();
  }

  Future<void> _setStateModel(
    TimerStateModel next, {
    bool syncText = false,
  }) async {
    setState(() => state = next.withFreshTimestamp());
    if (syncText) _syncTextFields();
    await _save();
  }

  void _syncTextFields() {
    eventName.text = state.eventName;
    roundLength.text = state.roundLengthMinutes.toString();
    currentRound.text = state.currentRound.toString();
    totalRounds.text = state.totalRounds.toString();
    tableRange.text = state.tableRange;
    tableCount.text = state.tableCount.toString();
    firstPlace.text = state.firstPlace;
    secondPlace.text = state.secondPlace;
    thirdPlace.text = state.thirdPlace;
  }

  int _readInt(TextEditingController controller, int fallback) {
    return int.tryParse(controller.text.trim()) ?? fallback;
  }

  Future<void> applySettings({required bool resetTimer}) async {
    final length =
        clampInt(_readInt(roundLength, state.roundLengthMinutes), 5, 180);
    final nowRemaining = resetTimer ? length * 60 : state.remainingNow;

    await _setStateModel(
      state.snapshot().copyWith(
            eventName: eventName.text.trim().isEmpty
                ? 'TCG Event'
                : eventName.text.trim(),
            roundLengthMinutes: length,
            currentRound:
                clampInt(_readInt(currentRound, state.currentRound), 1, 99),
            totalRounds:
                clampInt(_readInt(totalRounds, state.totalRounds), 1, 99),
            tableRange: tableRange.text.trim().isEmpty
                ? '1-12'
                : tableRange.text.trim(),
            tableCount:
                clampInt(_readInt(tableCount, state.tableCount), 1, 120),
            firstPlace: firstPlace.text.trim(),
            secondPlace: secondPlace.text.trim(),
            thirdPlace: thirdPlace.text.trim(),
            eventFinished: resetTimer ? false : state.eventFinished,
            remainingSeconds: nowRemaining,
          ),
    );
  }

  Future<void> changeGame(String value) async {
    await _setStateModel(state.snapshot().copyWith(game: value));
  }

  Future<void> changeMatchFormat(String value) async {
    await _setStateModel(
      state.snapshot().copyWith(matchFormat: normalizeMatchFormat(value)),
    );
  }

  Future<void> changeLogoMode(bool value) async {
    await _setStateModel(state.snapshot().copyWith(useCustomLogo: value));
  }

  Future<void> toggleTimer() async {
    if (state.eventFinished) return;

    final snap = state.snapshot();
    await _setStateModel(
      snap.copyWith(
        running: snap.remainingSeconds > 0 ? !snap.running : false,
      ),
    );
  }

  Future<void> addFiveMinutes() async {
    final snap = state.snapshot();
    await _setStateModel(
      snap.copyWith(remainingSeconds: snap.remainingSeconds + 300),
    );
  }

  Future<void> resetTimer() async {
    final confirmed = await showConfirmDialog(
      title: 'Reset timer?',
      message:
          'This will stop the timer and reset it to the full round length. The event will no longer be marked as finished.',
      confirmText: 'Reset Timer',
      confirmColor: const Color(0xFFFB7185),
    );

    if (!confirmed) return;

    await _setStateModel(
      state.copyWith(
        running: false,
        eventFinished: false,
        remainingSeconds: state.roundLengthMinutes * 60,
      ),
    );
  }

  Future<bool> showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    Color? confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: confirmColor == null
                  ? null
                  : FilledButton.styleFrom(backgroundColor: confirmColor),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<void> showInfoDialog({
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> nextRound() async {
    if (state.eventFinished) return;

    if (state.currentRound >= state.totalRounds) {
      // Do not finish the event through Next Round anymore.
      // Finish Event is now the only button that ends the event
      // and opens the Winner Screen.
      await showInfoDialog(
        title: 'Final round reached',
        message:
            'This is already the final round. Use the Finish Event button to end the event and show the winner screen.',
      );
      return;
    }

    final next = state.currentRound + 1;

    // Simple direct action: no confirmation dialog here.
    // This avoids the earlier issue where the confirmation popup could block
    // the button flow in the browser/Electron build.
    await _setStateModel(
      state.copyWith(
        currentRound: next,
        running: false,
        eventFinished: false,
        remainingSeconds: state.roundLengthMinutes * 60,
      ),
      syncText: true,
    );
  }

  Future<void> finishEventManually() async {
    if (state.eventFinished) return;

    // Save the winner names before ending the event.
    // The Winner Screen reads these values from TimerStateModel.
    await _setStateModel(
      state.snapshot().copyWith(
            running: false,
            eventFinished: true,
            remainingSeconds: 0,
            firstPlace: firstPlace.text.trim(),
            secondPlace: secondPlace.text.trim(),
            thirdPlace: thirdPlace.text.trim(),
          ),
      syncText: true,
    );

    // Automatically switch to the Player Screen.
    // Because eventFinished is now true, PlayerScreen will show WinnerScreen.
    if (!playerOnly && mounted) {
      setState(() => page = 1);
      keyboardFocusNode.requestFocus();
    }
  }

  Future<void> loadPreset(EventPreset preset) async {
    await _setStateModel(
      state.copyWith(
        eventName: preset.name,
        game: preset.game,
        matchFormat: preset.matchFormat,
        roundLengthMinutes: preset.roundLengthMinutes,
        currentRound: 1,
        totalRounds: preset.rounds,
        tableRange: preset.tables,
        eventFinished: false,
        firstPlace: '',
        secondPlace: '',
        thirdPlace: '',
        remainingSeconds: preset.roundLengthMinutes * 60,
        running: false,
      ),
      syncText: true,
    );
  }

  Future<EventPreset?> showPresetEditorDialog({
    required String title,
    EventPreset? preset,
  }) async {
    final nameController = TextEditingController(
      text: preset?.name ?? eventName.text.trim(),
    );
    final roundLengthController = TextEditingController(
      text: (preset?.roundLengthMinutes ??
              clampInt(_readInt(roundLength, state.roundLengthMinutes), 5, 180))
          .toString(),
    );
    final roundsController = TextEditingController(
      text: (preset?.rounds ??
              clampInt(_readInt(totalRounds, state.totalRounds), 1, 99))
          .toString(),
    );
    final tablesController = TextEditingController(
      text: preset?.tables ?? tableRange.text.trim(),
    );
    String selectedGame = preset?.game ?? state.game;
    String selectedMatchFormat = preset?.matchFormat ?? state.matchFormat;

    try {
      return await showDialog<EventPreset>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(title),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Preset name',
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedGame,
                          decoration: const InputDecoration(labelText: 'Game'),
                          items: gameOptions
                              .map(
                                (game) => DropdownMenuItem(
                                  value: game,
                                  child: Text(game),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() => selectedGame = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedMatchFormat,
                          decoration:
                              const InputDecoration(labelText: 'Match format'),
                          items: matchFormatOptions
                              .map(
                                (format) => DropdownMenuItem(
                                  value: format,
                                  child: Text(format),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() => selectedMatchFormat = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: roundLengthController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Round length in minutes',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: roundsController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Total rounds',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: tablesController,
                          decoration: const InputDecoration(
                            labelText: 'Tables used',
                            hintText: '1-12 or 1-6,9-12',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      final presetName = nameController.text.trim().isEmpty
                          ? 'New Event Preset'
                          : nameController.text.trim();
                      final presetRoundLength = clampInt(
                        int.tryParse(roundLengthController.text.trim()) ??
                            state.roundLengthMinutes,
                        5,
                        180,
                      );
                      final presetRounds = clampInt(
                        int.tryParse(roundsController.text.trim()) ??
                            state.totalRounds,
                        1,
                        99,
                      );
                      final presetTables = tablesController.text.trim().isEmpty
                          ? '1-12'
                          : tablesController.text.trim();

                      Navigator.of(dialogContext).pop(
                        EventPreset(
                          presetName,
                          selectedGame,
                          selectedMatchFormat,
                          presetRoundLength,
                          presetRounds,
                          presetTables,
                        ),
                      );
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('Save Preset'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      nameController.dispose();
      roundLengthController.dispose();
      roundsController.dispose();
      tablesController.dispose();
    }
  }

  Future<void> saveCurrentSetupAsPreset() async {
    final created = EventPreset(
      eventName.text.trim().isEmpty ? state.eventName : eventName.text.trim(),
      state.game,
      state.matchFormat,
      clampInt(_readInt(roundLength, state.roundLengthMinutes), 5, 180),
      clampInt(_readInt(totalRounds, state.totalRounds), 1, 99),
      tableRange.text.trim().isEmpty
          ? state.tableRange
          : tableRange.text.trim(),
    );

    await _setPresets([...presets, created]);
  }

  Future<void> createPreset(EventPreset preset) async {
    await _setPresets([...presets, preset]);
  }

  Future<void> updatePreset(int index, EventPreset preset) async {
    if (index < 0 || index >= presets.length) return;
    final next = [...presets];
    next[index] = preset;
    await _setPresets(next);
  }

  Future<void> deletePresetDirect(int index) async {
    if (index < 0 || index >= presets.length) return;
    final next = [...presets]..removeAt(index);
    await _setPresets(next);
  }

  Future<void> restoreDefaultPresetsDirect() async {
    await _setPresets([...presets, ...EventPreset.defaultPresets()]);
  }

  Future<void> editPreset(int index) async {
    if (index < 0 || index >= presets.length) return;

    final edited = await showPresetEditorDialog(
      preset: presets[index],
      title: 'Edit preset',
    );

    if (edited == null) return;

    final next = [...presets];
    next[index] = edited;
    await _setPresets(next);
  }

  Future<void> deletePreset(int index) async {
    if (index < 0 || index >= presets.length) return;

    final confirmed = await showConfirmDialog(
      title: 'Delete preset?',
      message:
          'This will delete "${presets[index].name}" from your saved presets.',
      confirmText: 'Delete Preset',
      confirmColor: const Color(0xFFFB7185),
    );

    if (!confirmed) return;

    final next = [...presets]..removeAt(index);
    await _setPresets(next);
  }

  Future<void> restoreDefaultPresets() async {
    final confirmed = await showConfirmDialog(
      title: 'Restore default presets?',
      message:
          'This will add the default Big Ink presets back into your preset list.',
      confirmText: 'Restore Defaults',
      confirmColor: const Color(0xFF5FB3FF),
    );

    if (!confirmed) return;

    await _setPresets([...presets, ...EventPreset.defaultPresets()]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF5FB3FF),
      scaffoldBackgroundColor: const Color(0xFF071120),
      fontFamily: 'Arial',
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Big Ink TCG Timer',
      theme: theme,
      home: playerOnly
          ? PlayerScreen(state: state)
          : Scaffold(
              body: Focus(
                focusNode: keyboardFocusNode,
                autofocus: true,
                onKeyEvent: handleKeyboard,
                child: SafeArea(
                  child: Row(
                    children: [
                      if (page != 1)
                        NavigationRail(
                          selectedIndex: page,
                          extended: MediaQuery.of(context).size.width > 1050,
                          onDestinationSelected: (value) {
                            if (value == 1) {
                              openPlayerScreenFullscreen();
                            } else {
                              setState(() => page = value);
                            }
                          },
                          backgroundColor: Colors.black.withOpacity(0.25),
                          destinations: const [
                            NavigationRailDestination(
                              icon: Icon(Icons.timer_outlined),
                              selectedIcon: Icon(Icons.timer),
                              label: Text('Timer'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.tv_outlined),
                              selectedIcon: Icon(Icons.tv),
                              label: Text('Player Screen'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.grid_view_outlined),
                              selectedIcon: Icon(Icons.grid_view),
                              label: Text('Tables'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.event_outlined),
                              selectedIcon: Icon(Icons.event),
                              label: Text('Presets'),
                            ),
                          ],
                        ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: [
                            AdminTimerPage(
                              key: const ValueKey('timer'),
                              state: state,
                              eventName: eventName,
                              roundLength: roundLength,
                              currentRound: currentRound,
                              totalRounds: totalRounds,
                              tableRange: tableRange,
                              tableCount: tableCount,
                              firstPlace: firstPlace,
                              secondPlace: secondPlace,
                              thirdPlace: thirdPlace,
                              onApplyReset: () =>
                                  applySettings(resetTimer: true),
                              onApplySave: () =>
                                  applySettings(resetTimer: false),
                              onGameChanged: changeGame,
                              onMatchFormatChanged: changeMatchFormat,
                              onUseCustomLogoChanged: changeLogoMode,
                              onToggle: toggleTimer,
                              onAddFive: addFiveMinutes,
                              onReset: resetTimer,
                              onNextRound: nextRound,
                              onFinishEvent: finishEventManually,
                            ),
                            PlayerScreen(
                              key: const ValueKey('player'),
                              state: state,
                            ),
                            TablesPage(
                              key: const ValueKey('tables'),
                              state: state,
                            ),
                            PresetsPage(
                              key: const ValueKey('presets'),
                              presets: presets,
                              onLoadPreset: loadPreset,
                              onSaveCurrentPreset: saveCurrentSetupAsPreset,
                              onCreatePreset: createPreset,
                              onUpdatePreset: updatePreset,
                              onDeletePreset: deletePresetDirect,
                              onRestoreDefaults: restoreDefaultPresetsDirect,
                            ),
                          ][page],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class AdminTimerPage extends StatelessWidget {
  const AdminTimerPage({
    required this.state,
    required this.eventName,
    required this.roundLength,
    required this.currentRound,
    required this.totalRounds,
    required this.tableRange,
    required this.tableCount,
    required this.firstPlace,
    required this.secondPlace,
    required this.thirdPlace,
    required this.onApplyReset,
    required this.onApplySave,
    required this.onGameChanged,
    required this.onMatchFormatChanged,
    required this.onUseCustomLogoChanged,
    required this.onToggle,
    required this.onAddFive,
    required this.onReset,
    required this.onNextRound,
    required this.onFinishEvent,
    super.key,
  });

  final TimerStateModel state;
  final TextEditingController eventName;
  final TextEditingController roundLength;
  final TextEditingController currentRound;
  final TextEditingController totalRounds;
  final TextEditingController tableRange;
  final TextEditingController tableCount;
  final TextEditingController firstPlace;
  final TextEditingController secondPlace;
  final TextEditingController thirdPlace;
  final Future<void> Function() onApplyReset;
  final Future<void> Function() onApplySave;
  final Future<void> Function(String value) onGameChanged;
  final Future<void> Function(String value) onMatchFormatChanged;
  final Future<void> Function(bool value) onUseCustomLogoChanged;
  final Future<void> Function() onToggle;
  final Future<void> Function() onAddFive;
  final Future<void> Function() onReset;
  final Future<void> Function() onNextRound;
  final Future<void> Function() onFinishEvent;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Timer Control',
      subtitle: 'Admin screen for your TCG event · $appVersion',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 950;
          return Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              SizedBox(
                width: wide
                    ? constraints.maxWidth * 0.57 - 10
                    : constraints.maxWidth,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              state.eventName,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          StatusBadge(
                            text: state.status,
                            color: state.statusColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.eventFinished
                            ? '${state.game} · ${state.matchFormat} · EVENT FINISHED · Tables ${state.tableRange}'
                            : '${state.game} · ${state.matchFormat} · Round ${state.currentRound}/${state.totalRounds} · Tables ${state.tableRange}',
                        style: softText,
                      ),
                      if (state.isFinalRound && !state.eventFinished) ...[
                        const SizedBox(height: 10),
                        const FinalRoundNotice(),
                      ],
                      if (state.eventFinished) ...[
                        const SizedBox(height: 10),
                        const EventFinishedNotice(),
                      ],
                      const SizedBox(height: 36),
                      Center(
                        child: FittedBox(
                          child: Text(
                            state.eventFinished
                                ? 'DONE'
                                : formatSeconds(state.remainingNow),
                            style: TextStyle(
                              fontSize: 130,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -8,
                              color: state.timerColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: onToggle,
                            icon: Icon(
                              state.running ? Icons.pause : Icons.play_arrow,
                            ),
                            label: Text(state.running ? 'Pause' : 'Start'),
                          ),
                          OutlinedButton.icon(
                            onPressed: onAddFive,
                            icon: const Icon(Icons.add),
                            label: const Text('+5 Min'),
                          ),
                          OutlinedButton.icon(
                            onPressed: onNextRound,
                            icon: const Icon(Icons.skip_next),
                            label: const Text('Next Round'),
                          ),
                          OutlinedButton.icon(
                            onPressed: onFinishEvent,
                            icon: const Icon(Icons.emoji_events_outlined),
                            label: const Text('Finish Event'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: wide
                    ? constraints.maxWidth * 0.43 - 10
                    : constraints.maxWidth,
                child: AppCard(
                  child: Column(
                    children: [
                      TextField(
                        controller: eventName,
                        decoration:
                            const InputDecoration(labelText: 'Event name'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: state.game,
                        decoration: const InputDecoration(labelText: 'Game'),
                        items: const [
                          DropdownMenuItem(
                            value: 'Disney Lorcana',
                            child: Text('Disney Lorcana'),
                          ),
                          DropdownMenuItem(
                            value: 'Pokémon',
                            child: Text('Pokémon'),
                          ),
                          DropdownMenuItem(
                            value: 'Magic Commander',
                            child: Text('Magic Commander'),
                          ),
                          DropdownMenuItem(
                            value: 'Yu-Gi-Oh!',
                            child: Text('Yu-Gi-Oh!'),
                          ),
                          DropdownMenuItem(
                            value: 'Random',
                            child: Text('Random'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) onGameChanged(value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: normalizeMatchFormat(state.matchFormat),
                        decoration:
                            const InputDecoration(labelText: 'Match format'),
                        items: matchFormatOptions
                            .map(
                              (format) => DropdownMenuItem(
                                value: format,
                                child: Text(format),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) onMatchFormatChanged(value);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: roundLength,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Round length in minutes',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: currentRound,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Current round',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: totalRounds,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Total rounds',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tableRange,
                        decoration: const InputDecoration(
                          labelText: 'Tables used',
                          hintText: '1-12 or 1-6,9-12',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tableCount,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Total tables in store',
                        ),
                      ),
                      const SizedBox(height: 18),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Use custom logo PNG',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: const Text(
                          'Off = BI logo. On = Big Ink logo.',
                          style: softText,
                        ),
                        value: state.useCustomLogo,
                        onChanged: onUseCustomLogoChanged,
                      ),
                      const SizedBox(height: 18),
                      const Divider(),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Winner Screen',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Enter the top 3 players manually. They will be displayed after the event is finished.',
                        style: softText,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: firstPlace,
                        decoration: const InputDecoration(
                          labelText: '1st place',
                          prefixIcon: Icon(Icons.looks_one_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: secondPlace,
                        decoration: const InputDecoration(
                          labelText: '2nd place',
                          prefixIcon: Icon(Icons.looks_two_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: thirdPlace,
                        decoration: const InputDecoration(
                          labelText: '3rd place',
                          prefixIcon: Icon(Icons.looks_3_outlined),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onApplyReset,
                          icon: const Icon(Icons.check),
                          label: const Text('Apply & Reset Timer'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onApplySave,
                          icon: const Icon(Icons.save),
                          label: const Text('Save Without Reset'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({required this.state, super.key});

  final TimerStateModel state;

  @override
  Widget build(BuildContext context) {
    final remaining = state.remainingNow;

    if (state.eventFinished) {
      return WinnerScreen(state: state);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        // The screen scales based on BOTH width and height.
        // This keeps it readable on a TV, but prevents overflow on smaller screens.
        final widthScale = (width / 1400).clamp(0.70, 1.45).toDouble();
        final heightScale = (height / 850).clamp(0.70, 1.45).toDouble();
        final scale = math.min(widthScale, heightScale);

        final compact = width < 900 || height < 650;

        final outerPadding = compact ? 14.0 : 28.0 * scale;
        final innerPadding = compact ? 22.0 : 42.0 * scale;
        final borderRadius = 34.0 * scale;

        final logoSize = compact ? 52.0 : 74.0 * scale;
        final headerTitleSize = compact ? 20.0 : 28.0 * scale;
        final eventNameSize = compact ? 42.0 : 78.0 * scale;
        final roundSize = compact ? 18.0 : 24.0 * scale;

        // Main timer size.
        // This is the most important number for readability from far away.
        final timerSize = remaining <= 0
            ? (compact ? 96.0 : 170.0 * scale)
            : (compact ? 120.0 : 330.0 * scale);

        final statusTextSize = compact ? 22.0 : 34.0 * scale;
        final instructionTextSize = compact ? 18.0 : 28.0 * scale;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topLeft,
              radius: 1.45,
              colors: [
                state.timerColor.withOpacity(0.28),
                const Color(0xFF06101F),
              ],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(outerPadding),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(color: Colors.white.withOpacity(0.14)),
                color: Colors.white.withOpacity(0.07),
              ),
              padding: EdgeInsets.all(innerPadding),
              child: Column(
                children: [
                  Row(
                    children: [
                      BigInkLogo(
                        size: logoSize,
                        useCustomLogo: state.useCustomLogo,
                      ),
                      SizedBox(width: 18 * scale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'EVENT TIMER',
                              style: TextStyle(
                                fontSize: headerTitleSize,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${state.game} · Tables ${state.tableRange}',
                              style: softText.copyWith(
                                fontSize: compact ? 13 : 16 * scale,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!compact)
                        StatusBadge(
                          text: state.status,
                          color: state.statusColor,
                        ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: width * 0.86,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  state.eventName,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: eventNameSize,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -4 * scale,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 18 * scale),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 10 * scale,
                              runSpacing: 10 * scale,
                              children: [
                                Chip(
                                  label: Text(
                                    'ROUND ${state.currentRound} / ${state.totalRounds}',
                                    style: TextStyle(
                                      fontSize: roundSize,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    normalizeMatchFormat(state.matchFormat),
                                    style: TextStyle(
                                      fontSize: roundSize,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 26 * scale),
                            Text(
                              remaining <= 0
                                  ? 'TIME CALLED'
                                  : formatSeconds(remaining),
                              style: TextStyle(
                                fontSize: timerSize,
                                height: 0.82,
                                fontWeight: FontWeight.w900,
                                letterSpacing:
                                    remaining <= 0 ? -7 * scale : -14 * scale,
                                color: state.timerColor,
                              ),
                            ),
                            SizedBox(height: 18 * scale),
                            Text(
                              remaining <= 0
                                  ? 'Please finish your current turn'
                                  : state.isFinalRound
                                      ? 'Final round in progress'
                                      : remaining <= 300
                                          ? 'Final five minutes'
                                          : 'Round in progress',
                              style: TextStyle(
                                fontSize: statusTextSize,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: 24 * scale,
                      vertical: compact ? 14 : 22 * scale,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24 * scale),
                      color: Colors.black.withOpacity(0.18),
                    ),
                    child: Text(
                      remaining <= 0
                          ? 'Time has been called. Finish the current turn according to event rules, then report your result.'
                          : state.isFinalRound
                              ? 'Final round — good luck, have fun, and report your final result after the round.'
                              : 'Good luck, have fun — please report your result after the round.',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: instructionTextSize,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class FinalRoundNotice extends StatelessWidget {
  const FinalRoundNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFFFACC15).withOpacity(0.12),
        border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.42)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFFACC15)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Final Round — use the Finish Event button when you are ready to show the winner screen.',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class EventFinishedNotice extends StatelessWidget {
  const EventFinishedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF5FB3FF).withOpacity(0.12),
        border: Border.all(color: const Color(0xFF5FB3FF).withOpacity(0.42)),
      ),
      child: const Row(
        children: [
          Icon(Icons.emoji_events_outlined, color: Color(0xFF5FB3FF)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Event Finished — the Player Screen now shows the winner podium.',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class WinnerScreen extends StatelessWidget {
  const WinnerScreen({required this.state, super.key});

  final TimerStateModel state;

  @override
  Widget build(BuildContext context) {
    final firstName = state.firstPlace.trim();
    final secondName = state.secondPlace.trim();
    final thirdName = state.thirdPlace.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final widthScale = (width / 1400).clamp(0.70, 1.45).toDouble();
        final heightScale = (height / 850).clamp(0.70, 1.45).toDouble();
        final scale = math.min(widthScale, heightScale);
        final compact = width < 900 || height < 650;

        final titleSize = compact ? 40.0 : 70.0 * scale;
        final subtitleSize = compact ? 16.0 : 24.0 * scale;
        final podiumNameSize = compact ? 24.0 : 38.0 * scale;
        final podiumPlaceSize = compact ? 16.0 : 24.0 * scale;

        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topLeft,
              radius: 1.45,
              colors: [Color(0x5538BDF8), Color(0xFF06101F)],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 28 * scale),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34 * scale),
                border: Border.all(color: Colors.white.withOpacity(0.14)),
                color: Colors.white.withOpacity(0.07),
              ),
              padding: EdgeInsets.all(compact ? 22 : 42 * scale),
              child: Column(
                children: [
                  Row(
                    children: [
                      BigInkLogo(
                        size: compact ? 52 : 74 * scale,
                        useCustomLogo: state.useCustomLogo,
                      ),
                      SizedBox(width: 18 * scale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'EVENT FINISHED',
                              style: TextStyle(
                                fontSize: compact ? 20 : 28 * scale,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${state.eventName} · ${state.game}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: softText.copyWith(
                                fontSize: compact ? 13 : 16 * scale,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!compact)
                        const StatusBadge(
                          text: 'WINNERS',
                          color: Color(0xFFFACC15),
                        ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.emoji_events,
                              size: compact ? 64 : 108 * scale,
                              color: const Color(0xFFFACC15),
                            ),
                            SizedBox(height: 10 * scale),
                            Text(
                              'WINNER PODIUM',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: titleSize,
                                height: 0.95,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -3.2 * scale,
                              ),
                            ),
                            SizedBox(height: 8 * scale),
                            Text(
                              'Congratulations and thank you for playing!',
                              style: TextStyle(
                                fontSize: subtitleSize,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withOpacity(0.78),
                              ),
                            ),
                            SizedBox(height: 30 * scale),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.end,
                              spacing: 22 * scale,
                              runSpacing: 18 * scale,
                              children: [
                                PodiumCard(
                                  placeLabel: '2nd Place',
                                  name: secondName.isEmpty
                                      ? 'Winner name'
                                      : secondName,
                                  isPlaceholder: secondName.isEmpty,
                                  icon: Icons.looks_two,
                                  width: compact ? 230 : 282 * scale,
                                  height: compact ? 150 : 220 * scale,
                                  nameSize: podiumNameSize,
                                  placeSize: podiumPlaceSize,
                                  accent: const Color(0xFFC0C7D2),
                                ),
                                PodiumCard(
                                  placeLabel: '1st Place',
                                  name: firstName.isEmpty
                                      ? 'Winner name'
                                      : firstName,
                                  isPlaceholder: firstName.isEmpty,
                                  icon: Icons.looks_one,
                                  width: compact ? 245 : 300 * scale,
                                  height: compact ? 180 : 270 * scale,
                                  nameSize: podiumNameSize + 7 * scale,
                                  placeSize: podiumPlaceSize,
                                  accent: const Color(0xFFFACC15),
                                  isChampion: true,
                                ),
                                PodiumCard(
                                  placeLabel: '3rd Place',
                                  name: thirdName.isEmpty
                                      ? 'Winner name'
                                      : thirdName,
                                  isPlaceholder: thirdName.isEmpty,
                                  icon: Icons.looks_3,
                                  width: compact ? 230 : 282 * scale,
                                  height: compact ? 150 : 220 * scale,
                                  nameSize: podiumNameSize,
                                  placeSize: podiumPlaceSize,
                                  accent: const Color(0xFFFB923C),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: 24 * scale,
                      vertical: compact ? 14 : 20 * scale,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24 * scale),
                      color: Colors.black.withOpacity(0.18),
                    ),
                    child: Text(
                      'Congratulations to our winners — and thank you to everyone for playing!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: compact ? 18 : 26 * scale,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PodiumCard extends StatelessWidget {
  const PodiumCard({
    required this.placeLabel,
    required this.name,
    required this.isPlaceholder,
    required this.icon,
    required this.width,
    required this.height,
    required this.nameSize,
    required this.placeSize,
    required this.accent,
    this.isChampion = false,
    super.key,
  });

  final String placeLabel;
  final String name;
  final bool isPlaceholder;
  final IconData icon;
  final double width;
  final double height;
  final double nameSize;
  final double placeSize;
  final Color accent;
  final bool isChampion;

  @override
  Widget build(BuildContext context) {
    final cardRadius = isChampion ? 30.0 : 26.0;

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cardRadius),
        color: accent.withOpacity(isChampion ? 0.18 : 0.13),
        border: Border.all(
          color: accent.withOpacity(isChampion ? 0.70 : 0.45),
          width: isChampion ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(isChampion ? 0.16 : 0.08),
            blurRadius: isChampion ? 28 : 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            placeLabel,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: placeSize,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: width - 44,
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: nameSize,
                      height: 1.02,
                      fontWeight:
                          isPlaceholder ? FontWeight.w700 : FontWeight.w900,
                      color: isPlaceholder
                          ? Colors.white.withOpacity(0.55)
                          : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TablesPage extends StatelessWidget {
  const TablesPage({required this.state, super.key});

  final TimerStateModel state;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Tables',
      subtitle: 'Blue/Yellow/Red = event tables. Green = free tables.',
      child: AppCard(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 1000
                ? 8
                : constraints.maxWidth > 650
                    ? 6
                    : 3;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: state.tableCount,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.35,
              ),
              itemBuilder: (context, index) {
                final table = index + 1;
                final active = state.tableIsActive(table);
                final color =
                    active ? state.timerColor : const Color(0xFF4ADE80);
                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: color.withOpacity(active ? 0.22 : 0.12),
                    border: Border.all(color: color.withOpacity(0.48)),
                  ),
                  child: Center(
                    child: Text(
                      'Table $table',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class PresetsPage extends StatefulWidget {
  const PresetsPage({
    required this.presets,
    required this.onLoadPreset,
    required this.onSaveCurrentPreset,
    required this.onCreatePreset,
    required this.onUpdatePreset,
    required this.onDeletePreset,
    required this.onRestoreDefaults,
    super.key,
  });

  final List<EventPreset> presets;
  final Future<void> Function(EventPreset preset) onLoadPreset;
  final Future<void> Function() onSaveCurrentPreset;
  final Future<void> Function(EventPreset preset) onCreatePreset;
  final Future<void> Function(int index, EventPreset preset) onUpdatePreset;
  final Future<void> Function(int index) onDeletePreset;
  final Future<void> Function() onRestoreDefaults;

  @override
  State<PresetsPage> createState() => _PresetsPageState();
}

class _PresetsPageState extends State<PresetsPage> {
  final presetName = TextEditingController();
  final presetRoundLength = TextEditingController(text: '50');
  final presetRounds = TextEditingController(text: '4');
  final presetTables = TextEditingController(text: '1-12');

  String presetGame = 'Disney Lorcana';
  String presetMatchFormat = 'BO1';
  int? editingIndex;

  @override
  void dispose() {
    presetName.dispose();
    presetRoundLength.dispose();
    presetRounds.dispose();
    presetTables.dispose();
    super.dispose();
  }

  void clearEditor() {
    setState(() {
      editingIndex = null;
      presetName.clear();
      presetGame = 'Disney Lorcana';
      presetMatchFormat = 'BO1';
      presetRoundLength.text = '50';
      presetRounds.text = '4';
      presetTables.text = '1-12';
    });
  }

  void startEditing(int index) {
    if (index < 0 || index >= widget.presets.length) return;
    final preset = widget.presets[index];
    setState(() {
      editingIndex = index;
      presetName.text = preset.name;
      presetGame = gameOptions.contains(preset.game) ? preset.game : 'Random';
      presetMatchFormat = matchFormatOptions.contains(preset.matchFormat)
          ? preset.matchFormat
          : 'BO1';
      presetRoundLength.text = preset.roundLengthMinutes.toString();
      presetRounds.text = preset.rounds.toString();
      presetTables.text = preset.tables;
    });
  }

  EventPreset readEditorPreset() {
    final name = presetName.text.trim().isEmpty
        ? 'New Event Preset'
        : presetName.text.trim();
    final roundLength = clampInt(
      int.tryParse(presetRoundLength.text.trim()) ?? 50,
      5,
      180,
    );
    final rounds = clampInt(
      int.tryParse(presetRounds.text.trim()) ?? 4,
      1,
      99,
    );
    final tables =
        presetTables.text.trim().isEmpty ? '1-12' : presetTables.text.trim();

    return EventPreset(
      name,
      presetGame,
      presetMatchFormat,
      roundLength,
      rounds,
      tables,
    );
  }

  Future<void> saveEditorPreset() async {
    final preset = readEditorPreset();
    final index = editingIndex;

    if (index == null) {
      await widget.onCreatePreset(preset);
    } else {
      await widget.onUpdatePreset(index, preset);
    }

    clearEditor();
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Event Presets',
      subtitle: 'Create, edit, delete, and load common event setups.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editingIndex == null ? 'Preset Editor' : 'Editing Preset',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  editingIndex == null
                      ? 'Create a new preset here, or save your current timer setup directly.'
                      : 'Change the preset values and save them back into the selected preset.',
                  style: softText,
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 850;
                    final fieldWidth = wide
                        ? (constraints.maxWidth - 24) / 3
                        : constraints.maxWidth;

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: fieldWidth,
                          child: TextField(
                            controller: presetName,
                            decoration: const InputDecoration(
                              labelText: 'Preset name',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: DropdownButtonFormField<String>(
                            value: presetGame,
                            decoration:
                                const InputDecoration(labelText: 'Game'),
                            items: gameOptions
                                .map(
                                  (game) => DropdownMenuItem(
                                    value: game,
                                    child: Text(game),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => presetGame = value);
                            },
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: DropdownButtonFormField<String>(
                            value: presetMatchFormat,
                            decoration: const InputDecoration(
                              labelText: 'Match format',
                            ),
                            items: matchFormatOptions
                                .map(
                                  (format) => DropdownMenuItem(
                                    value: format,
                                    child: Text(format),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => presetMatchFormat = value);
                            },
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: TextField(
                            controller: presetRoundLength,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Round length in minutes',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: TextField(
                            controller: presetRounds,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Total rounds',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: TextField(
                            controller: presetTables,
                            decoration: const InputDecoration(
                              labelText: 'Tables used',
                              hintText: '1-12 or 1-6,9-12',
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: saveEditorPreset,
                      icon: const Icon(Icons.save),
                      label: Text(
                        editingIndex == null
                            ? 'Save as New Preset'
                            : 'Save Edited Preset',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: clearEditor,
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear Editor'),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.onSaveCurrentPreset,
                      icon: const Icon(Icons.add),
                      label: const Text('Save Current Setup as Preset'),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.onRestoreDefaults,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Add Default Presets'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (widget.presets.isEmpty)
            const AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No presets saved yet',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Use “Save as New Preset” or “Save Current Setup as Preset” to create your first preset.',
                    style: softText,
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 18,
              runSpacing: 18,
              children: List.generate(widget.presets.length, (index) {
                final preset = widget.presets[index];
                return SizedBox(
                  width: 340,
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preset.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${preset.game} · ${preset.matchFormat}\n${preset.rounds} rounds · ${preset.roundLengthMinutes} min\nTables ${preset.tables}',
                          style: softText,
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => widget.onLoadPreset(preset),
                            icon: const Icon(Icons.playlist_add_check),
                            label: const Text('Load Preset'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => startEditing(index),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Edit'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => widget.onDeletePreset(index),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Delete'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class PageScaffold extends StatelessWidget {
  const PageScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(26),
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: softText),
        const SizedBox(height: 22),
        child,
        const SizedBox(height: 22),
        Text(appVersion, style: softText.copyWith(fontSize: 12)),
      ],
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white.withOpacity(0.075),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: Colors.white.withOpacity(0.12)),
      ),
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.text, required this.color, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(0.18),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class BigInkLogo extends StatelessWidget {
  const BigInkLogo({
    this.size = 74,
    this.useCustomLogo = false,
    super.key,
  });

  final double size;
  final bool useCustomLogo;

  @override
  Widget build(BuildContext context) {
    if (!useCustomLogo) return _builtInLogo();

    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/images/big_ink_logo.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _builtInLogo(),
      ),
    );
  }

  Widget _builtInLogo() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: const LinearGradient(
          colors: [Color(0xFF5FB3FF), Color(0xFF7C3AED)],
        ),
      ),
      child: Center(
        child: Text(
          'BI',
          style: TextStyle(
            fontSize: size * 0.35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class TimerStateModel {
  const TimerStateModel({
    required this.eventName,
    required this.game,
    required this.matchFormat,
    required this.roundLengthMinutes,
    required this.currentRound,
    required this.totalRounds,
    required this.tableRange,
    required this.tableCount,
    required this.useCustomLogo,
    required this.eventFinished,
    required this.firstPlace,
    required this.secondPlace,
    required this.thirdPlace,
    required this.remainingSeconds,
    required this.running,
    required this.lastUpdateMillis,
  });

  factory TimerStateModel.defaults() {
    return TimerStateModel(
      eventName: 'Lorcana Weekly League',
      game: 'Disney Lorcana',
      matchFormat: 'BO1',
      roundLengthMinutes: 50,
      currentRound: 1,
      totalRounds: 6,
      tableRange: '1-12',
      tableCount: 24,
      useCustomLogo: false,
      eventFinished: false,
      firstPlace: '',
      secondPlace: '',
      thirdPlace: '',
      remainingSeconds: 50 * 60 + 00,
      running: false,
      lastUpdateMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory TimerStateModel.fromJson(Map<String, dynamic> json) {
    return TimerStateModel(
      eventName: json['eventName'] as String? ?? 'TCG Event',
      game: json['game'] as String? ?? 'Disney Lorcana',
      matchFormat:
          normalizeMatchFormat(json['matchFormat'] as String? ?? 'BO1'),
      roundLengthMinutes: (json['roundLengthMinutes'] as num?)?.toInt() ?? 50,
      currentRound: (json['currentRound'] as num?)?.toInt() ?? 1,
      totalRounds: (json['totalRounds'] as num?)?.toInt() ?? 4,
      tableRange: json['tableRange'] as String? ?? '1-12',
      tableCount: (json['tableCount'] as num?)?.toInt() ?? 24,
      useCustomLogo: json['useCustomLogo'] as bool? ?? false,
      eventFinished: json['eventFinished'] as bool? ?? false,
      firstPlace: json['firstPlace'] as String? ?? '',
      secondPlace: json['secondPlace'] as String? ?? '',
      thirdPlace: json['thirdPlace'] as String? ?? '',
      remainingSeconds: (json['remainingSeconds'] as num?)?.toInt() ?? 50 * 60,
      running: json['running'] as bool? ?? false,
      lastUpdateMillis: (json['lastUpdateMillis'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  final String eventName;
  final String game;
  final String matchFormat;
  final int roundLengthMinutes;
  final int currentRound;
  final int totalRounds;
  final String tableRange;
  final int tableCount;
  final bool useCustomLogo;
  final bool eventFinished;
  final String firstPlace;
  final String secondPlace;
  final String thirdPlace;
  final int remainingSeconds;
  final bool running;
  final int lastUpdateMillis;

  bool get isFinalRound => currentRound >= totalRounds;

  int get remainingNow {
    if (eventFinished) return 0;
    if (!running) return remainingSeconds < 0 ? 0 : remainingSeconds;
    final elapsed =
        ((DateTime.now().millisecondsSinceEpoch - lastUpdateMillis) / 1000)
            .floor();
    final value = remainingSeconds - elapsed;
    return value < 0 ? 0 : value;
  }

  String get status {
    if (eventFinished) return 'FINISHED';
    if (remainingNow <= 0) return 'TIME CALLED';
    return running ? 'RUNNING' : 'PAUSED';
  }

  Color get timerColor {
    if (eventFinished) return const Color(0xFF5FB3FF);
    final r = remainingNow;
    if (r <= 60) return const Color(0xFFFB7185);
    if (r <= 300) return const Color(0xFFFB923C);
    if (r <= 600) return const Color(0xFFFACC15);
    return const Color(0xFF5FB3FF);
  }

  Color get statusColor {
    if (eventFinished) return const Color(0xFF5FB3FF);
    if (remainingNow <= 0) return const Color(0xFFFB7185);
    if (!running) return const Color(0xFFFACC15);
    return const Color(0xFF4ADE80);
  }

  TimerStateModel snapshot() => copyWith(
        remainingSeconds: remainingNow,
        lastUpdateMillis: DateTime.now().millisecondsSinceEpoch,
      );

  TimerStateModel withFreshTimestamp() =>
      copyWith(lastUpdateMillis: DateTime.now().millisecondsSinceEpoch);

  bool tableIsActive(int number) {
    final parts =
        tableRange.replaceAll('–', '-').replaceAll(' ', '').split(',');
    for (final part in parts) {
      if (part.contains('-')) {
        final range = part.split('-');
        if (range.length != 2) continue;
        final a = int.tryParse(range[0]);
        final b = int.tryParse(range[1]);
        if (a == null || b == null) continue;
        final low = a < b ? a : b;
        final high = a > b ? a : b;
        if (number >= low && number <= high) return true;
      } else {
        if (int.tryParse(part) == number) return true;
      }
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'eventName': eventName,
        'game': game,
        'matchFormat': matchFormat,
        'roundLengthMinutes': roundLengthMinutes,
        'currentRound': currentRound,
        'totalRounds': totalRounds,
        'tableRange': tableRange,
        'tableCount': tableCount,
        'useCustomLogo': useCustomLogo,
        'eventFinished': eventFinished,
        'firstPlace': firstPlace,
        'secondPlace': secondPlace,
        'thirdPlace': thirdPlace,
        'remainingSeconds': remainingNow,
        'running': running && remainingNow > 0 && !eventFinished,
        'lastUpdateMillis': DateTime.now().millisecondsSinceEpoch,
      };

  TimerStateModel copyWith({
    String? eventName,
    String? game,
    String? matchFormat,
    int? roundLengthMinutes,
    int? currentRound,
    int? totalRounds,
    String? tableRange,
    int? tableCount,
    bool? useCustomLogo,
    bool? eventFinished,
    String? firstPlace,
    String? secondPlace,
    String? thirdPlace,
    int? remainingSeconds,
    bool? running,
    int? lastUpdateMillis,
  }) {
    return TimerStateModel(
      eventName: eventName ?? this.eventName,
      game: game ?? this.game,
      matchFormat: matchFormat ?? this.matchFormat,
      roundLengthMinutes: roundLengthMinutes ?? this.roundLengthMinutes,
      currentRound: currentRound ?? this.currentRound,
      totalRounds: totalRounds ?? this.totalRounds,
      tableRange: tableRange ?? this.tableRange,
      tableCount: tableCount ?? this.tableCount,
      useCustomLogo: useCustomLogo ?? this.useCustomLogo,
      eventFinished: eventFinished ?? this.eventFinished,
      firstPlace: firstPlace ?? this.firstPlace,
      secondPlace: secondPlace ?? this.secondPlace,
      thirdPlace: thirdPlace ?? this.thirdPlace,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      running: running ?? this.running,
      lastUpdateMillis: lastUpdateMillis ?? this.lastUpdateMillis,
    );
  }
}

class EventPreset {
  const EventPreset(
    this.name,
    this.game,
    this.matchFormat,
    this.roundLengthMinutes,
    this.rounds,
    this.tables,
  );

  factory EventPreset.fromJson(Map<String, dynamic> json) {
    return EventPreset(
      json['name'] as String? ?? 'Event Preset',
      json['game'] as String? ?? 'Disney Lorcana',
      normalizeMatchFormat(json['matchFormat'] as String? ?? 'BO1'),
      (json['roundLengthMinutes'] as num?)?.toInt() ?? 50,
      (json['rounds'] as num?)?.toInt() ?? 4,
      json['tables'] as String? ?? '1-12',
    );
  }

  static List<EventPreset> defaultPresets() {
    return const [
      EventPreset(
        'Lorcana Weekly League',
        'Disney Lorcana',
        'BO1',
        50,
        4,
        '1-12',
      ),
      EventPreset('Pokémon Casual Night', 'Pokémon', 'BO1', 30, 3, '13-20'),
      EventPreset('Commander Night', 'Magic Commander', 'BO3', 60, 1, '1-8'),
    ];
  }

  final String name;
  final String game;
  final String matchFormat;
  final int roundLengthMinutes;
  final int rounds;
  final String tables;

  Map<String, dynamic> toJson() => {
        'name': name,
        'game': game,
        'matchFormat': matchFormat,
        'roundLengthMinutes': roundLengthMinutes,
        'rounds': rounds,
        'tables': tables,
      };
}

const matchFormatOptions = ['BO1', 'BO3'];

const gameOptions = [
  'Disney Lorcana',
  'Pokémon',
  'Magic Commander',
  'Yu-Gi-Oh!',
  'Random',
];

String normalizeMatchFormat(String value) {
  return matchFormatOptions.contains(value) ? value : 'BO1';
}

const softText = TextStyle(color: Color(0xB3FFFFFF));

String formatSeconds(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = safe ~/ 60;
  final rest = safe % 60;
  return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}

int clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}
