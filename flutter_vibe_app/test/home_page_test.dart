import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vibe_app/home_page.dart';

void main() {
  testWidgets('home page opens the todo list flow', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    expect(find.text(homeTitle), findsNWidgets(2));
    expect(find.text(homeButtonLabel), findsOneWidget);

    await tester.tap(find.byKey(helloButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Todo List'), findsOneWidget);
    expect(find.text('No todos yet.'), findsOneWidget);
  });
}
