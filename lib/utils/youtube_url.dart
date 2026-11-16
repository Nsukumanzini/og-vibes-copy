final RegExp _youtubeVideoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// Extracts a YouTube video ID from regular, shortened, embed, Shorts, and
/// YouTube Live URLs. A raw 11-character video ID is accepted as well.
String? youtubeVideoId(String input) {
  final value = input.trim();
  if (_youtubeVideoIdPattern.hasMatch(value)) return value;

  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;

  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  String? candidate;

  if (host == 'youtu.be') {
    candidate = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
  } else if (host == 'youtube.com' ||
      host == 'm.youtube.com' ||
      host == 'music.youtube.com' ||
      host == 'youtube-nocookie.com') {
    final firstSegment = uri.pathSegments.isEmpty
        ? null
        : uri.pathSegments.first;
    if (firstSegment == 'watch') {
      candidate = uri.queryParameters['v'];
    } else if (const <String>{
      'live',
      'embed',
      'shorts',
    }.contains(firstSegment)) {
      candidate = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
    }
  }

  final clean = candidate?.trim();
  return clean != null && _youtubeVideoIdPattern.hasMatch(clean) ? clean : null;
}

String? canonicalYoutubeUrl(String input) {
  final id = youtubeVideoId(input);
  return id == null ? null : 'https://www.youtube.com/watch?v=$id';
}
