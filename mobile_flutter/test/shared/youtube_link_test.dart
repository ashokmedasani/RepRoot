import 'package:reproot/shared/video/youtube_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// The parser decides whether a professional's link plays inside the app or gets
/// handed to the browser, so the interesting cases are the ones where it must
/// say *no*.
void main() {
  group('youtubeVideoId accepts the shapes professionals actually paste', () {
    const id = 'dQw4w9WgXcQ';

    test('watch URL', () {
      expect(youtubeVideoId('https://www.youtube.com/watch?v=$id'), id);
    });

    test('watch URL with extra query params', () {
      expect(
        youtubeVideoId('https://www.youtube.com/watch?v=$id&list=PL123&index=2'),
        id,
      );
    });

    test('youtu.be short link', () {
      expect(youtubeVideoId('https://youtu.be/$id'), id);
    });

    test('youtu.be with a start time', () {
      expect(youtubeVideoId('https://youtu.be/$id?t=42'), id);
    });

    test('embed URL', () {
      expect(youtubeVideoId('https://www.youtube.com/embed/$id'), id);
    });

    test('shorts URL', () {
      expect(youtubeVideoId('https://www.youtube.com/shorts/$id'), id);
    });

    test('mobile host', () {
      expect(youtubeVideoId('https://m.youtube.com/watch?v=$id'), id);
    });

    test('bare youtube.com host, no www', () {
      expect(youtubeVideoId('https://youtube.com/watch?v=$id'), id);
    });

    test('surrounding whitespace is tolerated', () {
      expect(youtubeVideoId('  https://youtu.be/$id  '), id);
    });
  });

  group('youtubeVideoId refuses everything else', () {
    test('a PDF link goes to the browser, not the player', () {
      expect(youtubeVideoId('https://example.com/plan.pdf'), isNull);
    });

    test('a Vimeo link is not YouTube', () {
      expect(youtubeVideoId('https://vimeo.com/123456789'), isNull);
    });

    test('empty and whitespace', () {
      expect(youtubeVideoId(''), isNull);
      expect(youtubeVideoId('   '), isNull);
    });

    test('a relative media path', () {
      expect(youtubeVideoId('/media/references/plan.pdf'), isNull);
    });

    // The reason youtubeVideoId checks the host before parsing an id: the
    // package's convertUrlToId treats any 11-character string without "http" in
    // it as a bare video id, so a plain note would otherwise come back playable.
    test('an 11-character note is not a video id', () {
      expect(youtubeVideoId('hello world'), isNull);
      expect(youtubeVideoId('dQw4w9WgXcQ'), isNull);
    });

    test('a host merely containing "youtube.com" is refused', () {
      expect(youtubeVideoId('https://youtube.com.evil.example/watch?v=x'), isNull);
      expect(youtubeVideoId('https://notyoutube.com/watch?v=dQw4w9WgXcQ'), isNull);
    });

    test('music.youtube.com — the backend rejects it, so the app does too', () {
      expect(
        youtubeVideoId('https://music.youtube.com/watch?v=dQw4w9WgXcQ'),
        isNull,
      );
    });
  });

  test('isYoutubeLink mirrors youtubeVideoId', () {
    expect(isYoutubeLink('https://youtu.be/dQw4w9WgXcQ'), isTrue);
    expect(isYoutubeLink('https://example.com/plan.pdf'), isFalse);
  });
}
