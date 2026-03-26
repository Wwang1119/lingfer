import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_state.dart';
import 'app/lens_app.dart';

void main() {
  // Force-disable any debug visualizers (especially baselines) that can show up
  // as "yellow double underlines" under text when enabled via DevTools.
  assert(() {
    debugPaintBaselinesEnabled = false;
    debugPaintSizeEnabled = false;
    debugPaintPointersEnabled = false;
    debugRepaintRainbowEnabled = false;
    return true;
  }());

  runApp(const LingferRoot());
}

class LingferRoot extends StatefulWidget {
  const LingferRoot({super.key});

  @override
  State<LingferRoot> createState() => _LingferRootState();
}

class _LingferRootState extends State<LingferRoot> {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_state.initialize);
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  static const Color _appleBlue = Color(0xFF007AFF);
  static const Color _liquidSelectionColor = Color(0x40D1D1D6);
  static const Color _appleSystemGray = Color(0xFF8E8E93);
  static const Color _handleDeepSpace = Color(0xFF3A3A3C);

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = ThemeData.light().textTheme.apply(
      fontFamilyFallback: const ['.SF UI Text', '.SF Pro Text', 'PingFang SC'],
    );
    const bodyPolish = TextStyle(height: 1.6, letterSpacing: 0.5);
    final polishedTextTheme = baseTextTheme.copyWith(
      bodyLarge: baseTextTheme.bodyLarge?.merge(bodyPolish),
      bodyMedium: baseTextTheme.bodyMedium?.merge(bodyPolish),
      bodySmall: baseTextTheme.bodySmall?.merge(bodyPolish),
    );

    return AppScope(
      state: _state,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '语渡',
        navigatorKey: lensNavigatorKey,
        scrollBehavior: const LingferScrollBehavior(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh'),
          Locale('en'),
        ],
        theme: ThemeData(
          platform: TargetPlatform.iOS,
          fontFamilyFallback: const ['.SF UI Text', '.SF Pro Text', 'PingFang SC'],
          textTheme: polishedTextTheme,
          textSelectionTheme: const TextSelectionThemeData(
            cursorColor: _appleSystemGray,
            selectionColor: _liquidSelectionColor,
            selectionHandleColor: _handleDeepSpace,
          ),
          cupertinoOverrideTheme: const CupertinoThemeData(
            brightness: Brightness.light,
            primaryColor: _appleBlue,
            selectionHandleColor: _handleDeepSpace,
          ),
        ),
        home: LensAppHost(state: _state),
      ),
    );
  }
}

class LingferScrollBehavior extends MaterialScrollBehavior {
  const LingferScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}
