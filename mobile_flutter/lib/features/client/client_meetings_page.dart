import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/api/client_api.dart';
import '../../core/api/models/notification_models.dart';
import '../../shared/widgets/app_widgets.dart';

/// "yyyy-MM-dd" for the slots endpoint's date params.
final _isoDay = DateFormat('yyyy-MM-dd');

/// The only two lengths the backend books a video meeting for.
const _requestDurations = [15, 30];

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

  /// Ask for a time on the professional's calendar. The request lands as
  /// `pending_approval` until they accept it — the same flow as the web's
  /// "Request a Meeting" panel.
  Future<void> requestMeeting() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _RequestMeetingSheet(),
    );
    if (sent != true) return;
    await load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Meeting request sent. It stays pending until your professional accepts it.',
          ),
        ),
      );
    }
  }

  Future<void> join(String link) async {
    final uri = Uri.tryParse(link);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> addToCalendar(ClientMeetingRecord meeting) async {
    try {
      final bytes = await ref
          .read(clientApiProvider)
          .downloadMeetingCalendarInvite(meeting.id);
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
        const SnackBar(
          content: Text('The calendar invite could not be opened.'),
        ),
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
                  if (meeting.status == 'pending_approval')
                    Text(
                      'Waiting for your professional to respond',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
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
      appBar: AppBar(
        title: const Text('Meetings'),
        actions: [
          TextButton.icon(
            onPressed: requestMeeting,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Request'),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: load, child: content),
    );
  }
}

/// "Request a Meeting" — date, length, title, notes, and one of the
/// professional's open slots for that date, posted to
/// /client/scheduling/meeting-requests/.
class _RequestMeetingSheet extends ConsumerStatefulWidget {
  const _RequestMeetingSheet();

  @override
  ConsumerState<_RequestMeetingSheet> createState() =>
      _RequestMeetingSheetState();
}

class _RequestMeetingSheetState extends ConsumerState<_RequestMeetingSheet> {
  final titleController = TextEditingController(text: 'Check-in meeting');
  final notesController = TextEditingController();

  late DateTime date;
  int duration = 30;
  List<String> slots = [];
  String selectedSlot = '';
  String timezone = '';
  bool availabilityConfigured = true;
  bool loadingSlots = true;
  bool sending = false;
  String message = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    date = DateTime(now.year, now.month, now.day);
    loadSlots();
  }

  @override
  void dispose() {
    titleController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> loadSlots() async {
    setState(() {
      loadingSlots = true;
      selectedSlot = '';
      slots = [];
    });
    final iso = _isoDay.format(date);
    try {
      // Single-day range, matching the web: the picker asks about one date.
      final response = await ref
          .read(clientApiProvider)
          .getSchedulingSlots(start: iso, end: iso, durationMinutes: duration);
      if (!mounted) return;
      setState(() {
        slots = response.slots[iso] ?? [];
        timezone = response.timezone;
        availabilityConfigured = response.availabilityConfigured;
        loadingSlots = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loadingSlots = false;
        message = error is ApiException
            ? error.message
            : 'Could not load available times.';
      });
    }
  }

  Future<void> send() async {
    if (selectedSlot.isEmpty) {
      setState(() => message = 'Choose an available time first.');
      return;
    }
    setState(() {
      sending = true;
      message = '';
    });
    try {
      await ref
          .read(clientApiProvider)
          .requestMeeting(
            start: selectedSlot,
            durationMinutes: duration,
            title: titleController.text.trim().isEmpty
                ? 'Check-in meeting'
                : titleController.text.trim(),
            notes: notesController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        sending = false;
        message = error is ApiException
            ? error.message
            : 'Could not send the meeting request.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Request a meeting',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('Date: ${DateFormat.yMMMEd().format(date)}'),
                ),
                TextButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: DateTime(now.year + 1),
                    );
                    if (picked == null) return;
                    setState(() => date = picked);
                    await loadSlots();
                  },
                  child: const Text('Change'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AppSegmentedFilter<int>(
              value: duration,
              options: [
                for (final minutes in _requestDurations)
                  (minutes, '$minutes minutes'),
              ],
              onChanged: (value) {
                setState(() => duration = value);
                loadSlots();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              maxLength: 180,
              decoration: const InputDecoration(
                labelText: 'Meeting title',
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesController,
              minLines: 2,
              maxLines: 3,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Notes for your professional',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              timezone.isEmpty
                  ? 'Available times'
                  : 'Available times ($timezone)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (loadingSlots)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (slots.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final slot in slots)
                    ChoiceChip(
                      label: Text(
                        DateFormat.jm().format(DateTime.parse(slot).toLocal()),
                      ),
                      selected: selectedSlot == slot,
                      onSelected: (_) => setState(() => selectedSlot = slot),
                    ),
                ],
              )
            else
              Text(
                availabilityConfigured
                    ? 'No available times on this date. Try another date.'
                    : 'Your professional has not added meeting availability yet. '
                          'Please ask them to update their availability before scheduling.',
              ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: sending || selectedSlot.isEmpty ? null : send,
              child: Text(sending ? 'Sending…' : 'Send request'),
            ),
          ],
        ),
      ),
    );
  }
}
