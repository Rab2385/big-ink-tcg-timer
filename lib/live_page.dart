// The Live page: everything the organizer needs while a round is running,
// plus control of what the player screen (screen 2) shows.
import 'package:flutter/material.dart';

import 'package:flutter_application_ft_event_timer/main.dart';

const _green = Color(0xFF4ADE80);
const _yellow = Color(0xFFFACC15);
const _orange = Color(0xFFFB923C);
const _muted = Color(0xFF8A9BB5);

class LivePage extends StatelessWidget {
  const LivePage({required this.app, super.key});

  final BigInkTimerAppState app;

  @override
  Widget build(BuildContext context) {
    final state = app.state;

    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.eventName,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${state.game} · ${state.matchFormat} · '
                    '${state.roundLengthMinutes} min',
                    style: softText,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                StatusBadge(text: state.status, color: state.statusColor),
                ScreenBadge(app: app),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final timer = TimerPanel(app: app);
            final screen = ScreenPanel(app: app);
            if (constraints.maxWidth < 960) {
              return Column(
                children: [timer, const SizedBox(height: 16), screen],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: timer),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: screen),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        const ShortcutHints(),
        const SizedBox(height: 14),
        Text(appVersion, style: softText.copyWith(fontSize: 12)),
      ],
    );
  }
}

class TimerPanel extends StatelessWidget {
  const TimerPanel({required this.app, super.key});

  final BigInkTimerAppState app;

