import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/entry.dart';
import '../models/filter.dart';
import '../models/group.dart';
import '../services/csv.dart';
import '../services/firebase_cloud.dart';
import '../services/google_sheets.dart';
import '../services/parser.dart';
import '../services/smart_parser.dart';
import '../services/store.dart';
import '../ui/glass.dart' show Aurora;

class PersonBalance {
  PersonBalance(this.name);
  final String name;

  /// Positive: they owe you. Negative: you owe them.
  double balance = 0;
  String last = '';
}

/// Single source of truth. The phone is the database; the Google Sheet is an
/// optional mirror that is brought up to date whenever there is internet.
class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;

  String currency = 'Rs';
  bool aiEnabled = false;
  String aiStatus = '';

  String googleEmail = '';
  String sheetId = '';
  String sheetUrl = '';
  int _sheetGid = 0;

  /// Which language the microphone listens for: 'ur_PK' or 'en_US'.
  String voiceLocale = 'ur_PK';

  late EntryStore _store;
  List<Entry> entries = [];
  List<Group> groups = [];
  List<GroupExpense> groupExpenses = [];
  Map<String, String> learned = {}; // word -> category the user chose before
  DateTime? lastExport;
  bool _nudgeDismissed = false;
  final Set<String> _deletes = {}; // removed on the phone, still in the sheet
  bool syncing = false;
  String? notice;

  final SmartParser smart = SmartParser();
  late GoogleSheets _google = GoogleSheets(clientId: kGoogleServerClientId);

  // Google / Firebase setup (pasted in the app, so no rebuild is needed to try it)
  String googleClientId = kGoogleServerClientId;
  String fbProject = kFirebaseProjectId;
  String fbApiKey = kFirebaseApiKey;
  bool cloudOn = false;
  String cloudEmail = '';
  bool cloudSyncing = false;
  String? cloudNotice;
  DateTime? lastCloudSync;
  FirebaseCloud? _fb;
  final Set<String> _cloudDirty = {}; // 'collection/id' waiting to be uploaded
  final Set<String> _cloudDeleted = {}; // 'collection/id' waiting to be deleted remotely

  EntryFilter filter = EntryFilter.none;
  bool onboarded = true;
  bool calmBackground = false;
  final NumberFormat _num = NumberFormat('#,##0.##');
  final math.Random _rng = math.Random();

  bool get connected => sheetId.isNotEmpty;
  bool get googleAvailable => googleClientId.isNotEmpty;
  bool get cloudConfigured => googleClientId.isNotEmpty && fbProject.isNotEmpty && fbApiKey.isNotEmpty;
  int get pendingCount => connected ? entries.where((e) => e.pending).length + _deletes.length : 0;
  SheetInfo get _sheet => SheetInfo(sheetId, sheetUrl, _sheetGid);

  String fmt(double n) => _num.format(n);
  String money(double n) => '$currency ${fmt(n)}';

  /// Short form for tight spots: 1,234 -> 1,234; 174,521 -> 174.5k; 2,300,000 -> 2.3M.
  String compact(double n) {
    final a = n.abs();
    if (a >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
    if (a >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (a >= 1e5) return '${(n / 1e3).toStringAsFixed(a >= 1e6 ? 0 : 1)}k';
    return fmt(n);
  }

  Future<void> setCalm(bool on) async {
    calmBackground = on;
    Aurora.calm.value = on;
    await _prefs.setBool('calm', on);
    notifyListeners();
  }

  // Derived values are recomputed at most once per change: widgets read them many times per frame.
  final Map<String, Object?> _memo = {};

  @override
  void notifyListeners() {
    _memo.clear();
    super.notifyListeners();
  }

  T _cached<T>(String key, T Function() compute) => (_memo[key] ??= compute()) as T;

  /* ---------------- startup & settings ---------------- */

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    currency = _prefs.getString('currency') ?? 'Rs';
    aiEnabled = _prefs.getBool('aiEnabled') ?? false;
    googleEmail = _prefs.getString('googleEmail') ?? '';
    sheetId = _prefs.getString('sheetId') ?? '';
    sheetUrl = _prefs.getString('sheetUrl') ?? '';
    _sheetGid = _prefs.getInt('sheetGid') ?? 0;
    _deletes.addAll(_prefs.getStringList('deletes') ?? const []);

    voiceLocale = _prefs.getString('voiceLocale') ?? 'ur_PK';
    onboarded = _prefs.getBool('onboarded') ?? false;
    calmBackground = _prefs.getBool('calm') ?? false;
    Aurora.calm.value = calmBackground;
    // Blank or missing values mean "use the built-in ones", never "no setup".
    String pick(String key, String fallback) {
      final v = _prefs.getString(key)?.trim() ?? '';
      return v.isEmpty ? fallback : v;
    }

    googleClientId = pick('googleClientId', kGoogleServerClientId);
    fbProject = pick('fbProject', kFirebaseProjectId);
    fbApiKey = pick('fbApiKey', kFirebaseApiKey);
    cloudOn = _prefs.getBool('cloudOn') ?? false;
    cloudEmail = _prefs.getString('cloudEmail') ?? '';
    _cloudDirty.addAll(_prefs.getStringList('cloudDirty') ?? const []);
    _cloudDeleted.addAll(_prefs.getStringList('cloudDeleted') ?? const []);
    _google = GoogleSheets(clientId: googleClientId);
    _nudgeDismissed = _prefs.getBool('nudgeDismissed') ?? false;
    final le = _prefs.getString('lastExport');
    lastExport = le == null ? null : DateTime.tryParse(le);
    try {
      learned = Map<String, String>.from(jsonDecode(_prefs.getString('learned') ?? '{}') as Map);
    } catch (_) {
      learned = {};
    }

    _store = await EntryStore.open();
    // v1 kept everything in one JSON string; move it into the database once.
    final legacy = _prefs.getString('entries');
    if (legacy != null) {
      try {
        final old = (jsonDecode(legacy) as List).map((e) => Entry.fromJson(Map<String, dynamic>.from(e as Map)));
        await _store.upsertMany(old);
      } catch (_) {
        // Unreadable legacy data is ignored.
      }
      await _prefs.remove('entries');
    }
    entries = await _store.all();
    groups = await _store.allGroups();
    groupExpenses = await _store.allGroupExpenses();
    _sort();
    _refreshHints();

    if (cloudOn && cloudConfigured) {
      _fb = FirebaseCloud(projectId: fbProject, apiKey: fbApiKey)
        ..uid = _prefs.getString('fbUid') ?? ''
        ..refreshToken = _prefs.getString('fbRefresh') ?? '';
      unawaited(syncCloud());
    }
    if (connected) unawaited(sync());
    if (aiEnabled) unawaited(startAi());
  }

  /// Feeds what the user taught the app into the parser.
  void _refreshHints() {
    learnedCategories = Map.of(learned);
    final names = <String, String>{};
    for (final e in entries) {
      final n = e.person.trim();
      if (n.contains(' ')) names.putIfAbsent(n.toLowerCase(), () => n);
    }
    knownPeople = names;
  }

  /// Remembers a category the user picked for these words, so next time it is automatic.
  Future<void> learn(Draft original, Draft fixed) async {
    if (fixed.type != EntryType.expense || fixed.category == original.category) return;
    if (fixed.category == 'Other' || fixed.category == 'Lending' || fixed.category == 'Income') return;
    final skip = {
      ...fixed.person.toLowerCase().split(RegExp(r'\s+')),
      'to', 'from', 'for', 'the', 'and', 'ko', 'se', 'ne', 'rs', 'pkr',
    };
    final words = <String>{};
    for (final text in [original.description, fixed.description]) {
      for (final w in text.toLowerCase().split(RegExp(r'[^\p{L}]+', unicode: true))) {
        if (w.length >= 3 && !skip.contains(w)) words.add(w);
      }
    }
    if (words.isEmpty) return;
    for (final w in words) {
      learned[w] = fixed.category;
    }
    await _prefs.setString('learned', jsonEncode(learned));
    _refreshHints();
    notifyListeners();
  }

  Future<void> forgetLearned() async {
    learned = {};
    await _prefs.remove('learned');
    _refreshHints();
    notifyListeners();
  }

  Future<void> setVoiceLocale(String l) async {
    voiceLocale = l;
    await _prefs.setString('voiceLocale', l);
    notifyListeners();
  }

  /* ---------------- backup ---------------- */

  bool get showBackupNudge =>
      !connected && !_nudgeDismissed && lastExport == null && (entries.length + groupExpenses.length) >= 10;

  Future<void> dismissNudge() async {
    _nudgeDismissed = true;
    await _prefs.setBool('nudgeDismissed', true);
    notifyListeners();
  }

  /// Writes all entries to a CSV file and returns its path.
  Future<String> exportCsv() async {
    final stamp = isoDate(DateTime.now());
    final f = File('${Directory.systemTemp.path}/spendline-$stamp.csv');
    await f.writeAsString(entriesToCsv(entries));
    lastExport = DateTime.now();
    await _prefs.setString('lastExport', lastExport!.toIso8601String());
    notifyListeners();
    return f.path;
  }

  /// Adds entries from a CSV made by [exportCsv]. Entries already here are left alone.
  Future<int> importCsv(String text) async {
    final have = {for (final e in entries) e.id};
    final fresh = [for (final e in entriesFromCsv(text)) if (!have.contains(e.id)) e.copyWith(pending: true)];
    if (fresh.isEmpty) return 0;
    await _store.upsertMany(fresh);
    for (final e in fresh) {
      _dirty('entries', e.id);
    }
    entries.addAll(fresh);
    _sort();
    _refreshHints();
    notifyListeners();
    unawaited(sync());
    return fresh.length;
  }

  Future<void> setCurrency(String c) async {
    currency = c.trim().isEmpty ? 'Rs' : c.trim();
    await _prefs.setString('currency', currency);
    notifyListeners();
  }

  Future<void> setAi(bool on) async {
    aiEnabled = on;
    await _prefs.setBool('aiEnabled', on);
    if (on) {
      await startAi();
    } else {
      aiStatus = '';
      notifyListeners();
    }
  }

  Future<void> startAi() async {
    aiStatus = 'Starting…';
    notifyListeners();
    try {
      await smart.load(onProgress: (pct) {
        aiStatus = 'Downloading model: ${pct.round()}%';
        notifyListeners();
      });
      aiStatus = 'Ready. Used only when a line is hard to read.';
    } catch (e) {
      aiStatus = e is StateError ? e.message : 'Smart parsing could not start: $e';
      aiEnabled = false;
      await _prefs.setBool('aiEnabled', false);
    }
    notifyListeners();
  }

  /* ---------------- Google Sheet (optional) ---------------- */

  /// Signs in, finds or creates the "Spendline" sheet, and uploads everything on the phone.
  Future<void> connectGoogle() async {
    final email = await _google.signIn();
    final info = await _google.ensureSpreadsheet();
    googleEmail = email;
    sheetId = info.id;
    sheetUrl = info.url;
    _sheetGid = info.gid;
    await _prefs.setString('googleEmail', email);
    await _prefs.setString('sheetId', sheetId);
    await _prefs.setString('sheetUrl', sheetUrl);
    await _prefs.setInt('sheetGid', _sheetGid);
    entries = [for (final e in entries) e.copyWith(pending: true)];
    await _store.upsertMany(entries);
    notifyListeners();
    await sync();
  }

  /// Stops syncing. Everything stays on the phone and in the sheet.
  Future<void> disconnectGoogle() async {
    await _google.signOut();
    googleEmail = '';
    sheetId = '';
    sheetUrl = '';
    _sheetGid = 0;
    _deletes.clear();
    notice = null;
    for (final k in ['googleEmail', 'sheetId', 'sheetUrl', 'sheetGid', 'deletes']) {
      await _prefs.remove(k);
    }
    notifyListeners();
  }

  /// Sends changes made while offline, then pulls rows added from elsewhere.
  Future<void> sync() async {
    if (!connected || syncing) return;
    syncing = true;
    notifyListeners();
    try {
      if (!await _google.restore()) {
        notice = 'Sign in to Google again to keep syncing.';
        return;
      }
      if (_deletes.isNotEmpty) {
        await _google.deleteRows(_sheet, {..._deletes});
        _deletes.clear();
        await _prefs.remove('deletes');
      }
      final pending = entries.where((e) => e.pending).toList();
      if (pending.isNotEmpty) {
        await _google.upsert(sheetId, pending);
        final sent = {for (final e in pending) e.id: e};
        entries = [for (final e in entries) sent[e.id] == e ? e.copyWith(pending: false) : e];
        await _store.upsertMany(entries.where((e) => sent.containsKey(e.id)));
      }
      final remote = await _google.readAll(sheetId);
      final have = {for (final e in entries) e.id};
      final added = remote.where((r) => !have.contains(r.id)).toList();
      if (added.isNotEmpty) {
        entries.addAll(added);
        await _store.upsertMany(added);
        _refreshHints();
      }
      _sort();
      notice = null;
    } on SheetsException catch (e) {
      notice = e.offline ? 'Offline. ${pendingCount == 0 ? 'Saved' : '$pendingCount saved'} on this phone, will sync later.' : e.message;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /* ---------------- entries ---------------- */

  String _newId() => 'l${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rng.nextInt(1 << 16).toRadixString(36)}';

  Future<Entry> add(Draft d, String raw) async {
    final now = DateTime.now();
    final desc = d.description.trim();
    final e = Entry(
      id: _newId(),
      date: d.date,
      time: '${two(now.hour)}:${two(now.minute)}',
      type: d.type,
      category: d.category,
      person: d.person.trim(),
      description: desc.isEmpty ? d.category : desc,
      amount: d.amount,
      note: raw,
      pending: true,
    );
    await _put(e);
    return e;
  }

  /// Replaces an entry after the user edited it.
  Future<void> update(Entry old, Entry changed) async {
    final i = entries.indexWhere((e) => e.id == old.id);
    if (i < 0) return;
    entries[i] = changed.copyWith(pending: true);
    _sort();
    _refreshHints();
    notifyListeners();
    await _store.upsert(entries.firstWhere((e) => e.id == old.id));
    _dirty('entries', old.id);
    unawaited(sync());
  }

  /// Puts an entry back (Undo after delete).
  Future<void> restore(Entry e) async {
    _deletes.remove(e.id);
    await _prefs.setStringList('deletes', _deletes.toList());
    await _put(e.copyWith(pending: true));
  }

  Future<void> _put(Entry e) async {
    entries.insert(0, e);
    _sort();
    _refreshHints();
    notifyListeners();
    await _store.upsert(e);
    _dirty('entries', e.id);
    unawaited(sync());
  }

  Future<void> remove(Entry e) async {
    entries.removeWhere((x) => x.id == e.id);
    if (connected) {
      _deletes.add(e.id);
      await _prefs.setStringList('deletes', _deletes.toList());
    }
    notifyListeners();
    await _store.delete(e.id);
    _gone('entries', e.id);
    unawaited(sync());
  }

  void _sort() => entries.sort((a, b) => b.sortKey.compareTo(a.sortKey));

  /* ---------------- Firebase sync ---------------- */

  Future<void> saveCloudConfig({required String clientId, required String project, required String apiKey}) async {
    googleClientId = clientId.trim().isEmpty ? kGoogleServerClientId : clientId.trim();
    fbProject = project.trim().isEmpty ? kFirebaseProjectId : project.trim();
    fbApiKey = apiKey.trim().isEmpty ? kFirebaseApiKey : apiKey.trim();
    // Only keep overrides that differ from the built-in values.
    Future<void> keep(String key, String v, String builtIn) =>
        v == builtIn ? _prefs.remove(key) : _prefs.setString(key, v);
    await keep('googleClientId', googleClientId, kGoogleServerClientId);
    await keep('fbProject', fbProject, kFirebaseProjectId);
    await keep('fbApiKey', fbApiKey, kFirebaseApiKey);
    _google = GoogleSheets(clientId: googleClientId);
    notifyListeners();
  }

  /// Forget anything pasted in Settings and use the values compiled into the app.
  Future<void> resetCloudConfig() =>
      saveCloudConfig(clientId: '', project: '', apiKey: '');

  /// The single "Back up & sync" switch: one Google sign-in, then Firebase sync and the Sheet copy.
  /// Firebase is required; if only the Sheet part fails the sync still stays on and [sheetNotice] says why.
  String? sheetNotice;
  bool get backupOn => cloudOn;

  Future<void> connectBackup() async {
    sheetNotice = null;
    await connectCloud();
    if (!connected) {
      try {
        await _attachSheet(_google.email);
      } on SheetsException catch (e) {
        sheetNotice = e.message;
        notifyListeners();
      }
    }
  }

  Future<void> disconnectBackup() async {
    if (connected) await disconnectGoogle();
    await disconnectCloud();
    sheetNotice = null;
    notifyListeners();
  }

  Future<void> _attachSheet(String email) async {
    final info = await _google.ensureSpreadsheet();
    googleEmail = email;
    sheetId = info.id;
    sheetUrl = info.url;
    _sheetGid = info.gid;
    await _prefs.setString('googleEmail', email);
    await _prefs.setString('sheetId', sheetId);
    await _prefs.setString('sheetUrl', sheetUrl);
    await _prefs.setInt('sheetGid', _sheetGid);
    entries = [for (final e in entries) e.copyWith(pending: true)];
    await _store.upsertMany(entries);
    notifyListeners();
    await sync();
  }

  /// Signs in with Google, then Firebase, uploads everything and starts syncing.
  Future<void> connectCloud() async {
    if (!cloudConfigured) throw SheetsException('Fill in the three setup values first.');
    final email = await _google.signIn();
    final token = _google.idToken;
    if (token == null) {
      throw SheetsException('Google did not return an ID token. Check that the Web client ID is the one from Firebase.');
    }
    final fb = FirebaseCloud(projectId: fbProject, apiKey: fbApiKey);
    await fb.signInWithGoogle(token);
    _fb = fb;
    cloudOn = true;
    cloudEmail = email;
    _cloudDeleted.clear();
    _cloudDirty
      ..clear()
      ..addAll(entries.map((e) => 'entries/${e.id}'))
      ..addAll(groups.map((g) => 'groups/${g.id}'))
      ..addAll(groupExpenses.map((e) => 'group_expenses/${e.id}'));
    await _persistCloud();
    notifyListeners();
    await syncCloud(throwErrors: true);
  }

  Future<void> disconnectCloud() async {
    cloudOn = false;
    cloudEmail = '';
    cloudNotice = null;
    _fb = null;
    _cloudDirty.clear();
    _cloudDeleted.clear();
    for (final k in ['cloudOn', 'cloudEmail', 'fbUid', 'fbRefresh', 'cloudDirty', 'cloudDeleted']) {
      await _prefs.remove(k);
    }
    notifyListeners();
  }

  Future<void> _persistCloud() async {
    await _prefs.setBool('cloudOn', cloudOn);
    await _prefs.setString('cloudEmail', cloudEmail);
    await _prefs.setStringList('cloudDirty', _cloudDirty.toList());
    await _prefs.setStringList('cloudDeleted', _cloudDeleted.toList());
    final fb = _fb;
    if (fb != null && fb.hasSession) {
      await _prefs.setString('fbUid', fb.uid);
      await _prefs.setString('fbRefresh', fb.refreshToken);
    }
  }

  void _dirty(String col, String id) {
    if (!cloudOn) return;
    _cloudDirty.add('$col/$id');
    _cloudDeleted.remove('$col/$id');
    unawaited(_persistCloud().then((_) => syncCloud()));
  }

  void _gone(String col, String id) {
    if (!cloudOn) return;
    _cloudDirty.remove('$col/$id');
    _cloudDeleted.add('$col/$id');
    unawaited(_persistCloud().then((_) => syncCloud()));
  }

  Map<String, dynamic>? _cloudDoc(String col, String id) {
    switch (col) {
      case 'entries':
        for (final e in entries) {
          if (e.id == id) return (e.toJson())..remove('pending');
        }
      case 'groups':
        for (final g in groups) {
          if (g.id == id) return g.toJson();
        }
      case 'group_expenses':
        for (final e in groupExpenses) {
          if (e.id == id) return e.toJson();
        }
    }
    return null;
  }

  /// Uploads local changes, then merges in whatever other devices changed.
  Future<void> syncCloud({bool throwErrors = false}) async {
    final fb = _fb;
    if (!cloudOn || fb == null || cloudSyncing) return;
    cloudSyncing = true;
    notifyListeners();
    try {
      final sentDirty = {..._cloudDirty};
      final sentGone = {..._cloudDeleted};
      final writes = <CloudWrite>[];
      for (final key in sentDirty) {
        final i = key.indexOf('/');
        final col = key.substring(0, i), id = key.substring(i + 1);
        final doc = _cloudDoc(col, id);
        if (doc != null) writes.add(CloudWrite.put(col, id, doc));
      }
      for (final key in sentGone) {
        final i = key.indexOf('/');
        writes.add(CloudWrite.delete(key.substring(0, i), key.substring(i + 1)));
      }
      if (writes.isNotEmpty) await fb.commit(writes);
      _cloudDirty.removeAll(sentDirty);
      _cloudDeleted.removeAll(sentGone);

      await _pullCloud(fb);
      lastCloudSync = DateTime.now();
      cloudNotice = null;
      await _persistCloud();
    } on SheetsException catch (e) {
      cloudNotice = e.offline ? 'Offline. Changes will upload when you are back online.' : e.message;
      if (throwErrors && !e.offline) rethrow;
    } finally {
      cloudSyncing = false;
      notifyListeners();
    }
  }

  bool _sameJson(Map<String, dynamic> a, Map<String, dynamic> b) => jsonEncode(a) == jsonEncode(b);

  Future<void> _pullCloud(FirebaseCloud fb) async {
    bool skip(String key) => _cloudDirty.contains(key) || _cloudDeleted.contains(key);

    for (final m in await fb.list('entries')) {
      final r = Entry.fromJson(m);
      if (r.id.isEmpty || skip('entries/${r.id}')) continue;
      final i = entries.indexWhere((e) => e.id == r.id);
      final incoming = r.copyWith(pending: connected);
      if (i < 0) {
        entries.add(incoming);
        await _store.upsert(incoming);
      } else if (!_sameJson(entries[i].copyWith(pending: false).toJson(), r.toJson())) {
        entries[i] = incoming;
        await _store.upsert(incoming);
      }
    }
    for (final m in await fb.list('groups')) {
      final g = Group.fromJson(m);
      if (g.id.isEmpty || skip('groups/${g.id}')) continue;
      final i = groups.indexWhere((x) => x.id == g.id);
      if (i < 0) {
        groups.add(g);
        await _store.upsertGroup(g);
      } else if (!_sameJson(groups[i].toJson(), g.toJson())) {
        groups[i] = g;
        await _store.upsertGroup(g);
      }
    }
    for (final m in await fb.list('group_expenses')) {
      final e = GroupExpense.fromJson(m);
      if (e.id.isEmpty || skip('group_expenses/${e.id}')) continue;
      final i = groupExpenses.indexWhere((x) => x.id == e.id);
      if (i < 0) {
        groupExpenses.add(e);
        await _store.upsertGroupExpense(e);
      } else if (!_sameJson(groupExpenses[i].toJson(), e.toJson())) {
        groupExpenses[i] = e;
        await _store.upsertGroupExpense(e);
      }
    }
    _sort();
    groupExpenses.sort((a, b) => b.date.compareTo(a.date));
    groups.sort((a, b) => b.created.compareTo(a.created));
    _refreshHints();
  }

  Future<void> completeOnboarding() async {
    onboarded = true;
    await _prefs.setBool('onboarded', true);
    notifyListeners();
  }

  /// Things the user logs again and again ("chai", "petrol"), for one-tap chips.
  List<String> get frequentPhrases => _cached('frequent', _computeFrequent);

  List<String> _computeFrequent() {
    final since = isoDate(DateTime.now().subtract(const Duration(days: 90)));
    final counts = <String, int>{};
    for (final e in entries) {
      if (e.type != EntryType.expense || e.date.compareTo(since) < 0) continue;
      final w = e.description.split(' · ').first.trim().toLowerCase();
      if (w.length < 3 || w.contains(RegExp(r'\d'))) continue;
      counts[w] = (counts[w] ?? 0) + 1;
    }
    final top = counts.entries.where((e) => e.value >= 2).toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in top.take(5)) cap(e.key)];
  }

  /* ---------------- filters ---------------- */

  void setFilter(EntryFilter f) {
    filter = f;
    notifyListeners();
  }

  List<Entry> get visibleEntries =>
      _cached('visible', () => filter.active ? entries.where(filter.matches).toList() : entries);

  List<String> get categoriesInUse => _cached('cats', () => entries.map((e) => e.category).toSet().toList()..sort());
  List<String> get peopleInUse => _cached(
      'peopleInUse',
      () => entries.map((e) => e.person.trim()).where((p) => p.isNotEmpty).map(cap).toSet().toList()..sort());

  /* ---------------- groups (Splitwise-style) ---------------- */

  List<GroupExpense> expensesOf(Group g) => [for (final e in groupExpenses) if (e.groupId == g.id) e];

  /// Your own balance in a group. Positive: the group owes you.
  double myBalance(Group g) => netBalances(g, expensesOf(g))[meName] ?? 0;

  /// Everyone the user has met in the ledger or groups, for quick member picking.
  List<String> get knownNames {
    final set = <String>{
      for (final e in entries) if (e.person.trim().isNotEmpty) cap(e.person.trim()),
      for (final g in groups) ...g.members,
    }..remove(meName);
    return set.toList()..sort();
  }

  Future<Group> addGroup(String name, List<String> others) async {
    final members = [meName, ...others.map((n) => cap(n.trim())).where((n) => n.isNotEmpty && n != meName)];
    final g = Group(
      id: 'g${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      name: name.trim().isEmpty ? 'New group' : name.trim(),
      members: members.toSet().toList(),
      created: DateTime.now().toIso8601String(),
    );
    groups.insert(0, g);
    notifyListeners();
    await _store.upsertGroup(g);
    _dirty('groups', g.id);
    return g;
  }

  Future<void> updateGroup(Group g) async {
    final i = groups.indexWhere((x) => x.id == g.id);
    if (i < 0) return;
    groups[i] = g;
    notifyListeners();
    await _store.upsertGroup(g);
    _dirty('groups', g.id);
  }

  Future<void> removeGroup(Group g) async {
    final gone = [for (final e in groupExpenses) if (e.groupId == g.id) e.id];
    groups.removeWhere((x) => x.id == g.id);
    groupExpenses.removeWhere((e) => e.groupId == g.id);
    notifyListeners();
    await _store.deleteGroup(g.id);
    _gone('groups', g.id);
    for (final id in gone) {
      _gone('group_expenses', id);
    }
  }

  Future<GroupExpense> addGroupExpense(
    Group g, {
    required String description,
    required double amount,
    required String paidBy,
    required Map<String, double> shares,
    required String date,
    bool settlement = false,
  }) async {
    final e = GroupExpense(
      id: 'x${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rng.nextInt(1 << 12).toRadixString(36)}',
      groupId: g.id,
      date: date,
      description: description.trim().isEmpty ? 'Expense' : description.trim(),
      amount: amount,
      paidBy: paidBy,
      shares: shares,
      settlement: settlement,
    );
    await restoreGroupExpense(e);
    return e;
  }

  Future<void> restoreGroupExpense(GroupExpense e) async {
    groupExpenses.insert(0, e);
    groupExpenses.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    await _store.upsertGroupExpense(e);
    _dirty('group_expenses', e.id);
  }

  Future<void> removeGroupExpense(GroupExpense e) async {
    groupExpenses.removeWhere((x) => x.id == e.id);
    notifyListeners();
    await _store.deleteGroupExpense(e.id);
    _gone('group_expenses', e.id);
  }

  /// All groups and their expenses as JSON text (CSV cannot hold splits).
  Future<String> exportGroups() async {
    final f = File('${Directory.systemTemp.path}/spendline-groups-${isoDate(DateTime.now())}.json');
    await f.writeAsString(jsonEncode({
      'groups': [for (final g in groups) g.toJson()],
      'expenses': [for (final e in groupExpenses) e.toJson()],
    }));
    return f.path;
  }

  /// Returns how many expenses were added. Groups and expenses already here are kept.
  Future<int> importGroups(String text) async {
    final m = jsonDecode(text) as Map;
    final haveG = {for (final g in groups) g.id};
    final haveE = {for (final e in groupExpenses) e.id};
    var added = 0;
    for (final j in (m['groups'] as List? ?? const [])) {
      final g = Group.fromJson(Map<String, dynamic>.from(j as Map));
      if (haveG.add(g.id)) {
        groups.add(g);
        await _store.upsertGroup(g);
        _dirty('groups', g.id);
      }
    }
    for (final j in (m['expenses'] as List? ?? const [])) {
      final e = GroupExpense.fromJson(Map<String, dynamic>.from(j as Map));
      if (haveE.add(e.id)) {
        groupExpenses.add(e);
        await _store.upsertGroupExpense(e);
        _dirty('group_expenses', e.id);
        added++;
      }
    }
    groupExpenses.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    return added;
  }

  /* ---------------- summaries ---------------- */

  String get _today => isoDate(DateTime.now());
  String get _month => _today.substring(0, 7);

  double _sum(bool Function(Entry e) test) => entries.where(test).fold(0.0, (s, e) => s + e.amount);
  double _sumC(String k, bool Function(Entry e) t) => _cached(k, () => _sum(t));

  double get spentThisMonth => _sumC('spentMonth', (e) => e.type == EntryType.expense && e.date.startsWith(_month));
  double get spentToday => _sumC('spentToday', (e) => e.type == EntryType.expense && e.date == _today);
  double get moneyInThisMonth => _sumC('moneyIn', (e) => e.type.isMoneyIn && e.date.startsWith(_month));

  /// Daily spending, oldest first, ending today.
  List<double> lastDays(int n) => _cached('days$n', () => _computeDays(n));

  List<double> _computeDays(int n) {
    final byDay = <String, double>{};
    for (final e in entries) {
      if (e.type == EntryType.expense) byDay[e.date] = (byDay[e.date] ?? 0) + e.amount;
    }
    final now = DateTime.now();
    return [for (var i = n - 1; i >= 0; i--) byDay[isoDate(DateTime(now.year, now.month, now.day - i))] ?? 0];
  }

  List<PersonBalance> get people => _cached('people', _computePeople);

  List<PersonBalance> _computePeople() {
    final map = <String, PersonBalance>{};
    for (final e in entries) {
      if (e.person.trim().isEmpty || (e.type != EntryType.given && e.type != EntryType.received)) continue;
      final key = e.person.trim().toLowerCase();
      final p = map.putIfAbsent(key, () => PersonBalance(cap(e.person.trim())));
      p.balance += e.type == EntryType.given ? e.amount : -e.amount;
      if (e.date.compareTo(p.last) > 0) p.last = e.date;
    }
    final list = map.values.toList()
      ..sort((a, b) {
        final c = b.balance.abs().compareTo(a.balance.abs());
        return c != 0 ? c : b.last.compareTo(a.last);
      });
    return list;
  }

  double get owedToYou => people.fold(0.0, (s, p) => s + (p.balance > 0 ? p.balance : 0));
}
