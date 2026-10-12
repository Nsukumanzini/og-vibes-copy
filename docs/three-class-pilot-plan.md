# OG Vibes three-class pilot

Use three classes only after the production checks pass. A practical first
pilot is 25 to 40 students per class, three lecturers and one administrator.

## Before inviting students

- Back up the Android upload keystore and `key.properties` in two encrypted locations.
- Create at least one active safety responder for every participating campus.
- Publish one test alert, slide, past paper, quiz, assessment and online class.
- Confirm each lecturer is assigned only to the modules they teach.
- Keep a paper or external emergency process available while SOS is being tested.

## Class 1: controlled workflow test

Start with one lecturer and 10 students. Test signup, email confirmation,
notification enrollment, module invitation, slides, quizzes, submissions,
messages, group chat, calls and SOS. Do not expand until every failure is
recorded and corrected.

## Class 2: mixed devices

Use Android APK, Android PWA and iPhone Home Screen PWA users. Test foreground,
background and terminated notifications, denied permissions, poor connectivity,
offline reopening and notification deep links.

## Class 3: realistic load

Run normal teaching activity across all three classes. Ask lecturers to publish
content and marks while students use feed and chat. Watch the Admin panel's
Operations resources: Push devices, Student notifications and App health events.

## Go/no-go measures

- At least 95% of supported, permission-granted devices have a current push token.
- At least 98% of notification records are `sent`; investigate every `failed`,
  `partial` and `no_devices` outcome.
- No student can read another student's private wallet, submission or SOS evidence.
- Suspended accounts cannot load live data or create/update/delete records.
- No unresolved critical client health event remains for 48 hours.
- Calls connect in the foreground and background on two different networks.

Students who refuse notification permission cannot be forced by the app. They
must still see the same records in the in-app notification centre.
