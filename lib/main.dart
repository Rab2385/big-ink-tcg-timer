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
    final pages = [
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
        onApplyReset: () => applySettings(resetTimer: true),
        onApplySave: () => applySettings(resetTimer: false),
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
        onDeletePreset: deletePreset,
        onRestoreDefaults: restoreDefaultPresets,
      ),
    ];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Big Ink TCG Timer',
      theme: buildAppTheme(),
      home: playerOnly
          ? PlayerScreen(state: state)
          : Scaffold(
              backgroundColor: Colors.transparent,
              body: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF060816),
                      Color(0xFF0B1020),
                      Color(0xFF11152A)
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedBackdrop(accent: state.timerColor),
                    ),
                    Focus(
                      focusNode: keyboardFocusNode,
                      autofocus: true,
                      onKeyEvent: handleKeyboard,
                      child: SafeArea(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 1080;
                            return stacked
                                ? Column(
                                    children: [
                                      TournamentNavigation(
                                        compact: true,
                                        selectedIndex: page,
                                        state: state,
                                        onSelected: (value) {
                                          if (value == 1) {
                                            openPlayerScreenFullscreen();
                                            return;
                                          }
                                          setState(() => page = value);
                                        },
                                      ),
                                      Expanded(
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 350,
                                          ),
                                          switchInCurve: Curves.easeOutCubic,
                                          switchOutCurve: Curves.easeInCubic,
                                          child: pages[page],
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      if (page != 1)
                                        TournamentNavigation(
                                          selectedIndex: page,
                                          state: state,
                                          onSelected: (value) {
                                            if (value == 1) {
                                              openPlayerScreenFullscreen();
                                              return;
                                            }
                                            setState(() => page = value);
                                          },
                                        ),
                                      Expanded(
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 350,
                                          ),
                                          switchInCurve: Curves.easeOutCubic,
                                          switchOutCurve: Curves.easeInCubic,
                                          child: pages[page],
                                        ),
                                      ),
                                    ],
                                  );
                          },
                        ),
                      ),
                    ),
                  ],
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
      subtitle:
          'Run rounds with a polished tournament dashboard built for TCG nights, leagues, and store championships.',
      accent: state.timerColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 1080;
          final leftWidth =
              wide ? constraints.maxWidth * 0.60 - 12 : constraints.maxWidth;
          final rightWidth =
              wide ? constraints.maxWidth * 0.40 - 12 : constraints.maxWidth;

          return Wrap(
            spacing: 24,
            runSpacing: 24,
            children: [
              SizedBox(
                width: leftWidth,
                child: Column(
                  children: [
                    HeroTimerCard(
                      state: state,
                      onToggle: onToggle,
                      onAddFive: onAddFive,
                      onReset: onReset,
                      onNextRound: onNextRound,
                      onFinishEvent: onFinishEvent,
                    ),
                    const SizedBox(height: 24),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionHeading(
                            eyebrow: 'Tournament flow',
                            title: 'Round timeline',
                            subtitle:
                                'Players can read the current round, match format, and table zone at a glance.',
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              MetricTile(
                                icon: Icons.style_outlined,
                                label: 'Format',
                                value: state.matchFormat,
                                accent: const Color(0xFF8B5CF6),
                              ),
                              MetricTile(
                                icon: Icons.timer_outlined,
                                label: 'Round length',
                                value: '${state.roundLengthMinutes} min',
                                accent: const Color(0xFF22D3EE),
                              ),
                              MetricTile(
                                icon: Icons.stadium_outlined,
                                label: 'Tables in play',
                                value: state.tableRange,
                                accent: const Color(0xFFF97316),
                              ),
                              MetricTile(
                                icon: Icons.emoji_events_outlined,
                                label: 'Stage',
                                value: state.stageLabel,
                                accent: state.statusColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          StatusNotice(
                            icon: state.eventFinished
                                ? Icons.workspace_premium_outlined
                                : state.isFinalRound
                                    ? Icons.priority_high_rounded
                                    : Icons.campaign_outlined,
                            title: state.eventFinished
                                ? 'Winner screen live'
                                : state.isFinalRound
                                    ? 'Final round spotlight'
                                    : 'Tournament ready',
                            message: state.eventFinished
                                ? 'The player display has switched to the podium presentation.'
                                : state.isFinalRound
                                    ? 'Use Finish Event after standings are final to celebrate the podium.'
                                    : 'Save changes any time, then launch the fullscreen player view for the venue display.',
                            accent: state.statusColor,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: rightWidth,
                child: Column(
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionHeading(
                            eyebrow: 'Event setup',
                            title: 'Control deck',
                            subtitle:
                                'Tune the event identity, round structure, and table layout before each tournament.',
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: eventName,
                            decoration: const InputDecoration(
                              labelText: 'Event name',
                              prefixIcon: Icon(Icons.auto_awesome),
                            ),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            value: state.game,
                            decoration: const InputDecoration(
                              labelText: 'Game',
                              prefixIcon: Icon(Icons.style_outlined),
                            ),
                            items: gameOptions
                                .map(
                                  (game) => DropdownMenuItem(
                                    value: game,
                                    child: Text(game),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) onGameChanged(value);
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            value: normalizeMatchFormat(state.matchFormat),
                            decoration: const InputDecoration(
                              labelText: 'Match format',
                              prefixIcon: Icon(Icons.layers_outlined),
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
                              if (value != null) onMatchFormatChanged(value);
                            },
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: roundLength,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Round length in minutes',
                              prefixIcon: Icon(Icons.hourglass_bottom_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: currentRound,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Current round',
                                    prefixIcon: Icon(Icons.flag_outlined),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextField(
                                  controller: totalRounds,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Total rounds',
                                    prefixIcon:
                                        Icon(Icons.format_list_numbered),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: tableRange,
                            decoration: const InputDecoration(
                              labelText: 'Tables used',
                              hintText: '1-12 or 1-6,9-12',
                              prefixIcon: Icon(Icons.grid_view_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: tableCount,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Total tables in store',
                              prefixIcon: Icon(Icons.table_restaurant_outlined),
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
                              'Keep the default BI badge or switch to your venue graphic.',
                              style: softText,
                            ),
                            value: state.useCustomLogo,
                            onChanged: onUseCustomLogoChanged,
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton.icon(
                                onPressed: onApplyReset,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Apply & Reset Timer'),
                              ),
                              OutlinedButton.icon(
                                onPressed: onApplySave,
                                icon: const Icon(Icons.save_outlined),
                                label: const Text('Save Without Reset'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionHeading(
                            eyebrow: 'Podium setup',
                            title: 'Winner presentation',
                            subtitle:
                                'Prepare the champion, runner-up, and third place names before you switch to the closing screen.',
                          ),
                          const SizedBox(height: 18),
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
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              gradient: const LinearGradient(
                                colors: [Color(0x22F59E0B), Color(0x22F97316)],
                              ),
                              border: Border.all(
                                color: const Color(0x44F8B84E),
                              ),
                            ),
                            child: const Text(
                              'The winner screen becomes a premium closing slide with glowing podium cards and animated lighting.',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
              center: Alignment.topCenter,
              radius: 1.2,
              colors: [
                state.timerColor.withOpacity(0.28),
                const Color(0xFF05070F),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                  child: AnimatedBackdrop(accent: state.timerColor)),
              Padding(
                padding: EdgeInsets.all(outerPadding),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xD9121830), Color(0xD50A1023)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: state.timerColor.withOpacity(0.20),
                        blurRadius: 60,
                        offset: const Offset(0, 28),
                      ),
                    ],
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
                                  'TOURNAMENT TIMER',
                                  style: TextStyle(
                                    fontSize: headerTitleSize,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.4,
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
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: width * 0.88),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: width * 0.86,
                                    ),
                                    child: Text(
                                      state.eventName,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: eventNameSize,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -3.5 * scale,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 18 * scale),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 12 * scale,
                                    runSpacing: 12 * scale,
                                    children: [
                                      ScreenStatPill(
                                        icon: Icons.flag_outlined,
                                        label:
                                            'ROUND ${state.currentRound} / ${state.totalRounds}',
                                      ),
                                      ScreenStatPill(
                                        icon: Icons.style_outlined,
                                        label: normalizeMatchFormat(
                                          state.matchFormat,
                                        ),
                                      ),
                                      ScreenStatPill(
                                        icon: Icons.table_restaurant_outlined,
                                        label: 'TABLES ${state.tableRange}',
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 26 * scale),
                                  TimeControlDisplay(
                                    state: state,
                                    size: compact ? 320 : 540 * scale,
                                    headlineSize: timerSize,
                                  ),
                                  SizedBox(height: 18 * scale),
                                  Text(
                                    state.playerHeadline,
                                    textAlign: TextAlign.center,
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
                      ),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 24 * scale,
                          vertical: compact ? 14 : 22 * scale,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24 * scale),
                          color: Colors.white.withOpacity(0.06),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        child: Text(
                          state.playerMessage,
                          textAlign: TextAlign.center,
                          maxLines: 3,
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
            ],
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
    return const StatusNotice(
      icon: Icons.warning_amber_rounded,
      title: 'Final round ready',
      message:
          'Use Finish Event when pairings and standings are complete to switch the venue screen to the winner podium.',
      accent: Color(0xFFFACC15),
    );
  }
}

class EventFinishedNotice extends StatelessWidget {
  const EventFinishedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatusNotice(
      icon: Icons.emoji_events_outlined,
      title: 'Closing scene live',
      message:
          'The player display is now presenting the podium view for the final standings.',
      accent: Color(0xFF38BDF8),
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
              center: Alignment.topCenter,
              radius: 1.3,
              colors: [Color(0x66F59E0B), Color(0xFF05070F)],
            ),
          ),
          child: Stack(
            children: [
              const Positioned.fill(
                child: AnimatedBackdrop(accent: Color(0xFFFACC15)),
              ),
              Padding(
                padding: EdgeInsets.all(compact ? 14 : 28 * scale),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(34 * scale),
                    border: Border.all(color: Colors.white.withOpacity(0.14)),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xE4191120), Color(0xE00B1023)],
                    ),
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
                                    letterSpacing: 1.2,
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
                              text: 'PODIUM',
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
                                Container(
                                  width: compact ? 96 : 132 * scale,
                                  height: compact ? 96 : 132 * scale,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const RadialGradient(
                                      colors: [
                                        Color(0x55FACC15),
                                        Color(0x11FACC15),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFFACC15)
                                            .withOpacity(0.30),
                                        blurRadius: 34,
                                        spreadRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.workspace_premium,
                                    size: compact ? 54 : 74 * scale,
                                    color: const Color(0xFFFACC15),
                                  ),
                                ),
                                SizedBox(height: 14 * scale),
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
                                          ? 'Runner-up'
                                          : secondName,
                                      isPlaceholder: secondName.isEmpty,
                                      icon: Icons.workspace_premium_outlined,
                                      width: compact ? 230 : 282 * scale,
                                      height: compact ? 170 : 238 * scale,
                                      nameSize: podiumNameSize,
                                      placeSize: podiumPlaceSize,
                                      accent: const Color(0xFFCBD5E1),
                                    ),
                                    PodiumCard(
                                      placeLabel: '1st Place',
                                      name: firstName.isEmpty
                                          ? 'Champion'
                                          : firstName,
                                      isPlaceholder: firstName.isEmpty,
                                      icon: Icons.emoji_events,
                                      width: compact ? 245 : 300 * scale,
                                      height: compact ? 210 : 296 * scale,
                                      nameSize: podiumNameSize + 7 * scale,
                                      placeSize: podiumPlaceSize,
                                      accent: const Color(0xFFFACC15),
                                      isChampion: true,
                                    ),
                                    PodiumCard(
                                      placeLabel: '3rd Place',
                                      name: thirdName.isEmpty
                                          ? 'Top cut'
                                          : thirdName,
                                      isPlaceholder: thirdName.isEmpty,
                                      icon: Icons.military_tech_outlined,
                                      width: compact ? 230 : 282 * scale,
                                      height: compact ? 170 : 238 * scale,
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
                          color: Colors.white.withOpacity(0.06),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        child: Text(
                          'Celebrate the finalists, thank your community, and get ready for the next tournament night.',
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
            ],
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
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withOpacity(isChampion ? 0.24 : 0.18),
            accent.withOpacity(0.05),
          ],
        ),
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
          Icon(icon, color: accent, size: isChampion ? 34 : 28),
          const SizedBox(height: 10),
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
      subtitle:
          'Highlight tournament zones with a cleaner venue map and live color coding.',
      accent: state.timerColor,
      child: Column(
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              MetricTile(
                icon: Icons.table_bar_outlined,
                label: 'Total tables',
                value: '${state.tableCount}',
                accent: const Color(0xFF22D3EE),
              ),
              MetricTile(
                icon: Icons.local_activity_outlined,
                label: 'Event range',
                value: state.tableRange,
                accent: state.timerColor,
              ),
              MetricTile(
                icon: Icons.bolt_outlined,
                label: 'Round status',
                value: state.stageLabel,
                accent: state.statusColor,
              ),
            ],
          ),
          const SizedBox(height: 24),
          AppCard(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 1200
                    ? 8
                    : constraints.maxWidth > 900
                        ? 6
                        : constraints.maxWidth > 560
                            ? 4
                            : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: state.tableCount,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 1.10,
                  ),
                  itemBuilder: (context, index) {
                    final table = index + 1;
                    final active = state.tableIsActive(table);
                    final color =
                        active ? state.timerColor : const Color(0xFF4ADE80);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            color.withOpacity(active ? 0.22 : 0.16),
                            color.withOpacity(active ? 0.08 : 0.05),
                          ],
                        ),
                        border: Border.all(color: color.withOpacity(0.48)),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(active ? 0.18 : 0.08),
                            blurRadius: active ? 24 : 12,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            active
                                ? Icons.flash_on_rounded
                                : Icons.check_circle_outline,
                            color: color,
                          ),
                          const Spacer(),
                          Text(
                            'Table $table',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            active ? 'In event rotation' : 'Available',
                            style: softText.copyWith(
                              color: active
                                  ? color.withOpacity(0.90)
                                  : const Color(0xFFB7FBCB),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
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
      subtitle:
          'Build reusable tournament recipes for weekly leagues, casual nights, and major store events.',
      accent: const Color(0xFF8B5CF6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeading(
                  eyebrow: 'Preset workshop',
                  title: editingIndex == null
                      ? 'Create a new event preset'
                      : 'Editing saved preset',
                  subtitle: editingIndex == null
                      ? 'Capture your best event structure once, then launch it in seconds.'
                      : 'Update the selected preset and keep your tournament flow consistent.',
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
              child: SectionHeading(
                eyebrow: 'Empty vault',
                title: 'No presets saved yet',
                subtitle:
                    'Use Save as New Preset or Save Current Setup as Preset to create your first tournament recipe.',
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
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF22D3EE), Color(0xFF8B5CF6)],
                            ),
                          ),
                          child: const Icon(Icons.auto_awesome),
                        ),
                        const SizedBox(height: 16),
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
    this.accent = const Color(0xFF38BDF8),
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              colors: [accent.withOpacity(0.18), const Color(0x22151B33)],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: softText.copyWith(fontSize: 15)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  InfoPill(
                    icon: Icons.bolt,
                    text: 'Venue-ready display',
                    color: accent,
                  ),
                  const InfoPill(
                    icon: Icons.auto_awesome,
                    text: 'Modern animated UI',
                    color: Color(0xFF8B5CF6),
                  ),
                  const InfoPill(
                    icon: Icons.timer_outlined,
                    text: appVersion,
                    color: Color(0xFF22D3EE),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        child,
      ],
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xD9111730), Color(0xCC0B1226)],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
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
        gradient: LinearGradient(
          colors: [color.withOpacity(0.22), color.withOpacity(0.08)],
        ),
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
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF22D3EE), Color(0xFF8B5CF6)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
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

class HeroTimerCard extends StatelessWidget {
  const HeroTimerCard({
    required this.state,
    required this.onToggle,
    required this.onAddFive,
    required this.onReset,
    required this.onNextRound,
    required this.onFinishEvent,
    super.key,
  });

  final TimerStateModel state;
  final Future<void> Function() onToggle;
  final Future<void> Function() onAddFive;
  final Future<void> Function() onReset;
  final Future<void> Function() onNextRound;
  final Future<void> Function() onFinishEvent;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 900;
          final ringSize = stacked ? 220.0 : 250.0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const InfoPill(
                    icon: Icons.sports_esports_outlined,
                    text: 'Tournament live',
                    color: Color(0xFF22D3EE),
                  ),
                  InfoPill(
                    icon: Icons.bolt_outlined,
                    text: state.stageLabel,
                    color: state.statusColor,
                  ),
                  InfoPill(
                    icon: Icons.grid_view_rounded,
                    text: 'Tables ${state.tableRange}',
                    color: const Color(0xFFF97316),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (stacked)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroTimerDetails(
                      state: state,
                      onToggle: onToggle,
                      onAddFive: onAddFive,
                      onReset: onReset,
                      onNextRound: onNextRound,
                      onFinishEvent: onFinishEvent,
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: _HeroTimerVisual(
                        state: state,
                        ringSize: ringSize,
                        headlineSize: 64,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _HeroTimerDetails(
                        state: state,
                        onToggle: onToggle,
                        onAddFive: onAddFive,
                        onReset: onReset,
                        onNextRound: onNextRound,
                        onFinishEvent: onFinishEvent,
                      ),
                    ),
                    const SizedBox(width: 28),
                    Expanded(
                      flex: 4,
                      child: _HeroTimerVisual(
                        state: state,
                        ringSize: ringSize,
                        headlineSize: 78,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              if (state.isFinalRound && !state.eventFinished)
                const FinalRoundNotice(),
              if (state.eventFinished) const EventFinishedNotice(),
            ],
          );
        },
      ),
    );
  }
}

class TimeControlDisplay extends StatelessWidget {
  const TimeControlDisplay({
    required this.state,
    required this.size,
    required this.headlineSize,
    super.key,
  });

  final TimerStateModel state;
  final double size;
  final double headlineSize;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: state.remainingRatio),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size * 0.88,
                height: size * 0.88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      state.timerColor.withOpacity(0.24),
                      state.timerColor.withOpacity(0.04),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: state.timerColor.withOpacity(0.28),
                      blurRadius: 34,
                      spreadRadius: 6,
                    ),
                  ],
                ),
              ),
              CustomPaint(
                size: Size.square(size),
                painter: RingPainter(
                  progress: value,
                  accent: state.timerColor,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.eventFinished
                        ? 'DONE'
                        : state.remainingNow <= 0
                            ? 'TIME'
                            : formatSeconds(state.remainingNow),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: headlineSize,
                      height: 0.9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: state.remainingNow <= 0 ? -2 : -4,
                      color: state.timerColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    state.eventFinished
                        ? 'Event complete'
                        : state.remainingNow <= 0
                            ? 'Called'
                            : 'Remaining',
                    style: softText.copyWith(
                      fontSize: size * 0.07,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroTimerDetails extends StatelessWidget {
  const _HeroTimerDetails({
    required this.state,
    required this.onToggle,
    required this.onAddFive,
    required this.onReset,
    required this.onNextRound,
    required this.onFinishEvent,
  });

  final TimerStateModel state;
  final Future<void> Function() onToggle;
  final Future<void> Function() onAddFive;
  final Future<void> Function() onReset;
  final Future<void> Function() onNextRound;
  final Future<void> Function() onFinishEvent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.eventName,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${state.game} · ${state.matchFormat} · Round ${state.currentRound}/${state.totalRounds}',
          style: softText.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 22),
        Text(
          state.playerHeadline,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: state.statusColor,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          state.playerMessage,
          style: softText.copyWith(height: 1.5),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onToggle,
              icon: Icon(
                state.running
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
              ),
              label: Text(
                state.running ? 'Pause Round' : 'Start Round',
              ),
            ),
            OutlinedButton.icon(
              onPressed: onAddFive,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('+5 Minutes'),
            ),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.replay_circle_filled_outlined),
              label: const Text('Reset'),
            ),
            OutlinedButton.icon(
              onPressed: onNextRound,
              icon: const Icon(Icons.skip_next_rounded),
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
    );
  }
}

