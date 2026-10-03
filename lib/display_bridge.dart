// Second screen support.
//
// In the Electron app, preload.js exposes `window.bigInkDesktop`, which lets
// the control window list the connected screens and open the player screen
// full screen on one of them. In a plain browser there is no such API, so the
// player screen opens as a popup window that can be dragged to the TV.
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_ft_event_timer/main.dart';

class ScreenInfo {
  const ScreenInfo({
    required this.id,
    required this.label,
    required this.width,
    required this.height,
    required this.primary,
  });

  factory ScreenInfo.fromJson(Map<String, dynamic> json) {
    return ScreenInfo(
      id: (json['id'] as num).toInt(),
      label: json['label'] as String? ?? 'Screen',
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      primary: json['primary'] as bool? ?? false,
    );
  }

  final int id;
  final String label;
  final int width;
  final int height;
  final bool primary;

  String get size => '$width × $height';
}

class DisplayStatus {
  const DisplayStatus({
    this.screens = const [],
    this.playerOpen = false,
    this.playerScreenId,
    this.windowed = false,
  });

  factory DisplayStatus.fromJson(Map<String, dynamic> json) {
    return DisplayStatus(
      screens: (json['screens'] as List<dynamic>? ?? [])
          .map((item) => ScreenInfo.fromJson(item as Map<String, dynamic>))
          .toList(),
      playerOpen: json['playerOpen'] as bool? ?? false,
      playerScreenId: (json['playerScreenId'] as num?)?.toInt(),
      windowed: json['windowed'] as bool? ?? false,
    );
  }

  /// Screens known to the desktop app. Empty in a browser.
  final List<ScreenInfo> screens;
  final bool playerOpen;
  final int? playerScreenId;

  /// True when the player screen runs in a normal window instead of full
  /// screen on its own display (browser popup, or no second screen).
  final bool windowed;

  bool get hasExternalScreen => screens.any((screen) => !screen.primary);

  ScreenInfo? screenById(int? id) {
    for (final screen in screens) {
      if (screen.id == id) return screen;
    }
    return null;
  }
}

@JS('bigInkDesktop')
external JSObject? get _desktopApi;

class DisplayBridge {
  DisplayBridge({required this.onChanged});

  /// Called when screens are plugged in or out, or the player window closes.
  final VoidCallback onChanged;

  html.WindowBase? _popup;
  Timer? _popupWatch;

  bool get isDesktop => _desktopApi != null;

  void start() {
    final api = _desktopApi;
    if (api == null) return;
    api.callMethod<JSAny?>('onChange'.toJS, onChanged.toJS);
  }

  Future<DisplayStatus> status() async {
    final api = _desktopApi;
    if (api != null) return _call(api, 'status');

    final open = _popup != null && _popup!.closed != true;
    return DisplayStatus(playerOpen: open, windowed: open);
  }

  /// Opens the player screen. On desktop it goes full screen on [screenId],
  /// or on the first secondary screen. Returns null if a browser blocked the
  /// popup.
  Future<DisplayStatus?> open({int? screenId}) async {
    final api = _desktopApi;
    if (api != null) return _call(api, 'openPlayer', screenId?.toJS);

    final url =
        Uri.base.removeFragment().replace(query: playerViewQuery).toString();
    _popup = html.window.open(
      url,
      'big-ink-player',
      'popup=yes,width=1280,height=720',
    );
    if (_popup == null) return null;

    // Browsers do not report when a popup is closed, so check periodically.
    _popupWatch?.cancel();
    _popupWatch = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_popup?.closed == true) {
        timer.cancel();
        _popup = null;
        onChanged();
      }
    });
    return status();
  }

  Future<DisplayStatus> close() async {
    final api = _desktopApi;
    if (api != null) return _call(api, 'closePlayer');

    _popupWatch?.cancel();
    _popup?.close();
    _popup = null;
    return status();
  }

  void dispose() {
    _popupWatch?.cancel();
  }

  Future<DisplayStatus> _call(JSObject api, String method, [JSAny? arg]) async {
    try {
      final promise = arg == null
          ? api.callMethod<JSPromise<JSString>>(method.toJS)
          : api.callMethod<JSPromise<JSString>>(method.toJS, arg);
      final text = (await promise.toDart).toDart;
      return DisplayStatus.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (error) {
      debugPrint('Display bridge call "$method" failed: $error');
      return const DisplayStatus();
    }
  }
}

@JS('navigator')
external JSObject get _navigator;

/// Keeps the screen from sleeping while the player screen is visible.
/// Browsers release the lock when the page is hidden, so it is requested
/// again whenever the page becomes visible.
class ScreenWakeLock {
  StreamSubscription<html.Event>? _visibility;
  bool _wanted = false;

  void keepOn() {
    _wanted = true;
    _visibility ??= html.document.onVisibilityChange.listen((_) {
      if (_wanted && html.document.visibilityState == 'visible') _request();
    });
    _request();
  }

  void release() {
    _wanted = false;
  }

  void dispose() {
    _visibility?.cancel();
  }

  Future<void> _request() async {
    try {
      final wakeLock = _navigator.getProperty<JSObject?>('wakeLock'.toJS);
      if (wakeLock == null) return;
      await wakeLock
          .callMethod<JSPromise<JSAny?>>('request'.toJS, 'screen'.toJS)
          .toDart;
    } catch (_) {
      // Not supported or refused (e.g. page hidden). The screen may sleep.
    }
  }
}
