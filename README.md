# Big Ink TCG Timer

**Big Ink TCG Timer** is a local event timer and player display app for tabletop / TCG events such as Disney Lorcana, Pokémon, Magic Commander, Yu-Gi-Oh!, and casual store events.

The app is built with **Flutter Web** and packaged with **Electron** for Windows use.

Current stable version:

```text
V1.2.2 Alena
```

---

## What the app does

The app is designed for running TCG events in a store or club environment.

It includes:

- Admin timer control
- Fullscreen player screen
- Round timer
- Round counter
- BO1 / BO3 match format display
- Table range display
- Final round notice
- Time called screen
- Winner screen with 1st / 2nd / 3rd place
- Editable event presets
- Custom logo toggle
- Table overview
- Local saving

---

## Main screens

### Timer Control

The admin screen is used to control the event.

You can set:

- Event name
- Game
- Match format: BO1 or BO3
- Round length
- Current round
- Total rounds
- Table range
- Total tables
- Winner names
- Logo mode

Timer controls:

- Start / Pause
- +5 minutes
- Next Round
- Finish Event

---

### Player Screen

The Player Screen is designed for a TV, beamer, or second monitor.

It shows:

- Big Ink logo or custom PNG logo
- Event name
- Game
- Tables
- Round number
- BO1 / BO3
- Timer
- Status text
- Player instructions

When time reaches zero, it shows:

```text
TIME CALLED
Please finish your current turn
```

---

### Winner Screen

When the event is finished, the Player Screen switches to the Winner Screen.

It shows:

- Event finished header
- Winner podium
- 1st place
- 2nd place
- 3rd place
- Closing message

Winner names are entered manually in the Timer Control screen.

---

### Tables

The Tables page gives a simple visual overview of table usage.

Active event tables are highlighted based on the selected table range.

Examples:

```text
1-12
1-6,9-12
3,5,7
```

---

### Presets

The Presets page lets you create, edit, delete, and load common event setups.

A preset stores:

- Preset name
- Game
- Match format
- Round length
- Total rounds
- Tables used

A preset does **not** store:

- Current round
- Remaining timer
- Running / paused state
- Winner names
- Event finished state

This keeps presets reusable for future events.

---

## Local saving

The app saves data locally using `shared_preferences`.

It stores:

```text
big_ink_tcg_timer_v1          -> current timer/event state
big_ink_tcg_timer_presets_v1  -> editable presets
```

This means your current event and presets stay saved after closing/reopening the app on the same machine.

---

## Custom logo PNG

The app can use either:

```text
Built-in BI logo
```

or:

```text
Custom PNG logo
```

To use a custom logo, place your file here:

```text
assets/images/big_ink_logo.png
```

Then make sure `pubspec.yaml` contains:

```yaml
flutter:
  uses-material-design: true

  assets:
    - assets/images/big_ink_logo.png
```

After adding or changing the logo, run:

```powershell
flutter clean
flutter pub get
flutter run -d chrome
```

For the packaged version, rebuild:

```powershell
flutter build web --release
npm.cmd run pack-folder
```

---

## Important architecture note

This project currently uses:

```dart
import 'dart:html' as html;
```

This is needed for the current browser fullscreen behavior.

Because of that, the current version is intended for:

```text
Flutter Web + Electron
```

It is **not** currently meant for direct native builds such as:

```powershell
flutter build windows
```

Use the Electron packaging flow instead.

---

## Development setup

### Requirements

Install:

- Flutter
- Dart
- Node.js
- npm
- Git
- Google Chrome or Microsoft Edge

---

## Run in Chrome for testing

From the project root:

```powershell
cd D:\Development\Projects\big_ink_tcg_timer_v1
flutter clean
flutter pub get
flutter run -d chrome
```

---

## Build the Flutter web version

```powershell
flutter build web --release
```

This creates the web build in:

```text
build/web
```

---

## Package as Windows Electron app

Use:

```powershell
npm.cmd run pack-folder
```

The shareable Windows app folder is created here:

```text
dist/win-unpacked
```

When sharing the app, copy the **whole folder**, not only the `.exe`.

Correct:

```text
dist/win-unpacked
```

Not enough:

```text
Big Ink TCG Timer.exe only
```

The `.exe` needs the bundled files and assets beside it.

---


## Current stable feature checklist

```text
✅ Start timer
✅ Pause timer
✅ +5 Min
✅ Next Round
✅ Final Round popup
✅ Finish Event
✅ Winner Screen
✅ Winner names saved
✅ Reload persistence
✅ Editable presets
✅ Save preset
✅ Edit preset
✅ Delete preset
✅ Load preset
✅ Custom logo toggle
✅ BO1 / BO3 display
✅ Table overview
```

---

## Known notes

### Flutter analyze warnings

The project may show informational warnings such as:

- `avoid_web_libraries_in_flutter`
- `withOpacity is deprecated`
- trailing comma formatting notes
- bool parameter style notes

These are currently not build-breaking.

The `dart:html` warning is expected for the current Flutter Web / Electron version.

---

## Future ideas

Possible future versions:

### V1.3 Backup & Settings

- Export presets
- Import presets
- Export full app backup
- Import full app backup
- Clear saved data
- Dedicated Settings page

### V1.4 Display customization

- Editable Player Screen message
- Editable Winner Screen message
- Player Screen size: Normal / Large / Extra Large
- Optional sound warnings

### V2.0 Multi-event mode

- Event A / Event B
- Separate timers
- Separate table ranges
- Split player screen

---

## Project status

```text
V1.2.2 Alena = Feature stable
Warnings = accepted for now
Cleanup = later polish task
```

This version is ready for continued testing and packaging as a local Windows event timer app.
By Robert
