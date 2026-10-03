import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_ft_event_timer/display_bridge.dart';
import 'package:flutter_application_ft_event_timer/live_page.dart';
import 'package:flutter_application_ft_event_timer/setup_page.dart';
import 'package:flutter_application_ft_event_timer/sound.dart';
import 'package:shared_preferences/shared_preferences.dart';

const storageKey = 'big_ink_tcg_timer_v1';
const presetsStorageKey = 'big_ink_tcg_timer_presets_v1';
const displayStorageKey = 'big_ink_tcg_timer_display_v1';
const messagesStorageKey = 'big_ink_tcg_timer_messages_v1';
const syncChannelName = 'big-ink-tcg-timer';
const appVersion = 'V1.2.3 Alena';

/// The player screen window is opened with `?view=player`. Flutter rewrites
/// the `#...` part of the URL on start, so a query parameter survives a
/// reload; `#player` is still accepted for older links and shortcuts.
const playerViewQuery = 'view=player';

bool isPlayerWindowUrl(Uri url) =>
    url.queryParameters['view'] == 'player' ||
    url.fragment.toLowerCase().contains('player');

void main() => runApp(const BigInkTimerApp());

class BigInkTimerApp extends StatefulWidget {
  const BigInkTimerApp({super.key});

  @override
  State<BigInkTimerApp> createState() => BigInkTimerAppState();
}

/// Navigation rail order.
abstract final class AppPage {
  static const live = 0;
  static const setup = 1;
  static const presets = 2;
}

/// Holds the event state and every action the pages can trigger. Pages get
/// this object and call its methods directly.
class BigInkTimerAppState extends State<BigInkTimerApp> {
  TimerStateModel state = TimerStateModel.defaults();
  List<EventPreset> presets = EventPreset.defaultPresets();
  SharedPreferences? prefs;
  Timer? ticker;
  StreamSubscription<html.Event>? fullscreenSubscription;
  StreamSubscription<html.MessageEvent>? syncSubscription;
  StreamSubscription<html.Event>? audioUnlockSubscription;
  html.BroadcastChannel? syncChannel;

  // The app state sits above MaterialApp, so its own context has no
  // Navigator or ScaffoldMessenger. Dialogs and snack bars go through these.
  final navigatorKey = GlobalKey<NavigatorState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  // Text fields are saved automatically shortly after typing stops.
  Timer? autosaveTimer;

  int page = AppPage.live;

  /// Fallback without a second screen: the player screen fills this window.
  bool fullscreenPlayer = false;

  /// True in the window that only shows the player screen (`#player`).
  late final bool playerOnly;

  late final DisplayBridge display = DisplayBridge(onChanged: refreshDisplay);
  DisplayStatus displayStatus = const DisplayStatus();

  /// The screen the player window was last opened on, and whether it should
  /// be open. Used to reopen it on start and to report a lost connection.
  int? rememberedScreenId;
  bool wantPlayerOpen = false;

  final wakeLock = ScreenWakeLock();
  final sound = SoundPlayer();
  int _lastTickRemaining = -1;
  int _tickCount = 0;

  List<String> recentMessages = [];

  final eventName = TextEditingController();
  final roundLength = TextEditingController();
  final currentRound = TextEditingController();
  final totalRounds = TextEditingController();
  final timeCalledNote = TextEditingController();
  final messageInput = TextEditingController();

