import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:og_vibes_student/screens/incoming_call_screen.dart';
import 'package:og_vibes_student/screens/settings_screen.dart';
import 'package:og_vibes_student/screens/donation_screen.dart';
import 'package:og_vibes_student/screens/suggestion_box_screen.dart';
import 'package:og_vibes_student/widgets/adaptive_scroll_body.dart';
import 'package:og_vibes_student/widgets/profile_photo_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: child,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('short pages preserve spacers and scroll to the final action', (
    tester,
  ) async {
    await show(
      tester,
      Scaffold(
        body: AdaptiveScrollBody(
          child: Column(
            children: [
              const SizedBox(height: 600),
              const Spacer(),
              TextButton(onPressed: () {}, child: const Text('Final action')),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Final action'));
    expect(find.text('Final action').hitTestable(), findsOneWidget);
  });

  testWidgets('incoming call actions remain reachable with large text', (
    tester,
  ) async {
    var answered = false;
    await show(
      tester,
      IncomingCallScreen(
        contactName: 'A student with a long nickname',
        callType: 'video',
        onAccept: () => answered = true,
        onDecline: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Join video'));
    await tester.tap(find.text('Join video'));
    expect(answered, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('suggestion form scrolls to submit', (tester) async {
    await show(tester, const SuggestionBoxScreen());
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Send suggestion'));
    expect(find.text('Send suggestion').hitTestable(), findsOneWidget);
  });

  testWidgets('donation form stays hidden until Donate is selected', (
    tester,
  ) async {
    await show(tester, const DonationScreen());
    expect(find.byType(TextField), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Donate'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Donate'));
    await tester.pump();
    expect(find.byType(TextField), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Close donation form'));
    await tester.tap(find.text('Close donation form'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settings header and account options can scroll', (tester) async {
    await show(tester, const SettingsScreen());
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -600));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(NestedScrollView), findsOneWidget);
  });

  testWidgets('profile photos open a zoomable viewer', (tester) async {
    await show(
      tester,
      const Scaffold(
        body: Center(
          child: ProfilePhotoButton(
            url: 'https://example.com/photo.png',
            name: 'Student',
            child: SizedBox(width: 80, height: 80, child: Text('Photo')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProfilePhotoViewer), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('Zoom in'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
