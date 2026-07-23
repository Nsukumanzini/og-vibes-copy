import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:og_vibes_student/screens/call_feature_screen.dart';

void main() {
  testWidgets('CallFeatureScreen shows the main call actions', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CallFeatureScreen()));

    expect(find.text('Call Feature'), findsOneWidget);
    expect(find.text('Start outgoing call'), findsOneWidget);
    expect(find.text('View call history'), findsOneWidget);
  });
}
