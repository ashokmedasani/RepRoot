import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import 'youtube_link.dart';
import 'youtube_player_page.dart';

/// Opens a professional's resource link: YouTube videos play in the app, everything
/// else (PDFs, images, arbitrary links) goes to the system handler as before.
///
/// The three screens that surface professional links — client Programs, client
/// Professional profile, professional Resources — each grew their own copy of this, all
/// pushing every link out to the browser. Videos are the reason the backend
/// insists a video resource *be* a YouTube link ("so they can be streamed
/// in-app"), so that promise is kept here, in one place.
///
/// [rawUrl] may be relative; it goes through [Env.mediaUrl] like every other
/// backend-supplied path.
Future<void> openResource(
  BuildContext context,
  String rawUrl, {
  String title = '',
  String description = '',
  String failureMessage = 'Could not open this link.',
}) async {
  if (rawUrl.trim().isEmpty) return;

  final resolved = Env.mediaUrl(rawUrl);

  final videoId = youtubeVideoId(resolved);
  if (videoId != null) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => YoutubePlayerPage(
          videoId: videoId,
          url: resolved,
          title: title,
          description: description,
        ),
      ),
    );
    return;
  }

  final uri = Uri.tryParse(resolved);
  if (uri == null) {
    if (context.mounted) _toast(context, failureMessage);
    return;
  }

  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) _toast(context, failureMessage);
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
