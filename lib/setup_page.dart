// Event setup in three steps: pick a template, adjust the details, choose
// the tables. Every change is saved right away.
import 'package:flutter/material.dart';

import 'package:flutter_application_ft_event_timer/main.dart';

const _accent = Color(0xFF5FB3FF);
const _green = Color(0xFF4ADE80);
const _muted = Color(0xFF8A9BB5);

class SetupPage extends StatefulWidget {
  const SetupPage({required this.app, super.key});

  final BigInkTimerAppState app;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  int step = 0;

  static const steps = ['Template', 'Details', 'Tables'];

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
              1 => _DetailsStep(app: app),
              _ => _TablesStep(app: app),
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
                    '${preset.rounds} × ${preset.roundLengthMinutes} min · Tables ${preset.tables}',
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
                      'A chime at 5 minutes left and at TIME.',
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
                        onPressed: state.soundEnabled ? app.testSound : null,
                        child: const Text('Test'),
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

class _TablesStep extends StatelessWidget {
  const _TablesStep({required this.app});

  final BigInkTimerAppState app;

  @override
  Widget build(BuildContext context) {
    final count = clampInt(int.tryParse(app.tableCount.text) ?? 24, 1, 120);
    final selected = parseTableRange(app.tableRange.text);

    void setTables(Set<int> tables) {
      if (tables.isEmpty) return;
      app.tableRange.text = formatTableRange(tables);
      app.saveFields();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(
              width: 260,
              child: NumberStepper(
                label: 'Tables in the store',
                controller: app.tableCount,
                min: 1,
                max: 120,
                onChanged: app.scheduleAutosave,
              ),
            ),
            SizedBox(
              width: 320,
              child: TextField(
                controller: app.tableRange,
                decoration: InputDecoration(
                  labelText: 'Tables used',
                  hintText: '1-12 or 1-6,9-12',
                  errorText: selected == null
                      ? 'Use numbers and ranges, e.g. 1-6,9-12'
                      : null,
                ),
                onChanged: (text) {
                  if (parseTableRange(text) != null) app.scheduleAutosave();
                },
              ),
            ),
            OutlinedButton(
              onPressed: () =>
                  setTables({for (var table = 1; table <= count; table++) table}),
              child: const Text('Select all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Click tables to add or remove them. '
          '${selected?.length ?? 0} of $count selected.',
          style: softText,
        ),
        const SizedBox(height: 14),
        TablePicker(
          count: count,
          selected: selected ?? const {},
          onToggle: (table) {
            final next = {...?selected};
            if (!next.remove(table)) next.add(table);
            setTables(next);
          },
        ),
      ],
    );
  }
}

/// A grid of table numbers. Selected tables are highlighted.
class TablePicker extends StatelessWidget {
  const TablePicker({
    required this.count,
    required this.selected,
    required this.onToggle,
    super.key,
  });

  final int count;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var table = 1; table <= count; table++)
          SizedBox(
            width: 64,
            height: 48,
            child: Material(
              color: selected.contains(table)
                  ? _accent.withOpacity(0.28)
                  : _green.withOpacity(0.06),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: selected.contains(table)
                      ? _accent
                      : Colors.white.withOpacity(0.16),
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onToggle(table),
                child: Center(
                  child: Text(
                    '$table',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: selected.contains(table) ? Colors.white : _muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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

/// Reads a table list such as "1-6,9-12" or "3, 5, 7". Returns null if any
/// part is not a positive number or range.
Set<int>? parseTableRange(String text) {
  final cleaned = text.replaceAll('–', '-').replaceAll(' ', '');
  if (cleaned.isEmpty) return null;

  final tables = <int>{};
  for (final part in cleaned.split(',')) {
    if (part.isEmpty) continue;
    final bounds = part.split('-');
    if (bounds.length == 1) {
      final table = int.tryParse(bounds[0]);
      if (table == null || table < 1) return null;
      tables.add(table);
    } else if (bounds.length == 2) {
      final a = int.tryParse(bounds[0]);
      final b = int.tryParse(bounds[1]);
      if (a == null || b == null || a < 1 || b < 1) return null;
      final low = a < b ? a : b;
      final high = a < b ? b : a;
      if (high - low > 999) return null;
      for (var table = low; table <= high; table++) {
        tables.add(table);
      }
    } else {
      return null;
    }
  }
  return tables.isEmpty ? null : tables;
}

/// Writes tables as compact ranges: {1,2,3,5,9,10} → "1-3,5,9-10".
String formatTableRange(Iterable<int> tables) {
  final sorted = tables.toSet().toList()..sort();
  final parts = <String>[];
  var i = 0;
  while (i < sorted.length) {
    var j = i;
    while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
      j++;
    }
    parts.add(i == j ? '${sorted[i]}' : '${sorted[i]}-${sorted[j]}');
    i = j + 1;
  }
  return parts.join(',');
}
