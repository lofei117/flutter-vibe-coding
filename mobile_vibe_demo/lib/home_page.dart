import 'package:flutter/material.dart';

// The mock agent edits only these values for the first runnable demo.
const String homeTitle = 'Mobile Vibe Coding Demo';
const String homeButtonLabel = 'Start2';
const Color homeButtonColor = Colors.green;
const String homeDescription =
    'Open UME and use AI Vibe Panel to modify this app.';

// Stable widget keys used as source-registry anchors. Do not rename without
// updating `lib/ume_plugins/source_registry.dart`.
const Key homeTitleKey = ValueKey('home.title');
const Key homeDescriptionKey = ValueKey('home.description');
const Key helloButtonKey = ValueKey('home.helloButton');

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(homeTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                homeTitle,
                key: homeTitleKey,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              const Text(
                homeDescription,
                key: homeDescriptionKey,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: helloButtonKey,
                style: FilledButton.styleFrom(backgroundColor: homeButtonColor),
                onPressed: () {},
                child: const Text(homeButtonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
