import '../models/entry.dart';

/// Rule-based sentence parser. Runs instantly on the phone, no network.
/// "Give to rizwan 1000" -> Given / Rizwan / Lending / 1000
/// "pay for lunch 500"   -> Expense / Food / 500
/// Keep test/parser_test.dart passing when you change anything here.

const Map<String, List<String>> categories = {
  'Food': ['nashta', 'naashta', 'nihari', 'haleem', 'roti', 'naan', 'chawal', 'rashan', 'ration', 'atta', 'dal', 'chicken', 'gosht', 'mithai', 'cake', 'biscuit', 'anda', 'eggs', 'icecream', 'lunch', 'dinner', 'breakfast', 'brunch', 'food', 'khana', 'pizza', 'burger', 'biryani', 'karahi', 'tea', 'chai', 'coffee', 'snack', 'snacks', 'restaurant', 'grocery', 'groceries', 'sabzi', 'fruit', 'fruits', 'meal', 'bakery', 'doodh', 'milk', 'juice', 'shawarma', 'paratha', 'foodpanda'],
  'Transport': ['uber', 'careem', 'bykea', 'indrive', 'yango', 'taxi', 'cab', 'rickshaw', 'petrol', 'fuel', 'diesel', 'cng', 'bus', 'train', 'metro', 'fare', 'parking', 'toll', 'flight', 'ticket', 'car', 'bike', 'tyre', 'mechanic'],
  'Bills': ['emi', 'installment', 'instalment', 'kist', 'qist', 'insurance', 'loan payment', 'bill', 'bills', 'electricity', 'bijli', 'gas', 'water', 'internet', 'wifi', 'mobile', 'phone', 'load', 'recharge', 'package', 'subscription', 'k-electric'],
  'Housing': ['rent', 'kiraya', 'maintenance', 'plumber', 'electrician', 'repair', 'furniture'],
  'Shopping': ['kapray', 'kapre', 'suit', 'jeans', 'dress', 'jootay', 'clothes', 'shirt', 'shoes', 'amazon', 'daraz', 'shopping', 'gift', 'gifts', 'watch', 'bag', 'cosmetics', 'mall'],
  'Health': ['medicine', 'medicines', 'doctor', 'pharmacy', 'hospital', 'dawai', 'clinic', 'dentist', 'lab', 'test', 'gym'],
  'Education': ['fee', 'fees', 'book', 'books', 'course', 'tuition', 'school', 'college', 'university', 'stationery'],
  'Charity': ['zakat', 'zakaat', 'sadqa', 'sadaqah', 'sadaqa', 'charity', 'donation', 'fitra', 'fitrana', 'khairat', 'masjid', 'mosque', 'eidi'],
  'Personal': ['haircut', 'barber', 'salon', 'parlour', 'parlor', 'beauty', 'makeup', 'soap', 'shampoo', 'perfume'],
  'Entertainment': ['movie', 'movies', 'netflix', 'spotify', 'youtube', 'game', 'games', 'cinema', 'concert', 'outing', 'trip'],
};

final List<String> catList = [...categories.keys, 'Lending', 'Income', 'Other'];

final Map<String, RegExp> _catRe = {
  for (final e in categories.entries)
    e.key: RegExp(r'\b(' + e.value.map(RegExp.escape).join('|') + r')(?:s|es)?\b'),
};

const Set<String> _stop = {
  'to', 'the', 'a', 'an', 'money', 'cash', 'rs', 'pkr', 'for', 'from', 'back', 'me', 'my', 'him', 'her',
  'some', 'amount', 'of', 'on', 'at', 'and', 'ko', 'se', 'ne', 'is', 'was', 'today', 'yesterday',
  'mujhe', 'diya', 'liya', 'bheja', 'wapas',
};

final RegExp _filler = RegExp(
    r'\b(pay|paid|paying|pays|spent|spend|spending|bought|buy|buying|purchase|purchased|for|on|at|the|a|an|of|some|rs\.?|pkr|rupees?|today|yesterday|kharcha|kharch|ka|ki|ke|ko|se|ne|mujhe|mein|me|my|and|money|cash|i|did|have|had|was|is)\b');

