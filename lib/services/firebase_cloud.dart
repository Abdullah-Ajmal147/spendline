import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'google_sheets.dart' show SheetsException;

/// Firestore value encoding for the REST API.
Map<String, dynamic> encodeValue(Object? v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': '$v'};
  if (v is double) return v.isFinite ? {'doubleValue': v} : {'nullValue': null};
  if (v is String) return {'stringValue': v};
  if (v is List) {
    return {
      'arrayValue': {'values': [for (final x in v) encodeValue(x)]},
    };
  }
  if (v is Map) return {'mapValue': {'fields': encodeFields(Map<String, dynamic>.from(v))}};
  return {'stringValue': '$v'};
}

Map<String, dynamic> encodeFields(Map<String, dynamic> m) => {for (final e in m.entries) e.key: encodeValue(e.value)};

Object? decodeValue(Map<String, dynamic> v) {
  if (v.containsKey('stringValue')) return v['stringValue'];
  if (v.containsKey('integerValue')) return int.parse('${v['integerValue']}');
  if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
  if (v.containsKey('booleanValue')) return v['booleanValue'];
  if (v.containsKey('arrayValue')) {
    final vals = (v['arrayValue'] as Map)['values'] as List? ?? const [];
    return [for (final x in vals) decodeValue(Map<String, dynamic>.from(x as Map))];
  }
  if (v.containsKey('mapValue')) {
    return decodeFields(Map<String, dynamic>.from(((v['mapValue'] as Map)['fields'] as Map?) ?? const {}));
  }
  return null;
}

Map<String, dynamic> decodeFields(Map<String, dynamic> f) =>
    {for (final e in f.entries) e.key: decodeValue(Map<String, dynamic>.from(e.value as Map))};

/// One pending change: a document to write, or an id to delete.
class CloudWrite {
  CloudWrite.put(this.collection, this.id, this.data);
  CloudWrite.delete(this.collection, this.id) : data = null;
  final String collection, id;
  final Map<String, dynamic>? data;
}

/// Free-tier Firebase sync over plain REST: Firebase Auth (Google ID token)
/// plus Firestore, under `users/{uid}/...`. No google-services.json needed.
class FirebaseCloud {
  FirebaseCloud({required this.projectId, required this.apiKey});

  final String projectId;
  final String apiKey;

  String uid = '';
  String refreshToken = '';
  String _idToken = '';
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);

  static const _timeout = Duration(seconds: 25);

  bool get hasSession => refreshToken.isNotEmpty && uid.isNotEmpty;

  String get _base => 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';
  String _docName(String col, String id) => 'projects/$projectId/databases/(default)/documents/users/$uid/$col/$id';

  /// Exchanges a Google ID token for a Firebase session.
  Future<void> signInWithGoogle(String googleIdToken) async {
    final r = await _json(
      'POST',
      Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=$apiKey'),
      body: {
        'postBody': 'id_token=$googleIdToken&providerId=google.com',
        'requestUri': 'http://localhost',
        'returnIdpCredential': true,
        'returnSecureToken': true,
      },
      auth: false,
    );
    uid = '${r['localId']}';
    _idToken = '${r['idToken']}';
    refreshToken = '${r['refreshToken']}';
    _expires = DateTime.now().add(Duration(seconds: int.tryParse('${r['expiresIn']}') ?? 3600) - const Duration(minutes: 2));
  }

  Future<void> _ensureToken() async {
    if (_idToken.isNotEmpty && DateTime.now().isBefore(_expires)) return;
    if (refreshToken.isEmpty) throw SheetsException('Not signed in to Firebase.');
    final res = await _send(
      'POST',
      Uri.parse('https://securetoken.googleapis.com/v1/token?key=$apiKey'),
      form: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
      auth: false,
    );
    _idToken = '${res['id_token']}';
    refreshToken = '${res['refresh_token'] ?? refreshToken}';
    uid = '${res['user_id'] ?? uid}';
    _expires = DateTime.now().add(Duration(seconds: int.tryParse('${res['expires_in']}') ?? 3600) - const Duration(minutes: 2));
  }

  /// Applies writes in batches of 200.
  Future<void> commit(List<CloudWrite> writes) async {
    for (var i = 0; i < writes.length; i += 200) {
      final chunk = writes.skip(i).take(200);
      await _json(
        'POST',
        Uri.parse('$_base:commit'),
        body: {
          'writes': [
            for (final w in chunk)
              if (w.data != null)
                {
                  'update': {'name': _docName(w.collection, w.id), 'fields': encodeFields(w.data!)},
                }
              else
                {'delete': _docName(w.collection, w.id)},
          ],
        },
      );
    }
  }

  Future<List<Map<String, dynamic>>> list(String collection) async {
    final out = <Map<String, dynamic>>[];
    String? token;
    do {
      final q = {'pageSize': '300', if (token != null) 'pageToken': token};
      final r = await _json('GET', Uri.parse('$_base/users/$uid/$collection').replace(queryParameters: q));
      for (final d in (r['documents'] as List? ?? const [])) {
        final f = ((d as Map)['fields'] as Map?) ?? const {};
        out.add(decodeFields(Map<String, dynamic>.from(f)));
      }
      token = r['nextPageToken'] as String?;
    } while (token != null);
    return out;
  }

  Future<Map<String, dynamic>> _json(String method, Uri uri, {Object? body, bool auth = true}) =>
      _send(method, uri, json: body, auth: auth);

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri, {
    Object? json,
    Map<String, String>? form,
    bool auth = true,
  }) async {
    if (auth) await _ensureToken();
    try {
      final req = http.Request(method, uri);
      if (auth) req.headers['Authorization'] = 'Bearer $_idToken';
      if (json != null) {
        req.headers['Content-Type'] = 'application/json; charset=utf-8';
        req.body = jsonEncode(json);
      } else if (form != null) {
        req.bodyFields = form;
      }
      final res = await http.Response.fromStream(await req.send().timeout(_timeout));
      final decoded = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
      if (res.statusCode >= 300) {
        final err = decoded is Map ? decoded['error'] : null;
        final msg = err is Map ? '${err['message'] ?? err['status']}' : '${res.statusCode}';
        throw SheetsException(_explain(msg, res.statusCode));
      }
      return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    } on SheetsException {
      rethrow;
    } on TimeoutException {
      throw SheetsException('Firebase took too long to answer.', offline: true);
    } on SocketException {
      throw SheetsException('No internet connection.', offline: true);
    } on HandshakeException {
      throw SheetsException('Secure connection failed.', offline: true);
    } on http.ClientException catch (e) {
      throw SheetsException('Network error: ${e.message}', offline: true);
    }
  }

  static String _explain(String msg, int code) {
    final m = msg.toUpperCase();
    if (m.contains('API_KEY') || m.contains('API KEY')) return 'The Firebase Web API key is wrong. Copy it again from Project settings.';
    if (m.contains('OPERATION_NOT_ALLOWED')) return 'Google sign-in is not enabled in Firebase. Authentication > Sign-in method > Google > Enable.';
    if (m.contains('INVALID_IDP_RESPONSE') || m.contains('AUDIENCE')) {
      return 'Firebase did not accept the Google token. The Web client ID here must be the one shown under Authentication > Google > Web SDK configuration.';
    }
    if (code == 403 || m.contains('PERMISSION_DENIED')) {
      return 'Firestore refused access. Publish the security rules from the setup guide, and make sure the database exists.';
    }
    if (code == 404 || m.contains('NOT_FOUND')) {
      return 'Firestore database not found. In Firebase: Build > Firestore Database > Create database.';
    }
    return 'Firebase said: $msg';
  }
}
