/**
 * Spendline backend — a tiny JSON API in your own Google account that the
 * Flutter app calls to read and write your Google Sheet.
 *
 * SETUP
 * 1. https://script.google.com → New project → name it "Spendline".
 * 2. Replace Code.gs with this file.
 * 3. Change APP_KEY below to a long random phrase only you know. The app asks for it.
 * 4. Deploy → New deployment → type "Web app".
 *      Execute as:      Me
 *      Who has access:  Anyone
 *    ("Anyone" is needed so the phone app can call it without a Google login screen.
 *     Every request still has to carry APP_KEY, and the script only touches the sheet you connect.)
 * 5. Authorize when asked, then copy the Web app URL (ends in /exec) into the app.
 *
 * After editing this file: Deploy → Manage deployments → edit → Version: New version.
 *
 * Rows go to a tab named "Expenses" (created automatically):
 * ID | Date | Time | Type | Category | Person | Description | Amount | Note
 */

const APP_KEY = 'CHANGE-ME';

const TAB = 'Expenses';
const HEADERS = ['ID', 'Date', 'Time', 'Type', 'Category', 'Person', 'Description', 'Amount', 'Note'];
const TYPES = ['Expense', 'Given', 'Received', 'Income'];

/* ---------- HTTP ---------- */

function doGet() {
  return json_({ ok: true, data: { app: 'spendline', keySet: APP_KEY !== 'CHANGE-ME' } });
}

function doPost(e) {
  try {
    if (APP_KEY === 'CHANGE-ME') throw new Error('Set APP_KEY at the top of Code.gs, then deploy a new version.');
    const req = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    if (req.key !== APP_KEY) throw new Error('Wrong app key. It must match APP_KEY in Code.gs.');

    let data;
    switch (req.action) {
      case 'config':     data = getConfig(); break;
      case 'connect':    data = connectSheet(req.url); break;
      case 'list':       data = listEntries(req.limit); break;
      case 'add':        data = addEntry(req.entry); break;
      case 'remove':     data = deleteEntry(req.id); break;
      case 'disconnect': data = disconnectSheet(); break;
      default: throw new Error('Unknown action: ' + req.action);
    }
    return json_({ ok: true, data: data });
  } catch (err) {
    return json_({ ok: false, error: String(err && err.message || err) });
  }
}

function json_(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}

/* ---------- sheet connection ---------- */

const props_ = () => PropertiesService.getScriptProperties();

function getConfig() {
  const url = props_().getProperty('SHEET_URL');
  if (!url) return { connected: false };
  try {
    const ss = SpreadsheetApp.openByUrl(url);
    return { connected: true, name: ss.getName(), url: ss.getUrl() };
  } catch (e) {
    return { connected: false, error: 'The saved sheet could not be opened. Paste the link again.' };
  }
}

function connectSheet(url) {
  url = String(url || '').trim();
  if (!/docs\.google\.com\/spreadsheets\/d\//.test(url)) {
    throw new Error('That is not a Google Sheets link. It should start with https://docs.google.com/spreadsheets/d/');
  }
  let ss;
  try {
    ss = SpreadsheetApp.openByUrl(url);
  } catch (e) {
    throw new Error('Could not open that sheet. Check the link and that your Google account can edit it.');
  }
  props_().setProperty('SHEET_URL', ss.getUrl());
  prepareTab_(ss);
  return { name: ss.getName(), url: ss.getUrl() };
}

function disconnectSheet() {
  props_().deleteProperty('SHEET_URL');
  return true;
}

function getSheet_() {
  const url = props_().getProperty('SHEET_URL');
  if (!url) throw new Error('NO_SHEET');
  return prepareTab_(SpreadsheetApp.openByUrl(url));
}

function prepareTab_(ss) {
  let sh = ss.getSheetByName(TAB);
  if (!sh) sh = ss.insertSheet(TAB);
  if (sh.getLastRow() === 0) {
    sh.appendRow(HEADERS);
    sh.getRange(1, 1, 1, HEADERS.length).setFontWeight('bold').setBackground('#0F2420').setFontColor('#FFFFFF');
    sh.setFrozenRows(1);
    sh.getRange('B:B').setNumberFormat('d mmm yyyy');
    sh.getRange('C:C').setNumberFormat('@');
    sh.getRange('H:H').setNumberFormat('#,##0.##');
    [80, 100, 60, 90, 110, 110, 220, 100, 240].forEach(function (w, i) { sh.setColumnWidth(i + 1, w); });
  }
  return sh;
}

/* ---------- entries ---------- */

function addEntry(e) {
  e = e || {};
  const amount = Number(e.amount);
  if (!(amount > 0)) throw new Error('Amount must be a number above zero.');
  const type = TYPES.indexOf(e.type) >= 0 ? e.type : 'Expense';

  const sh = getSheet_();
  const tz = sh.getParent().getSpreadsheetTimeZone();
  const dateStr = /^\d{4}-\d{2}-\d{2}$/.test(e.date) ? e.date : Utilities.formatDate(new Date(), tz, 'yyyy-MM-dd');
  const time = /^\d{2}:\d{2}$/.test(e.time) ? e.time : Utilities.formatDate(new Date(), tz, 'HH:mm');
  const id = Utilities.getUuid().slice(0, 8);

  const row = [
    id,
    Utilities.parseDate(dateStr, tz, 'yyyy-MM-dd'),
    time,
    type,
    clean_(e.category) || 'Other',
    clean_(e.person),
    clean_(e.description),
    amount,
    clean_(e.raw)
  ];

  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try { sh.appendRow(row); } finally { lock.releaseLock(); }

  return { id: id, date: dateStr, time: time, type: type, category: row[4], person: row[5],
           description: row[6], amount: amount, note: row[8] };
}

function listEntries(limit) {
  const sh = getSheet_();
  const last = sh.getLastRow();
  if (last < 2) return [];
  limit = Math.min(Number(limit) || 1500, 5000);
  const start = Math.max(2, last - limit + 1);
  const n = last - start + 1;
  const range = sh.getRange(start, 1, n, HEADERS.length);
  const v = range.getValues();
  const d = range.getDisplayValues();
  const tz = sh.getParent().getSpreadsheetTimeZone();

  const out = [];
  for (let i = n - 1; i >= 0; i--) {
    const r = v[i];
    if (!r[7]) continue;
    out.push({
      id: String(r[0] || ('row' + (start + i))),
      date: r[1] instanceof Date ? Utilities.formatDate(r[1], tz, 'yyyy-MM-dd') : String(r[1]),
      time: d[i][2],
      type: TYPES.indexOf(r[3]) >= 0 ? r[3] : 'Expense',
      category: String(r[4] || 'Other'),
      person: String(r[5] || ''),
      description: String(r[6] || ''),
      amount: Number(r[7]) || 0,
      note: String(r[8] || '')
    });
  }
  return out;
}

function deleteEntry(id) {
  const sh = getSheet_();
  id = String(id);
  let rowNum = 0;
  const m = /^row(\d+)$/.exec(id);           // rows typed by hand have no ID
  if (m) rowNum = Number(m[1]);
  else {
    const cell = sh.getRange('A2:A').createTextFinder(id).matchEntireCell(true).findNext();
    if (cell) rowNum = cell.getRow();
  }
  if (!rowNum) throw new Error('That entry is no longer in the sheet.');
  sh.deleteRow(rowNum);
  return true;
}

/* Stops text like "=IMPORTXML(...)" from being run as a formula. */
function clean_(s) {
  s = String(s == null ? '' : s).trim().slice(0, 300);
  return /^[=+\-@]/.test(s) ? "'" + s : s;
}
