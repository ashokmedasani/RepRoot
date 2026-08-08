import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/chat_api.dart';
import '../../core/api/client_api.dart';
import '../../core/api/models/client_models.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/video/open_resource.dart';
import '../../shared/widgets/app_widgets.dart';
import '../professional/professional_format.dart';

enum _ProfessionalTab { profile, chat }

/// The professional as the client sees them, plus messaging — Profile and Chat
/// live as two segments of the same tab rather than a profile page with a
/// separate chat page bolted on.
///
/// Every profile section is optional by design: the backend only sends what
/// the professional set visible on their profile, so an absent section means
/// "private", not "missing".
/// Replica of mobile/src/app/pages/client/professional/client-professional.page.ts and
/// mobile/src/app/pages/client/chat/client-chat.page.ts.
class ClientProfessionalPage extends ConsumerStatefulWidget {
  const ClientProfessionalPage({super.key});

  @override
  ConsumerState<ClientProfessionalPage> createState() => _ClientProfessionalPageState();
}

class _ClientProfessionalPageState extends ConsumerState<ClientProfessionalPage> {
  _ProfessionalTab _tab = _ProfessionalTab.profile;

  // --- profile ---
  ClientProfessionalProfile? _professional;
  List<AdditionalInfoItem> _sharedInfo = [];
  bool _profileLoading = true;
  String _message = '';

