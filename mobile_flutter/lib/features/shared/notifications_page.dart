import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
          ? await ref.read(professionalAuthApiProvider).getNotifications()
          : await ref.read(clientApiProvider).getNotifications();
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifications'),
      actions: [TextButton(onPressed: readAll, child: const Text('Read all'))],
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
          ? ListView(
              children: [
                Padding(padding: const EdgeInsets.all(24), child: Text(error)),
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
                  trailing: Text(item.category),
                );
              },
            ),
    ),
  );
}
