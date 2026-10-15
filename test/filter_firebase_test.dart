import 'package:flutter_test/flutter_test.dart';
import 'package:spendline/models/entry.dart';
import 'package:spendline/models/filter.dart';
import 'package:spendline/services/firebase_cloud.dart';

Entry e(String id, String date, EntryType t, String cat, String person, String desc, double amt, {String note = ''}) =>
    Entry(id: id, date: date, time: '10:00', type: t, category: cat, person: person, description: desc, amount: amt, note: note);

void main() {
  final all = [
    e('1', '2026-10-01', EntryType.expense, 'Food', '', 'Lunch', 500),
    e('2', '2026-10-10', EntryType.given, 'Lending', 'Rizwan', 'To Rizwan', 1000, note: 'rizwan ko 1000'),
    e('3', '2026-10-12', EntryType.received, 'Lending', 'Ali', 'From Ali', 300),
    e('4', '2026-10-14', EntryType.expense, 'Transport', '', 'Uber', 350),
  ];
  List<String> ids(EntryFilter f) => [for (final x in all.where(f.matches)) x.id];

  test('empty filter is inactive and matches all', () {
    expect(EntryFilter.none.active, isFalse);
    expect(ids(EntryFilter.none), ['1', '2', '3', '4']);
  });
  test('by type, category, person', () {
    expect(ids(const EntryFilter(types: {EntryType.expense})), ['1', '4']);
    expect(ids(const EntryFilter(category: 'Lending')), ['2', '3']);
    expect(ids(const EntryFilter(person: 'rizwan')), ['2']);
  });
  test('date range is inclusive', () {
    expect(ids(const EntryFilter(from: '2026-10-10', to: '2026-10-12')), ['2', '3']);
  });
  test('search covers description, person, note and amount', () {
    expect(ids(const EntryFilter(query: 'uber')), ['4']);
    expect(ids(const EntryFilter(query: 'RIZWAN')), ['2']);
    expect(ids(const EntryFilter(query: '300')), ['3']);
  });
  test('combined filters narrow further; copyWith can clear a field', () {
    final f = const EntryFilter(types: {EntryType.expense}, category: 'Food');
    expect(ids(f), ['1']);
    expect(f.copyWith(category: null).category, isNull);
    expect(f.copyWith(query: 'x').category, 'Food');
  });

  test('firestore value encoding round trips', () {
    final data = {
      'id': 'a1',
      'amount': 1500.5,
      'count': 3,
      'ok': true,
      'members': ['You', 'Ali'],
      'shares': {'You': 750.25, 'Ali': 750.25},
      'note': 'رضوان',
    };
    final back = decodeFields(encodeFields(data));
    expect(back['amount'], 1500.5);
    expect(back['count'], 3);
    expect(back['ok'], true);
    expect(back['members'], ['You', 'Ali']);
    expect((back['shares'] as Map)['Ali'], 750.25);
    expect(back['note'], 'رضوان');
  });
}
