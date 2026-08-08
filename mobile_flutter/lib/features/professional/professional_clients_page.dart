import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/chat_api.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/client_models.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/api/plan_lock_api.dart';
import '../../core/api/professional_auth_api.dart';
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
  int _notificationUnread = 0;

  /// Which groups the current plan has locked. A downgrade doesn't delete
  /// anything — it locks the groups beyond the new limit and suspends the
  /// clients inside them (see the backend's plan_lock_cascade). Those clients
  /// can't sign in and the group can't be worked with, so showing either here
  /// is just noise on the roster you actually manage.
  Set<int> _lockedGroupIds = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadUnread();
    _loadNotificationCount();
    _loadLockStatus();
    // Same 5s cadence as the Ionic page.
    _unreadPoll = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        _loadUnread();
        _loadNotificationCount();
      },
    );
  }

  /// Header badge only — fetched once on open rather than polled, since the
  /// notification inbox changes far less often than chat and this page already
  /// runs a 5s poll for per-client unread counts.
  /// Called on open and again on every unread poll — this page is kept alive
  /// by the tab shell, so a one-off fetch would leave the bell frozen.
  Future<void> _loadNotificationCount() async {
    try {
      final inbox =
          await ref.read(professionalAuthApiProvider).getNotifications(limit: 1);
      if (mounted) setState(() => _notificationUnread = inbox.unreadCount);
    } catch (_) {/* the badge just stays at zero */}
  }

  @override
  void dispose() {
    _unreadPoll?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadLockStatus() async {
    try {
      final status = await ref.read(planLockApiProvider).getLockStatus();
      if (!mounted) return;
      setState(() {
        _lockedGroupIds =
            status.section(PlanLockModelKey.groups).lockedIds.toSet();
      });
    } catch (_) {
      // Unknown lock state shows everything rather than hiding real clients —
      // over-showing is recoverable, silently losing a client from the roster
      // is not.
      if (mounted) setState(() => _lockedGroupIds = {});
    }
  }

  /// Clients on the roster: everyone except those stranded in a locked group.
  List<ClientAccessRecord> get _visibleClients => _lockedGroupIds.isEmpty
      ? _clients
      : _clients
          .where((c) => c.group == null || !_lockedGroupIds.contains(c.group))
          .toList();

  int _clientCountForGroup(int groupId) =>
      _visibleClients.where((c) => c.group == groupId).length;

  /// Groups worth offering as a filter: not locked by the plan, and actually
  /// holding at least one client. A locked group has no reachable clients, and
  /// an empty one can only ever filter the list down to nothing — either way
  /// it's a dead end here. Both stay visible and manageable under
  /// Manage → Groups; they just aren't offered as a way to slice this roster.
  List<ProfessionalGroup> get _filterableGroups => _groups
      .where((g) =>
          !_lockedGroupIds.contains(g.id) && _clientCountForGroup(g.id) > 0)
      .toList();

  List<ClientAccessRecord> get _filteredClients {
    final term = _search.text.trim().toLowerCase();
    final matches = _visibleClients.where((client) {
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

  // ----- summary band — 1:1 port of professional-clients.component's
  // activeClients/pendingClients getters (the website's summary-band
  // section). Was entirely missing on mobile. -----

  // All four counts run off _visibleClients, not _clients: a suspended client
  // in a plan-locked group isn't on the roster, so counting them here would
  // make the totals disagree with the list directly underneath.
  int get _activeClientCount => _visibleClients.where((c) => c.isActive).length;

  int get _pendingPasswordCount =>
      _visibleClients.where((c) => c.mustChangePassword).length;

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
      // No AppBar — same header shape as every other tab: eyebrow/title in a
      // row with the page's own action (Add client) at top-right. Search
      // moves down into the body, right under the title, instead of a
      // second bar stacked under the AppBar.
      body: SafeArea(
        child: PagePad(
          onRefresh: _load,
          children: [
            PageHeader(
              eyebrow: 'CLIENT WORKSPACE',
              title: 'Clients',
              info: 'Everyone you work with, and the record you keep on '
                  'each of them.\n\n'
                  'Open a client to reach their workspace, assigned '
                  'templates, payments, chat, and account actions.\n\n'
                  'Clients arrive here from a lead form, a group sign-up '
                  'link, or by being added directly with the + button.',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => context.go(Routes.professionalClientCreate),
                    icon: const Icon(Icons.add),
                    tooltip: 'Add client',
                  ),
                  // The bell appears on every primary tab except More (which
                  // reaches Notifications through its own menu row), so unread
                  // state is visible wherever you happen to be standing.
                  NotificationBell(
                    unread: _notificationUnread,
                    onTap: () => context.go(Routes.professionalNotifications),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // The website's summary-band — Total/Active/Pending
            // passwords/Groups — was missing on mobile entirely.
            CompactStatRow(
              stats: [
                CompactStat(
                  icon: Icons.people_outline,
                  accent: MenuAccent.blue,
                  value: '${_visibleClients.length}',
                  label: 'Total Clients',
                ),
                CompactStat(
                  icon: Icons.check_circle_outline,
                  accent: MenuAccent.green,
                  value: '$_activeClientCount',
                  label: 'Active Clients',
                ),
                CompactStat(
                  icon: Icons.lock_clock_outlined,
                  accent: MenuAccent.orange,
                  value: '$_pendingPasswordCount',
                  label: 'Pending Passwords',
                ),
                CompactStat(
                  icon: Icons.folder_open_outlined,
                  accent: MenuAccent.purple,
                  value: '${_groups.where((g) => !_lockedGroupIds.contains(g.id)).length}',
                  label: 'Groups',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
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
            const SizedBox(height: AppSpacing.md),
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
          ),
          if (_filterableGroups.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            _GroupFilterBar(
              groups: _filterableGroups,
              selected: _groupFilter,
              countFor: _clientCountForGroup,
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
      ),
    );
  }
}

/// Group filter as a single control rather than a chip per group.
///
/// A horizontal chip row worked at three groups and fell apart at thirty:
/// every group got a chip, so finding one meant scrolling a strip sideways
/// with no way to search and no idea how many were off-screen. This shows the
/// current selection and opens a searchable sheet, so it costs one row of
/// height no matter how many groups exist.
class _GroupFilterBar extends StatelessWidget {
  const _GroupFilterBar({
    required this.groups,
    required this.selected,
    required this.countFor,
    required this.onSelect,
  });

  final List<ProfessionalGroup> groups;
  final String selected;
  final int Function(int groupId) countFor;
  final ValueChanged<String> onSelect;

  String _labelFor(BuildContext context) {
    if (selected == 'all') return 'All groups';
    final match = groups.where((g) => '${g.id}' == selected).firstOrNull;
    return match?.name ?? 'All groups';
  }

  Future<void> _pick(BuildContext context) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _GroupPickerSheet(
        groups: groups,
        selected: selected,
        countFor: countFor,
      ),
    );
    if (chosen != null) onSelect(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isFiltered = selected != 'all';

    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _pick(context),
            borderRadius: AppRadius.pillAll,
            child: Container(
              height: AppSize.buttonHeightSm + 4,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.card),
              decoration: BoxDecoration(
                color: isFiltered ? tokens.primarySoft : tokens.surfaceSoft,
                borderRadius: AppRadius.pillAll,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list,
                    size: AppSize.iconRow,
                    color: isFiltered ? context.colors.primary : tokens.muted,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _labelFor(context),
                      style: context.text.labelMedium?.copyWith(
                        color: isFiltered ? tokens.primaryStrong : tokens.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.expand_more,
                    size: AppSize.iconRow,
                    color: isFiltered ? context.colors.primary : tokens.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isFiltered) ...[
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            onPressed: () => onSelect('all'),
            icon: const Icon(Icons.close),
            iconSize: AppSize.iconRow,
            tooltip: 'Clear group filter',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }
}

/// The picker itself — searchable once the list is long enough to need it.
class _GroupPickerSheet extends StatefulWidget {
  const _GroupPickerSheet({
    required this.groups,
    required this.selected,
    required this.countFor,
  });

  final List<ProfessionalGroup> groups;
  final String selected;
  final int Function(int groupId) countFor;

  @override
  State<_GroupPickerSheet> createState() => _GroupPickerSheetState();
}

class _GroupPickerSheetState extends State<_GroupPickerSheet> {
  final _query = TextEditingController();

  /// Below this many groups a search field is more clutter than help.
  static const _searchThreshold = 8;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = _query.text.trim().toLowerCase();
    final visible = term.isEmpty
        ? widget.groups
        : widget.groups
            .where((g) => g.name.toLowerCase().contains(term))
            .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.sm,
                AppSpacing.screen,
                AppSpacing.sm,
              ),
              child: Text('Filter by group', style: context.text.titleMedium),
            ),
            if (widget.groups.length >= _searchThreshold)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  0,
                  AppSpacing.screen,
                  AppSpacing.sm,
                ),
                child: TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search groups...',
                    prefixIcon: Icon(Icons.search, size: AppSize.iconRow),
                  ),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  RadioGroup<String>(
                    groupValue: widget.selected,
                    onChanged: (value) =>
                        Navigator.of(context).pop(value ?? 'all'),
                    child: Column(
                      children: [
                        const RadioListTile<String>(
                          value: 'all',
                          title: Text('All groups'),
                        ),
                        for (final group in visible)
                          RadioListTile<String>(
                            value: '${group.id}',
                            title: Text(group.name),
                            subtitle: Text(
                              '${widget.countFor(group.id)} client'
                              '${widget.countFor(group.id) == 1 ? '' : 's'}',
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (visible.isEmpty && term.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.screen),
                      child: EmptyState(message: 'No groups match that search.'),
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
