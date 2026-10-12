class LiveSession {
  const LiveSession({
    required this.id,
    required this.module,
    required this.subject,
    required this.topic,
    required this.time,
    required this.isLive,
    required this.lecturer,
    this.requiredAttendanceSeconds = 1800,
  });

  final String id;
  final String module;
  final String subject;
  final String topic;
  final String time;
  final bool isLive;
  final String lecturer;
  final int requiredAttendanceSeconds;
}
