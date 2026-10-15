import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import 'glass.dart';
import 'theme.dart';

const _packageName = 'com.spendline.spendline';

const _rules = '''rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}''';

/// Walks through the one-time Google/Firebase setup and tests each connection.
class CloudSetupScreen extends StatefulWidget {
  const CloudSetupScreen({super.key, required this.state});
  final AppState state;

  @override
  State<CloudSetupScreen> createState() => _CloudSetupScreenState();
}

class _CloudSetupScreenState extends State<CloudSetupScreen> {
  late final _client = TextEditingController(text: s.googleClientId);
  late final _project = TextEditingController(text: s.fbProject);
  late final _key = TextEditingController(text: s.fbApiKey);
  String? _result;
  bool _ok = false;
  bool _busy = false;

  AppState get s => widget.state;

  @override
  void dispose() {
    _client.dispose();
    _project.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() => s.saveCloudConfig(clientId: _client.text, project: _project.text, apiKey: _key.text);

  Future<void> _run(String doing, Future<void> Function() job, String done) async {
    setState(() {
      _busy = true;
      _result = doing;
      _ok = false;
    });
    try {
      await _save();
      await job();
      if (mounted) {
        setState(() {
          _result = done;
          _ok = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _result = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    toast('$what copied');
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      _copy(url, 'Link');
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
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 40), children: [
                Row(children: [
                  Press(
                    onTap: () => Navigator.pop(context),
                    label: 'Back',
                    child: Glass(radius: 999, padding: const EdgeInsets.all(9), child: Icon(Icons.arrow_back_rounded, size: 20, color: p.ink)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Google & Firebase setup', style: display(21, color: p.ink))),
                ]),
                const SizedBox(height: 10),
                Text(
                  'One-time, free, about 10 minutes. You do this once as the app owner; users of the Play Store build '
                  'then just tap Connect. Nothing here needs a credit card.',
                  style: body(14, color: p.ink2),
                ),
                const SizedBox(height: 14),
                _step(p, 1, 'Create a Firebase project', [
                  'Open the Firebase console and tap "Add project". Any name. Turn Google Analytics off.',
                ], [
                  _Action('Open Firebase console', () => _open('https://console.firebase.google.com')),
                ]),
                _step(p, 2, 'Turn on Google sign-in', [
                  'Build > Authentication > Get started > Sign-in method > Google > Enable. Choose your email as support email and Save.',
                  'Then open Google again and expand "Web SDK configuration". Copy the Web client ID (ends in .apps.googleusercontent.com) into box 1 below.',
                ]),
                _step(p, 3, 'Register this Android app', [
                  'Project settings (gear) > General > Add app > Android.',
                  'Package name: $_packageName',
                  'SHA-1: the fingerprint of the key that signs your APK. Without it sign-in fails.',
                  'Test builds (debug key):  keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android',
                  'Play Store build: Play Console > Setup > App signing > "App signing key certificate" SHA-1. Add that one too.',
                  'You can skip downloading google-services.json, this app does not need it.',
                ], [
                  _Action('Copy package name', () => _copy(_packageName, 'Package name')),
                ]),
                _step(p, 4, 'Copy two more values', [
                  'Project settings > General: copy "Project ID" into box 2 and "Web API Key" into box 3.',
                ]),
                _step(p, 5, 'Create the database (for Firebase sync)', [
                  'Build > Firestore Database > Create database > any location > Start in production mode.',
                  'Open the Rules tab, replace everything with the rules below, and Publish. They let each user read and write only their own data.',
                ], [
                  _Action('Copy rules', () => _copy(_rules, 'Rules')),
                ]),
                _step(p, 6, 'Allow Google Sheets (for the Sheet backup)', [
                  'In the Google Cloud console, pick the same project. APIs & Services > Library: enable "Google Sheets API" and "Google Drive API".',
                  'APIs & Services > OAuth consent screen: add the scope .../auth/drive.file, and add your own Google account under Test users while the app is in Testing.',
                ], [
                  _Action('Open Google Cloud console', () => _open('https://console.cloud.google.com/apis/library')),
                ]),
                const SizedBox(height: 6),
                Text('Paste your values', style: display(18, color: p.ink)),
                const SizedBox(height: 8),
                _field(p, '1 · Web client ID', _client, 'xxxx.apps.googleusercontent.com'),
                _field(p, '2 · Firebase project ID', _project, 'my-spendline'),
                _field(p, '3 · Firebase Web API key', _key, 'AIza…'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () async {
                      await s.resetCloudConfig();
                      setState(() {
                        _client.text = s.googleClientId;
                        _project.text = s.fbProject;
                        _key.text = s.fbApiKey;
                        _result = 'Using the values built into this app.';
                        _ok = true;
                      });
                    },
                    child: const Text('Use the built-in values'),
                  ),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run('Signing in to Google…', s.connectGoogle, 'Connected. The "Spendline" sheet is in your Google Drive.'),
                      child: const Text('Test Google Sheet'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _run('Signing in to Firebase…', s.connectCloud, 'Firebase sync is on.'),
                      child: const Text('Test Firebase'),
                    ),
                  ),
                ]),
                if (_result != null) ...[
                  const SizedBox(height: 12),
                  Glass(
                    radius: 18,
                    padding: const EdgeInsets.all(14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (_busy)
                        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Icon(_ok ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 20, color: _ok ? p.recv : p.spent),
                      const SizedBox(width: 10),
                      Expanded(child: SelectableText(_result!, style: body(14, color: p.ink))),
                    ]),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _field(Palette p, String label, TextEditingController c, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          autocorrect: false,
          enableSuggestions: false,
          style: body(14.5, color: p.ink),
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

  Widget _step(Palette p, int n, String title, List<String> lines, [List<_Action> actions = const []]) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Glass(
          radius: 22,
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 14, backgroundColor: p.recvBg, child: Text('$n', style: display(14, color: p.recv))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: body(15.5, color: p.ink, weight: FontWeight.w700)),
                for (final l in lines)
                  Padding(padding: const EdgeInsets.only(top: 5), child: Text(l, style: body(13.5, color: p.ink2))),
                if (actions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 8, children: [
                      for (final a in actions) OutlinedButton(onPressed: a.run, child: Text(a.label)),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
      );
}

class _Action {
  _Action(this.label, this.run);
  final String label;
  final VoidCallback run;
}
