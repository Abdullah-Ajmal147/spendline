import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'dart:convert';

import '../models/entry.dart';
import '../models/group.dart';

/// On-device database. Single table, written one row at a time so saving
/// stays instant however many entries there are.
class EntryStore {
  EntryStore._(this._db);
  final Database _db;

  static Future<EntryStore> open() async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'spendline.db'),
      version: 2,
      onUpgrade: (db, from, _) async {
        if (from < 2) await _createGroupTables(db);
      },
      onCreate: (db, _) async {
        await _createGroupTables(db);
        await db.execute('''
          CREATE TABLE entries (
            id TEXT PRIMARY KEY,
            date TEXT NOT NULL,
            time TEXT NOT NULL,
            type TEXT NOT NULL,
            category TEXT NOT NULL,
            person TEXT NOT NULL,
            description TEXT NOT NULL,
            amount REAL NOT NULL,
            note TEXT NOT NULL,
            pending INTEGER NOT NULL
          )''');
        await db.execute('CREATE INDEX entries_date ON entries(date)');
      },
    );
    return EntryStore._(db);
  }

  static Future<void> _createGroupTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        members TEXT NOT NULL,
        created TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_expenses (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        date TEXT NOT NULL,
        description TEXT NOT NULL,
        amount REAL NOT NULL,
        paid_by TEXT NOT NULL,
        shares TEXT NOT NULL,
        settlement INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS group_expenses_group ON group_expenses(group_id)');
  }

  Future<List<Group>> allGroups() async {
    final rows = await _db.query('groups', orderBy: 'created DESC');
    return [
      for (final r in rows)
        Group(
          id: r['id']! as String,
          name: r['name']! as String,
          members: [for (final m in jsonDecode(r['members']! as String) as List) '$m'],
          created: r['created']! as String,
        ),
    ];
  }

  Future<void> upsertGroup(Group g) => _db.insert(
        'groups',
        {'id': g.id, 'name': g.name, 'members': jsonEncode(g.members), 'created': g.created},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> deleteGroup(String id) async {
    await _db.delete('group_expenses', where: 'group_id = ?', whereArgs: [id]);
    await _db.delete('groups', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<GroupExpense>> allGroupExpenses() async {
    final rows = await _db.query('group_expenses', orderBy: 'date DESC, id DESC');
    return [
      for (final r in rows)
        GroupExpense(
          id: r['id']! as String,
          groupId: r['group_id']! as String,
          date: r['date']! as String,
          description: r['description']! as String,
          amount: ((r['amount'] as num?) ?? 0).toDouble(),
          paidBy: r['paid_by']! as String,
          shares: {
            for (final e in (jsonDecode(r['shares']! as String) as Map).entries) '${e.key}': (e.value as num).toDouble(),
          },
          settlement: r['settlement'] == 1,
        ),
    ];
  }

  Future<void> upsertGroupExpense(GroupExpense e) => _db.insert(
        'group_expenses',
        {
          'id': e.id,
          'group_id': e.groupId,
          'date': e.date,
          'description': e.description,
          'amount': e.amount,
          'paid_by': e.paidBy,
          'shares': e.sharesJson(),
          'settlement': e.settlement ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> deleteGroupExpense(String id) => _db.delete('group_expenses', where: 'id = ?', whereArgs: [id]);

  Map<String, Object?> _row(Entry e) => {
        'id': e.id,
        'date': e.date,
        'time': e.time,
        'type': e.type.label,
        'category': e.category,
        'person': e.person,
        'description': e.description,
        'amount': e.amount,
        'note': e.note,
        'pending': e.pending ? 1 : 0,
      };

  Future<List<Entry>> all() async {
    final rows = await _db.query('entries', orderBy: 'date DESC, time DESC');
    return [
      for (final r in rows)
        Entry(
          id: r['id']! as String,
          date: r['date']! as String,
          time: r['time']! as String,
          type: EntryType.fromLabel(r['type']),
          category: r['category']! as String,
          person: r['person']! as String,
          description: r['description']! as String,
          amount: ((r['amount'] as num?) ?? 0).toDouble(),
          note: (r['note'] as String?) ?? '',
          pending: r['pending'] == 1,
        ),
    ];
  }

  Future<void> upsert(Entry e) => _db.insert('entries', _row(e), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> upsertMany(Iterable<Entry> entries) async {
    final b = _db.batch();
    for (final e in entries) {
      b.insert('entries', _row(e), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
  }

  Future<void> delete(String id) => _db.delete('entries', where: 'id = ?', whereArgs: [id]);
}
