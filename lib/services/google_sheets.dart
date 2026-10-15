import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../models/entry.dart';

class SheetsException implements Exception {
  SheetsException(this.message, {this.offline = false});

  final String message;

  /// True when Google could not be reached. Entries stay on the phone and
  /// are sent on the next sync.
  final bool offline;

  @override
  String toString() => message;
}

class SheetInfo {
  SheetInfo(this.id, this.url, this.gid);
  final String id;
  final String url;

  /// Numeric id of the "Expenses" tab, needed to delete rows.
  final int gid;
}

/// Writes entries to a spreadsheet in the user's own Google Drive.
///
/// Uses the `drive.file` scope: the app can only see files it created itself,
/// which Google treats as a non-sensitive scope. No API key is involved.
class GoogleSheets {
  static const _scopes = ['https://www.googleapis.com/auth/drive.file'];
  static const _tab = 'Expenses';
  static const _title = 'Spendline';
  static const _timeout = Duration(seconds: 25);
  static const _header = ['ID', 'Date', 'Time', 'Type', 'Category', 'Person', 'Description', 'Amount', 'Note'];

  GoogleSheets({this.clientId = ''});

  /// Web OAuth client ID (from Firebase: Authentication > Google > Web SDK configuration).
  final String clientId;

  bool get configured => clientId.isNotEmpty;

  static bool _initialised = false; // the sign-in plugin can only be initialised once per launch
  GoogleSignInAccount? _account;

  /// Google ID token of the signed-in account, used to sign in to Firebase.
  String? get idToken => _account?.authentication.idToken;
  String get email => _account?.email ?? '';

  Future<void> _init() async {
    if (_initialised) return;
    await GoogleSignIn.instance.initialize(serverClientId: clientId);
    _initialised = true;
  }