  @override
  void initState() {
    super.initState();
    playerOnly = isPlayerWindowUrl(Uri.base);
    _syncTextFields();
    _load();

    syncChannel = html.BroadcastChannel(syncChannelName);
    syncSubscription = syncChannel!.onMessage.listen(_onSyncMessage);

    // Browsers only allow sound after a click or key press. Unlock audio on
    // the first one, so the sounds can play later on their own. (The desktop
    // app allows sound right away.)
    sound.prime();
    audioUnlockSubscription = html.document.on['pointerdown'].listen((_) {
      sound.prime();
      if (playerOnly) _reportPlayerAlive();
    });

    if (playerOnly) {
      // Ask the control window for the current state right away.
      _post({'type': 'hello'});
      _reportPlayerAlive();
      wakeLock.keepOn();
    } else {
      display.start();
      HardwareKeyboard.instance.addHandler(_handleKey);
    }

    fullscreenSubscription = html.document.onFullscreenChange.listen((_) {
      if (fullscreenPlayer && html.document.fullscreenElement == null) {
        setState(() => fullscreenPlayer = false);
        wakeLock.release();
      }
    });

    // A sub-second tick keeps the display within 250 ms of each second
    // boundary, so the countdown never visibly skips a second.
    ticker = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      _tickCount++;
      if (playerOnly) {
        // Updates arrive over the sync channel. Re-reading the saved state
        // every few seconds is only a safety net.
        if (_tickCount % 12 == 0) await _reloadForPlayerScreen();
        if (_tickCount % 8 == 0) _reportPlayerAlive();
      } else {
        _playSounds();
        // Only the control window writes state. The player window just
        // reads, so it can never overwrite a change made by the admin.
        if (state.running && state.remainingNow <= 0) {
          _playTimeUpSound();
          await _setStateModel(state.withTimeCalled());
        }
      }

      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    autosaveTimer?.cancel();
    fullscreenSubscription?.cancel();
    syncSubscription?.cancel();
    audioUnlockSubscription?.cancel();
    syncChannel?.close();
    display.dispose();
    wakeLock.dispose();
    if (!playerOnly) HardwareKeyboard.instance.removeHandler(_handleKey);
    for (final controller in [
      eventName,
      roundLength,
      currentRound,
      totalRounds,
      timeCalledNote,
      messageInput,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Loading, saving and syncing
  // ---------------------------------------------------------------------

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
    _loadRecentMessages();
    _syncTextFields();
    if (mounted) setState(() {});

    if (!playerOnly) await _restorePlayerWindow();
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
    if (playerOnly) return;
    prefs ??= await SharedPreferences.getInstance();
    await prefs!.setString(storageKey, jsonEncode(state.toJson()));
  }

  Future<void> _savePresets() async {
    if (playerOnly) return;
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
    _broadcastState();
    await _save();
  }

  void _post(Map<String, dynamic> message) {
    try {
      syncChannel?.postMessage(jsonEncode(message));
    } catch (_) {
      // The player window falls back to re-reading saved state.
    }
  }

  void _broadcastState() {
    if (playerOnly) return;
    _post({'type': 'state', 'state': state.toJson()});
  }

  void _onSyncMessage(html.MessageEvent event) {
    final data = event.data;
    if (data is! String) return;

    try {
      final message = jsonDecode(data) as Map<String, dynamic>;
      final type = message['type'];
      if (type == 'hello' && !playerOnly) {
        _broadcastState();
      } else if (type == 'player-alive' && !playerOnly) {
        _playerSoundReadyAt = message['audio'] == true
            ? DateTime.now().millisecondsSinceEpoch
            : 0;
      } else if (type == 'state' && playerOnly) {
        final next = TimerStateModel.fromJson(
          message['state'] as Map<String, dynamic>,
        );
        if (mounted) setState(() => state = next);
      } else if (type == 'sound' && playerOnly) {
        _playLocally(
          message['sound'] as String?,
          (message['volume'] as num?)?.toDouble() ?? state.soundVolume,
        );
      }
    } catch (_) {
      // Ignore messages from other versions of the app.
    }
  }

  void _syncTextFields() {
    eventName.text = state.eventName;
    roundLength.text = state.roundLengthMinutes.toString();
    currentRound.text = state.currentRound.toString();
    totalRounds.text = state.totalRounds.toString();
    timeCalledNote.text = state.timeCalledNote;
  }

  int _readInt(TextEditingController controller, int fallback) {
    return int.tryParse(controller.text.trim()) ?? fallback;
  }

  /// Called on every keystroke in the setup fields. Saves once typing pauses.
  void scheduleAutosave() {
    autosaveTimer?.cancel();
    autosaveTimer = Timer(const Duration(milliseconds: 400), saveFields);
  }

  /// Saves pending field edits right away, so actions that re-sync the
  /// text fields from the saved state never discard what was just typed.
  Future<void> flushAutosave() async {
    if (autosaveTimer?.isActive != true) return;
    autosaveTimer!.cancel();
    await saveFields();
  }

  /// Saves the setup text fields. Never touches a running timer: a new
  /// round length applies from the next round or a restart.
  Future<void> saveFields() async {
    autosaveTimer?.cancel();

    await _setStateModel(
      state.copyWith(
        eventName: eventName.text.trim().isEmpty
            ? 'TCG Event'
            : eventName.text.trim(),
        roundLengthMinutes:
            clampInt(_readInt(roundLength, state.roundLengthMinutes), 5, 180),
        currentRound:
            clampInt(_readInt(currentRound, state.currentRound), 1, 99),
        totalRounds: clampInt(_readInt(totalRounds, state.totalRounds), 1, 99),
        timeCalledNote: timeCalledNote.text.trim(),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Messages and undo
  // ---------------------------------------------------------------------

  void showMessage(
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
          width: 520,
          action: actionLabel == null || onAction == null
              ? null
              : SnackBarAction(label: actionLabel, onPressed: onAction),
        ),
      );
  }

  /// Applies [next] right away and offers to undo it for a few seconds,
  /// instead of asking for confirmation first.
  Future<void> _commitWithUndo(
    TimerStateModel next,
    String message, {
    bool syncText = false,
  }) async {
    final before = state;
    await _setStateModel(next, syncText: syncText);
    showMessage(
      message,
      actionLabel: 'Undo',
      onAction: () => _setStateModel(before, syncText: true),
    );
  }

  // ---------------------------------------------------------------------
  // Timer actions
  // ---------------------------------------------------------------------

  /// The one big button on the Live page. What it does depends on the
  /// moment: start/pause, then next round, then finish the event.
  Future<void> primaryAction() async {
    if (state.eventFinished) {
      setState(() => page = AppPage.setup);
      return;
    }
    if (state.timeCalled) {
      await nextRound();
      return;
    }
    await toggleTimer();
  }

  String get primaryActionLabel {
    if (state.eventFinished) return 'Start New Event';
    if (state.timeCalled) {
      return state.isFinalRound ? 'Finish Event' : 'Next Round';
    }
    return state.running ? 'Pause' : 'Start';
  }

  Future<void> toggleTimer() async {
    if (state.eventFinished) return;
    sound.prime();

    final remaining = state.remainingNow;
    await _setStateModel(
      state.withTimer(
        running: remaining > 0 && !state.running,
        remainingSeconds: remaining,
      ),
    );
  }

  Future<void> adjustTime(int seconds) async {
    if (state.eventFinished) return;
    final next = state.adjustedBy(seconds);
    final sign = seconds < 0 ? '−' : '+';
    await _commitWithUndo(
      next,
      '$sign${seconds.abs() ~/ 60} min · now ${formatSeconds(next.remainingNow)}',
    );
  }

  Future<void> setRemainingTime(int seconds) async {
    if (state.eventFinished) return;
    final next = state.withTimer(
      running: state.running && seconds > 0,
      remainingSeconds: seconds,
    );
    await _commitWithUndo(next, 'Timer set to ${formatSeconds(seconds)}');
  }

  Future<void> nextRound() async {
    if (state.eventFinished) return;
    await flushAutosave();

    // In the final round, "next" means ending the event.
    if (state.isFinalRound) {
      await finishEvent();
      return;
    }

    final next = state.currentRound + 1;
    await _commitWithUndo(
      state
          .withTimer(
            running: false,
            remainingSeconds: state.roundLengthMinutes * 60,
          )
          .copyWith(currentRound: next, displayMode: DisplayMode.timer),
      'Round $next is ready · ${formatSeconds(state.roundLengthMinutes * 60)}',
      syncText: true,
    );
  }

  Future<void> restartRound() async {
    await flushAutosave();
    await _commitWithUndo(
      state
          .withTimer(
            running: false,
            remainingSeconds: state.roundLengthMinutes * 60,
          )
          .copyWith(eventFinished: false, displayMode: DisplayMode.timer),
      'Round ${state.currentRound} restarted',
    );
  }

  /// Asks for the top three, then shows the podium on the player screen.
  Future<void> finishEvent() async {
    if (state.eventFinished) return;
    await flushAutosave();
    if (!mounted) return;

    final dialogContext = navigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) return;
    final winners = await showFinishEventDialog(dialogContext, state);
    if (winners == null) return;

    await _commitWithUndo(
      state.withTimer(running: false, remainingSeconds: 0).copyWith(
            eventFinished: true,
            displayMode: DisplayMode.winners,
            firstPlace: winners[0],
            secondPlace: winners[1],
            thirdPlace: winners[2],
          ),
      'Event finished · the podium is on the player screen',
    );
  }

  /// Keeps the event settings but starts again at round 1.
  Future<void> startNewEvent() async {
    autosaveTimer?.cancel();
    await _commitWithUndo(
      _freshEvent(state),
      'New event ready · round 1',
      syncText: true,
    );
  }

  TimerStateModel _freshEvent(TimerStateModel base) {
    return base
        .withTimer(
          running: false,
          remainingSeconds: base.roundLengthMinutes * 60,
        )
        .copyWith(
          currentRound: 1,
          eventFinished: false,
          displayMode: DisplayMode.timer,
          playerMessage: '',
          firstPlace: '',
          secondPlace: '',
          thirdPlace: '',
        );
  }

  // ---------------------------------------------------------------------
  // Player screen content
  // ---------------------------------------------------------------------

  Future<void> setDisplayMode(DisplayMode mode) async {
    await _setStateModel(state.copyWith(displayMode: mode));
  }

  Future<void> toggleBlackScreen() async {
    final back = state.eventFinished ? DisplayMode.winners : DisplayMode.timer;
    await setDisplayMode(
      state.displayMode == DisplayMode.black ? back : DisplayMode.black,
    );
  }

  Future<void> showPlayerMessage([String? text]) async {
    final message = (text ?? messageInput.text).trim();
    if (message.isEmpty) return;
    messageInput.text = message;
    await _setStateModel(state.copyWith(playerMessage: message));
    await _rememberMessage(message);
  }

  Future<void> hidePlayerMessage() async {
    await _setStateModel(state.copyWith(playerMessage: ''));
  }

  Future<void> togglePlayerMessage() async {
    if (state.playerMessage.isNotEmpty) {
      await hidePlayerMessage();
    } else {
      await showPlayerMessage();
    }
  }

  void _loadRecentMessages() {
    recentMessages = prefs?.getStringList(messagesStorageKey) ?? [];
  }

  Future<void> _rememberMessage(String message) async {
    final next = [message, ...recentMessages.where((m) => m != message)];
    setState(() => recentMessages = next.take(5).toList());
    await prefs?.setStringList(messagesStorageKey, recentMessages);
  }

  // ---------------------------------------------------------------------
  // Second screen
  // ---------------------------------------------------------------------

  Future<void> refreshDisplay() async {
    final next = await display.status();
    if (mounted) setState(() => displayStatus = next);
  }

  Future<void> _restorePlayerWindow() async {
    final raw = prefs?.getString(displayStorageKey);
    if (raw != null) {
      try {
        final saved = jsonDecode(raw) as Map<String, dynamic>;
        rememberedScreenId = (saved['screenId'] as num?)?.toInt();
        wantPlayerOpen = saved['open'] as bool? ?? false;
      } catch (_) {
        // Start without a remembered screen.
      }
    }

    await refreshDisplay();

    // Reopen the player screen where it was, if that screen is connected.
    // Browsers block popups without a click, so this is desktop only.
    if (display.isDesktop &&
        wantPlayerOpen &&
        !displayStatus.playerOpen &&
        displayStatus.screenById(rememberedScreenId) != null) {
      await openPlayerWindow(screenId: rememberedScreenId);
    }
  }

  Future<void> _saveDisplayChoice() async {
    await prefs?.setString(
      displayStorageKey,
      jsonEncode({'screenId': rememberedScreenId, 'open': wantPlayerOpen}),
    );
  }

  Future<void> openPlayerWindow({int? screenId}) async {
    final remembered = displayStatus.screenById(rememberedScreenId) != null
        ? rememberedScreenId
        : null;
    final status = await display.open(screenId: screenId ?? remembered);

    if (status == null) {
      showMessage(
        'The browser blocked the player window. Allow pop-ups for this page and try again.',
      );
      return;
    }

    setState(() {
      displayStatus = status;
      wantPlayerOpen = status.playerOpen;
      if (status.playerScreenId != null) {
        rememberedScreenId = status.playerScreenId;
      }
    });
    await _saveDisplayChoice();
    _broadcastState();
  }

  Future<void> closePlayerWindow() async {
    final status = await display.close();
    setState(() {
      displayStatus = status;
      wantPlayerOpen = false;
    });
    await _saveDisplayChoice();
  }

  /// Fallback without a second screen: show the player screen full screen in
  /// this window. Esc returns to the control panel.
  void openPlayerScreenFullscreen() {
    setState(() => fullscreenPlayer = true);
    // Browsers allow fullscreen only directly after a user action.
    html.document.documentElement?.requestFullscreen();
    wakeLock.keepOn();
  }

  void exitPlayerScreenFullscreen() {
    if (html.document.fullscreenElement != null) {
      html.document.exitFullscreen();
    }
    wakeLock.release();
    if (mounted) setState(() => fullscreenPlayer = false);
  }

  // ---------------------------------------------------------------------
  // Keyboard shortcuts and sounds
  // ---------------------------------------------------------------------

  bool get _isTyping {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && fullscreenPlayer) {
      exitPlayerScreenFullscreen();
      return true;
    }

    // Leave keys alone while typing, in dialogs, and with modifier keys.
    final keyboard = HardwareKeyboard.instance;
    if (_isTyping ||
        navigatorKey.currentState?.canPop() == true ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return false;
    }

    if (key == LogicalKeyboardKey.space) {
      primaryAction();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      adjustTime(-60);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      adjustTime(60);
    } else if (key == LogicalKeyboardKey.keyN) {
      nextRound();
    } else if (key == LogicalKeyboardKey.keyM) {
      togglePlayerMessage();
    } else if (key == LogicalKeyboardKey.keyB) {
      toggleBlackScreen();
    } else {
      return false;
    }
    return true;
  }

  void _playSounds() {
    final remaining = state.remainingNow;
    final previous = _lastTickRemaining;
    _lastTickRemaining = remaining;

    // Only chime while the clock runs down on its own, not after a manual
    // jump such as −1 min or loading a preset.
    if (!state.soundEnabled || previous < 0 || previous - remaining > 2) {
      return;
    }
    if (previous > 300 && remaining <= 300 && remaining > 0) {
      _playSound(SoundCue.warning);
    }
  }

  /// Rings the bell when a running round reaches zero. Called at the moment
  /// the timer stops, so it does not depend on catching the exact tick (the
  /// window may be in the background). A timer that ran out long ago, e.g.
  /// while the app was closed, stays silent.
  void _playTimeUpSound() {
    if (!state.soundEnabled || state.eventFinished) return;
    final late = DateTime.now().millisecondsSinceEpoch - state.endsAtMillis;
    if (late > 15000) return;
    _playSound(SoundCue.timeUp);
  }

  /// When the player window last said it can play sound (0 = it cannot).
  int _playerSoundReadyAt = 0;

  /// True while a player window is open and able to play sound. It reports
  /// in every 2 seconds.
  bool get soundOnPlayerScreen =>
      DateTime.now().millisecondsSinceEpoch - _playerSoundReadyAt < 5000;

  /// Plays a cue on the player screen (the TV speakers). If no player window
  /// can play sound, the laptop plays it instead so it is never lost.
  void _playSound(String cue) {
    if (soundOnPlayerScreen) {
      _post({'type': 'sound', 'sound': cue, 'volume': state.soundVolume});
    } else {
      _playLocally(cue, state.soundVolume);
    }
  }

  void _playLocally(String? cue, double volume) {
    if (cue == SoundCue.warning) sound.warning(volume);
    if (cue == SoundCue.timeUp) sound.timeUp(volume);
  }

  void _reportPlayerAlive() {
    _post({'type': 'player-alive', 'audio': sound.isReady});
  }

  // ---------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------

  Future<void> changeGame(String value) async {
    await _setStateModel(state.copyWith(game: normalizeGame(value)));
  }

  Future<void> changeMatchFormat(String value) async {
    await _setStateModel(
      state.copyWith(matchFormat: normalizeMatchFormat(value)),
    );
  }

  Future<void> changeLogoMode(bool value) async {
    await _setStateModel(state.copyWith(useCustomLogo: value));
  }

  Future<void> changeSound({bool? enabled, double? volume}) async {
    sound.prime();
    await _setStateModel(
      state.copyWith(soundEnabled: enabled, soundVolume: volume),
    );
  }

  void testWarningSound() {
    sound.prime();
    _playSound(SoundCue.warning);
  }

  void testTimeUpSound() {
    sound.prime();
    _playSound(SoundCue.timeUp);
  }

  // ---------------------------------------------------------------------
  // Presets
  // ---------------------------------------------------------------------

  Future<void> loadPreset(EventPreset preset) async {
    // The preset replaces the setup fields, so pending edits are dropped.
    autosaveTimer?.cancel();
    final base = state.copyWith(
      eventName: preset.name,
      game: preset.game,
      matchFormat: preset.matchFormat,
      roundLengthMinutes: preset.roundLengthMinutes,
      totalRounds: preset.rounds,
      timeCalledNote: preset.timeCalledNote,
    );
    await _commitWithUndo(
      _freshEvent(base),
      'Loaded preset "${preset.name}"',
      syncText: true,
    );
  }

  Future<void> saveCurrentSetupAsPreset() async {
    await flushAutosave();
    final created = EventPreset(
      state.eventName,
      state.game,
      state.matchFormat,
      state.roundLengthMinutes,
      state.totalRounds,
      timeCalledNote: state.timeCalledNote,
    );

    await _setPresets([...presets, created]);
    showMessage('Saved "${created.name}" as preset.');
  }

  Future<void> createPreset(EventPreset preset) async {
    await _setPresets([...presets, preset]);
  }

  /// Replaces the preset with the same id. If it was deleted in the meantime,
  /// the edit is kept as a new preset instead of overwriting another one.
  Future<void> updatePreset(EventPreset preset) async {
    final index = presets.indexWhere((item) => item.id == preset.id);
    if (index < 0) {
      await _setPresets([...presets, preset]);
      return;
    }
    final next = [...presets];
    next[index] = preset;
    await _setPresets(next);
  }

  Future<void> deletePreset(String id) async {
    final index = presets.indexWhere((item) => item.id == id);
    if (index < 0) return;

    final removed = presets[index];
    await _setPresets([...presets]..removeAt(index));

    showMessage(
      'Deleted preset "${removed.name}".',
      actionLabel: 'Undo',
      onAction: () {
        if (presets.any((item) => item.id == removed.id)) return;
        final at = math.min(index, presets.length);
        _setPresets([...presets]..insert(at, removed));
      },
    );
  }

  Future<void> restoreDefaultPresets() async {
    final missing = EventPreset.missingDefaults(presets);
    if (missing.isEmpty) {
      showMessage('All default presets are already in your list.');
      return;
    }
    await _setPresets([...presets, ...missing]);
    showMessage(
      'Added ${missing.length} default preset${missing.length == 1 ? '' : 's'}.',
    );
  }

  void goTo(int target) {
    setState(() => page = target);
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
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      title: playerOnly ? 'Big Ink TCG Timer – Player Screen' : 'Big Ink TCG Timer',
      theme: theme,
      // The player window is opened with #player in the URL. Without this,
      // Flutter would try to treat that as a route name.
      initialRoute: '/',
      // The player screen needs a Material ancestor for its round chips.
      home: playerOnly
          ? Scaffold(body: PlayerScreen(state: state))
          : fullscreenPlayer
              ? Scaffold(body: PlayerScreen(state: state))
              : Scaffold(
                  body: SafeArea(
                    child: Row(
                      children: [
                        NavigationRail(
                          selectedIndex: page,
                          extended: MediaQuery.of(context).size.width > 1250,
                          onDestinationSelected: (value) async {
                            await flushAutosave();
                            goTo(value);
                          },
                          backgroundColor: Colors.black.withOpacity(0.25),
                          destinations: const [
                            NavigationRailDestination(
                              icon: Icon(Icons.timer_outlined),
                              selectedIcon: Icon(Icons.timer),
                              label: Text('Live'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.tune_outlined),
                              selectedIcon: Icon(Icons.tune),
                              label: Text('Setup'),
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
                              LivePage(key: const ValueKey('live'), app: this),
                              SetupPage(key: const ValueKey('setup'), app: this),
                              PresetsPage(
                                key: const ValueKey('presets'),
                                presets: presets,
                                onLoadPreset: (preset) async {
                                  await loadPreset(preset);
                                  goTo(AppPage.live);
                                },
                                onSaveCurrentPreset: saveCurrentSetupAsPreset,
                                onCreatePreset: createPreset,
                                onUpdatePreset: updatePreset,
                                onDeletePreset: deletePreset,
                                onRestoreDefaults: restoreDefaultPresets,
                              ),
                            ][page],
                          ),
                        ),
                      ],
                    ),
                  ),
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

    if (state.displayMode == DisplayMode.black) {
      return const ColoredBox(color: Colors.black, child: SizedBox.expand());
    }
    if (state.eventFinished || state.displayMode == DisplayMode.winners) {
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
        final hasMessage = state.playerMessage.isNotEmpty;

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
                              state.game,
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
                            Opacity(
                              opacity: !state.running && remaining > 0
                                  ? 0.55
                                  : 1,
                              child: Text(
                                remaining <= 0
                                    ? 'TIME CALLED'
                                    : formatSeconds(remaining),
                                style: TextStyle(
                                  fontSize: timerSize,
                                  height: 0.82,
                                  fontWeight: FontWeight.w900,
                                  // Equal-width digits keep the time from
                                  // shifting sideways as it counts down.
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  letterSpacing:
                                      remaining <= 0 ? -7 * scale : -8 * scale,
                                  color: state.timerColor,
                                ),
                              ),
                            ),
                            SizedBox(height: 18 * scale),
                            Text(
                              remaining <= 0
                                  ? 'Please finish your current turn'
                                  : !state.running
                                      ? 'Paused'
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
                            if (remaining <= 0 &&
                                state.timeCalledNote.isNotEmpty) ...[
                              SizedBox(height: 8 * scale),
                              Text(
                                state.timeCalledNote,
                                style: TextStyle(
                                  fontSize: statusTextSize * 0.8,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFFACC15),
                                ),
                              ),
                            ],
                            if (remaining <= 0 && state.calledAtMillis > 0) ...[
                              SizedBox(height: 8 * scale),
                              Text(
                                'Overtime +${formatSeconds(state.overtimeSeconds)}',
                                style: softText.copyWith(
                                  fontSize: statusTextSize * 0.7,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8 * scale),
                    child: LinearProgressIndicator(
                      value: state.progress,
                      minHeight: compact ? 6 : 10 * scale,
                      color: state.timerColor,
                      backgroundColor: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  SizedBox(height: 14 * scale),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: 24 * scale,
                      vertical: compact ? 14 : 22 * scale,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24 * scale),
                      color: hasMessage
                          ? const Color(0xFFFACC15).withOpacity(0.18)
                          : Colors.black.withOpacity(0.18),
                      border: hasMessage
                          ? Border.all(
                              color: const Color(0xFFFACC15).withOpacity(0.6),
                              width: 2,
                            )
                          : null,
                    ),
                    child: Text(
                      hasMessage
                          ? state.playerMessage
                          : remaining <= 0
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
                                // Places without a name are left out.
                                if (secondName.isNotEmpty)
                                  PodiumCard(
                                    placeLabel: '2nd Place',
                                    name: secondName,
                                    isPlaceholder: false,
                                    icon: Icons.looks_two,
                                    width: compact ? 230 : 282 * scale,
                                    height: compact ? 150 : 220 * scale,
                                    nameSize: podiumNameSize,
                                    placeSize: podiumPlaceSize,
                                    accent: const Color(0xFFC0C7D2),
                                  ),
                                if (firstName.isNotEmpty)
                                  PodiumCard(
                                    placeLabel: '1st Place',
                                    name: firstName,
                                    isPlaceholder: false,
                                    icon: Icons.looks_one,
                                    width: compact ? 245 : 300 * scale,
                                    height: compact ? 180 : 270 * scale,
                                    nameSize: podiumNameSize + 7 * scale,
                                    placeSize: podiumPlaceSize,
                                    accent: const Color(0xFFFACC15),
                                    isChampion: true,
                                  ),
                                if (thirdName.isNotEmpty)
                                  PodiumCard(
                                    placeLabel: '3rd Place',
                                    name: thirdName,
                                    isPlaceholder: false,
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
  final Future<void> Function(EventPreset preset) onUpdatePreset;
  final Future<void> Function(String id) onDeletePreset;
  final Future<void> Function() onRestoreDefaults;

  @override
  State<PresetsPage> createState() => _PresetsPageState();
}

class _PresetsPageState extends State<PresetsPage> {
  final presetName = TextEditingController();
  final presetRoundLength = TextEditingController(text: '50');
  final presetRounds = TextEditingController(text: '4');
  final presetNote = TextEditingController();

  String presetGame = 'Disney Lorcana';
  String presetMatchFormat = 'BO1';
  // The id of the preset being edited. An id stays valid when other presets
  // are deleted, unlike a list index.
  String? editingId;

  @override
  void dispose() {
    presetName.dispose();
    presetRoundLength.dispose();
    presetRounds.dispose();
    presetNote.dispose();
    super.dispose();
  }

  void clearEditor() {
    setState(() {
      editingId = null;
      presetName.clear();
      presetGame = 'Disney Lorcana';
      presetMatchFormat = 'BO1';
      presetRoundLength.text = '50';
      presetRounds.text = '4';
      presetNote.clear();
    });
  }

  void startEditing(EventPreset preset) {
    setState(() {
      editingId = preset.id;
      presetName.text = preset.name;
      presetGame = normalizeGame(preset.game);
      presetMatchFormat = matchFormatOptions.contains(preset.matchFormat)
          ? preset.matchFormat
          : 'BO1';
      presetRoundLength.text = preset.roundLengthMinutes.toString();
      presetRounds.text = preset.rounds.toString();
      presetNote.text = preset.timeCalledNote;
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

    return EventPreset(
      name,
      presetGame,
      presetMatchFormat,
      roundLength,
      rounds,
      id: editingId,
      timeCalledNote: presetNote.text.trim(),
    );
  }

  Future<void> saveEditorPreset() async {
    final preset = readEditorPreset();

    if (editingId == null) {
      await widget.onCreatePreset(preset);
    } else {
      await widget.onUpdatePreset(preset);
    }

    clearEditor();
  }

  Future<void> deletePreset(EventPreset preset) async {
    if (preset.id == editingId) clearEditor();
    await widget.onDeletePreset(preset.id);
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
                  editingId == null ? 'Preset Editor' : 'Editing Preset',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  editingId == null
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
                          width: wide ? fieldWidth * 2 + 12 : fieldWidth,
                          child: TextField(
                            controller: presetNote,
                            decoration: const InputDecoration(
                              labelText: 'Note shown at TIME (optional)',
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
                        editingId == null
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
                          '${preset.game} · ${preset.matchFormat}\n${preset.rounds} rounds · ${preset.roundLengthMinutes} min'
                          '${preset.timeCalledNote.isEmpty ? '' : '\nAt TIME: ${preset.timeCalledNote}'}',
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
                                onPressed: () => startEditing(preset),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Edit'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => deletePreset(preset),
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
    required this.useCustomLogo,
    required this.eventFinished,
    required this.firstPlace,
    required this.secondPlace,
    required this.thirdPlace,
    required this.remainingSeconds,
    required this.running,
    required this.lastUpdateMillis,
    this.endsAtMillis = 0,
    this.calledAtMillis = 0,
    this.displayMode = DisplayMode.timer,
    this.playerMessage = '',
    this.timeCalledNote = '',
    this.soundEnabled = true,
    this.soundVolume = 0.7,
  });

  factory TimerStateModel.defaults() {
    return TimerStateModel(
      eventName: 'Lorcana Weekly League',
      game: 'Disney Lorcana',
      matchFormat: 'BO1',
      roundLengthMinutes: 50,
      currentRound: 1,
      totalRounds: 6,
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
    final running = json['running'] as bool? ?? false;
    final remainingSeconds =
        (json['remainingSeconds'] as num?)?.toInt() ?? 50 * 60;
    final lastUpdateMillis = (json['lastUpdateMillis'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;

    // Data saved before endsAtMillis existed: derive the end time the same
    // way the old remainingSeconds + lastUpdateMillis pair implied it.
    final endsAtMillis = (json['endsAtMillis'] as num?)?.toInt() ??
        (running ? lastUpdateMillis + remainingSeconds * 1000 : 0);

    return TimerStateModel(
      eventName: json['eventName'] as String? ?? 'TCG Event',
      game: normalizeGame(json['game'] as String? ?? 'Disney Lorcana'),
      matchFormat:
          normalizeMatchFormat(json['matchFormat'] as String? ?? 'BO1'),
      roundLengthMinutes: (json['roundLengthMinutes'] as num?)?.toInt() ?? 50,
      currentRound: (json['currentRound'] as num?)?.toInt() ?? 1,
      totalRounds: (json['totalRounds'] as num?)?.toInt() ?? 4,
      useCustomLogo: json['useCustomLogo'] as bool? ?? false,
      eventFinished: json['eventFinished'] as bool? ?? false,
      firstPlace: json['firstPlace'] as String? ?? '',
      secondPlace: json['secondPlace'] as String? ?? '',
      thirdPlace: json['thirdPlace'] as String? ?? '',
      remainingSeconds: remainingSeconds,
      running: running,
      lastUpdateMillis: lastUpdateMillis,
      endsAtMillis: endsAtMillis,
      calledAtMillis: (json['calledAtMillis'] as num?)?.toInt() ?? 0,
      displayMode: DisplayMode.parse(json['displayMode'] as String?),
      playerMessage: json['playerMessage'] as String? ?? '',
      timeCalledNote: json['timeCalledNote'] as String? ?? '',
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      soundVolume:
          ((json['soundVolume'] as num?)?.toDouble() ?? 0.7).clamp(0.0, 1.0),
    );
  }

  final String eventName;
  final String game;
  final String matchFormat;
  final int roundLengthMinutes;
  final int currentRound;
  final int totalRounds;
  final bool useCustomLogo;
  final bool eventFinished;
  final String firstPlace;
  final String secondPlace;
  final String thirdPlace;
  final int remainingSeconds;
  final bool running;
  final int lastUpdateMillis;

  /// Wall-clock time (ms since epoch) at which a running timer reaches zero.
  /// Only meaningful while [running]; paused timers use [remainingSeconds].
  final int endsAtMillis;

  /// When time was called (ms since epoch), or 0. Used for the overtime count.
  final int calledAtMillis;

  /// What the player screen shows: the timer, the winner podium, or nothing.
  final DisplayMode displayMode;

  /// Announcement shown at the bottom of the player screen, if not empty.
  final String playerMessage;

  /// Shown under TIME, e.g. "Finish the turn + 3 turns".
  final String timeCalledNote;

  final bool soundEnabled;
  final double soundVolume;

  bool get isFinalRound => currentRound >= totalRounds;

  bool get timeCalled => !eventFinished && remainingNow <= 0;

  /// Seconds since time was called, or 0 while the round is still running.
  int get overtimeSeconds {
    if (!timeCalled || calledAtMillis <= 0) return 0;
    final value =
        (DateTime.now().millisecondsSinceEpoch - calledAtMillis) ~/ 1000;
    return value < 0 ? 0 : value;
  }

  /// Share of the round that is left, from 1.0 (full) to 0.0.
  double get progress {
    final total = roundLengthMinutes * 60;
    if (total <= 0) return 0;
    return (remainingNow / total).clamp(0.0, 1.0);
  }

  int get remainingNow {
    if (eventFinished) return 0;
    if (!running) return remainingSeconds < 0 ? 0 : remainingSeconds;
    final leftMillis = endsAtMillis - DateTime.now().millisecondsSinceEpoch;
    // Round up so the display shows 00:01 until the very last moment and
    // only reaches 00:00 when time is actually up.
    final value = (leftMillis / 1000).ceil();
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

  /// Sets the timer to [remainingSeconds] and starts or stops it.
  TimerStateModel withTimer({
    required bool running,
    required int remainingSeconds,
  }) {
    final safe = remainingSeconds < 0 ? 0 : remainingSeconds;
    return copyWith(
      running: running,
      remainingSeconds: safe,
      endsAtMillis:
          running ? DateTime.now().millisecondsSinceEpoch + safe * 1000 : 0,
      calledAtMillis: 0,
    );
  }

  /// Stops a timer that ran out and remembers when that happened.
  TimerStateModel withTimeCalled() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final calledAt =
        running && endsAtMillis > 0 && endsAtMillis <= now ? endsAtMillis : now;
    return withTimer(running: false, remainingSeconds: 0)
        .copyWith(calledAtMillis: calledAt);
  }

  /// Adds [seconds] (or removes them, if negative) without losing the
  /// sub-second position of a running timer.
  TimerStateModel adjustedBy(int seconds) {
    if (!running) {
      return withTimer(running: false, remainingSeconds: remainingNow + seconds);
    }
    final nextEnd = endsAtMillis + seconds * 1000;
    return copyWith(
      endsAtMillis: nextEnd,
      remainingSeconds:
          ((nextEnd - DateTime.now().millisecondsSinceEpoch) / 1000).ceil(),
    );
  }

  TimerStateModel withFreshTimestamp() =>
      copyWith(lastUpdateMillis: DateTime.now().millisecondsSinceEpoch);

  Map<String, dynamic> toJson() => {
        'eventName': eventName,
        'game': game,
        'matchFormat': matchFormat,
        'roundLengthMinutes': roundLengthMinutes,
        'currentRound': currentRound,
        'totalRounds': totalRounds,
        'useCustomLogo': useCustomLogo,
        'eventFinished': eventFinished,
        'firstPlace': firstPlace,
        'secondPlace': secondPlace,
        'thirdPlace': thirdPlace,
        'remainingSeconds': remainingNow,
        'running': running && remainingNow > 0 && !eventFinished,
        'endsAtMillis': endsAtMillis,
        'calledAtMillis': calledAtMillis,
        'displayMode': displayMode.name,
        'playerMessage': playerMessage,
        'timeCalledNote': timeCalledNote,
        'soundEnabled': soundEnabled,
        'soundVolume': soundVolume,
        'lastUpdateMillis': DateTime.now().millisecondsSinceEpoch,
      };

  TimerStateModel copyWith({
    String? eventName,
    String? game,
    String? matchFormat,
    int? roundLengthMinutes,
    int? currentRound,
    int? totalRounds,
    bool? useCustomLogo,
    bool? eventFinished,
    String? firstPlace,
    String? secondPlace,
    String? thirdPlace,
    int? remainingSeconds,
    bool? running,
    int? lastUpdateMillis,
    int? endsAtMillis,
    int? calledAtMillis,
    DisplayMode? displayMode,
    String? playerMessage,
    String? timeCalledNote,
    bool? soundEnabled,
    double? soundVolume,
  }) {
    return TimerStateModel(
      eventName: eventName ?? this.eventName,
      game: game ?? this.game,
      matchFormat: matchFormat ?? this.matchFormat,
      roundLengthMinutes: roundLengthMinutes ?? this.roundLengthMinutes,
      currentRound: currentRound ?? this.currentRound,
      totalRounds: totalRounds ?? this.totalRounds,
      useCustomLogo: useCustomLogo ?? this.useCustomLogo,
      eventFinished: eventFinished ?? this.eventFinished,
      firstPlace: firstPlace ?? this.firstPlace,
      secondPlace: secondPlace ?? this.secondPlace,
      thirdPlace: thirdPlace ?? this.thirdPlace,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      running: running ?? this.running,
      lastUpdateMillis: lastUpdateMillis ?? this.lastUpdateMillis,
      endsAtMillis: endsAtMillis ?? this.endsAtMillis,
      calledAtMillis: calledAtMillis ?? this.calledAtMillis,
      displayMode: displayMode ?? this.displayMode,
      playerMessage: playerMessage ?? this.playerMessage,
      timeCalledNote: timeCalledNote ?? this.timeCalledNote,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      soundVolume: soundVolume ?? this.soundVolume,
    );
  }
}

enum DisplayMode {
  timer,
  winners,
  black;

  static DisplayMode parse(String? name) => DisplayMode.values.firstWhere(
        (mode) => mode.name == name,
        orElse: () => DisplayMode.timer,
      );
}

class EventPreset {
  EventPreset(
    this.name,
    this.game,
    this.matchFormat,
    this.roundLengthMinutes,
    this.rounds, {
    String? id,
    this.timeCalledNote = '',
  }) : id = id ?? newPresetId();

  factory EventPreset.fromJson(Map<String, dynamic> json) {
    return EventPreset(
      json['name'] as String? ?? 'Event Preset',
      normalizeGame(json['game'] as String? ?? 'Disney Lorcana'),
      normalizeMatchFormat(json['matchFormat'] as String? ?? 'BO1'),
      (json['roundLengthMinutes'] as num?)?.toInt() ?? 50,
      (json['rounds'] as num?)?.toInt() ?? 4,
      // Presets saved before ids existed get a fresh one on load.
      id: json['id'] as String?,
      timeCalledNote: json['timeCalledNote'] as String? ?? '',
    );
  }

  static List<EventPreset> defaultPresets() {
    return [
      EventPreset(
        'Lorcana Weekly League',
        'Disney Lorcana',
        'BO1',
        50,
        4,
        id: 'default-lorcana-weekly',
      ),
      EventPreset(
        'Pokémon Casual Night',
        'Pokémon',
        'BO1',
        30,
        3,
        id: 'default-pokemon-casual',
      ),
      EventPreset(
        'Commander Night',
        'Magic Commander',
        'BO3',
        60,
        1,
        id: 'default-commander-night',
      ),
    ];
  }

  /// Default presets that are not in [existing] yet, matched by id or by
  /// name (older saved defaults have no fixed id).
  static List<EventPreset> missingDefaults(List<EventPreset> existing) {
    final ids = existing.map((preset) => preset.id).toSet();
    final names = existing.map((preset) => preset.name).toSet();
    return defaultPresets()
        .where(
          (preset) =>
              !ids.contains(preset.id) && !names.contains(preset.name),
        )
        .toList();
  }

  final String id;
  final String timeCalledNote;
  final String name;
  final String game;
  final String matchFormat;
  final int roundLengthMinutes;
  final int rounds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'timeCalledNote': timeCalledNote,
        'name': name,
        'game': game,
        'matchFormat': matchFormat,
        'roundLengthMinutes': roundLengthMinutes,
        'rounds': rounds,
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

/// Maps unknown game names (old or edited saved data) to 'Random', so the
/// game dropdowns always find their current value in the item list.
String normalizeGame(String value) {
  return gameOptions.contains(value) ? value : 'Random';
}

final _presetIdRandom = math.Random();

String newPresetId() {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = _presetIdRandom.nextInt(0x7fffffff).toRadixString(36);
  return 'preset-$time-$salt';
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