  @override
  Widget build(BuildContext context) {
    final state = app.state;
    final finished = state.eventFinished;
    final called = state.timeCalled;

    final String detail;
    if (finished) {
      detail = 'Event finished · start a new event in Setup';
    } else if (called) {
      final note =
          state.timeCalledNote.isEmpty ? '' : ' · ${state.timeCalledNote}';
      detail =
          'Time called · overtime +${formatSeconds(state.overtimeSeconds)}$note';
    } else if (state.running) {
      final end = DateTime.fromMillisecondsSinceEpoch(state.endsAtMillis);
      detail = 'Ends at ${_clock(end)}';
    } else {
      detail = 'Paused · press Space to start';
    }

    final IconData primaryIcon;
    if (finished) {
      primaryIcon = Icons.restart_alt;
    } else if (called) {
      primaryIcon =
          state.isFinalRound ? Icons.emoji_events_outlined : Icons.skip_next;
    } else {
      primaryIcon = state.running ? Icons.pause : Icons.play_arrow;
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                finished
                    ? 'ALL ${state.totalRounds} ROUNDS PLAYED'
                    : 'ROUND ${state.currentRound} OF ${state.totalRounds}',
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              const Spacer(),
              if (state.isFinalRound && !finished)
                const StatusBadge(text: 'FINAL ROUND', color: _yellow),
            ],
          ),
          const SizedBox(height: 10),
          RoundStepper(
            current: finished ? state.totalRounds + 1 : state.currentRound,
            total: state.totalRounds,
          ),
          const SizedBox(height: 18),
          Tooltip(
            message: 'Click to set the time',
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: finished ? null : () => _setTime(context),
              child: FittedBox(
                child: Text(
                  finished
                      ? 'DONE'
                      : called
                          ? 'TIME'
                          : formatSeconds(state.remainingNow),
                  style: TextStyle(
                    fontSize: 150,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: state.timerColor,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: 8,
              color: state.timerColor,
              backgroundColor: Colors.white.withOpacity(0.08),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: softText.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    style: called && state.isFinalRound && !finished
                        ? FilledButton.styleFrom(
                            backgroundColor: _yellow,
                            foregroundColor: Colors.black,
                          )
                        : null,
                    onPressed: app.primaryAction,
                    icon: Icon(primaryIcon),
                    label: Text(
                      app.primaryActionLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              for (final (label, seconds) in const [
                ('−1', -60),
                ('+1', 60),
                ('+5', 300),
              ]) ...[
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed:
                          finished ? null : () => app.adjustTime(seconds),
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                if (seconds != 300) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // After TIME the big button already moves on, so don't repeat it.
              if (!called || finished)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: finished ? null : app.nextRound,
                    icon: Icon(
                      state.isFinalRound
                          ? Icons.emoji_events_outlined
                          : Icons.skip_next,
                    ),
                    label: Text(
                      state.isFinalRound ? 'Finish Event' : 'Next Round',
                    ),
                  ),
                ),
              if (!called || finished) const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: app.restartRound,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Restart Round'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _setTime(BuildContext context) async {
    final seconds = await showSetTimeDialog(context, app.state.remainingNow);
    if (seconds != null) await app.setRemainingTime(seconds);
  }
}

class ScreenPanel extends StatelessWidget {
  const ScreenPanel({required this.app, super.key});

  final BigInkTimerAppState app;

  @override
  Widget build(BuildContext context) {
    final state = app.state;
    final status = app.displayStatus;
    final desktop = app.display.isDesktop;
    final screen = status.screenById(status.playerScreenId);
    // A finished event shows the podium even when "Timer" was selected.
    final shownMode =
        state.eventFinished && state.displayMode == DisplayMode.timer
            ? DisplayMode.winners
            : state.displayMode;

    final String output;
    if (status.playerOpen && screen != null && !status.windowed) {
      output = '${screen.label} · ${screen.size}';
    } else if (status.playerOpen) {
      output = desktop
          ? 'Window on this screen. Drag it to the TV.'
          : 'Separate window. Drag it to the TV and press F11.';
    } else if (desktop && !status.hasExternalScreen) {
      output = 'No second screen connected.';
    } else {
      output = 'Not shown yet.';
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              const Text(
                'PLAYER SCREEN',
                style: TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              SegmentedButton<DisplayMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(value: DisplayMode.timer, label: Text('Timer')),
                  ButtonSegment(
                    value: DisplayMode.winners,
                    label: Text('Winners'),
                  ),
                  ButtonSegment(value: DisplayMode.black, label: Text('Black')),
                ],
                selected: {shownMode},
                onSelectionChanged: (selection) =>
                    app.setDisplayMode(selection.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PlayerPreview(state: state),
          const SizedBox(height: 12),
          Text(output, style: softText),
          const SizedBox(height: 4),
          Text(
            !state.soundEnabled
                ? 'Sound is off (Setup → Details).'
                : app.soundOnPlayerScreen
                    ? 'Sound plays on the player screen (TV speakers).'
                    : status.playerOpen
                        ? 'Sound plays on this laptop. Click once in the player window to play it on the TV.'
                        : 'Sound plays on this laptop until the player screen is open.',
            style: softText.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status.playerOpen)
                OutlinedButton.icon(
                  onPressed: app.closePlayerWindow,
                  icon: const Icon(Icons.close),
                  label: const Text('Close Player Screen'),
                )
              else
                FilledButton.icon(
                  onPressed: app.openPlayerWindow,
                  icon: const Icon(Icons.tv),
                  label: Text(
                    desktop && !status.hasExternalScreen
                        ? 'Open in Window'
                        : 'Show on Screen 2',
                  ),
                ),
              if (desktop && status.screens.length > 1)
                OutlinedButton.icon(
                  onPressed: () => _chooseScreen(context),
                  icon: const Icon(Icons.monitor_outlined),
                  label: const Text('Choose Screen'),
                ),
              TextButton.icon(
                onPressed: app.openPlayerScreenFullscreen,
                icon: const Icon(Icons.fullscreen),
                label: const Text('Full Screen Here'),
              ),
            ],
          ),
          const Divider(height: 32),
          const Text(
            'MESSAGE TO PLAYERS',
            style: TextStyle(
              color: _muted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: app.messageInput,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Pairings for round 4 are up',
                    isDense: true,
                  ),
                  onSubmitted: (_) => app.showPlayerMessage(),
                ),
              ),
              const SizedBox(width: 8),
              if (state.playerMessage.isEmpty)
                FilledButton.tonal(
                  onPressed: app.showPlayerMessage,
                  child: const Text('Show'),
                )
              else
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _yellow,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: app.hidePlayerMessage,
                  child: const Text('Hide'),
                ),
            ],
          ),
          if (state.playerMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'On screen: “${state.playerMessage}”',
              style: const TextStyle(color: _yellow, fontSize: 13),
            ),
          ],
          if (app.recentMessages.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final message in app.recentMessages)
                  ActionChip(
                    label: Text(message, overflow: TextOverflow.ellipsis),
                    onPressed: () => app.showPlayerMessage(message),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _chooseScreen(BuildContext context) async {
    final status = app.displayStatus;
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Show the player screen on'),
        children: [
          for (final screen in status.screens)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(screen.id),
              child: ListTile(
                leading: Icon(
                  screen.id == status.playerScreenId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(screen.label),
                subtitle: Text(
                  screen.primary
                      ? '${screen.size} · this screen (covers the control panel)'
                      : screen.size,
                ),
              ),
            ),
        ],
      ),
    );
    if (chosen != null) await app.openPlayerWindow(screenId: chosen);
  }
}

/// Whether the player screen is showing, for the header.
class ScreenBadge extends StatelessWidget {
  const ScreenBadge({required this.app, super.key});

  final BigInkTimerAppState app;

  @override
  Widget build(BuildContext context) {
    final status = app.displayStatus;
    if (status.playerOpen) {
      return const StatusBadge(text: 'SCREEN 2 LIVE', color: _green);
    }
    if (app.wantPlayerOpen) {
      return const StatusBadge(text: 'SCREEN 2 DISCONNECTED', color: _orange);
    }
    return const StatusBadge(text: 'SCREEN 2 OFF', color: _muted);
  }
}

/// A small live copy of the player screen.
class PlayerPreview extends StatelessWidget {
  const PlayerPreview({required this.state, super.key});