  static String _explain(GoogleSignInException e) {
    final d = e.description ?? '';
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Sign-in was cancelled.';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google rejected this app\'s setup. Check in Firebase: the Android app has package '
            'com.spendline.spendline and the SHA-1 of the key this APK was signed with, and the Web client ID '
            'pasted here is correct. ($d)';
      case GoogleSignInExceptionCode.interrupted:
        return 'Sign-in was interrupted. Try again.';
      default:
        if (d.toLowerCase().contains('no credential')) {
          return 'No Google account was offered. Add a Google account to this phone, and check the Android app '
              'SHA-1 in Firebase matches this build.';
        }
        return 'Google sign-in failed: ${d.isEmpty ? e.code.name : d}';
    }
  }

  /// Shows the Google account picker and asks for the Drive-file scope.
  Future<String> signIn() async {
    if (!configured) {
      throw SheetsException('Paste the Web client ID in box 1 first (see step 2).');
    }
    try {
      await _init();
      _account = await GoogleSignIn.instance.authenticate();
      await _account!.authorizationClient.authorizeScopes(_scopes);
      return _account!.email;
    } on GoogleSignInException catch (e) {
      throw SheetsException(_explain(e));
    } on SheetsException {
      rethrow;
    } catch (e) {
      throw SheetsException('Google sign-in failed: $e');
    }
  }

  /// Signs back in silently on later launches. Returns false if the user has to sign in again.
  Future<bool> restore() async {
    if (!configured) return false;
    try {
      await _init();
      _account ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
      return _account != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _init();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    _account = null;
  }

  Future<Map<String, String>> _headers() async {
    final acc = _account;
    if (acc == null) throw SheetsException('Not signed in to Google.');
    try {
      final h = await acc.authorizationClient.authorizationHeaders(_scopes, promptIfNecessary: true);
      if (h == null) throw SheetsException('Google did not give access to Sheets.');
      return h;
    } on GoogleSignInException catch (e) {
      throw SheetsException(_explain(e));
    }
  }

  /* ---------------- spreadsheet ---------------- */

  /// Opens the Spendline sheet created earlier (even after a reinstall), or makes a new one.
  Future<SheetInfo> ensureSpreadsheet({String? knownId}) async {
    if (knownId != null && knownId.isNotEmpty) {
      try {
        return await _info(knownId);
      } on SheetsException catch (e) {
        if (e.offline) rethrow;
      }
    }
    final found = await _call(
      'GET',
      'https://www.googleapis.com/drive/v3/files',
      query: {
        'q': "name='$_title' and mimeType='application/vnd.google-apps.spreadsheet' and trashed=false",
        'fields': 'files(id)',
        'orderBy': 'createdTime',
      },
    );
    final files = (found['files'] as List?) ?? const [];
    if (files.isNotEmpty) return _info('${(files.first as Map)['id']}');

    final created = await _call('POST', 'https://sheets.googleapis.com/v4/spreadsheets', body: {
      'properties': {'title': _title},
      'sheets': [
        {
          'properties': {'title': _tab, 'gridProperties': {'frozenRowCount': 1}},
        },
      ],
    });
    final id = '${created['spreadsheetId']}';
    await _call(
      'PUT',
      'https://sheets.googleapis.com/v4/spreadsheets/$id/values/$_tab!A1:I1',
      query: {'valueInputOption': 'RAW'},
      body: {
        'values': [_header],
      },
    );
    return _parseInfo(created);
  }

  Future<SheetInfo> _info(String id) async {
    final m = await _call('GET', 'https://sheets.googleapis.com/v4/spreadsheets/$id',
        query: {'fields': 'spreadsheetId,spreadsheetUrl,sheets.properties'});
    return _parseInfo(m);
  }

  SheetInfo _parseInfo(Map<String, dynamic> m) {
    final sheets = (m['sheets'] as List?) ?? const [];
    var gid = 0;
    for (final s in sheets) {
      final p = (s as Map)['properties'] as Map?;
      if (p != null && p['title'] == _tab) gid = (p['sheetId'] as num?)?.toInt() ?? 0;
    }
    return SheetInfo('${m['spreadsheetId']}', '${m['spreadsheetUrl'] ?? ''}', gid);
  }

  /* ---------------- rows ---------------- */

  static List<Object> _row(Entry e) =>
      [e.id, e.date, e.time, e.type.label, e.category, e.person, e.description, e.amount, e.note];

  Future<List<Entry>> readAll(String sheetId) async {
    final m = await _call(
      'GET',
      'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$_tab!A2:I',
      query: {'valueRenderOption': 'UNFORMATTED_VALUE'},
    );
    final out = <Entry>[];
    for (final r in (m['values'] as List?) ?? const []) {
      final c = r as List;
      String at(int i) => i < c.length ? '${c[i]}' : '';
      final id = at(0);
      if (id.isEmpty) continue;
      out.add(Entry(
        id: id,
        date: at(1),
        time: at(2),
        type: EntryType.fromLabel(at(3)),
        category: at(4).isEmpty ? 'Other' : at(4),
        person: at(5),
        description: at(6),
        amount: c.length > 7 && c[7] is num ? (c[7] as num).toDouble() : double.tryParse(at(7)) ?? 0,
        note: at(8),
      ));
    }
    return out;
  }

  Future<List<String>> _ids(String sheetId) async {
    final m = await _call('GET', 'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$_tab!A:A');
    return [for (final r in (m['values'] as List?) ?? const []) (r as List).isEmpty ? '' : '${r.first}'];
  }

  /// Adds new rows and rewrites rows whose id is already in the sheet.
  Future<void> upsert(String sheetId, List<Entry> entries) async {
    if (entries.isEmpty) return;
    final ids = await _ids(sheetId); // index 0 is the header row
    final updates = <Map<String, Object>>[];
    final appends = <List<Object>>[];
    for (final e in entries) {
      final i = ids.indexOf(e.id);
      if (i > 0) {
        updates.add({'range': '$_tab!A${i + 1}:I${i + 1}', 'values': [_row(e)]});
      } else {
        appends.add(_row(e));
      }
    }
    final base = 'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values';
    if (updates.isNotEmpty) {
      await _call('POST', '$base:batchUpdate', body: {'valueInputOption': 'RAW', 'data': updates});
    }
    if (appends.isNotEmpty) {
      await _call(
        'POST',
        '$base/$_tab!A:I:append',
        query: {'valueInputOption': 'RAW', 'insertDataOption': 'INSERT_ROWS'},
        body: {'values': appends},
      );
    }
  }

  Future<void> deleteRows(SheetInfo sheet, Set<String> idsToDelete) async {
    if (idsToDelete.isEmpty) return;
    final ids = await _ids(sheet.id);
    final rows = [
      for (var i = 1; i < ids.length; i++)
        if (idsToDelete.contains(ids[i])) i,
    ]..sort((a, b) => b.compareTo(a)); // bottom first so indexes stay valid
    if (rows.isEmpty) return;
    await _call('POST', 'https://sheets.googleapis.com/v4/spreadsheets/${sheet.id}:batchUpdate', body: {
      'requests': [
        for (final r in rows)
          {
            'deleteDimension': {
              'range': {'sheetId': sheet.gid, 'dimension': 'ROWS', 'startIndex': r, 'endIndex': r + 1},
            },
          },
      ],
    });
  }

  /* ---------------- http ---------------- */

  Future<Map<String, dynamic>> _call(
    String method,
    String url, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = Uri.parse(url).replace(queryParameters: query);
    final headers = await _headers();
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        req.headers['Content-Type'] = 'application/json; charset=utf-8';
        req.body = jsonEncode(body);
      }
      final res = await http.Response.fromStream(await req.send().timeout(_timeout));
      if (res.statusCode == 401) {
        await _account?.authorizationClient.clearAuthorizationToken(
          accessToken: headers['Authorization']!.replaceFirst('Bearer ', ''),
        );
        throw SheetsException('Google session expired. Try again.');
      }
      final decoded = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
      if (res.statusCode >= 300) {
        final msg = decoded is Map ? (decoded['error'] is Map ? decoded['error']['message'] : decoded['error']) : null;
        throw SheetsException('Google said: ${msg ?? res.statusCode}');
      }
      return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    } on SheetsException {
      rethrow;
    } on TimeoutException {
      throw SheetsException('Google took too long to answer.', offline: true);
    } on SocketException {
      throw SheetsException('No internet connection.', offline: true);
    } on HandshakeException {
      throw SheetsException('Secure connection failed.', offline: true);
    } on http.ClientException catch (e) {
      throw SheetsException('Network error: ${e.message}', offline: true);
    }
  }
}
