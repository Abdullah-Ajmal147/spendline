import 'package:flutter_test/flutter_test.dart';
import 'package:spendline/models/entry.dart';
import 'package:spendline/services/csv.dart';

void main() {
  test('round trip keeps commas, quotes, newlines and Urdu', () {
    final e = [
      const Entry(
        id: 'a1',
        date: '2026-10-15',
        time: '14:05',
        type: EntryType.given,
        category: 'Lending',
        person: 'رضوان',
        description: 'To "Riz", for lunch',
        amount: 1500.5,
        note: 'line one\nline two, with comma',
      ),
      const Entry(
        id: 'b2',
        date: '2026-10-14',
        time: '09:00',
        type: EntryType.expense,
        category: 'Food',
        person: '',
        description: 'Chai',
        amount: 120,
      ),
    ];
    final back = entriesFromCsv(entriesToCsv(e));
    expect(back.length, 2);
    expect(back[0].description, 'To "Riz", for lunch');
    expect(back[0].note, 'line one\nline two, with comma');
    expect(back[0].person, 'رضوان');
    expect(back[0].amount, 1500.5);
    expect(back[0].type, EntryType.given);
    expect(back[1].amount, 120);
  });

  test('junk rows are skipped', () {
    expect(entriesFromCsv('hello\n1,2,3\n'), isEmpty);
  });
}
