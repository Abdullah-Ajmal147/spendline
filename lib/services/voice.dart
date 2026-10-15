import 'package:speech_to_text/speech_to_text.dart';

/// Thin wrapper around Android/iOS speech recognition. Free and on the phone's
/// own recogniser, no key needed. Text comes back through [onText].
class Voice {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;

  bool get listening => _stt.isListening;

  Future<bool> _init(void Function(String error) onError, void Function() onDone) async {
    _ready = await _stt.initialize(
      onError: (e) => onError(e.errorMsg),
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') onDone();
      },
    );
    return _ready;
  }

  /// [pref] is 'ur_PK' or 'en_US'. Falls back to the phone's own language if that one is missing.
  Future<String?> _pick(String pref) async {
    final all = await _stt.locales();
    final lang = pref.split('_').first;
    String? best;
    for (final l in all) {
      final id = l.localeId.replaceAll('-', '_');
      if (id == pref) return l.localeId;
      if (best == null && id.startsWith('${lang}_')) best = l.localeId;
    }
    return best;
  }

  /// Returns an error message, or null when listening started.
  Future<String?> start({
    required String locale,
    required void Function(String text, bool isFinal) onText,
    required void Function() onDone,
  }) async {
    String? err;
    if (!_ready && !await _init((e) => err = e, onDone)) {
      return 'Speech recognition is not available. Check the microphone permission.';
    }
    final id = await _pick(locale);
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        localeId: id,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 20),
      ),
      onResult: (r) => onText(r.recognizedWords, r.finalResult),
    );
    return err;
  }

  Future<void> stop() => _stt.stop();
}
