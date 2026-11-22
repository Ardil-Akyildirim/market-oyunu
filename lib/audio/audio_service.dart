import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Music (menu / day / night) and sound effects. Every call is wrapped in try/catch:
/// audio problems must never crash the game (e.g. browsers blocking autoplay).
///
/// Music uses two players so tracks cross-fade instead of cutting. Sound effects use
/// low-latency players and never take audio focus, so they cannot interrupt the music.
class AudioService with WidgetsBindingObserver {
  AudioService._();
  static final AudioService instance = AudioService._();

  bool musicOn = true;
  bool sfxOn = true;
  double musicVol = 0.8; // 0..1 (settings slider)
  double sfxVol = 0.8; // 0..1 (settings slider)

  final List<AudioPlayer> _mp = [AudioPlayer(), AudioPlayer()];
  int _cur = 0;
  final List<AudioPlayer> _pool = List.generate(8, (_) => AudioPlayer());
  int _next = 0;
  String? _track;
  bool _musicPlaying = false;
  bool _pausedByApp = false;
  Timer? _fadeTimer;
  final Map<String, DateTime> _lastPlayed = {};
  bool _loaded = false;

  static const double _musicBase = 0.45;
  double get _target => (_musicBase * musicVol).clamp(0.0, 1.0).toDouble();

  static const Map<String, double> _sfxVolume = {
    'click': 0.55,
    'step': 0.22,
    'swish': 0.6,
    'hit': 0.9,
    'cash': 0.85,
    'scan': 0.6,
    'pickup': 0.6,
    'steal': 0.7,
    'bell': 0.55,
    'truck': 0.6,
    'order': 0.6,
    'error': 0.55,
    'night': 0.7,
    'dawn': 0.7,
  };

  // Minimum gap between two plays of the same effect (seconds)
  static const Map<String, double> _cooldown = {
    'step': 0.18,
    'swish': 0.15,
    'click': 0.05,
  };

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      musicOn = prefs.getBool('audio_music_on') ?? true;
      sfxOn = prefs.getBool('audio_sfx_on') ?? true;
      musicVol = prefs.getDouble('audio_music_vol') ?? 0.8;
      sfxVol = prefs.getDouble('audio_sfx_vol') ?? 0.8;
    } catch (_) {}
    try {
      // Never request audio focus: sound effects must not interrupt the music.
      final ctx = AudioContext(
        android: AudioContextAndroid(
          audioFocus: AndroidAudioFocus.none,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.game,
          stayAwake: false,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      );
      await AudioPlayer.global.setAudioContext(ctx);
      for (final p in [..._mp, ..._pool]) {
        try {
          await p.setAudioContext(ctx);
        } catch (_) {}
      }
    } catch (_) {}
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      if (_musicPlaying && !_pausedByApp) {
        _pausedByApp = true;
        _fadeTimer?.cancel();
        for (final p in _mp) {
          p.pause().catchError((_) {});
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedByApp) {
        _pausedByApp = false;
        if (musicOn && _musicPlaying) {
          _mp[_cur].setVolume(_target).catchError((_) {});
          _mp[_cur].resume().catchError((_) {});
        }
      }
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('audio_music_on', musicOn);
      await prefs.setBool('audio_sfx_on', sfxOn);
      await prefs.setDouble('audio_music_vol', musicVol);
      await prefs.setDouble('audio_sfx_vol', sfxVol);
    } catch (_) {}
  }

  /// 'menu', 'day' or 'night'. Cross-fades from the previous track.
  Future<void> playMusic(String track) async {
    await load();
    if (_track == track && _musicPlaying) return;
    _track = track;
    if (!musicOn) return;
    try {
      _fadeTimer?.cancel();
      final outgoing = _mp[_cur];
      final incomingIdx = 1 - _cur;
      final incoming = _mp[incomingIdx];
      // the idle player may still be fading out from an earlier switch
      await incoming.stop();
      await incoming.setReleaseMode(ReleaseMode.loop);
      await incoming.setVolume(0.0);
      await incoming.play(AssetSource('audio/music_$track.wav'));
      final hadMusic = _musicPlaying;
      _cur = incomingIdx;
      _musicPlaying = true;

      const steps = 14;
      const stepMs = 100; // ~1.4 s cross-fade
      int i = 0;
      _fadeTimer = Timer.periodic(const Duration(milliseconds: stepMs), (t) {
        i++;
        final k = (i / steps).clamp(0.0, 1.0).toDouble();
        try {
          incoming.setVolume(_target * k);
          if (hadMusic) outgoing.setVolume(_target * (1 - k));
        } catch (_) {}
        if (i >= steps) {
          t.cancel();
          outgoing.stop().catchError((_) {});
        }
      });
    } catch (_) {
      _musicPlaying = false;
    }
  }

  Future<void> stopMusic() async {
    _fadeTimer?.cancel();
    _musicPlaying = false;
    _track = null;
    for (final p in _mp) {
      try {
        await p.stop();
      } catch (_) {}
    }
  }

  Future<void> setMusicOn(bool on) async {
    musicOn = on;
    await _save();
    if (!on) {
      final t = _track;
      await stopMusic();
      _track = t;
    } else if (_track != null) {
      final t = _track!;
      _track = null;
      await playMusic(t);
    }
  }

  Future<void> setSfxOn(bool on) async {
    sfxOn = on;
    await _save();
  }

  Future<void> setMusicVolume(double v) async {
    musicVol = v.clamp(0.0, 1.0).toDouble();
    if (_musicPlaying && (_fadeTimer == null || !_fadeTimer!.isActive)) {
      try {
        await _mp[_cur].setVolume(_target);
      } catch (_) {}
    }
    await _save();
  }

  Future<void> setSfxVolume(double v) async {
    sfxVol = v.clamp(0.0, 1.0).toDouble();
    await _save();
  }

  void sfx(String name) {
    if (!sfxOn || sfxVol <= 0) return;
    final cd = _cooldown[name];
    if (cd != null) {
      final now = DateTime.now();
      final last = _lastPlayed[name];
      if (last != null && now.difference(last).inMilliseconds < cd * 1000) return;
      _lastPlayed[name] = now;
    }
    try {
      final p = _pool[_next];
      _next = (_next + 1) % _pool.length;
      final v = ((_sfxVolume[name] ?? 0.6) * sfxVol * 1.2).clamp(0.0, 1.0).toDouble();
      unawaited(() async {
        try {
          await p.stop();
          await p.play(AssetSource('audio/sfx_$name.wav'), volume: v);
        } catch (_) {}
      }());
    } catch (_) {}
  }
}
