import 'package:flutter_test/flutter_test.dart';
import 'package:spendline/models/entry.dart';
import 'package:spendline/services/parser.dart';

/// (sentence, type, amount, person, category or '' to skip)
const E = EntryType.expense, G = EntryType.given, R = EntryType.received, I = EntryType.income;

const cases = <(String, EntryType, double, String, String)>[
  ('ahmed ko 2000 udhaar diye', G, 2000, 'Ahmed', 'Lending'),
  ('ahmed ne 500 wapas kiye', R, 500, 'Ahmed', 'Lending'),
  ('bijli ka bill 4500 bhara', E, 4500, '', 'Bills'),
  ('petrol 3000 dalwaya', E, 3000, '', 'Transport'),
  ('salary mil gayi 90000', I, 90000, '', 'Income'),
  ('abdullah se 1500 udhaar liye', R, 1500, 'Abdullah', 'Lending'),
  ('bhai ko 10000 bheja', G, 10000, 'Bhai', 'Lending'),
  ('mobile load 500 karwaya', E, 500, '', 'Bills'),
  ('rickshaw 150', E, 150, '', 'Transport'),
  ('dawai 800 li', E, 800, '', 'Health'),
  ('usman ne 3000 udhaar diya', R, 3000, 'Usman', 'Lending'),
  ('usman ko 3000 wapas kar diye', G, 3000, 'Usman', 'Lending'),
  ('I paid 500 to Ali for lunch', E, 500, 'Ali', 'Food'),
  ('Ali paid me 500', R, 500, 'Ali', 'Lending'),
  ('received 5000 from client', R, 5000, 'Client', 'Lending'),
  ('gave 500 to ali yesterday', G, 500, 'Ali', 'Lending'),
  ('spent 1200 on groceries yesterday', E, 1200, '', 'Food'),
  ('bought shoes for 3500', E, 3500, '', 'Shopping'),
  ('movie tickets 1200 for 2', E, 1200, '', 'Entertainment'),
  ('3 shirts 4500', E, 4500, '', 'Shopping'),
  ('emi 15000', E, 15000, '', 'Bills'),
  ('school fee 8000', E, 8000, '', 'Education'),
  ('zakat 5000', E, 5000, '', 'Charity'),
  ('sadqa 1000', E, 1000, '', 'Charity'),
  ('donation 500', E, 500, '', 'Charity'),
  ('haircut 500', E, 500, '', 'Personal'),
  ('ghar ka rashan 12000', E, 12000, '', 'Food'),
  ('sui gas bill 3200', E, 3200, '', 'Bills'),
  ('careem 450', E, 450, '', 'Transport'),
  ('foodpanda 1500', E, 1500, '', 'Food'),
  ('nashta 200', E, 200, '', 'Food'),
  ('nihari 900', E, 900, '', 'Food'),
  ('hamza ko 1k diye', G, 1000, 'Hamza', 'Lending'),
  ('2 hazar ali ko diye', G, 2000, 'Ali', 'Lending'),
  ('ali se 5 sau liye', R, 500, 'Ali', 'Lending'),
  ('ek hazar rizwan ko', G, 1000, 'Rizwan', 'Lending'),
  ('rizwan ko ek hazar diye', G, 1000, 'Rizwan', 'Lending'),
  ('aaj lunch 450', E, 450, '', 'Food'),
  ('kal petrol 2500', E, 2500, '', 'Transport'),
  ('rent 25000 diya', E, 25000, '', 'Housing'),
  ('pay rent 25000', E, 25000, '', 'Housing'),
  ('Paid electricity bill Rs 6,200', E, 6200, '', 'Bills'),
  ('Rs 500 tea', E, 500, '', 'Food'),
  ('500 rs ki chai', E, 500, '', 'Food'),
  ('chai pi 100 ki', E, 100, '', 'Food'),
  ('1500 ka petrol', E, 1500, '', 'Transport'),
  ('gift 2000 sara ko', G, 2000, 'Sara', ''),
  ('bonus 10000 mila', I, 10000, '', 'Income'),
  ('freelance payment 45000', I, 45000, '', 'Income'),
  ('sara ne 800 diye', R, 800, 'Sara', 'Lending'),
  ('mujhe bilal se 1200 milne hain', G, 1200, 'Bilal', 'Lending'),
  ('usman ko 3000 dene hain', R, 3000, 'Usman', 'Lending'),
];

void main() {
  final now = DateTime(2026, 10, 15, 14, 30);
  final failures = <String>[];
  tearDownAll(() {
    for (final f in failures) {
      // ignore: avoid_print
      print('MISS $f');
    }
  });
  for (final c in cases) {
    test(c.$1, () {
      final d = parseEntry(c.$1, now: now);
      final bad = <String>[];
      if (d.type != c.$2) bad.add('type ${d.type.label} != ${c.$2.label}');
      if (d.amount != c.$3) bad.add('amount ${d.amount} != ${c.$3}');
      if (c.$4.isNotEmpty && d.person != c.$4) bad.add('person "${d.person}" != "${c.$4}"');
      if (c.$5.isNotEmpty && d.category != c.$5) bad.add('category ${d.category} != ${c.$5}');
      if (bad.isNotEmpty) failures.add('${c.$1}  ->  ${bad.join('; ')}');
      expect(bad, isEmpty, reason: bad.join('; '));
    });
  }
}
