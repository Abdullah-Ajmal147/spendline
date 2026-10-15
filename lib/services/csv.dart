import '../models/entry.dart';
import 'parser.dart' show maxAmount;

const csvHeader = ['ID', 'Date', 'Time', 'Type', 'Category', 'Person', 'Description', 'Amount', 'Note'];

/// Spreadsheet apps run a cell that starts with = + - @ as a formula. A leading apostrophe makes it text.
String _safe(String v) => RegExp(r'^[=+\-@\t\r]').hasMatch(v) ? "'$v" : v;
String _unsafe(String v) => RegExp(r"^'[=+\-@\t\r]").hasMatch(v) ? v.substring(1) : v;

String _cell(String v) => RegExp(r'[",\r\n]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;

/// Same columns as the Google Sheet. Starts with a BOM so Excel shows Urdu correctly.
String entriesToCsv(List<Entry> entries) {
  final b = StringBuffer('﻿')..writeln(csvHeader.join(','));
  for (final e in entries) {
    b.writeln([_safe(e.id), e.date, e.time, e.type.label, _safe(e.category), _safe(e.person), _safe(e.description), '${e.amount}', _safe(e.note)]
        .map(_cell)
        .join(','));
  }
  return b.toString();
}

List<List<String>> _rows(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var any = false;
  void endCell() {
    row.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    endCell();
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
    row = <String>[];
    any = false;
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
      any = true;
    } else if (c == ',') {
      endCell();
      any = true;
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      cell.write(c);
      any = true;
    }
  }
  if (any || cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// Reads a file made by [entriesToCsv] (or the Google Sheet downloaded as CSV).
/// Rows that do not look like entries are skipped.
List<Entry> entriesFromCsv(String text) {
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final out = <Entry>[];
  final seen = <String>{};
  for (final r in _rows(text)) {
    if (r.length < 8 || r[0] == 'ID') continue;
    final id = _unsafe(r[0]).trim();
    final amount = double.tryParse(r[7].trim());
    if (id.isEmpty || amount == null || !amount.isFinite || amount <= 0 || amount > maxAmount) continue;
    if (!_validDate(r[1].trim()) || !seen.add(id)) continue;
    out.add(Entry(
      id: id,
      date: r[1].trim(),
      time: r[2].trim(),
      type: EntryType.fromLabel(r[3]),
      category: r[4].isEmpty ? 'Other' : _unsafe(r[4]),
      person: _unsafe(r[5]),
      description: _unsafe(r[6]),
      amount: amount,
      note: r.length > 8 ? _unsafe(r[8]) : '',
    ));
  }
  return out;
}

bool _validDate(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return false;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final dt = DateTime(y, mo, d);
  return dt.year == y && dt.month == mo && dt.day == d;
}
