import 'package:flutter_tts/flutter_tts.dart';

/// Suara arahan navigasi (guna enjin Text-to-Speech telefon).
class VoiceGuide {
  final FlutterTts _tts = FlutterTts();

  bool enabled = true;
  bool _ready = false;

  /// Bahasa yang berjaya ditetapkan (ms-MY, ms, id-ID) atau null.
  String? language;

  Future<void> init() async {
    try {
      for (final lang in const ['ms-MY', 'ms', 'id-ID']) {
        final ok = await _tts.isLanguageAvailable(lang);
        if (ok == true || ok == 1) {
          await _tts.setLanguage(lang);
          language = lang;
          break;
        }
      }
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(false);
      try {
        // Kecilkan bunyi muzik/radio sebentar semasa arahan disebut.
        await _tts.setAudioAttributesForNavigation();
      } catch (_) {}
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  bool get usingMalay => language == 'ms-MY' || language == 'ms';

  Future<void> speak(String text) async {
    if (!enabled || !_ready || text.isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(text, focus: true);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
