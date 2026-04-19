import 'package:flutter/material.dart';

// The mock agent edits only these values for the first runnable demo.
const String homeTitle = 'Mobile Vibe Coding Demo';
const String homeButtonLabel = 'StartWQ';
const Color homeButtonColor = Colors.red;

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
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              const Text(
                'Open UME and use AI Vibe Panel to modify this app.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
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
