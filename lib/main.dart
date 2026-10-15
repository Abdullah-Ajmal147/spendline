import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/smart_parser.dart';
import 'state/app_state.dart';
import 'ui/glass.dart';
import 'ui/chat_screen.dart';
import 'ui/onboarding_screen.dart';
import 'ui/splash_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SmartParser.initEngine();
  final state = AppState();
  await state.init();
  runApp(SpendlineApp(state: state));
}

class SpendlineApp extends StatelessWidget {
  const SpendlineApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spendline',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      // Very large system fonts break dense layouts; 1.4x still honours accessibility settings.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4)),
        child: child!,
      ),
      themeMode: ThemeMode.system,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: _Root(state: state),
    );
  }
}

/// Splash, then the one-time intro, then the chat.
class _Root extends StatefulWidget {
  const _Root({required this.state});
  final AppState state;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _splashDone = false;
  late bool _intro = !widget.state.onboarded;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (!_splashDone) {
      child = SplashScreen(key: const ValueKey('splash'), onDone: () => setState(() => _splashDone = true));
    } else if (_intro) {
      child = OnboardingScreen(
        key: const ValueKey('intro'),
        state: widget.state,
        onDone: () => setState(() => _intro = false),
      );
    } else {
      child = ChatScreen(key: const ValueKey('chat'), state: widget.state);
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 450), child: child);
  }
}
