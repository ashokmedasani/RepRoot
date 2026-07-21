import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/chat_api.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/client_models.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';

enum ClientStatusFilter { all, active, inactive }

/// Clients tab — searchable list with All / Active / Inactive filters.
/// Replica of mobile/src/app/pages/professional/clients/professional-clients.page.ts.
class ProfessionalClientsPage extends ConsumerStatefulWidget {
  const ProfessionalClientsPage({super.key});

  @override
  ConsumerState<ProfessionalClientsPage> createState() => _ProfessionalClientsPageState();
}

class _ProfessionalClientsPageState extends ConsumerState<ProfessionalClientsPage> {
  final _search = TextEditingController();

  List<ClientAccessRecord> _clients = [];
  List<ProfessionalGroup> _groups = [];
  Map<String, int> _unreadByClient = {};
  Map<String, DateTime> _lastUnreadAt = {};
  bool _isLoading = true;
  String _message = '';
  String _groupFilter = 'all';
  ClientStatusFilter _statusFilter = ClientStatusFilter.all;
  Timer? _unreadPoll;

  @override
  void initState() {
    super.initState();
    _load();
    _loadUnread();
    // Same 5s cadence as the Ionic page.
    _unreadPoll = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadUnread(),
    );
  }

  @override
  void dispose() {
    _unreadPoll?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<ClientAccessRecord> get _filteredClients {
    final term = _search.text.trim().toLowerCase();
    final matches = _clients.where((client) {
      final matchesSearch = term.isEmpty ||
          client.displayName.toLowerCase().contains(term) ||
          client.email.toLowerCase().contains(term) ||
          client.username.toLowerCase().contains(term) ||
          client.groupName.toLowerCase().contains(term);
      final matchesGroup =
          _groupFilter == 'all' || '${client.group}' == _groupFilter;
      final matchesStatus = switch (_statusFilter) {
        ClientStatusFilter.all => true,
        ClientStatusFilter.active => client.isActive,
        ClientStatusFilter.inactive => !client.isActive,
      };
      return matchesSearch && matchesGroup && matchesStatus;
    }).toList();

    // Clients waiting on a reply come first, newest message at the top; everyone
    // else stays alphabetical. Deliberately only unread chats float: this list is
    // a roster of 100 people that a professional searches by name, so reordering all
    // of it by chat activity would move familiar rows around for no reason.
    // Reading a chat drops it out of the unread map and the row settles back into
    // place on the next poll.
    //
    // The name comparison has to be spelled out rather than returning 0 for
    // "no opinion": List.sort is not stable, so equal-ranked rows would come
    // back in whatever order the sort happened to leave them.
    matches.sort((a, b) {
      final aAt = _lastUnreadFor(a.id);
      final bAt = _lastUnreadFor(b.id);
      if (aAt != null && bAt != null) return bAt.compareTo(aAt);
      if (aAt != null) return -1;
      if (bAt != null) return 1;
      return a.displayName.compareTo(b.displayName);
    });
    return matches;
  }

  int _unreadFor(int clientId) => _unreadByClient['$clientId'] ?? 0;

  DateTime? _lastUnreadFor(int clientId) => _lastUnreadAt['$clientId'];

  String _badgeLabel(int count) => count > 99 ? '99+' : '$count';

  String _initials(ClientAccessRecord client) {
    final first = client.firstName.isNotEmpty ? client.firstName[0] : '';
    final last = client.lastName.isNotEmpty ? client.lastName[0] : '';
    final letters = '$first$last'.toUpperCase();
    return letters.isEmpty ? 'C' : letters;
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _message = '';
    });

    final api = ref.read(formsGroupsApiProvider);
    try {
      final overview = await api.getOverview();
      if (!mounted) return;
      setState(() => _groups = overview.groups);

      if (overview.groups.isEmpty) {
        setState(() {
          _clients = [];
          _isLoading = false;
        });
        return;
      }

      // Clients live per group, so fan out and flatten — a failing group must
      // not lose the others, matching the catchError in the Ionic forkJoin.
      final responses = await Future.wait(
        overview.groups.map((group) async {
          try {
            return (await api.getGroupUsers(group.id)).clients;
          } catch (_) {
            return <ClientAccessRecord>[];
          }
        }),
      );

      if (!mounted) return;
      final all = responses.expand((list) => list).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
      setState(() {
        _clients = all;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not load clients. Pull to retry.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUnread() async {
    try {
      final summary = await ref.read(chatApiProvider).getProfessionalUnreadCounts();
      if (mounted) {
        setState(() {
          _unreadByClient = summary.byClient;
          _lastUnreadAt = summary.lastUnreadAt;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unreadByClient = {};
          _lastUnreadAt = {};
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredClients;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clients'),
        actions: [
          IconButton(
            onPressed: () => context.go(Routes.professionalClientCreate),
            icon: const Icon(Icons.add),
            tooltip: 'Add client',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              0,
              AppSpacing.screen,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search clients...',
                prefixIcon: const Icon(Icons.search, size: AppSize.iconRow),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: AppSize.iconRow),
                        onPressed: () => setState(() => _search.clear()),
                      ),
              ),
            ),
          ),
        ),
      ),
      body: PagePad(
        onRefresh: _load,
        children: [
          SegmentedButton<ClientStatusFilter>(
            segments: const [
              ButtonSegment(
                value: ClientStatusFilter.all,
                label: Text('All Clients'),
              ),
              ButtonSegment(
                value: ClientStatusFilter.active,
                label: Text('Active'),
              ),
              ButtonSegment(
                value: ClientStatusFilter.inactive,
                label: Text('Inactive'),
              ),
            ],
            selected: {_statusFilter},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _statusFilter = selection.first),
            style: SegmentedButton.styleFrom(
              textStyle: context.text.labelMedium,
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (_groups.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            _GroupChips(
              groups: _groups,
              selected: _groupFilter,
              onSelect: (value) => setState(() => _groupFilter = value),
            ),
          ],
          if (_message.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorNote(message: _message, onRetry: _load),
          ],
          const SizedBox(height: AppSpacing.md),

          if (_isLoading)
            for (var i = 0; i < 6; i++) const SkeletonBox(height: 68)
          else if (filtered.isEmpty)
            EmptyState(
              compact: false,
              icon: Icons.people_outline,
              message: _clients.isEmpty
                  ? 'No clients yet.'
                  : 'No clients match your filters.',
              actionLabel: _clients.isEmpty ? 'Add your first client' : null,
              onAction: _clients.isEmpty
                  ? () => context.go(Routes.professionalClientCreate)
                  : null,
            )
          else
            for (final client in filtered)
              RowItem(
                title: client.displayName.isEmpty
                    ? client.username
                    : client.displayName,
                subtitle: client.groupName.isEmpty ? 'No group' : client.groupName,
                leading: AppAvatar(
                  initials: _initials(client),
                  imageUrl: Env.mediaUrl(client.photo),
                  size: 40,
                ),
                trailing: _unreadFor(client.id) > 0
                    ? _UnreadBadge(label: _badgeLabel(_unreadFor(client.id)))
                    : (client.isActive
                        ? null
                        : const StatusPill(label: 'Inactive')),
                onTap: () => context.go('${Routes.professionalClients}/${client.id}'),
              ),
        ],
      ),
    );
  }
}

class _GroupChips extends StatelessWidget {
  const _GroupChips({
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  final List<ProfessionalGroup> groups;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(context, 'All groups', 'all'),
          for (final group in groups) _chip(context, group.name, '${group.id}'),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, String value) {
    final on = selected == value;
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        onTap: () => onSelect(value),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? tokens.primarySoft : context.colors.surface,
            border: Border.all(
              color: on ? context.colors.primary : tokens.border,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: on ? tokens.primaryStrong : tokens.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Unread chat count — the .message-count rule (a fixed rose red in both
/// themes, matching the Ionic app).
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label unread messages',
      child: Container(
        constraints: const BoxConstraints(minWidth: 22),
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFE11D48),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: context.text.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 10.5,
          ),
        ),
      ),
    );
  }
}