class _HeroTimerVisual extends StatelessWidget {
  const _HeroTimerVisual({
    required this.state,
    required this.ringSize,
    required this.headlineSize,
  });

  final TimerStateModel state;
  final double ringSize;
  final double headlineSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TimeControlDisplay(
          state: state,
          size: ringSize,
          headlineSize: headlineSize,
        ),
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            MiniMetric(
              label: 'Round length',
              value: '${state.roundLengthMinutes} min',
            ),
            MiniMetric(
              label: 'Total tables',
              value: '${state.tableCount}',
            ),
          ],
        ),
      ],
    );
  }
}

class RingPainter extends CustomPainter {
  RingPainter({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.06;
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;

    final base = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..shader = SweepGradient(
        colors: [accent.withOpacity(0.20), accent, const Color(0xFFFFFFFF)],
        stops: const [0.0, 0.7, 1.0],
        startAngle: -math.pi / 2,
        endAngle: 1.5 * math.pi,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, base);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant RingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.accent != accent;
  }
}

class StatusNotice extends StatelessWidget {
  const StatusNotice({
    required this.icon,
    required this.title,
    required this.message,
    required this.accent,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [accent.withOpacity(0.20), accent.withOpacity(0.06)],
        ),
        border: Border.all(color: accent.withOpacity(0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(message, style: softText.copyWith(height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TournamentNavigation extends StatelessWidget {
  const TournamentNavigation({
    required this.selectedIndex,
    required this.state,
    required this.onSelected,
    this.compact = false,
    super.key,
  });

  final int selectedIndex;
  final TimerStateModel state;
  final ValueChanged<int> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = [
      (icon: Icons.timer_outlined, label: 'Timer'),
      (icon: Icons.tv_outlined, label: 'Player Screen'),
      (icon: Icons.grid_view_outlined, label: 'Tables'),
      (icon: Icons.event_note_outlined, label: 'Presets'),
    ];

    final rail = compact
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Row(
              children: List.generate(items.length, (index) {
                final item = items[index];
                return Padding(
                  padding: EdgeInsets.only(
                      right: index == items.length - 1 ? 0 : 12),
                  child: NavigationChip(
                    icon: item.icon,
                    label: item.label,
                    selected: selectedIndex == index,
                    onTap: () => onSelected(index),
                  ),
                );
              }),
            ),
          )
        : SizedBox(
            width: 290,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 20),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        BigInkLogo(size: 54),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Big Ink Timer',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                'Tournament command center',
                                style: softText,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: LinearGradient(
                          colors: [
                            state.timerColor.withOpacity(0.20),
                            state.timerColor.withOpacity(0.06),
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StatusBadge(
                            text: state.status,
                            color: state.statusColor,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            formatSeconds(state.remainingNow),
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: state.timerColor,
                              letterSpacing: -1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${state.game} · Round ${state.currentRound}/${state.totalRounds}',
                            style: softText.copyWith(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Column(
                      children: List.generate(items.length, (index) {
                        final item = items[index];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == items.length - 1 ? 0 : 10,
                          ),
                          child: NavigationChip(
                            icon: item.icon,
                            label: item.label,
                            selected: selectedIndex == index,
                            onTap: () => onSelected(index),
                            fullWidth: true,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      appVersion,
                      style: softText.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );

    return rail;
  }
}

class NavigationChip extends StatelessWidget {
  const NavigationChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.fullWidth = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? const Color(0xFF22D3EE) : Colors.white;
    final background =
        selected ? const Color(0x3322D3EE) : Colors.white.withOpacity(0.04);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          width: fullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: background,
            border: Border.all(
              color: selected
                  ? const Color(0x6622D3EE)
                  : Colors.white.withOpacity(0.06),
            ),
          ),
          child: Row(
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
            color: Color(0xFF7DD3FC),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: softText.copyWith(height: 1.5)),
      ],
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 170),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [accent.withOpacity(0.20), accent.withOpacity(0.05)],
          ),
          border: Border.all(color: accent.withOpacity(0.32)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent),
            const SizedBox(height: 16),
            Text(label, style: softText.copyWith(fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class MiniMetric extends StatelessWidget {
  const MiniMetric({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Text(label, style: softText.copyWith(fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class InfoPill extends StatelessWidget {
  const InfoPill({
    required this.icon,
    required this.text,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(0.14),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class ScreenStatPill extends StatelessWidget {
  const ScreenStatPill({
    required this.icon,
    required this.label,
    super.key,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withOpacity(0.08),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF7DD3FC)),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class AnimatedBackdrop extends StatefulWidget {
  const AnimatedBackdrop({
    required this.accent,
    super.key,
  });

  final Color accent;

  @override
  State<AnimatedBackdrop> createState() => _AnimatedBackdropState();
}

class _AnimatedBackdropState extends State<AnimatedBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final shift = controller.value;
        return Stack(
          children: [
            Positioned(
              top: -120 + 80 * shift,
              left: -60 + 120 * shift,
              child: BackdropOrb(
                size: 320,
                color: widget.accent.withOpacity(0.24),
              ),
            ),
            Positioned(
              right: -110 + 60 * shift,
              top: 120 - 70 * shift,
              child: BackdropOrb(
                size: 280,
                color: const Color(0xFF8B5CF6).withOpacity(0.20),
              ),
            ),
            Positioned(
              bottom: -120 + 60 * shift,
              left: MediaQuery.of(context).size.width * 0.35,
              child: BackdropOrb(
                size: 360,
                color: const Color(0xFF22D3EE).withOpacity(0.10),
              ),
            ),
          ],
        );
      },
    );
  }
}

class BackdropOrb extends StatelessWidget {
  const BackdropOrb({required this.size, required this.color, super.key});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }
}

ThemeData buildAppTheme() {
  const accent = Color(0xFF22D3EE);
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: accent,
    secondary: const Color(0xFF8B5CF6),
    surface: const Color(0xFF10162B),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF070A14),
    fontFamily: 'Arial',
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        borderSide: BorderSide(color: accent, width: 1.2),
      ),
      labelStyle: const TextStyle(color: Color(0xFFB7C2D9)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white.withOpacity(0.08),
      side: BorderSide(color: Colors.white.withOpacity(0.10)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: const Color(0xFF03121A),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withOpacity(0.14)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF11182E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
  );
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

  int get totalRoundSeconds => roundLengthMinutes * 60;

  double get remainingRatio {
    final total = totalRoundSeconds;
    if (eventFinished || total <= 0) return 0;
    return (remainingNow / total).clamp(0.0, 1.0).toDouble();
  }

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

  String get stageLabel {
    if (eventFinished) return 'Winners';
    if (remainingNow <= 0) return 'Time called';
    if (isFinalRound) return 'Final round';
    if (remainingNow <= 300) return 'Final five';
    return running ? 'Round live' : 'Ready';
  }

  String get playerHeadline {
    if (eventFinished) return 'Event complete';
    if (remainingNow <= 0) return 'Please finish your current turn';
    if (isFinalRound) return 'Final round in progress';
    if (remainingNow <= 300) return 'Final five minutes';
    return running ? 'Round in progress' : 'Round paused';
  }

  String get playerMessage {
    if (eventFinished) {
      return 'The event is finished and the podium presentation is live.';
    }
    if (remainingNow <= 0) {
      return 'Time has been called. Finish the current turn according to event rules, then report your result.';
    }
    if (isFinalRound) {
      return 'Final round — good luck, have fun, and report your final result after the round.';
    }
    if (!running) {
      return 'The tournament clock is paused. Prepare players for the next action.';
    }
    return 'Good luck, have fun — please report your result after the round.';
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
