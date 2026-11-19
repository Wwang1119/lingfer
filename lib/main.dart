import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_state.dart';
import 'app/lens_app.dart';
import 'features/companion/lingfer_theme.dart';

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

  @override
  Widget build(BuildContext context) {
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
        supportedLocales: const [Locale('zh'), Locale('en')],
        theme: lingferTheme(),
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
