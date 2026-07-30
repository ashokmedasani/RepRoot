import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// The hosts the in-app player accepts.
///
/// Deliberately the same tuple as YOUTUBE_HOSTS in backend/accounts/serializers.py.
/// The backend rejects a video resource whose link isn't one of these ("Videos must
/// be YouTube links so they can be streamed in-app"), so anything else can't be
/// saved as a video in the first place. If that list ever grows — music.youtube.com
/// is the obvious candidate — grow both together or the app will hand a link to the
/// player that the backend swore was YouTube.
const _youtubeHosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'youtu.be',
};

/// The YouTube video id in [url], or null if [url] isn't a YouTube link.
///
/// The host is checked before the id is parsed, and that order matters:
/// `convertUrlToId` treats *any* 11-character string without "http" in it as a bare
/// video id, so an innocent note like "hello world" would come back as a video.
/// Requiring a real YouTube URL first closes that off.
String? youtubeVideoId(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return null;
  if (!_youtubeHosts.contains(uri.host.toLowerCase())) return null;

  final id = YoutubePlayerController.convertUrlToId(trimmed);
  return (id == null || id.isEmpty) ? null : id;
}

/// Whether [url] can be played by the in-app player.
bool isYoutubeLink(String url) => youtubeVideoId(url) != null;
