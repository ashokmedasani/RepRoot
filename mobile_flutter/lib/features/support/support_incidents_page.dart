import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/client_api.dart';
import '../../core/api/models/support_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import '../professional/professional_format.dart';

enum SupportRole { professional, client }

/// Help & Support — one screen for both roles, as in the Ionic app.
/// The professional and client endpoints return the same shape; only the path
/// prefix and auth scheme differ, so the role just picks the API.
/// Replica of mobile/src/app/pages/shared/support-incidents.page.ts.
class SupportIncidentsPage extends ConsumerStatefulWidget {
  const SupportIncidentsPage({super.key, required this.role});

  final SupportRole role;

  @override
  ConsumerState<SupportIncidentsPage> createState() =>
      _SupportIncidentsPageState();
}

class _SupportIncidentsPageState extends ConsumerState<SupportIncidentsPage> {
  List<SupportIncident> _incidents = [];
  int _activeCount = 0;
  int _activeLimit = 3;
  bool _loading = true;
  bool _isSubmitting = false;
  String _message = '';
  bool _messageIsError = false;

  String _category = SupportCategory.feedback;
  final _subject = TextEditingController();
  final _description = TextEditingController();
  XFile? _screenshot;

  final Map<String, TextEditingController> _followUps = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    for (final c in _followUps.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canCreate => _activeCount < _activeLimit;

  Future<SupportListResponse> _fetch() =>
      widget.role == SupportRole.professional
      ? ref.read(professionalAuthApiProvider).getSupportIncidents()
      : ref.read(clientApiProvider).getSupportIncidents();

  Future<void> _load() async {
    try {
      final response = await _fetch();
      if (!mounted) return;
      setState(() {
        _incidents = response.incidents;
        _activeCount = response.activeCount;
        _activeLimit = response.activeLimit;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _setMessage('Support requests could not be loaded.', true);
    }
  }

  void _setMessage(String text, bool isError) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = isError;
    });
  }

