import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/chat_api.dart';
import '../../core/api/client_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import '../trainer/trainer_format.dart';

/// Client chat with their trainer.
/// Replica of mobile/src/app/pages/client/chat/client-chat.page.ts.
class ClientChatPage extends ConsumerStatefulWidget {
  const ClientChatPage({super.key});

  @override
  ConsumerState<ClientChatPage> createState() => _ClientChatPageState();
}

class _ClientChatPageState extends ConsumerState<ClientChatPage> {
  List<ChatMessageRecord> _messages = [];
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    // Same 8s cadence as the Ionic page.
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _loadMessages());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Polls incrementally: only messages newer than the last one seen.
  Future<void> _loadMessages() async {
    try {
      final lastId = _messages.isNotEmpty ? _messages.last.id : null;
      final messages =
          await ref.read(clientApiProvider).getChatMessages(afterId: lastId);
      if (!mounted) return;
      if (messages.isNotEmpty) {
        setState(() => _messages = [..._messages, ...messages]);
        _scrollToEnd();
      }
    } catch (_) {/* a failed poll must not disturb the screen */}
    if (mounted && _loading) setState(() => _loading = false);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _draft.text.trim();
    if (text.isEmpty) return;
    _draft.clear();
    try {
      final sent = await ref.read(clientApiProvider).sendChatMessage(text);
      if (!mounted) return;
      setState(() => _messages = [..._messages, sent]);
      _scrollToEnd();
    } catch (_) {
      // Put the text back so it is not lost.
      if (mounted) {
        setState(() => _draft.text = text);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message failed to send.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        leading: BackButton(onPressed: () => context.go(Routes.clientMore)),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const PagePad(children: [SkeletonBox(height: 60), SkeletonBox(height: 60)])
                : _messages.isEmpty
                    ? const EmptyState(
                        compact: false,
                        icon: Icons.chat_bubble_outline,
                        message: 'No messages yet.\nSay hello to your trainer.',
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(AppSpacing.screen),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) =>
                            _Bubble(message: _messages[index]),
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.sm,
                AppSpacing.screen,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _draft,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: 'Message…'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                    iconSize: AppSize.iconRow,
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessageRecord message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Mirrored from the trainer's view: here "mine" is the client's message.
    final mine = !message.isTrainer;

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
            topLeft: const Radius.circular(AppRadius.md),
            topRight: const Radius.circular(AppRadius.md),
            bottomLeft: Radius.circular(mine ? AppRadius.md : 2),
            bottomRight: Radius.circular(mine ? 2 : AppRadius.md),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: context.text.bodyMedium?.copyWith(
                color: mine ? context.colors.onPrimary : context.colors.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              dateTimeLabel(message.createdAt),
              style: context.text.labelSmall?.copyWith(
                color: mine
                    ? context.colors.onPrimary.withValues(alpha: 0.75)
                    : tokens.muted,
                fontSize: 9.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
