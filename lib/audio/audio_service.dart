import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Music (day / night) and sound effects. Every call is wrapped in try/catch:
/// audio problems must never crash the game (e.g. browsers blocking autoplay).
class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  bool musicOn = true;
  bool sfxOn = true;

  final AudioPlayer _music = AudioPlayer();
  final List<AudioPlayer> _pool = List.generate(8, (_) => AudioPlayer());
  int _next = 0;
  String? _track;
  bool _musicPlaying = false;
  int _musicToken = 0;
  final Map<String, DateTime> _lastPlayed = {};
  bool _loaded = false;

  static const double _musicVolume = 0.32;

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
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('audio_music_on', musicOn);
      await prefs.setBool('audio_sfx_on', sfxOn);
    } catch (_) {}
  }

  /// 'day' or 'night'. Starts the loop (cross-fading from the previous track).
  Future<void> playMusic(String track) async {
    await load();
    if (_track == track && _musicPlaying) return;
    _track = track;
    if (!musicOn) return;
    final token = ++_musicToken;
    try {
      if (_musicPlaying) {
        await _fade(0.0, 350, token);
      }
      if (token != _musicToken) return;
      await _music.stop();
      await _music.setReleaseMode(ReleaseMode.loop);
      await _music.setVolume(0.0);
      await _music.play(AssetSource('audio/music_$track.wav'));
      _musicPlaying = true;
      await _fade(_musicVolume, 700, token);
    } catch (_) {
      _musicPlaying = false;
    }
  }

  Future<void> _fade(double to, int ms, int token) async {
    const steps = 10;
    double from = to == 0.0 ? _musicVolume : 0.0;
    for (int i = 1; i <= steps; i++) {
      if (token != _musicToken) return;
      try {
        await _music.setVolume(from + (to - from) * (i / steps));
      } catch (_) {}
      await Future.delayed(Duration(milliseconds: ms ~/ steps));
    }
  }

  Future<void> stopMusic() async {
    _musicToken++;
    _musicPlaying = false;
    try {
      await _music.stop();
    } catch (_) {}
  }

  Future<void> pauseMusic() async {
    try {
      await _music.pause();
    } catch (_) {}
  }

  Future<void> resumeMusic() async {
    if (!musicOn) return;
    try {
      await _music.resume();
    } catch (_) {}
  }

  Future<void> setMusicOn(bool on) async {
    musicOn = on;
    await _save();
    if (!on) {
      await stopMusic();
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

  void sfx(String name) {
    if (!sfxOn) return;
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
      unawaited(p
          .play(AssetSource('audio/sfx_$name.wav'), volume: _sfxVolume[name] ?? 0.6)
          .catchError((_) {}));
    } catch (_) {}
  }
}
