import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_poc/main.dart';

void main() {
  testWidgets('Voice Assistant screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const GemmaPocApp());
    await tester.pump();

    expect(find.text('Voice Assistant'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
