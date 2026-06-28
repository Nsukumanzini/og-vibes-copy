import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:og_vibes_student/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('MyApp renders material root', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
