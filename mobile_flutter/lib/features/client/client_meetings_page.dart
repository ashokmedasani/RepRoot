import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/client_api.dart';
import '../../core/api/models/notification_models.dart';

class ClientMeetingsPage extends ConsumerStatefulWidget {
  const ClientMeetingsPage({super.key});

  @override
  ConsumerState<ClientMeetingsPage> createState() => _ClientMeetingsPageState();
}

class _ClientMeetingsPageState extends ConsumerState<ClientMeetingsPage> {
  List<ClientMeetingRecord> meetings = [];
  bool loading = true;
  String message = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await ref.read(clientApiProvider).getMeetings();
      if (mounted) {
        setState(() {
          meetings = rows;
          loading = false;
          message = '';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          loading = false;
          message = error.toString();
        });
      }
    }
  }

  Future<void> respond(ClientMeetingRecord meeting, String status) async {
    await ref.read(clientApiProvider).respondToMeeting(meeting.id, status);
    await load();
  }

  Future<void> join(String link) async {
    final uri = Uri.tryParse(link);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (message.isNotEmpty) {
      content = ListView(
        children: [
          Padding(padding: const EdgeInsets.all(24), child: Text(message)),
        ],
      );
    } else {
      content = ListView.builder(
        itemCount: meetings.length,
        itemBuilder: (context, index) {
          final meeting = meetings[index];
          return Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meeting.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (meeting.startAt != null)
                    Text(
                      DateFormat.yMMMd().add_jm().format(
                        meeting.startAt!.toLocal(),
                      ),
                    ),
                  if (meeting.notes.isNotEmpty) Text(meeting.notes),
                  Text('Response: ${meeting.myResponseStatus}'),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (meeting.status == 'scheduled' &&
                          meeting.myResponseStatus != 'accepted')
                        FilledButton(
                          onPressed: () => respond(meeting, 'accepted'),
                          child: const Text('Accept'),
                        ),
                      if (meeting.status == 'scheduled' &&
                          meeting.myResponseStatus != 'declined')
                        OutlinedButton(
                          onPressed: () => respond(meeting, 'declined'),
                          child: const Text('Decline'),
                        ),
                      if (meeting.meetingUrl.isNotEmpty)
                        TextButton(
                          onPressed: () => join(meeting.meetingUrl),
                          child: const Text('Join meeting'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Meetings')),
      body: RefreshIndicator(onRefresh: load, child: content),
    );
  }
}
