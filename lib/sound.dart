// Short chimes for "5 minutes left" and "time called", synthesized with the
// Web Audio API so no sound files need to be bundled.
import 'dart:js_interop';

@JS('AudioContext')
extension type _AudioContext._(JSObject _) implements JSObject {
  external factory _AudioContext();
  external String get state;
  external double get currentTime;
  external _AudioNode get destination;
  external JSPromise<JSAny?> resume();
  external _Oscillator createOscillator();
  external _Gain createGain();
}

extension type _AudioNode._(JSObject _) implements JSObject {
  external JSAny? connect(_AudioNode destination);
}

extension type _AudioParam._(JSObject _) implements JSObject {
  external set value(double value);
  external void setValueAtTime(double value, double time);
  external void exponentialRampToValueAtTime(double value, double time);
}

extension type _Oscillator._(JSObject _) implements _AudioNode {
  external set type(String type);
  external _AudioParam get frequency;
  external void start(double when);
  external void stop(double when);
}

extension type _Gain._(JSObject _) implements _AudioNode {
  external _AudioParam get gain;
}

class SoundPlayer {
  _AudioContext? _context;

  /// Browsers only allow audio after a user action. Call this from a click
  /// or key handler (e.g. Start) so later chimes can play on their own.
  void prime() {
    try {
      _context ??= _AudioContext();
      if (_context!.state == 'suspended') _context!.resume();
    } catch (_) {
      _context = null;
    }
  }

  /// Two rising tones.
  void warning(double volume) => _chime(const [660, 880], volume);

  /// Three tones, repeated once.
  void timeUp(double volume) =>
      _chime(const [880, 660, 880, 660, 880, 660], volume, gap: 0.42);

  void _chime(List<double> frequencies, double volume, {double gap = 0.38}) {
    final context = _context;
    if (context == null || volume <= 0.01) return;

    try {
      final start = context.currentTime + 0.05;
      for (var i = 0; i < frequencies.length; i++) {
        final at = start + i * gap;
        final oscillator = context.createOscillator()..type = 'sine';
        oscillator.frequency.value = frequencies[i];

        final gain = context.createGain();
        gain.gain
          ..setValueAtTime(0.0001, at)
          ..exponentialRampToValueAtTime(volume * 0.6, at + 0.02)
          ..exponentialRampToValueAtTime(0.0001, at + 1.1);

        oscillator.connect(gain);
        gain.connect(context.destination);
        oscillator
          ..start(at)
          ..stop(at + 1.2);
      }
    } catch (_) {
      // Audio is a nice-to-have; never let it break the timer.
    }
  }
}