final RegExp _moneyVerbs = RegExp(
    r'\b(give|gave|given|giving|lend|lent|loan|loaned|send|sent|transfer|transferred|diya|bheja|udhaar|udhar|qarz|received|recieved|receive|got|back|borrowed|returned|wapas|liya|ne|mujhe|to|from|me)\b');

const Map<String, double> _mult = {
  'k': 1e3, 'sau': 100, 'hundred': 100, 'thousand': 1e3, 'hazar': 1e3, 'hazaar': 1e3, 'hzar': 1e3, 'lakh': 1e5, 'lac': 1e5,
};

final RegExp _amountRe = RegExp(
    r'(?:(rs\.?|pkr|₨|\$|rupees?)\s*)?(\d+(?:\.\d+)?)\s*(k|sau|hundred|thousand|hazaar|hazar|hzar|lakh|lac)?\s*(rs|pkr|rupees?|/-)?(?![a-z0-9])',
    caseSensitive: false);

/// Spelling variants (Roman Urdu, a little Urdu script) mapped to one token,
/// so the rules below only deal with one spelling. '' drops the word.
const Map<String, List<String>> _canon = {
  'diya': ['dy', 'dey', 'dya', 'dia', 'diya', 'diye', 'dye', 'di', 'de', 'dai', 'deya', 'dedia', 'dediya', 'dediye', 'dedy', 'دیے', 'دیا', 'دی', 'دے', 'دئیے'],
  'liya': ['liye', 'liya', 'lye', 'liay', 'lia', 'mila', 'mile', 'mili', 'aaya', 'aaye', 'aye', 'لیا', 'لیے', 'ملا', 'ملے'],
  'bheja': ['bhej', 'bheja', 'bhejy', 'bheji', 'bhejdiya', 'bhejdia', 'بھیجا', 'بھیجے'],
  'ko': ['ko', 'کو'],
  'se': ['se', 'say', 'sey', 'سے'],
  'ne': ['ne', 'نے'],
  'mujhe': ['mujhe', 'mujhy', 'mjhe', 'mujy', 'muje', 'mujh', 'مجھے'],
  'rs': ['rs', 'rs.', 'rupay', 'rupaye', 'rupey', 'rupee', 'rupees', 'روپے', 'روپیہ'],
  'kal': ['kal', 'کل'],
  'aaj': ['aaj', 'آج'],
  'parson': ['parson', 'parsoon', 'parsun', 'پرسوں'],
  'sau': ['sau', 'سو'],
  'hazaar': ['hazaar', 'ہزار'],
  'lakh': ['lakh', 'لاکھ'],
  'ek': ['ek', 'ایک'],
  'do': ['do', 'دو'],
  'teen': ['teen', 'تین'],
  'chaar': ['chaar', 'چار'],
  'paanch': ['paanch', 'پانچ'],
  'chhe': ['chhe', 'چھ'],
  'saat': ['saat', 'سات'],
  'aath': ['aath', 'آٹھ'],
  'nau': ['nau', 'نو'],
  'das': ['das', 'دس'],
  'bees': ['bees', 'بیس'],
  'tees': ['tees', 'تیس'],
  'pachas': ['pachas', 'پچاس'],
  'dedh': ['dedh', 'ڈیڑھ'],
  'dhai': ['dhai', 'ڈھائی'],
  '': ['mainy', 'maine', 'mene', 'mainay', 'main', 'ha', 'hai', 'hain', 'hy', 'hein', 'tha', 'thy', 'thi', 'hun', 'hoon', 'ہے', 'ہیں', 'تھا', 'تھی', 'میں'],
};

final Map<String, String> _canonOf = {
  for (final e in _canon.entries) for (final v in e.value) v: e.key,
};

const Map<String, num> _numWords = {
  'ek': 1, 'aik': 1, 'one': 1, 'do': 2, 'two': 2, 'teen': 3, 'three': 3, 'char': 4, 'chaar': 4, 'four': 4,
  'panch': 5, 'paanch': 5, 'five': 5, 'chay': 6, 'chhe': 6, 'che': 6, 'six': 6, 'saat': 7, 'seven': 7,
  'aath': 8, 'eight': 8, 'nau': 9, 'nine': 9, 'das': 10, 'ten': 10, 'bees': 20, 'twenty': 20, 'tees': 30,
  'chalis': 40, 'pachas': 50, 'fifty': 50, 'saath': 60, 'sattar': 70, 'assi': 80, 'nabbe': 90,
  'dedh': 1.5, 'dhai': 2.5, 'dhaai': 2.5, 'sawa': 1.25,
};

