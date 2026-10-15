import 'dart:convert';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

import '../models/entry.dart';
import 'parser.dart';

/// Optional on-device model (Qwen3 0.6B, open weights, ~350 MB, no Hugging Face
/// token needed) that reads sentences the rule parser is unsure about.
///
/// Everything model-specific lives in this file, so the model or package can be
/// swapped without touching the UI. The rest of the app only uses
/// [load], [ready] and [parse].
///
/// NOTE: flutter_edge_ai (formerly flutter_gemma) 2.x is new. Calls follow its
/// README as of Oct 2026. `_model` is `dynamic` on purpose so a renamed type
/// does not break the build; tighten it once `flutter analyze` runs.
class SmartParser {
  static const modelUrl =
      'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm';

  static bool _engineReady = false;

  /// Call once in main() before runApp.
  static Future<void> initEngine() async {
    try {
      await FlutterEdgeAi.initialize(inferenceEngines: const [LiteRtLmEngine()]);
      _engineReady = true;
    } catch (_) {
      _engineReady = false;
    }
  }

  dynamic _model;
  Future<void>? _loading;

  bool get ready => _model != null;

  /// Downloads the model the first time (progress 0–100), then loads it.
  Future<void> load({required void Function(double percent) onProgress}) {
    return _loading ??= _load(onProgress).catchError((Object e) {
      _loading = null;
      throw e;
    });
  }

  Future<void> _load(void Function(double) onProgress) async {
    if (!_engineReady) {
      throw StateError('On-device AI is not available on this phone. The built-in parser still works.');
    }
    try {
      _model = await FlutterEdgeAi.getActiveModel(maxTokens: 512);
      return;
    } on StateError {
      // No model installed yet.
    }
    await FlutterEdgeAi.installModel(modelType: ModelType.qwen3, fileType: ModelFileType.litertlm)
        .fromNetwork(modelUrl)
        .withProgress((progress) => onProgress(progress.toDouble()))
        .install();
    _model = await FlutterEdgeAi.getActiveModel(maxTokens: 512);
  }

  static final String _instructions =
      'Convert a short note about money into JSON. Reply with JSON only, no other text.\n'
      'Schema: {"type":"Expense"|"Given"|"Received"|"Income","amount":number,"person":string,'
      '"category":"${catList.join('"|"')}","description":string}\n'
      'Given = the user gave or lent money to a person. Received = a person gave or returned money to the user. '
      'person is "" when nobody is named. description is 1 to 4 words.';

  /// Returns an improved draft, or null if the model gave nothing usable.
  Future<Draft?> parse(String text, Draft fallback) async {
    final model = _model;
    if (model == null) return null;

    final chat = await model.createChat();
    await chat.addQueryChunk(Message.text(text: '$_instructions\n\nNote: $text /no_think', isUser: true));
    final buf = StringBuffer();
    await for (final r in chat.generateChatResponseAsync()) {
      if (r is TextResponse) buf.write(r.token);
    }

    final out = buf.toString().replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    final a = out.indexOf('{');
    final b = out.lastIndexOf('}');
    if (a < 0 || b <= a) return null;

    final dynamic j;
    try {
      j = jsonDecode(out.substring(a, b + 1));
    } on FormatException {
      return null;
    }
    if (j is! Map) return null;

    final d = fallback.copy()..smart = true;
    for (final t in EntryType.values) {
      if (t.label == j['type']) d.type = t;
    }
    final amount = j['amount'];
    if (d.amount <= 0 && amount is num && amount > 0) d.amount = amount.toDouble();
    if (j['person'] is String) d.person = cap((j['person'] as String).trim());
    if (catList.contains(j['category'])) d.category = j['category'] as String;
    if (j['description'] is String && (j['description'] as String).trim().isNotEmpty) {
      d.description = cap((j['description'] as String).trim());
    }
    d.confidence = 0.9;
    return d;
  }
}