  // --- chat ---
  List<ChatMessageRecord> _messages = [];
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  Timer? _chatPoll;
  bool _chatLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadMessages();
    // Same 8s cadence as the Ionic chat page. Kept running for as long as
    // this tab is mounted, regardless of which segment is showing, so
    // messages (and the unread badge) stay fresh even while on Profile.
    _chatPoll = Timer.periodic(const Duration(seconds: 8), (_) => _loadMessages());
  }

  @override
  void dispose() {
    _chatPoll?.cancel();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final me = await ref.read(clientApiProvider).getMe();
      if (!mounted) return;
      setState(() {
        _professional = me.professionalProfile;
        _sharedInfo = me.sharedAdditionalInfo;
        _message = '';
        _profileLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not load your professional.';
        _profileLoading = false;
      });
    }
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
    if (mounted && _chatLoading) setState(() => _chatLoading = false);
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

  Future<void> _open(String raw, {String title = ''}) async {
    if (raw.isEmpty) return;
    await openResource(context, raw, title: title);
  }

  String get _initials {
    final parts = (_professional?.professionalName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0])
        .join()
        .toUpperCase();
    if (parts.isEmpty) return 'T';
    return parts.length > 2 ? parts.substring(0, 2) : parts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Professional')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.sm,
              AppSpacing.screen,
              AppSpacing.sm,
            ),
            child: SegmentedButton<_ProfessionalTab>(
              segments: const [
                ButtonSegment(value: _ProfessionalTab.profile, label: Text('Profile')),
                ButtonSegment(value: _ProfessionalTab.chat, label: Text('Chat')),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          Expanded(
            // Both segments stay in the tree so the chat poll timer and
            // scroll position survive switching back and forth.
            child: IndexedStack(
              index: _tab == _ProfessionalTab.profile ? 0 : 1,
              children: [
                _profileBody(),
                _chatBody(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileBody() {
    if (_profileLoading) {
      return const PagePad(
        children: [SkeletonBox(height: 110), SkeletonBox(height: 160)],
      );
    }

    final professional = _professional;
    return PagePad(
      onRefresh: _loadProfile,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _loadProfile),

        if (professional == null)
          const EmptyState(
            compact: false,
            icon: Icons.person_outline,
            message: 'Your professional has not shared their profile yet.',
          )
        else ...[
          AppCard(
            child: Row(
              children: [
                AppAvatar(
                  initials: _initials,
                  imageUrl: Env.mediaUrl(professional.profilePhotoUrl),
                  size: 60,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(professional.professionalName, style: context.text.titleMedium),
                      if (professional.professionalHeadline.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          professional.professionalHeadline,
                          style: context.text.bodySmall,
                        ),
                      ],
                      if (professional.location.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Icon(Icons.place_outlined,
                                size: 14, color: context.tokens.muted),
                            const SizedBox(width: 2),
                            Text(professional.location, style: context.text.bodySmall),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (professional.aboutMe.isNotEmpty) ...[
            const SectionHeader(title: 'About'),
            AppCard(child: Text(professional.aboutMe, style: context.text.bodyMedium)),
          ],

          if (professional.professionalSummary != null) ...[
            const SectionHeader(title: 'Professional details'),
            AppCard(
              child: Column(
                children: [
                  _kv('Type', professional.professionalSummary!.professionalType),
                  _kv(
                    'Experience',
                    professional.professionalSummary!.yearsExperience != null
                        ? '${professional.professionalSummary!.yearsExperience} years'
                        : '',
                  ),
                  _kv('Specializations',
                      professional.professionalSummary!.specializations),
                  _kv('Languages', professional.professionalSummary!.languagesKnown),
                ],
              ),
            ),
          ],

          if (professional.trainingStyle.isNotEmpty) ...[
            const SectionHeader(title: 'Training style'),
            AppCard(
              child: Text(professional.trainingStyle, style: context.text.bodyMedium),
            ),
          ],

          if (professional.certification != null) ...[
            const SectionHeader(title: 'Certification'),
            AppCard(
              child: Column(
                children: [
                  _kv('Name', professional.certification!.name),
                  _kv('Issued by', professional.certification!.issuedBy),
                  _kv('Year', professional.certification!.year?.toString() ?? ''),
                  if (professional.certification!.fileUrl.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _open(professional.certification!.fileUrl),
                        icon: const Icon(Icons.open_in_new, size: AppSize.iconRow),
                        label: const Text('View certificate'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],

          if (professional.images.isNotEmpty) ...[
            const SectionHeader(title: 'Gallery'),
            SizedBox(
              height: 132,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final image in professional.images)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: GestureDetector(
                        onTap: () => _open(image.url),
                        child: ClipRRect(
                          borderRadius: AppRadius.mdAll,
                          child: Image.network(
                            Env.mediaUrl(image.url),
                            width: 132,
                            height: 132,
                            fit: BoxFit.cover,
                            // A broken image must not blank the gallery.
                            errorBuilder: (_, _, _) => Container(
                              width: 132,
                              height: 132,
                              color: context.tokens.surfaceSoft,
                              child: Icon(Icons.broken_image_outlined,
                                  color: context.tokens.muted),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],

          if (professional.links.isNotEmpty) ...[
            const SectionHeader(title: 'Links'),
            for (final link in professional.links)
              RowItem(
                title: link.title.isEmpty ? link.url : link.title,
                subtitle: link.title.isEmpty ? null : link.url,
                leading: Icon(Icons.link, size: 20, color: context.colors.primary),
                trailing: const Icon(Icons.open_in_new, size: AppSize.iconRow),
                onTap: () => _open(link.url, title: link.title),
              ),
          ],
        ],

        if (_sharedInfo.isNotEmpty) ...[
          const SectionHeader(title: 'Shared with you'),
          for (final item in _sharedInfo)
            RowItem(
              title: item.title,
              subtitle: item.text.isNotEmpty ? item.text : item.link,
              leading: Icon(
                switch (item.type) {
                  AdditionalInfoType.link => Icons.link,
                  AdditionalInfoType.reference => Icons.folder_open_outlined,
                  _ => Icons.notes_outlined,
                },
                size: 20,
                color: context.tokens.accent,
              ),
              onTap: item.link.isNotEmpty
                  ? () => _open(item.link, title: item.title)
                  : null,
            ),
        ],
      ],
    );
  }

  Widget _kv(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: context.text.bodySmall)),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: context.text.titleSmall,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatBody() {
    return Column(
      children: [
        Expanded(
          child: _chatLoading
              ? const PagePad(
                  children: [SkeletonBox(height: 60), SkeletonBox(height: 60)],
                )
              : _messages.isEmpty
                  ? const EmptyState(
                      compact: false,
                      icon: Icons.chat_bubble_outline,
                      message: 'No messages yet.\nSay hello to your professional.',
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
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessageRecord message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Mirrored from the professional's view: here "mine" is the client's message.
    final mine = !message.isProfessional;

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