final RegExp _numWordRe = RegExp(
    r'\b(' + _numWords.keys.join('|') + r')\s+(sau|hundred|hazaar|hazar|hzar|thousand|lakh|lac|k)\b');

/// Largest amount accepted from a sentence. Anything above is treated as "no amount", not stored.
const double maxAmount = 1e11;

/// Arabic-Indic, Extended (Urdu/Persian), Devanagari and full-width digits to ASCII.
String _asciiDigits(String t) {
  final b = StringBuffer();
  for (final r in t.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else if (r >= 0x0966 && r <= 0x096F) {
      b.writeCharCode(0x30 + r - 0x0966);
    } else if (r >= 0xFF10 && r <= 0xFF19) {
      b.writeCharCode(0x30 + r - 0xFF10);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

final RegExp _grouped = RegExp(r'(?<![\d,.])\d{1,3}(?:,\d{2,3})+(?![\d])');
final RegExp _westernGroup = RegExp(r'^\d{1,3}(,\d{3})+$');
final RegExp _indianGroup = RegExp(r'^\d{1,2}(,\d{2})+,\d{3}$');

/// Lowercase, strip noise, unify spellings and turn number words into digits.
String _normalize(String raw) {
  var t = _asciiDigits(raw.toLowerCase());
  // 1,000 and 1,00,000 are amounts; "100,200" is not a valid grouping and is left alone.
  t = t.replaceAllMapped(_grouped, (m) {
    final g = m[0]!;
    return (_westernGroup.hasMatch(g) || _indianGroup.hasMatch(g)) ? g.replaceAll(',', '') : g;
  });
  t = t
      .replaceAll('کے لیے', ' for ')
      .replaceAll(RegExp(r'[!?;,،۔]'), ' ')
      .replaceAll(RegExp(r'\b(ke|k|ky) (liye|liay|lye)\b'), ' for ');
  t = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => _canonOf[w] ?? w).where((w) => w.isNotEmpty).join(' ');
  t = t.replaceAllMapped(_numWordRe, (m) => '${_numWords[m[1]]} ${m[2]}');
  t = t.replaceAllMapped(RegExp(r'(?<!\d\s)(?<!\d)\b(sau|hundred)\b'), (m) => '100');
  return ' $t ';
}

/// Filled by AppState from what the user corrected before. Lowercase word -> category.
Map<String, String> learnedCategories = {};

/// Names the user has used before, lowercase -> display form ("rizwan ahmed" -> "Rizwan Ahmed").
Map<String, String> knownPeople = {};

const _months = {
  'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3, 'apr': 4, 'april': 4,
  'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7, 'aug': 8, 'august': 8, 'sep': 9, 'sept': 9,
  'september': 9, 'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
};
const _weekdays = {
  'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4, 'friday': 5, 'saturday': 6, 'sunday': 7,
  'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7,
};

DateTime? _ymd(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final x = DateTime(y, m, d);
  return x.month == m ? x : null;
}

/// Pulls a date phrase out of the sentence ("kal", "5 oct", "3 days ago", "monday").
/// Returns the date (or null) and the sentence without that phrase, so the
/// numbers in a date are never mistaken for the amount.
(DateTime?, String) _takeDate(String t, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  DateTime ago(int n) => DateTime(today.year, today.month, today.day - n);
  final monthNames = _months.keys.join('|');
  final dayNames = _weekdays.keys.join('|');

  DateTime? found;

  RegExp re(String p) => RegExp(p);
  Match? m;

  if ((m = re(r'\b(\d{1,3})\s+(?:din|dino|days?)\s+(?:pehle|pehly|pehlay|ago)\b').firstMatch(t)) != null) {
    found = ago(int.parse(m!.group(1)!));
    return (found, t.replaceFirst(m.group(0)!, ' '));
  }
  if ((m = re(r'\b(?:pichle|pichhle|last)\s+(?:hafte|haftay|week)\b').firstMatch(t)) != null) {
    return (ago(7), t.replaceFirst(m!.group(0)!, ' '));
  }
  if ((m = re(r'\b(?:pichle|pichhle|last)\s+(?:mahine|month)\b').firstMatch(t)) != null) {
    return (DateTime(today.year, today.month - 1, today.day), t.replaceFirst(m!.group(0)!, ' '));
  }
  if ((m = re(r'\bday before yesterday\b|\bparson\b').firstMatch(t)) != null) {
    return (ago(2), t.replaceFirst(m!.group(0)!, ' '));
  }
  // "kal" is yesterday or tomorrow in Urdu; an expense log means yesterday.
  if ((m = re(r'\byesterday\b|\bkal\b|\blast night\b').firstMatch(t)) != null) {
    return (ago(1), t.replaceFirst(m!.group(0)!, ' '));
  }
  if ((m = re(r'\btoday\b|\baaj\b').firstMatch(t)) != null) {
    return (today, t.replaceFirst(m!.group(0)!, ' '));
  }

  // 2026-10-05 and 2026/10/05 (year first), before the day-first patterns below.
  final iso = RegExp(r'(?<![\d.])(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?![\d])').firstMatch(t);
  if (iso != null) {
    final d = _ymd(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
    if (d != null) return (d, t.replaceFirst(iso[0]!, ' '));
  }

  int yearFor(String? y, int month, int day) {
    if (y != null && y.isNotEmpty) {
      final n = int.parse(y);
      return n < 100 ? 2000 + n : n;
    }
    // No year: a date still in the future must mean last year.
    final cand = _ymd(today.year, month, day);
    return cand != null && cand.isAfter(today) ? today.year - 1 : today.year;
  }

  // "5 oct", "5th october 2025"
  m = re(r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(' + monthNames + r')\b(?:\s+(\d{4}))?').firstMatch(t);
  if (m != null) {
    final month = _months[m.group(2)]!;
    final day = int.parse(m.group(1)!);
    final d = _ymd(yearFor(m.group(3), month, day), month, day);
    if (d != null) return (d, t.replaceFirst(m.group(0)!, ' '));
  }
  // "oct 5", "october 5th"
  m = re(r'\b(' + monthNames + r')\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:\s+(\d{4}))?').firstMatch(t);
  if (m != null) {
    final month = _months[m.group(1)]!;
    final day = int.parse(m.group(2)!);
    final d = _ymd(yearFor(m.group(3), month, day), month, day);
    if (d != null) return (d, t.replaceFirst(m.group(0)!, ' '));
  }
  // "5/10", "05-10-2026" (day first, as in Pakistan)
  m = re(r'(?<![\d.])(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?(?![\d.])').firstMatch(t);
  if (m != null) {
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final d = _ymd(yearFor(m.group(3), month, day), month, day);
    if (d != null) return (d, t.replaceFirst(m.group(0)!, ' '));
  }
  // "monday", "last friday": most recent such day, never today
  m = re(r'\b(?:last\s+|pichle\s+)?(' + dayNames + r')\b').firstMatch(t);
  if (m != null) {
    final wd = _weekdays[m.group(1)]!;
    var back = (today.weekday - wd) % 7;
    if (back == 0) back = 7;
    return (ago(back), t.replaceFirst(m.group(0)!, ' '));
  }
  return (found, t);
}

/// The category a sentence points to by words alone (taught words win), or null.
String? _lexCategory(String text) {
  for (final w in text.split(RegExp(r'\s+'))) {
    final taught = learnedCategories[w];
    if (taught != null) return taught;
  }
  // The earliest keyword wins: "movie tickets" is Entertainment, not Transport.
  String? best;
  var bestAt = 1 << 30;
  for (final e in _catRe.entries) {
    final m = e.value.firstMatch(text);
    if (m != null && m.start < bestAt) {
      best = e.key;
      bestAt = m.start;
    }
  }
  return best;
}

String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String two(int n) => n.toString().padLeft(2, '0');
String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';

/// An editable guess shown in the preview card before saving.
class Draft {
  Draft({
    required this.type,
    required this.amount,
    required this.person,
    required this.category,
    required this.description,
    required this.date,
    required this.confidence,
    this.smart = false,
  });

  EntryType type;
  double amount;
  String person;
  String category;
  String description;
  String date; // yyyy-MM-dd
  double confidence; // 0..1, below 0.8 means "best guess"
  bool smart; // filled by the on-device model

  Draft copy() => Draft(
        type: type,
        amount: amount,
        person: person,
        category: category,
        description: description,
        date: date,
        confidence: confidence,
        smart: smart,
      );

  bool get needsPerson => type == EntryType.given || type == EntryType.received;
}

class _Amount {
  _Amount(this.value, this.score, this.text);
  final double value;
  final double score;
  final String text;
}

Draft parseEntry(String raw, {DateTime? now}) {
  now ??= DateTime.now();

  final (dateFound, t) = _takeDate(_normalize(raw), now);

  // Amount: prefer one written with a currency or "k", otherwise the largest number.
  _Amount? best;
  for (final m in _amountRe.allMatches(t)) {
    final mult = m[3] != null ? _mult[m[3]!.toLowerCase()]! : 1.0;
    final value = (double.tryParse(m[2]!) ?? double.nan) * mult;
    if (!value.isFinite || value <= 0 || value > maxAmount) continue; // absurd or malformed: not an amount
    final hasUnit = m[1] != null || m[3] != null || m[4] != null;
    final score = (hasUnit ? 1e12 : 0.0) + value;
    if (best == null || score > best.score) best = _Amount(value, score, m[0]!);
  }
  var rest = best != null ? t.replaceFirst(best.text, ' ') : t;

  var d = dateFound ?? DateTime(now.year, now.month, now.day);

  const word = r"([\p{L}][\p{L}.'-]*)";
  String grab(RegExp re) {
    final x = re.firstMatch(rest);
    final w = x?.group(1);
    return (w != null && !_stop.contains(w)) ? w : '';
  }

  var type = EntryType.expense;
  var person = '';
  var hit = false;

  bool has(String pattern) => RegExp(pattern).hasMatch(rest);
  RegExp w(String pattern) => RegExp(pattern, unicode: true);
  // `(?<=\s)` instead of `\b` before a captured name, so Urdu-script names work.
  const lead = r'(?<=\s)';

  final hasKo = has(r'\bko\b');
  final giveVerb = has(r'\b(diya|bheja|gave|give|sent|paid|transferred)\b');

  if (has(r'\b(salary|income|earned|earning|bonus|freelance|profit|tankhwah|tankhwa|commission|stipend)\b')) {
    type = EntryType.income;
    hit = true;
  } else if (has(r'\b(milne|milna|lene|lena|baqi|baki|wasool|wusool)\b') && has(r'\bse\b')) {
    // "bilal se 1200 milne hain": Bilal still owes me.
    type = EntryType.given;
    hit = true;
    person = grab(w(lead + word + r' se\b'));
  } else if (has(r'\b(dene|dena|dene wale)\b') && (hasKo || has(r'\b(ka|ki|ke)\b'))) {
    // "usman ko 3000 dene hain": I still owe Usman.
    type = EntryType.received;
    hit = true;
    person = grab(w(lead + word + r' (?:ko|ka|ki)\b'));
  } else if (has(r'\b(received|recieved|receive|got back|borrowed|liya|returned)\b') ||
      (has(r'\bwapas\b') && !hasKo) ||
      has(r'\b(gave|paid|sent|transferred|returned) (me|back)\b') ||
      has(r'\bgot\b.*\bfrom\b') ||
      (has(r'\bmujhe\b') && giveVerb) ||
      (has(r'\bne\b') && giveVerb && !hasKo)) {
    type = EntryType.received;
    hit = true;
    person = grab(w(r'\bfrom ' + word));
    if (person.isEmpty) person = grab(w(lead + word + r' se\b'));
    if (person.isEmpty) person = grab(w(lead + word + r' ne\b'));
    if (person.isEmpty) person = grab(w(lead + word + r' (?:returned|gave|paid|sent|transferred)\b'));
  } else if (has(r'\b(give|gave|given|giving|lend|lent|loan|loaned|send|sent|transfer|transferred|diya|bheja|udhaar|udhar|qarz)\b') ||
      (has(r'\bwapas\b') && hasKo)) {
    type = EntryType.given;
    hit = true;
    person = grab(w(r'\bto ' + word));
    if (person.isEmpty) person = grab(w(lead + word + r' ko\b'));
    if (person.isEmpty) {
      person = grab(w(r'\b(?:gave|give|given|lent|lend|loaned|loan|sent|send|transferred|transfer)\s+' + word));
    }
    if (person.isEmpty) person = grab(w(r'\bfor ' + word));
    if (person.isEmpty && !hasKo && _lexCategory(rest) != null) {
      type = EntryType.expense; // "rent 25000 diya"
    }
  } else if (has(r'\b(pay|paid|spent|spend|bought|buy|purchase|purchased|kharcha|kharch)\b')) {
    hit = true;
    // "pay for lunch to abdullah 500": still an expense, remember who it went to.
    if (has(r'\b(pay|paid)\b')) person = grab(w(r'\bto ' + word));
  }

  if (type == EntryType.expense && hasKo) {
    final cand = grab(w(lead + word + r' ko\b'));
    if (cand.isNotEmpty && _lexCategory(cand) == null && !_numWords.containsKey(cand) && !_mult.containsKey(cand)) {
      type = EntryType.given;
      person = cand;
      hit = true;
    }
  }

  // A name the user has typed in full before ("rizwan ahmed") beats the single word grabbed above.
  if (knownPeople.isNotEmpty && (type == EntryType.given || type == EntryType.received || person.isNotEmpty)) {
    final padded = ' ${rest.replaceAll(RegExp(r'\s+'), ' ')} ';
    final names = knownPeople.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final n in names) {
      if (padded.contains(' $n ')) {
        person = n;
        break;
      }
    }
  }

  var category = 'Other';
  if (type == EntryType.given || type == EntryType.received) {
    category = 'Lending';
  } else if (type == EntryType.income) {
    category = 'Income';
  } else {
    // What the user corrected before wins over the built-in word lists.
    final taught = rest.split(RegExp(r'\s+')).where(learnedCategories.containsKey);
    if (taught.isNotEmpty) {
      category = learnedCategories[taught.first]!;
      hit = true;
    } else {
      final lex = _lexCategory(rest);
      if (lex != null) {
        category = lex;
        hit = true;
      }
    }
  }

  // Description from whatever words are left.
  var left = rest;
  if (person.isNotEmpty) {
    left = left.replaceAll(
        RegExp(r'(?<![\p{L}\p{N}])' + RegExp.escape(person) + r'(?![\p{L}\p{N}])', unicode: true), ' ');
  }
  left = left
      .replaceAll(_moneyVerbs, ' ')
      .replaceAll(_filler, ' ')
      .replaceAll(RegExp(r"[^\p{L}\p{N}\s'-]", unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  final p = knownPeople[person] ?? cap(person);
  String description;
  if (type == EntryType.given) {
    description = (p.isNotEmpty ? 'To $p' : 'Given') + (left.isNotEmpty ? ' · $left' : '');
  } else if (type == EntryType.received) {
    description = (p.isNotEmpty ? 'From $p' : 'Received') + (left.isNotEmpty ? ' · $left' : '');
  } else {
    description = left.isNotEmpty ? cap(left) : (category != 'Other' ? category : type.label);
    if (p.isNotEmpty) description = '$description · $p';
  }

  final needsPerson = type == EntryType.given || type == EntryType.received;
  final confidence = (best != null ? .5 : 0) + (hit ? .35 : 0) + (!needsPerson || p.isNotEmpty ? .15 : 0);

  return Draft(
    type: type,
    amount: best != null ? (best.value * 100).round() / 100 : 0,
    person: p,
    category: category,
    description: description,
    date: isoDate(d),
    confidence: confidence.toDouble(),
  );
}

/// Splits "lunch 500, chai 120 aur gave ali 2000" into separate drafts.
/// Only splits when every piece has its own amount; otherwise it is one entry.
List<Draft> parseMany(String raw, {DateTime? now}) {
  final pieces = raw
      .split(RegExp(r'[\n;]|,(?!\d)|\s+(?:aur|and|phir|then)\s+', caseSensitive: false))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (pieces.length > 1) {
    final drafts = [for (final p in pieces) parseEntry(p, now: now)];
    if (drafts.every((d) => d.amount > 0)) return drafts;
  }
  return [parseEntry(raw, now: now)];
}
