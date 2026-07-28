import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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

  Future<void> addToCalendar(ClientMeetingRecord meeting) async {
    try {
      final bytes =
          await ref.read(clientApiProvider).downloadMeetingCalendarInvite(meeting.id);
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/reproot-meeting-${meeting.id}.ics');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/calendar')],
          subject: meeting.title,
          text: 'Add this RepRoot meeting to your mobile calendar.',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The calendar invite could not be opened.')),
      );
    }
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
                      if (meeting.status == 'scheduled')
                        TextButton.icon(
                          onPressed: () => addToCalendar(meeting),
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: const Text('Add to calendar'),
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
