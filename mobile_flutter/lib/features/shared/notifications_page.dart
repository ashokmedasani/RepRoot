import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/client_api.dart';
import '../../core/api/models/notification_models.dart';
import '../../core/api/professional_auth_api.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key, required this.professional});
  final bool professional;
  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  NotificationInbox? inbox;
  String error = '';
  bool loading = true;
  String? category;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final value = widget.professional
          ? await ref.read(professionalAuthApiProvider).getNotifications(category: category)
          : await ref.read(clientApiProvider).getNotifications(category: category);
      if (mounted) {
        setState(() {
          inbox = value;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> read(AppNotificationRecord item) async {
    if (widget.professional) {
      await ref
          .read(professionalAuthApiProvider)
          .markNotificationRead(id: item.id);
    } else {
      await ref.read(clientApiProvider).markNotificationRead(id: item.id);
    }
    await load();
  }

  Future<void> readAll() async {
    if (widget.professional) {
      await ref.read(professionalAuthApiProvider).markNotificationRead();
    } else {
      await ref.read(clientApiProvider).markNotificationRead();
    }
    await load();
  }

  /// Deletes the whole inbox rather than just marking it read.
  ///
  /// Professional-only for now: the client API has no matching endpoint, so
  /// the action is hidden rather than offered and then failing.
  Future<void> clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text(
          'Every notification is deleted, not just marked read. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result =
          await ref.read(professionalAuthApiProvider).clearNotifications();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.deletedCount == 1
                ? '1 notification cleared.'
                : '${result.deletedCount} notifications cleared.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not clear notifications.')),
      );
    }
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifications'),
      actions: [
        IconButton(
          onPressed: () => context.push(
            widget.professional
                ? '/professional/tabs/more/notifications/preferences'
                : '/client/tabs/more/notifications/preferences',
          ),
          icon: const Icon(Icons.tune),
          tooltip: 'Preferences',
        ),
        TextButton(onPressed: readAll, child: const Text('Read all')),
        if (widget.professional)
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') clearAll();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'clear', child: Text('Clear all')),
            ],
          ),
      ],
    ),
    body: Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: category == null,
                  onSelected: (_) {
                    setState(() => category = null);
                    load();
                  },
                ),
              ),
              for (final c in NotificationCategory.all)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(NotificationCategory.label(c)),
                    selected: category == c,
                    onSelected: (_) {
                      setState(() => category = c);
                      load();
                    },
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error.isNotEmpty
                ? ListView(
                    children: [
                      Padding(padding: const EdgeInsets.all(24), child: Text(error)),
                    ],
                  )
                : (inbox?.notifications.isEmpty ?? true)
                ? ListView(
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No notifications here.'),
                      ),
                    ],
                  )
                : ListView.separated(
                    itemCount: inbox?.notifications.length ?? 0,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = inbox!.notifications[index];
                      return ListTile(
                        onTap: () => read(item),
                        leading: Icon(
                          item.isRead
                              ? Icons.notifications_none
                              : Icons.notifications_active,
                        ),
                        title: Text(
                          item.title,
                          style: TextStyle(
                            fontWeight: item.isRead
                                ? FontWeight.w500
                                : FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(item.body),
                        trailing: Text(NotificationCategory.label(item.category)),
                      );
                    },
                  ),
          ),
        ),
      ],
    ),
  );
}
