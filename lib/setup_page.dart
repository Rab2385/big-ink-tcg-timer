// Event setup in two steps: pick a template, then adjust the details.
// Every change is saved right away.
import 'package:flutter/material.dart';

import 'package:flutter_application_ft_event_timer/main.dart';

const _accent = Color(0xFF5FB3FF);
const _muted = Color(0xFF8A9BB5);

class SetupPage extends StatefulWidget {
  const SetupPage({required this.app, super.key});

  final BigInkTimerAppState app;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  int step = 0;

  static const steps = ['Template', 'Details'];

  BigInkTimerAppState get app => widget.app;

  Future<void> goToStep(int next) async {
    await app.flushAutosave();
    setState(() => step = next);
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Event Setup',
      subtitle: 'Changes are saved automatically. A running timer is not affected.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < steps.length; i++)
                ChoiceChip(
                  label: Text('${i + 1} · ${steps[i]}'),
                  selected: step == i,
                  showCheckmark: false,
                  onSelected: (_) => goToStep(i),
                ),
            ],
          ),
          const SizedBox(height: 16),
          AppCard(
            child: switch (step) {
              0 => _TemplateStep(app: app, onPicked: () => goToStep(1)),
              _ => _DetailsStep(app: app),
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (step > 0)
                OutlinedButton.icon(
                  onPressed: () => goToStep(step - 1),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              const Spacer(),
              if (step < steps.length - 1)
                OutlinedButton.icon(
                  onPressed: () => goToStep(step + 1),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text('Next: ${steps[step + 1]}'),
                ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () async {
                  await app.flushAutosave();
                  app.goTo(AppPage.live);
                },
                icon: const Icon(Icons.timer),
                label: const Text('Go to Live'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TemplateStep extends StatelessWidget {
  const _TemplateStep({required this.app, required this.onPicked});

  final BigInkTimerAppState app;
  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Start a new event',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        const Text(
          'Pick a preset to start at round 1 with its settings, or keep the current settings.',
          style: softText,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final preset in app.presets)
              _TemplateCard(
                title: preset.name,
                detail: '${preset.game} · ${preset.matchFormat}\n'
                    '${preset.rounds} × ${preset.roundLengthMinutes} min',
                onTap: () async {
                  await app.loadPreset(preset);
                  onPicked();
                },
              ),
            _TemplateCard(
              title: 'Keep current settings',
              detail: '${app.state.game} · ${app.state.matchFormat}\n'
                  'Restart at round 1, clear winners',
              icon: Icons.restart_alt,
              onTap: () async {
                await app.startNewEvent();
                onPicked();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => app.goTo(AppPage.presets),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Manage presets'),
        ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.title,
    required this.detail,
    required this.onTap,
    this.icon = Icons.event,
  });

  final String title;
  final String detail;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Material(
        color: Colors.white.withOpacity(0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withOpacity(0.14)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: _accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(detail, style: softText.copyWith(fontSize: 13)),
                    ],
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

class _DetailsStep extends StatelessWidget {
  const _DetailsStep({required this.app});

  final BigInkTimerAppState app;

  @override
  Widget build(BuildContext context) {
    final state = app.state;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 760;
        final half = wide ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: constraints.maxWidth,
              child: TextField(
                controller: app.eventName,
                decoration: const InputDecoration(labelText: 'Event name'),
                onChanged: (_) => app.scheduleAutosave(),
              ),
            ),
            SizedBox(
              width: half,
              child: DropdownButtonFormField<String>(
                value: normalizeGame(state.game),
                decoration: const InputDecoration(labelText: 'Game'),
                items: [
                  for (final game in gameOptions)
                    DropdownMenuItem(value: game, child: Text(game)),
                ],
                onChanged: (value) {
                  if (value != null) app.changeGame(value);
                },
              ),
            ),
            SizedBox(
              width: half,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Match format',
                  border: InputBorder.none,
                ),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    for (final format in matchFormatOptions)
                      ButtonSegment(value: format, label: Text(format)),
                  ],
                  selected: {normalizeMatchFormat(state.matchFormat)},
                  onSelectionChanged: (selection) =>
                      app.changeMatchFormat(selection.first),
                ),
              ),
            ),
            SizedBox(
              width: half,
              child: NumberStepper(
                label: 'Round length (minutes)',
                controller: app.roundLength,
                min: 5,
                max: 180,
                step: 5,
                onChanged: app.scheduleAutosave,
                helper: 'Applies from the next round or a restart.',
              ),
            ),
            SizedBox(
              width: half,
              child: NumberStepper(
                label: 'Total rounds',
                controller: app.totalRounds,
                min: 1,
                max: 99,
                onChanged: app.scheduleAutosave,
              ),
            ),
            SizedBox(
              width: half,
              child: NumberStepper(
                label: 'Current round',
                controller: app.currentRound,
                min: 1,
                max: 99,
                onChanged: app.scheduleAutosave,
              ),
            ),
            SizedBox(
              width: half,
              child: TextField(
                controller: app.timeCalledNote,
                decoration: const InputDecoration(
                  labelText: 'Note shown at TIME (optional)',
                  hintText: 'e.g. Finish the turn, then 3 more turns',
                ),
                onChanged: (_) => app.scheduleAutosave(),
              ),
            ),
            SizedBox(
              width: constraints.maxWidth,
              child: const Divider(),
            ),
            SizedBox(
              width: half,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Use custom logo PNG',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: const Text(
                  'Off = BI logo. On = assets/images/big_ink_logo.png.',
                  style: softText,
                ),
                value: state.useCustomLogo,
                onChanged: app.changeLogoMode,
              ),
            ),
            SizedBox(
              width: half,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Sound signals',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: const Text(
                      'A chime at 5 minutes left and a bell at TIME.',
                      style: softText,
                    ),
                    value: state.soundEnabled,
                    onChanged: (value) => app.changeSound(enabled: value),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.volume_down, color: _muted),
                      Expanded(
                        child: Slider(
                          value: state.soundVolume,
                          onChanged: state.soundEnabled
                              ? (value) => app.changeSound(volume: value)
                              : null,
                        ),
                      ),
                      TextButton(
                        onPressed:
                            state.soundEnabled ? app.testWarningSound : null,
                        child: const Text('Test 5 min'),
                      ),
                      TextButton(
                        onPressed:
                            state.soundEnabled ? app.testTimeUpSound : null,
                        child: const Text('Test TIME'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A number field with − and + buttons.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    required this.label,
    required this.controller,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.helper,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final int min;
  final int max;
  final int step;
  final String? helper;
  final VoidCallback onChanged;

  void _add(int delta) {
    final current = int.tryParse(controller.text.trim()) ?? min;
    controller.text = clampInt(current + delta, min, max).toString();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: IconButton(
          tooltip: '−$step',
          onPressed: () => _add(-step),
          icon: const Icon(Icons.remove),
        ),
        suffixIcon: IconButton(
          tooltip: '+$step',
          onPressed: () => _add(step),
          icon: const Icon(Icons.add),
        ),
      ),
      onChanged: (_) => onChanged(),
    );
  }
}