  Future<void> _pickScreenshot() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1400,
      imageQuality: 85,
    );
    if (picked != null) setState(() => _screenshot = picked);
  }

  Future<void> _submit() async {
    if (_subject.text.trim().isEmpty ||
        _description.text.trim().isEmpty ||
        !_canCreate ||
        _isSubmitting) {
      _setMessage('Add a subject and description first.', true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      if (widget.role == SupportRole.professional) {
        await ref
            .read(professionalAuthApiProvider)
            .createSupportIncident(
              category: _category,
              subject: _subject.text.trim(),
              description: _description.text.trim(),
              screenshotPath: _screenshot?.path,
              screenshotName: _screenshot?.name,
            );
      } else {
        await ref
            .read(clientApiProvider)
            .createSupportIncident(
              category: _category,
              subject: _subject.text.trim(),
              description: _description.text.trim(),
              screenshotPath: _screenshot?.path,
              screenshotName: _screenshot?.name,
            );
      }
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _category = SupportCategory.feedback;
        _subject.clear();
        _description.clear();
        _screenshot = null;
      });
      _setMessage('Support request submitted.', false);
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _setMessage(error.message, true);
    }
  }

  Future<void> _act(
    SupportIncident incident,
    String action, {
    String body = '',
  }) async {
    try {
      if (widget.role == SupportRole.professional) {
        await ref
            .read(professionalAuthApiProvider)
            .actOnSupportIncident(incident.incidentId, action, body: body);
      } else {
        await ref
            .read(clientApiProvider)
            .actOnSupportIncident(incident.incidentId, action, body: body);
      }
      _followUps[incident.incidentId]?.clear();
      _setMessage(
        action == 'reopen' ? 'Request reopened.' : 'Reply sent.',
        false,
      );
      await _load();
    } on ApiException catch (error) {
      _setMessage(error.message, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final backRoute = widget.role == SupportRole.professional
        ? Routes.professionalMore
        : Routes.clientMore;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Help and Support')),
        body: const PagePad(
          children: [SkeletonBox(height: 200), SkeletonBox(height: 100)],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help and Support'),
        leading: BackButton(onPressed: () => context.go(backRoute)),
      ),
      body: PagePad(
        onRefresh: _load,
        children: [
          if (_message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AppCard(
                color: (_messageIsError ? context.colors.error : tokens.success)
                    .withValues(alpha: 0.08),
                child: Text(
                  _message,
                  style: context.text.bodySmall?.copyWith(
                    color: _messageIsError
                        ? context.colors.error
                        : tokens.success,
                  ),
                ),
              ),
            ),

          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Report a bug or send feedback',
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Support requests are tracked here. You can have up to '
                  '$_activeLimit active requests.',
                  style: context.text.bodySmall,
                ),
                if (!_canCreate) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.12),
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Text(
                      'You have reached the $_activeLimit-request limit. New '
                      'requests are available after one is resolved or closed.',
                      style: context.text.bodySmall?.copyWith(
                        color: tokens.accent,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Request type'),
                  items: SupportCategory.all
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(SupportCategory.label(c)),
                        ),
                      )
                      .toList(),
                  onChanged: _canCreate
                      ? (v) => setState(
                          () => _category = v ?? SupportCategory.feedback,
                        )
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _subject,
                  enabled: _canCreate,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Subject'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _description,
                  enabled: _canCreate,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _canCreate ? _pickScreenshot : null,
                      icon: const Icon(
                        Icons.image_outlined,
                        size: AppSize.iconRow,
                      ),
                      label: const Text('Screenshot'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, AppSize.buttonHeightSm),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _screenshot?.name ?? 'Optional',
                        style: context.text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_screenshot != null)
                      IconButton(
                        onPressed: () => setState(() => _screenshot = null),
                        icon: const Icon(Icons.close),
                        iconSize: AppSize.iconRow,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Remove',
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _canCreate && !_isSubmitting ? _submit : null,
                  child: Text(
                    _isSubmitting ? 'Submitting…' : 'Submit support request',
                  ),
                ),
              ],
            ),
          ),

          SectionHeader(title: 'Your requests (${_incidents.length})'),
          if (_incidents.isEmpty)
            const EmptyState(
              compact: false,
              icon: Icons.support_agent_outlined,
              message: 'No support requests yet.',
            )
          else
            for (final incident in _incidents) _incidentCard(incident),
        ],
      ),
    );
  }

  Widget _incidentCard(SupportIncident incident) {
    final tokens = context.tokens;
    _followUps.putIfAbsent(incident.incidentId, () => TextEditingController());

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    incident.incidentId,
                    style: context.text.labelMedium?.copyWith(
                      color: tokens.muted,
                    ),
                  ),
                ),
                StatusPill(
                  label: SupportStatus.label(incident.status),
                  tone: incident.needsReply
                      ? PillTone.warn
                      : incident.isFinished
                      ? PillTone.good
                      : PillTone.info,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(incident.subject, style: context.text.titleSmall),
            const SizedBox(height: 2),
            Text(
              '${SupportCategory.label(incident.category)} · ${shortDate(incident.createdAt)}',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(incident.description, style: context.text.bodySmall),

            if (incident.messages.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              for (final message in incident.messages)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: message.isSupport
                          ? tokens.primarySoft
                          : tokens.surfaceSoft,
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${message.authorName.isEmpty ? (message.isSupport ? 'Support' : 'You') : message.authorName} · ${dateTimeLabel(message.createdAt)}',
                          style: context.text.labelSmall?.copyWith(
                            color: tokens.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(message.body, style: context.text.bodySmall),
                      ],
                    ),
                  ),
                ),
            ],

            if (incident.resolutionNote.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Resolution: ${incident.resolutionNote}',
                style: context.text.bodySmall?.copyWith(color: tokens.success),
              ),
            ],

            if (incident.needsReply) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _followUps[incident.incidentId],
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reply to support',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                onPressed: () {
                  final body = _followUps[incident.incidentId]!.text.trim();
                  if (body.isEmpty) return;
                  _act(incident, 'follow_up', body: body);
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppSize.buttonHeightSm),
                ),
                child: const Text('Send reply'),
              ),
            ],

            if (incident.isFinished) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                onPressed: () => _act(incident, 'reopen'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSize.buttonHeightSm),
                ),
                child: const Text('Reopen'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
