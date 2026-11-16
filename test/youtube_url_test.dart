import 'package:flutter_test/flutter_test.dart';
import 'package:og_vibes_student/utils/youtube_url.dart';

void main() {
  const id = 'dQw4w9WgXcQ';

  test('extracts IDs from supported YouTube URL formats', () {
    expect(youtubeVideoId('https://www.youtube.com/watch?v=$id'), id);
    expect(youtubeVideoId('https://youtube.com/live/$id?si=share'), id);
    expect(youtubeVideoId('https://youtu.be/$id?t=10'), id);
    expect(youtubeVideoId('https://www.youtube.com/embed/$id'), id);
    expect(youtubeVideoId('https://m.youtube.com/shorts/$id'), id);
    expect(youtubeVideoId(id), id);
  });

  test('rejects non-YouTube and malformed URLs', () {
    expect(youtubeVideoId('https://example.com/watch?v=$id'), isNull);
    expect(youtubeVideoId('https://youtube.com/live/too-short'), isNull);
    expect(youtubeVideoId('not a url'), isNull);
  });

  test('canonicalizes a YouTube Live URL', () {
    expect(
      canonicalYoutubeUrl('https://youtube.com/live/$id?si=share'),
      'https://www.youtube.com/watch?v=$id',
    );
  });
}
