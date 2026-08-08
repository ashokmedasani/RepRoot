import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/chat_api.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

/// Full-screen chat with one client.
///
/// Previously this lived as a tab inside the client-detail page, stacked under
/// that page's header and tab bar, inside the app's bottom-nav shell. On a
/// ~760pt phone that left roughly 260pt for messages — about three bubbles —
/// and the on-screen keyboard then covered most of those. As its own route it
/// gets the whole viewport, which is what every messaging UI gives a
/// conversation.
class ProfessionalClientChatPage extends ConsumerStatefulWidget {
  const ProfessionalClientChatPage({
    super.key,
    required this.clientId,
    this.clientName = '',
  });

  final int clientId;
  final String clientName;

  @override
  ConsumerState<ProfessionalClientChatPage> createState() =>
      _ProfessionalClientChatPageState();
}

class _ProfessionalClientChatPageState
    extends ConsumerState<ProfessionalClientChatPage> {
  final _draft = TextEditingController();
  final _scroll = ScrollController();

  List<ChatMessageRecord> _messages = [];
  XFile? _pendingImage;
  bool _isSending = false;
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Polls incrementally: only messages newer than the last one seen.
  Future<void> _load() async {
    try {
      final lastId = _messages.isNotEmpty ? _messages.last.id : null;
      final fresh = await ref
          .read(chatApiProvider)
          .getProfessionalMessages(widget.clientId, afterId: lastId);
      if (!mounted) return;
      setState(() {
        if (fresh.isNotEmpty) _messages = [..._messages, ...fresh];
        _loading = false;
      });
      if (fresh.isNotEmpty) _scrollToEnd();
    } catch (_) {
      // A failed poll must not disturb a conversation already on screen.
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked != null && mounted) setState(() => _pendingImage = picked);
  }

  Future<void> _send() async {
    final text = _draft.text.trim();
    final image = _pendingImage;
    // An image alone is a valid message; only block when there's neither.
    if ((text.isEmpty && image == null) || _isSending) return;

    setState(() => _isSending = true);
    _draft.clear();
    try {
      final sent = await ref.read(chatApiProvider).sendProfessionalMessage(
            widget.clientId,
            text,
            imagePath: image?.path,
            imageName: image?.name,
          );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, sent];
        _pendingImage = null;
        _isSending = false;
      });
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message failed to send.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.clientName.isNotEmpty ? widget.clientName : 'Chat',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading && _messages.isEmpty
                  ? const PagePad(children: [SkeletonBox(height: 60)])
                  : _messages.isEmpty
                      ? const EmptyState(
                          compact: false,
                          icon: Icons.chat_bubble_outline,
                          message:
                              'No messages yet.\nSay hello to start the conversation.',
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(AppSpacing.screen),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) =>
                              ChatBubble(message: _messages[index]),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.sm,
                AppSpacing.screen,
                AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_pendingImage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          Icon(Icons.image_outlined,
                              size: AppSize.iconRow,
                              color: context.colors.primary),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _pendingImage!.name,
                              style: context.text.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                setState(() => _pendingImage = null),
                            icon: const Icon(Icons.close),
                            iconSize: AppSize.iconRow,
                            tooltip: 'Remove image',
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _isSending ? null : _pickImage,
                        icon: const Icon(Icons.image_outlined),
                        iconSize: AppSize.iconButton,
                        tooltip: 'Attach image',
                      ),
                      Expanded(
                        child: TextField(
                          controller: _draft,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration:
                              const InputDecoration(hintText: 'Message…'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      IconButton.filled(
                        onPressed: _isSending ? null : _send,
                        icon: const Icon(Icons.send),
                        iconSize: AppSize.iconRow,
                        tooltip: 'Send',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One chat bubble. Public so the client-side conversation can render messages
/// identically instead of keeping its own near-duplicate copy.
class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});

  final ChatMessageRecord message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final mine = message.isProfessional;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: mine ? context.colors.primary : tokens.surfaceSoft,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadius.tile),
            topRight: const Radius.circular(AppRadius.tile),
            bottomLeft: Radius.circular(mine ? AppRadius.tile : 2),
            bottomRight: Radius.circular(mine ? 2 : AppRadius.tile),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // A message may be an image, text, or both — the backend allows
            // blank text when an image is attached.
            if (message.hasImage) ...[
              ClipRRect(
                borderRadius: AppRadius.controlAll,
                child: Image.network(
                  Env.mediaUrl(message.imageUrl),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    color: tokens.surfaceSoft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image_outlined,
                            size: AppSize.iconRow, color: tokens.muted),
                        const SizedBox(width: AppSpacing.sm),
                        Text('Image unavailable', style: context.text.bodySmall),
                      ],
                    ),
                  ),
                ),
              ),
              if (message.text.isNotEmpty) const SizedBox(height: AppSpacing.sm),
            ],
            if (message.text.isNotEmpty)
              Text(
                message.text,
                style: context.text.bodyMedium?.copyWith(
                  color:
                      mine ? context.colors.onPrimary : context.colors.onSurface,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              dateTimeLabel(message.createdAt),
              style: context.text.labelSmall?.copyWith(
                color: mine
                    ? context.colors.onPrimary.withValues(alpha: 0.75)
                    : tokens.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