  final TimerStateModel state;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.14)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: IgnorePointer(
            child: FittedBox(
              child: SizedBox(
                width: 1600,
                height: 900,
                child: PlayerScreen(state: state),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RoundStepper extends StatelessWidget {
  const RoundStepper({required this.current, required this.total, super.key});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF5FB3FF);
    final count = total.clamp(1, 24);
    return Row(
      children: [
        for (var round = 1; round <= count; round++) ...[
          if (round > 1) const SizedBox(width: 5),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: round < current
                    ? accent.withOpacity(0.55)
                    : round == current
                        ? accent
                        : Colors.white.withOpacity(0.1),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class ShortcutHints extends StatelessWidget {
  const ShortcutHints({super.key});

  @override
  Widget build(BuildContext context) {
    const hints = [
      ('Space', 'Start / pause'),
      ('Left / Right', '−1 / +1 min'),
      ('N', 'Next round'),
      ('M', 'Message on/off'),
      ('B', 'Black screen'),
      ('Esc', 'Leave full screen'),
    ];
    return Wrap(
      spacing: 18,
      runSpacing: 8,
      children: [
        for (final (key, label) in hints)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Text(
                  key,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(label, style: softText.copyWith(fontSize: 13)),
            ],
          ),
      ],
    );
  }
}

String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

/// Reads "12:30" as 12 min 30 s and "12" as 12 minutes. Returns null for
/// anything else.
int? parseTimeInput(String text) {
  final value = text.trim();
  if (value.isEmpty) return null;

  final parts = value.split(':');
  if (parts.length == 1) {
    final minutes = int.tryParse(parts[0]);
    if (minutes == null || minutes < 0 || minutes > 600) return null;
    return minutes * 60;
  }
  if (parts.length == 2) {
    final minutes = int.tryParse(parts[0].isEmpty ? '0' : parts[0]);
    final seconds = int.tryParse(parts[1]);
    if (minutes == null || seconds == null) return null;
    if (minutes < 0 || minutes > 600 || seconds < 0 || seconds > 59) {
      return null;
    }
    return minutes * 60 + seconds;
  }
  return null;
}

Future<int?> showSetTimeDialog(BuildContext context, int currentSeconds) {
  return showDialog<int>(
    context: context,
    builder: (_) => SetTimeDialog(initialSeconds: currentSeconds),
  );
}

class SetTimeDialog extends StatefulWidget {
  const SetTimeDialog({required this.initialSeconds, super.key});

  final int initialSeconds;

  @override
  State<SetTimeDialog> createState() => _SetTimeDialogState();
}

class _SetTimeDialogState extends State<SetTimeDialog> {
  late final controller =
      TextEditingController(text: formatSeconds(widget.initialSeconds));
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final seconds = parseTimeInput(controller.text);
    if (seconds == null) {
      setState(() => error = 'Enter minutes (25) or minutes:seconds (12:30).');
      return;
    }
    Navigator.of(context).pop(seconds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set remaining time'),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Time left',
            hintText: '12:30',
            errorText: error,
          ),
          onSubmitted: (_) => submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: submit, child: const Text('Set Time')),
      ],
    );
  }
}

/// Asks for the top three. Returns [first, second, third], or null if
/// cancelled. Empty names are left off the podium.
Future<List<String>?> showFinishEventDialog(
  BuildContext context,
  TimerStateModel state,
) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => FinishEventDialog(state: state),
  );
}

class FinishEventDialog extends StatefulWidget {
  const FinishEventDialog({required this.state, super.key});

  final TimerStateModel state;

  @override
  State<FinishEventDialog> createState() => _FinishEventDialogState();
}

class _FinishEventDialogState extends State<FinishEventDialog> {
  late final names = [
    TextEditingController(text: widget.state.firstPlace),
    TextEditingController(text: widget.state.secondPlace),
    TextEditingController(text: widget.state.thirdPlace),
  ];

  static const places = [
    ('1st place', _yellow),
    ('2nd place', Color(0xFFC0C7D2)),
    ('3rd place (optional)', _orange),
  ];

  @override
  void dispose() {
    for (final controller in names) {
      controller.dispose();
    }
    super.dispose();
  }

  void submit() => Navigator.of(context)
      .pop(names.map((controller) => controller.text.trim()).toList());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Finish event'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'These names appear on the player screen. Empty places are left out.',
              style: softText,
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < 3; i++) ...[
              TextField(
                controller: names[i],
                autofocus: i == 0,
                decoration: InputDecoration(
                  labelText: places[i].$1,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor: places[i].$2,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                onSubmitted: (_) => i == 2 ? submit() : null,
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _yellow,
            foregroundColor: Colors.black,
          ),
          onPressed: submit,
          icon: const Icon(Icons.emoji_events),
          label: const Text('Show Winners'),
        ),
      ],
    );
  }
}
