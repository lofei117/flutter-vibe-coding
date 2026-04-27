import 'package:flutter/material.dart';

import 'home_page.dart';

class FlutterVibeApp extends StatelessWidget {
  const FlutterVibeApp({super.key, this.builder});

  /// Optional `MaterialApp.builder` override so the host can wrap the
  /// navigator with extra overlays (e.g. the Feedback ticket launcher) while
  /// staying inside the Material/Theme/Directionality scope.
  final TransitionBuilder? builder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Vibe Coding',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      builder: builder,
      home: const HomePage(),
    );
  }
}
