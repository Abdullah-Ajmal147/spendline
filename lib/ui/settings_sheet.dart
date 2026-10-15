import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../state/app_state.dart';
import 'cloud_setup_screen.dart';
import 'glass.dart';
import 'groups_screen.dart';
import 'home_screen.dart' show SummaryScreen;
import 'theme.dart';

Future<void> showSettings(BuildContext context, AppState s) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SettingsScreen(state: s)));

/// Writes a CSV of every entry and opens the share sheet (Drive, WhatsApp, email…).
Future<void> shareBackup(AppState s) async {
  try {
    final files = [XFile(await s.exportCsv()), if (s.groups.isNotEmpty) XFile(await s.exportGroups())];
    await SharePlus.instance.share(ShareParams(files: files, subject: 'Spendline backup'));
  } catch (e) {
    toast('Could not create the backup: $e');
  }
}

Future<void> importBackup(AppState s) async {
  try {
    final picked = await FilePicker.pickFiles();
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null) return;
    final text = await File(path).readAsString();
    final isGroups = path.toLowerCase().endsWith('.json');
    final n = isGroups ? await s.importGroups(text) : await s.importCsv(text);
    toast(n == 0 ? 'Nothing new in that file' : 'Added $n ${isGroups ? 'group expenses' : 'entries'}');
  } catch (e) {
    toast('Could not read that file: $e');
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _currency = TextEditingController(text: widget.state.currency);
  String? _error;
  bool _busy = false;

  AppState get s => widget.state;

  @override
  void dispose() {
    _currency.dispose();
    super.dispose();
  }

  void _openSetup() => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CloudSetupScreen(state: s)));

  Future<void> _toggleBackup(bool on) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (on) {
        await s.connectBackup();
        toast('Backup & sync is on');
      } else {
        await s.disconnectBackup();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(children: [
        const Positioned.fill(child: Aurora()),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListenableBuilder(
                listenable: s,
                builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 40), children: [
                  Row(children: [
                    Press(
                      onTap: () => Navigator.pop(context),
                      label: 'Back',
                      child: Glass(radius: 999, padding: const EdgeInsets.all(9), child: Icon(Icons.arrow_back_rounded, size: 20, color: p.ink)),
                    ),
                    const SizedBox(width: 12),
                    Text('Tools & settings', style: display(24, color: p.ink)),
                  ]),
                  const SizedBox(height: 18),
                  _hero(p),
                  _section(p, 'Your data'),
                  _group(p, [
                    _row(p,
                        icon: Icons.ios_share_rounded,
                        title: 'Save a backup file',
                        subtitle: s.lastExport == null
                            ? 'Entries as CSV, groups as JSON. Keep it anywhere.'
                            : 'Last saved ${s.lastExport!.toString().substring(0, 10)}',
                        onTap: () => shareBackup(s)),
                    _row(p,
                        icon: Icons.restore_rounded,
                        title: 'Restore from a file',
                        subtitle: 'Adds entries that are not here yet.',
                        onTap: () => importBackup(s)),
                    _row(p,
                        icon: Icons.bar_chart_rounded,
                        title: 'Month summary',
                        subtitle: 'Spending, who owes you, last 14 days.',
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute<void>(builder: (_) => SummaryScreen(state: s)))),
                    _row(p,
                        icon: Icons.groups_rounded,
                        title: 'Groups',
                        subtitle: '${s.groups.length} ${s.groups.length == 1 ? 'group' : 'groups'}, split costs with friends.',
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute<void>(builder: (_) => GroupsScreen(state: s)))),
                  ]),
                  _section(p, 'Preferences'),
                  _group(p, [
                    _row(p,
                        icon: Icons.payments_outlined,
                        title: 'Currency label',
                        subtitle: 'Shown in the app only.',
                        trailing: SizedBox(
                          width: 76,
                          child: TextField(
                            controller: _currency,
                            maxLength: 4,
                            textAlign: TextAlign.center,
                            style: body(15, color: p.ink, weight: FontWeight.w600),
                            decoration: const InputDecoration(counterText: '', isDense: true),
                            onChanged: s.setCurrency,
                          ),
                        )),
                    _row(p,
                        icon: Icons.mic_none_rounded,
                        title: 'Voice language',
                        subtitle: 'What the microphone listens for.',
                        trailing: SegmentedButton<String>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(value: 'ur_PK', label: Text('Urdu')),
                            ButtonSegment(value: 'en_US', label: Text('English')),
                          ],
                          selected: {s.voiceLocale},
                          onSelectionChanged: (v) => s.setVoiceLocale(v.first),
                        )),
                    _row(p,
                        icon: Icons.blur_on_rounded,
                        title: 'Calm background',
                        subtitle: 'Stops the slow colour movement. Lighter on battery.',
                        trailing: Switch(value: s.calmBackground, onChanged: s.setCalm)),
                    if (s.learned.isNotEmpty)
                      _row(p,
                          icon: Icons.auto_awesome_outlined,
                          title: 'Learned from you',
                          subtitle: '${s.learned.length} words remembered for categories.',
                          trailing: TextButton(onPressed: s.forgetLearned, child: const Text('Forget'))),
                  ]),
                  _section(p, 'Smart parsing'),
                  _group(p, [
                    _row(p,
                        icon: Icons.psychology_alt_outlined,
                        title: 'On-device AI',
                        subtitle: s.aiStatus.isNotEmpty
                            ? s.aiStatus
                            : 'Optional. Reads unusual sentences on this phone (about 350 MB download). Nothing leaves the phone.',
                        trailing: Switch(value: s.aiEnabled, onChanged: s.setAi)),
                  ]),
                  _section(p, 'About'),
                  _group(p, [
                    _row(p,
                        icon: Icons.tune_rounded,
                        title: 'Developer setup',
                        subtitle: 'Google & Firebase values used for sign-in.',
                        onTap: _openSetup),
                    _row(p, icon: Icons.info_outline_rounded, title: 'Spendline', subtitle: 'Say it. It is logged.  ·  v1.0.0'),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _hero(Palette p) {
    final on = s.backupOn;
    final line = on
        ? (s.cloudNotice ??
            '${s.cloudEmail}${s.lastCloudSync == null ? '' : ' · synced ${s.lastCloudSync!.toString().substring(11, 16)}'}')
        : 'Keeps your entries safe, on every phone you sign in to, plus a Google Sheet copy.';
    return Glass(
      radius: 28,
      strong: true,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: on ? p.recvBg : p.field, borderRadius: BorderRadius.circular(16)),
            child: Icon(on ? Icons.cloud_done_rounded : Icons.cloud_upload_outlined, color: on ? p.recv : p.ink2),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(on ? 'Backup & sync is on' : 'Back up & sync', style: body(17, color: p.ink, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(line, style: body(13, color: p.ink2)),
            ]),
          ),
          const SizedBox(width: 8),
          _busy
              ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4))
              : Switch(value: on, onChanged: s.cloudConfigured ? _toggleBackup : null),
        ]),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: body(13.5, color: p.spent)),
        ],
        if (on && s.sheetNotice != null) ...[
          const SizedBox(height: 10),
          Text('Sync is on, but the Google Sheet copy failed: ${s.sheetNotice}', style: body(13, color: p.lent)),
        ],
        if (on && s.connected) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: s.sheetUrl));
              toast('Sheet link copied');
            },
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text('Copy Google Sheet link'),
          ),
        ],
      ]),
    );
  }

  Widget _section(Palette p, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
        child: Text(t.toUpperCase(), style: eyebrow(p.ink3, size: 11)),
      );

  Widget _group(Palette p, List<Widget> rows) => Glass.flat(
        radius: 24,
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 64, color: p.edge),
            rows[i],
          ],
        ]),
      );

  Widget _row(Palette p,
      {required IconData icon, required String title, required String subtitle, Widget? trailing, VoidCallback? onTap}) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(13)),
          child: Icon(icon, size: 20, color: p.accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: body(15, color: p.ink, weight: FontWeight.w600)),
            const SizedBox(height: 1),
            Text(subtitle, style: body(12.5, color: p.ink2)),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
        if (trailing == null && onTap != null) Icon(Icons.chevron_right_rounded, color: p.ink3),
      ]),
    );
    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}
