import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/theme/app_tokens.dart';
import '../widgets/app_widgets.dart';

/// Plays a professional's video resource inside the app.
///
/// ## Why this is built the way it is
///
/// This embeds YouTube's own IFrame player (`youtube_player_iframe` is a thin
/// wrapper over the IFrame Player API) rather than resolving a stream URL and
/// feeding it to a video widget. Packages that do the latter — youtube_explode
/// and friends — break YouTube's Terms of Service, which allow playback only
/// through the official player, and they break the moment YouTube rotates its
/// signature cipher. So:
///
///  * Controls, branding and the fullscreen button stay on. The ToS forbid
///    hiding or obscuring the player's UI, and ads are served by the player —
///    nothing here may cover or skip them.
///  * Audio is never separated from video, and there is no background playback.
///  * If the video's owner disallows embedding (error 101/150), the app says so
///    and offers YouTube. That restriction is the owner's decision to make; the
///    compliant response is to hand the viewer over, not to route around it.
///  * `privacyEnhancedMode` serves from youtube-nocookie.com, YouTube's own
///    privacy-preserving embed — clients watching a workout shouldn't pick up
///    ad-tracking cookies from their professional's resource library.
class YoutubePlayerPage extends StatefulWidget {
  const YoutubePlayerPage({
    super.key,
    required this.videoId,
    required this.url,
    this.title = '',
    this.description = '',
  });

  final String videoId;

  /// The original link, for the "Open in YouTube" fallback.
  final String url;
  final String title;
  final String description;

  @override
  State<YoutubePlayerPage> createState() => _YoutubePlayerPageState();
}

class _YoutubePlayerPageState extends State<YoutubePlayerPage> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      // Opening the page is the tap that asks for the video, so starting muted
      // or waiting for a second tap would just be in the way.
      autoPlay: true,
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
        privacyEnhancedMode: true,
        // showControls / showVideoAnnotations stay at their defaults (on).
        // Turning them off would hide the player's own UI, which the ToS
        // don't allow.
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  Future<void> _openInYoutube() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open YouTube.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.isEmpty ? 'Video' : widget.title),
        actions: [
          IconButton(
            onPressed: _openInYoutube,
            icon: const Icon(Icons.open_in_new),
            iconSize: AppSize.iconRow,
            tooltip: 'Open in YouTube',
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Black behind the player: a 16:9 box on a light page shows letterbox
          // bars in the page colour, which looks broken.
          ColoredBox(
            color: Colors.black,
            // No YoutubePlayerScaffold: as of 6.x the player drives fullscreen
            // itself through an OverlayPortal, and the wrapper is deprecated.
            child: YoutubePlayer(controller: _controller, aspectRatio: 16 / 9),
          ),
          YoutubeValueBuilder(
            controller: _controller,
            buildWhen: (previous, current) => previous.error != current.error,
            builder: (context, value) {
              if (!value.hasError) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.screen),
                child: _PlaybackError(
                  error: value.error,
                  onOpenInYoutube: _openInYoutube,
                ),
              );
            },
          ),
          if (widget.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screen),
              child: Text(widget.description, style: context.text.bodyMedium),
            ),
        ],
      ),
    );
  }
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({required this.error, required this.onOpenInYoutube});

  final YoutubeError error;
  final VoidCallback onOpenInYoutube;

  /// Plain language, and honest about whose decision it was. A professional reading
  /// "error 101" has no idea whether they typed the link wrong or the video's
  /// owner locked it down.
  String get _message => switch (error) {
        // YouTube reports the same "embedding disabled" restriction under three
        // codes (101/150/152); all three mean the same thing to a reader.
        YoutubeError.notEmbeddable ||
        YoutubeError.sameAsNotEmbeddable ||
        YoutubeError.sameAsNotEmbeddable2 =>
          "This video's owner doesn't allow it to play inside other apps. "
              'You can still watch it on YouTube.',
        YoutubeError.videoNotFound ||
        YoutubeError.cannotFindVideo =>
          'This video is unavailable — it may have been removed or made private.',
        YoutubeError.invalidParam =>
          "That link doesn't point at a YouTube video.",
        _ => "This video couldn't be played here.",
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ErrorNote(message: _message),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: onOpenInYoutube,
          icon: const Icon(Icons.open_in_new, size: AppSize.iconRow),
          label: const Text('Watch on YouTube'),
        ),
      ],
    );
  }
}
