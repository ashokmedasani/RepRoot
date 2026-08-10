import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/api/plan_lock_api.dart';
import '../../core/api/scheduling_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

enum FormsTab { forms, groups }

/// Form Requests panel sub-tab — mirrors the web's `SubmissionView`.
enum SubmissionView { pending, approved, deleted }

/// Forms & Groups — the lead form builder, groups, and lead requests.
/// Replica of mobile/src/app/pages/professional/forms-groups/professional-forms-groups.page.ts.
class ProfessionalFormsGroupsPage extends ConsumerStatefulWidget {
  const ProfessionalFormsGroupsPage({super.key, this.initialTab});

  /// From ?tab=groups|requests, as the Manage hub links deep into a tab.
  final String? initialTab;

  @override
  ConsumerState<ProfessionalFormsGroupsPage> createState() =>
      _ProfessionalFormsGroupsPageState();
}

/// Mutable field row for the builder — DynamicField is immutable.
class _DraftField {
  _DraftField({
    this.label = '',
    this.fieldType = DynamicFieldType.shortText,
    this.required = false,
    this.placeholder = '',
    this.helpText = '',
    List<String>? options,
  }) : options = options ?? [];

  String label;
  String fieldType;
  bool required;
  String placeholder;
  String helpText;
  List<String> options;

  DynamicField toField() => DynamicField(
    label: label.trim(),
    fieldType: fieldType,
    required: required,
    placeholder: placeholder,
    helpText: helpText,
    options: DynamicFieldType.withOptions.contains(fieldType)
        ? options
        : const [],
  );

  static _DraftField from(DynamicField field) => _DraftField(
    label: field.label,
    fieldType: field.fieldType,
    required: field.required,
    placeholder: field.placeholder,
    helpText: field.helpText,
    options: [...field.options],
  );
}

class _ProfessionalFormsGroupsPageState
    extends ConsumerState<ProfessionalFormsGroupsPage> {
  FormsTab _tab = FormsTab.forms;
  FormsGroupsOverview? _overview;
  PlanLockStatus _lockStatus = const PlanLockStatus();
  String _message = '';
  bool _loading = true;

  // Lead form editor
  final _formTitle = TextEditingController();
  List<_DraftField> _customFields = [];

  /// Which of the professional's (possibly several) lead forms the Forms tab
  /// is showing — mirrors the web's `selectedLeadFormId`.
  int? _selectedLeadFormId;

  /// The form id `_openFormEditor()` is currently editing — null means the
  /// editor is creating a brand-new form rather than editing an existing one.
  int? _editingFormId;

  /// Mobile-only addition to the "Viewing form" dropdown (the web has no
  /// equivalent): shows every form's requests together, tagged by form.
  /// Consolidates what an earlier pass built as a separate chip-filter row.
  bool _viewingAllForms = false;

  // Introductory-meeting requests, shared across every lead form (the
  // backend does not scope this list by form — see forms_groups_api.dart).
  List<LeadMeetingRequest> _meetingRequests = [];
  final Map<int, TextEditingController> _followupDrafts = {};
  int _reviewingMeetingRequestId = 0;
  int _sendingFollowupId = 0;

  // Mirrors the web create-form wizard's `hasAvailability` check
  // (professional-lead-form-create.component.ts): the intro-meeting toggle
  // cannot be turned on until at least one weekly availability window is
  // active, matching the backend guard in ProfessionalLeadFormMeetingView.
  bool _hasAvailability = false;

  // Form Requests panel
  SubmissionView _submissionView = SubmissionView.pending;
  String _monthFilter = '';
  late final List<({String value, String label})> _monthOptions =
      _createLastSixMonthOptions();

  // Group form
  bool _showGroupForm = false;
  bool _isSavingGroup = false;
  final _groupName = TextEditingController();
  final _groupDescription = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = switch (widget.initialTab) {
      'groups' => FormsTab.groups,
      // 'requests' used to be its own tab; the Form Requests panel now lives
      // inside the Lead Forms tab, so route it there instead.
      'requests' => FormsTab.forms,
      _ => FormsTab.forms,
    };
    _load();
  }

  @override
  void dispose() {
    _formTitle.dispose();
    _groupName.dispose();
    _groupDescription.dispose();
    for (final controller in _followupDrafts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final overview = await ref.read(formsGroupsApiProvider).getOverview();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _message = '';
        _loading = false;
        // If the previously-selected form was deleted (or nothing was
        // selected yet), fall back to the professional's default form —
        // mirrors the web's loadOverview() reconciliation.
        final stillExists = overview.leadForms.any(
          (form) => form.id == _selectedLeadFormId,
        );
        if (!stillExists) {
          _selectedLeadFormId = overview.leadForm?.id;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not load forms and groups.';
        _loading = false;
      });
    }
    await _loadLockStatus();
    await _loadMeetingRequests();
    await _loadAvailabilityStatus();
  }

  Future<void> _loadAvailabilityStatus() async {
    try {
      final windows = await ref
          .read(schedulingApiProvider)
          .listAvailabilityWindows();
      if (mounted) {
        setState(() => _hasAvailability = windows.any((w) => w.isActive));
      }
    } catch (_) {
      // Leave the switch enabled rather than block on a failed check — the
      // backend still enforces the rule and reports it via the toast.
      if (mounted) setState(() => _hasAvailability = true);
    }
  }

  Future<void> _loadMeetingRequests() async {
    try {
      final requests = await ref
          .read(formsGroupsApiProvider)
          .getLeadMeetingRequests();
      if (mounted) setState(() => _meetingRequests = requests);
    } catch (error, stackTrace) {
      debugPrint(
        'Lead meeting requests load failed '
        '(${error.runtimeType})\n$stackTrace',
      );
    }
  }

  List<({String value, String label})> _createLastSixMonthOptions() {
    final now = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return List.generate(6, (index) {
      final month = DateTime(now.year, now.month - index, 1);
      final value = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      return (value: value, label: '${months[month.month - 1]} ${month.year}');
    });
  }

  Future<void> _loadLockStatus() async {
    try {
      final status = await ref.read(planLockApiProvider).getLockStatus();
      if (mounted) setState(() => _lockStatus = status);
    } catch (error, stackTrace) {
      debugPrint(
        'Plan lock status load failed (${error.runtimeType})\n$stackTrace',
      );
    }
  }

  // ----- plan-limit lock ordering (groups) -----

  PlanLockSection get _groupLock =>
      _lockStatus.section(PlanLockModelKey.groups);

  /// Until the lock-status call lands (or if it fails) there is no split to
  /// honour, so groups render flat and drag is disabled.
  bool get _groupLockLoaded =>
      _lockStatus.sections.containsKey(PlanLockModelKey.groups);

  /// Order comes from the lock status' active_ids, never a separate local
  /// list, so a drag cannot drift out of sync with the stored order.
  List<ProfessionalGroup> get _activeGroups {
    final groups = _overview?.groups ?? const <ProfessionalGroup>[];
    if (!_groupLockLoaded) return groups;
    final byId = {for (final group in groups) group.id: group};
    return [
      for (final id in _groupLock.activeIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  List<ProfessionalGroup> get _lockedGroups {
    if (!_groupLockLoaded) return const [];
    final lockedIds = _groupLock.lockedIds.toSet();
    return (_overview?.groups ?? const <ProfessionalGroup>[])
        .where((group) => lockedIds.contains(group.id))
        .toList();
  }

  bool get _canReorderGroups => _groupLockLoaded && _activeGroups.length > 1;

  /// Locked groups are never in the payload — the backend rejects any order
  /// that includes one (plan_lock_status.reorder_active_items).
  // onReorderItem already adjusts newIndex for the removed row.
  Future<void> _reorderGroups(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    final previous = _lockStatus;
    final orderedIds = [..._groupLock.activeIds];
    if (oldIndex < 0 || oldIndex >= orderedIds.length) return;
    orderedIds.insert(newIndex, orderedIds.removeAt(oldIndex));

    // Optimistic so the row stays where it was dropped during the round trip.
    setState(() {
      _lockStatus = _lockStatus.withSection(
        PlanLockModelKey.groups,
        _groupLock.copyWith(activeIds: orderedIds),
      );
    });

    try {
      final status = await ref
          .read(planLockApiProvider)
          .reorder(PlanLockModelKey.groups, orderedIds);
      if (mounted) setState(() => _lockStatus = status);
    } catch (error) {
      if (!mounted) return;
      setState(() => _lockStatus = previous);
      _toast(
        error is ApiException ? error.message : 'Could not reorder groups.',
      );
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(milliseconds: 2400),
      ),
    );
  }

  Future<void> _shareLink(String url, String title) async {
    if (url.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(title: title, uri: Uri.parse(url)),
      );
    } catch (_) {
      // Fall back to the clipboard if no share target handles it.
      await Clipboard.setData(ClipboardData(text: url));
      _toast('Link copied to clipboard.');
    }
  }

  // ----- lead form -----

  bool _formMandatory = false;
  bool _togglingStatus = false;
  bool _togglingMeeting = false;

  /// Every lead form the professional has (plan-gated by max_lead_forms).
  List<LeadForm> get _leadForms => _overview?.leadForms ?? const <LeadForm>[];

  /// "All forms" is only a real mode when there is more than one form to
  /// combine. Without this the view would go blank if the professional was
  /// in All-forms mode and then deleted their way back down to one form.
  bool get _showingAllForms => _viewingAllForms && _leadForms.length > 1;

  /// The form the Forms tab is currently showing. Falls back to the
  /// overview's default form (or the first form) so this never goes blank
  /// just because the id in [_selectedLeadFormId] hasn't caught up yet.
  LeadForm? get _selectedLeadForm {
    final forms = _leadForms;
    if (forms.isEmpty) return _overview?.leadForm;
    final id = _selectedLeadFormId;
    if (id != null) {
      final match = forms.where((form) => form.id == id).firstOrNull;
      if (match != null) return match;
    }
    return _overview?.leadForm ?? forms.first;
  }

  /// `null` selects "All forms" (mobile-only). Otherwise picks a specific
  /// lead form for both the lead panel and the Form Requests panel below it.
  void _selectLeadForm(int? formId) {
    if (formId == null) {
      if (_viewingAllForms) return;
      setState(() => _viewingAllForms = true);
      return;
    }
    if (!_viewingAllForms && formId == _selectedLeadFormId) return;
    setState(() {
      _viewingAllForms = false;
      _selectedLeadFormId = formId;
    });
  }

  void _startFormEdit() {
    final leadForm = _selectedLeadForm;
    _editingFormId = leadForm?.id;
    _formTitle.text = leadForm?.title ?? 'Training Enquiry';
    _formMandatory = leadForm?.isMandatory ?? false;
    // Core fields are built in and not editable — only custom ones show.
    _customFields = (leadForm?.fields ?? [])
        .where((field) => !field.isCore)
        .map(_DraftField.from)
        .toList();
    _openFormEditor();
  }

  /// Opens the same editor as [_startFormEdit] but blank and untied to any
  /// existing form id, so saving creates a new lead form instead.
  void _startFormCreate() {
    _editingFormId = null;
    _formTitle.text = '';
    _formMandatory = false;
    _customFields = [];
    _openFormEditor();
  }

  Future<bool> _saveForm() async {
    final creating = _editingFormId == null;
    try {
      final saved = await ref
          .read(formsGroupsApiProvider)
          .saveLeadForm(
            _formTitle.text.trim(),
            _customFields
                .where((field) => field.label.trim().isNotEmpty)
                .map((field) => field.toField())
                .toList(),
            isMandatory: _formMandatory,
            formId: _editingFormId,
          );
      if (!mounted) return false;
      setState(() {
        _viewingAllForms = false;
        _selectedLeadFormId = saved.id;
      });
      await _load();
      _toast(creating ? 'Form created.' : 'Form saved.');
      return true;
    } on ApiException catch (error) {
      if (!mounted) return false;
      setState(() => _message = error.message);
      _toast(error.message);
      return false;
    }
  }

  Future<void> _toggleLeadFormActive(bool active) async {
    final formId = _selectedLeadForm?.id;
    if (_togglingStatus || formId == null) return;
    setState(() => _togglingStatus = true);
    try {
      await ref
          .read(formsGroupsApiProvider)
          .updateLeadFormStatus(active, formId: formId);
      await _load();
      _toast(active ? 'Form enabled.' : 'Form disabled.');
    } on ApiException catch (error) {
      _toast(error.message);
    }
    if (mounted) setState(() => _togglingStatus = false);
  }

  Future<void> _toggleIntroMeeting(bool enabled) async {
    final formId = _selectedLeadForm?.id;
    if (_togglingMeeting) return;
    setState(() => _togglingMeeting = true);
    try {
      await ref
          .read(formsGroupsApiProvider)
          .saveLeadMeetingSettings(
            introductoryMeetingEnabled: enabled,
            formId: formId,
          );
      await _load();
      _toast(enabled ? 'Intro meetings enabled.' : 'Intro meetings disabled.');
    } on ApiException catch (error) {
      _toast(error.message);
    }
    if (mounted) setState(() => _togglingMeeting = false);
  }

  Future<void> _editMeetingSettings(LeadForm leadForm) async {
    final titleCtrl = TextEditingController(
      text: leadForm.introductoryMeetingTitle,
    );
    final durationCtrl = TextEditingController(
      text: '${leadForm.introductoryMeetingDurationMinutes}',
    );
    final noticeCtrl = TextEditingController(
      text: '${leadForm.introductoryMeetingMinNoticeHours}',
    );
    final advanceCtrl = TextEditingController(
      text: '${leadForm.introductoryMeetingMaxAdvanceDays}',
    );
    var requiresApproval = leadForm.introductoryMeetingRequiresApproval;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Meeting settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Meeting title'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duration (minutes)',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: noticeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minimum notice (hours)',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: advanceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max advance (days)',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Requires my approval'),
                  value: requiresApproval,
                  onChanged: (value) =>
                      setDialogState(() => requiresApproval = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => context.pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppSize.buttonHeightSm),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      try {
        await ref
            .read(formsGroupsApiProvider)
            .saveLeadMeetingSettings(
              introductoryMeetingTitle: titleCtrl.text.trim(),
              introductoryMeetingDurationMinutes:
                  int.tryParse(durationCtrl.text.trim()) ??
                  leadForm.introductoryMeetingDurationMinutes,
              introductoryMeetingMinNoticeHours:
                  int.tryParse(noticeCtrl.text.trim()) ??
                  leadForm.introductoryMeetingMinNoticeHours,
              introductoryMeetingMaxAdvanceDays:
                  int.tryParse(advanceCtrl.text.trim()) ??
                  leadForm.introductoryMeetingMaxAdvanceDays,
              introductoryMeetingRequiresApproval: requiresApproval,
              formId: leadForm.id,
            );
        await _load();
        _toast('Meeting settings saved.');
      } on ApiException catch (error) {
        _toast(error.message);
      }
    }
    titleCtrl.dispose();
    durationCtrl.dispose();
    noticeCtrl.dispose();
    advanceCtrl.dispose();
  }

  // ----- introductory meeting requests -----

  /// The backend doesn't scope meeting requests by lead form (see
  /// getLeadMeetingRequests()), so when a specific form is selected this
  /// matches on the form's title — the only signal the payload carries.
  List<LeadMeetingRequest> _meetingRequestsFor(LeadForm? form) {
    if (_showingAllForms || form == null) return _meetingRequests;
    return _meetingRequests
        .where((request) => request.formTitle == form.title)
        .toList();
  }

  List<LeadMeetingRequest> _upcomingMeetingsOf(
    List<LeadMeetingRequest> requests,
  ) {
    final now = DateTime.now();
    final upcoming =
        requests
            .where(
              (r) =>
                  r.isAccepted && (r.requestedStartDate?.isAfter(now) ?? false),
            )
            .toList()
          ..sort(
            (a, b) => (a.requestedStartDate ?? now).compareTo(
              b.requestedStartDate ?? now,
            ),
          );
    return upcoming.take(5).toList();
  }

  List<LeadMeetingRequest> _overdueMeetingsOf(
    List<LeadMeetingRequest> requests,
  ) {
    final now = DateTime.now();
    final overdue =
        requests
            .where(
              (r) =>
                  r.isAccepted &&
                  (r.requestedStartDate?.isBefore(now) ?? false),
            )
            .toList()
          ..sort(
            (a, b) => (b.requestedStartDate ?? now).compareTo(
              a.requestedStartDate ?? now,
            ),
          );
    return overdue.take(5).toList();
  }

  Future<void> _reviewMeetingRequest(
    LeadMeetingRequest request,
    String action,
  ) async {
    if (_reviewingMeetingRequestId != 0) return;
    setState(() => _reviewingMeetingRequestId = request.id);
    try {
      final result = await ref
          .read(formsGroupsApiProvider)
          .reviewLeadMeetingRequest(request.id, action);
      await _loadMeetingRequests();
      _toast(result.message);
    } on ApiException catch (error) {
      _toast(error.message);
    }
    if (mounted) setState(() => _reviewingMeetingRequestId = 0);
  }

  TextEditingController _followupControllerFor(int requestId) =>
      _followupDrafts.putIfAbsent(requestId, TextEditingController.new);

  Future<void> _sendMeetingFollowup(LeadMeetingRequest request) async {
    final message = _followupControllerFor(request.id).text.trim();
    if (message.isEmpty || _sendingFollowupId != 0) return;
    setState(() => _sendingFollowupId = request.id);
    try {
      final result = await ref
          .read(formsGroupsApiProvider)
          .reviewLeadMeetingRequest(
            request.id,
            'send_followup',
            trainerNote: message,
          );
      _followupControllerFor(request.id).clear();
      await _loadMeetingRequests();
      _toast(result.message);
    } on ApiException catch (error) {
      _toast(error.message);
    }
    if (mounted) setState(() => _sendingFollowupId = 0);
  }

  // ----- approval -----

  /// Opens the form-request detail — the applicant's submitted answers plus the
  /// create-client-access form — as a sheet, mirroring the web's
  /// professional-form-request-detail page. Approving without first seeing what
  /// was submitted was the gap this closes.
  Future<void> _openRequest(LeadSubmission submission) async {
    // Label the submitted answers using the form the applicant actually
    // filled in, not just whichever form happens to be selected — matters
    // once a professional has more than one lead form.
    final sourceForm = _leadForms
        .where((form) => form.id == submission.leadForm)
        .firstOrNull;
    final outcome = await showModalBottomSheet<_RequestOutcome>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FormRequestSheet(
        submission: submission,
        groups: _overview?.groups ?? const [],
        leadFormFields:
            sourceForm?.fields ?? _overview?.leadForm?.fields ?? const [],
      ),
    );

    if (outcome == null || !mounted) return;

    if (outcome.rejected) {
      await _deletePending(submission);
      return;
    }

    await _load();
    // The password is only shown once — surface it so it can be copied.
    if (mounted) await _showCredentials(outcome.username, outcome.password);
  }

  Future<void> _showCredentials(String username, String password) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Client created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share these one-time credentials. The client must change the '
              'password on first login.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            SelectableText(
              'Username: $username',
              style: context.text.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            SelectableText(
              'Password: $password',
              style: context.text.titleSmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '$username / $password'));
              context.pop();
              _toast('Credentials copied.');
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => context.pop(),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePending(LeadSubmission submission) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${submission.applicantName}?'),
        content: const Text('This enquiry will be removed from your requests.'),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(formsGroupsApiProvider).deletePendingForm(submission.id);
      await _load();
    } catch (_) {
      _toast('Could not delete the request.');
    }
  }

  // ----- groups -----

  Future<void> _createGroup() async {
    setState(() => _isSavingGroup = true);
    try {
      await ref
          .read(formsGroupsApiProvider)
          .createGroup(_groupName.text.trim(), _groupDescription.text.trim());
      if (!mounted) return;
      setState(() {
        _isSavingGroup = false;
        _showGroupForm = false;
        _groupName.clear();
        _groupDescription.clear();
      });
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSavingGroup = false;
        _message = error.message;
      });
    }
  }

  // ----- build -----

  /// Explains a section without permanently spending screen space on the
  /// explanation. Plan locking in particular needs a sentence of context the
  /// first time someone meets it, and never again afterwards.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forms and Groups'),
        leading: BackButton(
          onPressed: () => context.go(Routes.professionalManage),
        ),
      ),
      body: _loading
          ? const PagePad(
              children: [SkeletonBox(height: 44), SkeletonBox(height: 180)],
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    AppSpacing.sm,
                    AppSpacing.screen,
                    AppSpacing.sm,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<FormsTab>(
                      segments: [
                        ButtonSegment(
                          value: FormsTab.forms,
                          label: Text('Lead Forms'),
                        ),
                        ButtonSegment(
                          value: FormsTab.groups,
                          label: Text('Client Groups'),
                        ),
                      ],
                      selected: {_tab},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _tab = s.first),
                    ),
                  ),
                ),
                Expanded(
                  child: switch (_tab) {
                    FormsTab.forms => _formsTab(),
                    FormsTab.groups => _groupsTab(),
                  },
                ),
              ],
            ),
    );
  }

  /// Lead Forms workspace tab — a faithful structural port of the web's
  /// `forms` tab in professional-forms-groups.component.html: a toolbar
  /// (dropdown + counter/create), the selected form's lead panel (header,
  /// link, stats, read-only fields, edit action, meeting settings), and a
  /// separate Form Requests panel below it. Editing takes over the whole
  /// tab, matching the previous inline-editor pattern.
  Widget _formsTab() {
    final overview = _overview;
    final forms = _leadForms;
    final leadForm = _showingAllForms ? null : _selectedLeadForm;

    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
        if (forms.isEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "You haven't created a form yet.",
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Create your public lead form so people can enquire.',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _startFormCreate,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, AppSize.buttonHeightSm),
                  ),
                  child: const Text('Create Form'),
                ),
              ],
            ),
          )
        else ...[
          _leadFormToolbar(forms, overview),
          if (leadForm != null) _leadPanel(leadForm),
          const SizedBox(height: AppSpacing.md),
          _formRequestsPanel(forms),
        ],
      ],
    );
  }

  /// The `.lead-form-toolbar`. Stacked rather than side-by-side: the form
  /// switcher takes the full card width (titles are long, and sharing the
  /// row with the counter + Create Form squeezed it down to a few
  /// characters), with the plan counter and Create Form on the row beneath
  /// so the button lands in the same place no matter how many forms exist.
  ///
  /// With a single form the switcher is omitted entirely — "All forms" and
  /// that one form render the same screen, so it was a 48px field that
  /// could not change anything.
  Widget _leadFormToolbar(List<LeadForm> forms, FormsGroupsOverview? overview) {
    final maxForms = overview?.maxLeadForms ?? 0;
    final atLimit = overview?.atLeadFormLimit ?? false;
    final dropdownValue = _showingAllForms ? 0 : (_selectedLeadForm?.id ?? 0);
    final showSwitcher = forms.length > 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showSwitcher) ...[
              DropdownButtonFormField<int>(
                initialValue: dropdownValue,
                decoration: const InputDecoration(labelText: 'Viewing form'),
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: 0, child: Text('All forms')),
                  for (final form in forms)
                    DropdownMenuItem(
                      value: form.id,
                      child: Text(
                        '${form.title} (${form.isActive ? 'Active' : 'Disabled'})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) =>
                    _selectLeadForm(value == 0 ? null : value),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    atLimit
                        ? 'Form limit reached on your plan '
                              '(${forms.length} of ${maxForms > 0 ? maxForms : '—'}).'
                        : '${forms.length} form${forms.length == 1 ? '' : 's'}',
                    style: context.text.bodySmall?.copyWith(
                      color: atLimit
                          ? context.colors.error
                          : context.tokens.muted,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: atLimit ? null : _startFormCreate,
                  icon: const Icon(Icons.add, size: AppSize.iconRow),
                  label: const Text('Create Form'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, AppSize.buttonHeightSm),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The `.lead-panel` — header row (title + status line left, enable
  /// switch top-right) and, while active, the link box, stats, read-only
  /// fields summary, Edit Form action, and the meeting settings sub-section.
  Widget _leadPanel(LeadForm leadForm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PUBLIC ENQUIRY FORM',
                          style: context.text.labelSmall?.copyWith(
                            color: context.tokens.muted,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(leadForm.title, style: context.text.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          leadForm.isActive
                              ? 'People with the link can submit this form.'
                              : 'The public form is unavailable until you enable it.',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: leadForm.isActive,
                        onChanged: _togglingStatus
                            ? null
                            : _toggleLeadFormActive,
                      ),
                      Text(
                        leadForm.isActive ? 'Enabled' : 'Disabled',
                        style: context.text.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
              if (leadForm.isActive) ...[
                const SizedBox(height: AppSpacing.md),
                _formLinkBox(leadForm),
                const SizedBox(height: AppSpacing.md),
                _statsGrid(leadForm),
                const SizedBox(height: AppSpacing.md),
                _fieldsSummaryReadOnly(leadForm),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: _startFormEdit,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, AppSize.buttonHeightSm),
                  ),
                  child: const Text('Edit Form'),
                ),
              ],
            ],
          ),
        ),
        if (leadForm.isActive) ...[
          const SizedBox(height: AppSpacing.md),
          _meetingSettingsSection(leadForm),
        ],
      ],
    );
  }

  Widget _formLinkBox(LeadForm leadForm) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.tokens.surfaceSoft,
        borderRadius: AppRadius.tileAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Public Form Link',
            style: context.text.labelSmall?.copyWith(
              color: context.tokens.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  leadForm.publicLink,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton(
                onPressed: leadForm.publicLink.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: leadForm.publicLink),
                        );
                        _toast('Link copied.');
                      },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSize.buttonHeightSm),
                ),
                child: const Text('Copy Link'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Total / Pending / Approved / Deleted — scoped to this specific form
  /// (a useful mobile refinement; the web sums across every form).
  Widget _statsGrid(LeadForm leadForm) {
    final overview = _overview;
    final pending = _submissionsForForm(
      overview?.pendingForms ?? const [],
      leadForm.id,
    ).length;
    final approved = _submissionsForForm(
      overview?.approvedForms ?? const [],
      leadForm.id,
    ).length;
    final deleted = _submissionsForForm(
      overview?.deletedForms ?? const [],
      leadForm.id,
    ).length;
    final total = pending + approved + deleted;

    return KpiGrid(
      children: [
        KpiTile(label: 'Total Requests', value: '$total'),
        KpiTile(label: 'Pending', value: '$pending'),
        KpiTile(label: 'Approved', value: '$approved'),
        KpiTile(label: 'Deleted', value: '$deleted'),
      ],
    );
  }

  List<LeadSubmission> _submissionsForForm(
    List<LeadSubmission> submissions,
    int? formId,
  ) {
    if (formId == null) return submissions;
    return submissions
        .where((submission) => submission.leadForm == formId)
        .toList();
  }

  /// Compact **read-only** fields summary — first 3 field names with a
  /// "(Required)" suffix, plus a "N more fields" line. There is no inline
  /// field editing here; that only happens in the form editor.
  Widget _fieldsSummaryReadOnly(LeadForm leadForm) {
    final fields = leadForm.fields;
    final shown = fields.take(3).toList();
    final remaining = fields.length - shown.length;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.tokens.surfaceSoft,
        borderRadius: AppRadius.tileAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Form Fields', style: context.text.titleSmall),
              ),
              Text(
                '${fields.where((field) => field.required).length} required',
                style: context.text.bodySmall?.copyWith(
                  color: context.tokens.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (shown.isEmpty)
            Text('No fields yet.', style: context.text.bodySmall)
          else
            for (final field in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  '${field.label}${field.required ? ' (Required)' : ''}',
                  style: context.text.bodyMedium,
                ),
              ),
          if (remaining > 0)
            Text(
              '$remaining more field${remaining == 1 ? '' : 's'}',
              style: context.text.bodySmall?.copyWith(
                color: context.tokens.muted,
              ),
            ),
        ],
      ),
    );
  }

  /// Introductory Meeting Settings sub-section: its own eyebrow/heading/
  /// status/switch, then — while enabled — pending meeting requests, the
  /// rule grid, upcoming meetings, and overdue meetings with a follow-up
  /// message + send action, finishing with the edit/setup link.
  Widget _meetingSettingsSection(LeadForm leadForm) {
    final enabled = leadForm.introductoryMeetingEnabled;
    final requests = _meetingRequestsFor(leadForm);
    final pendingRequests = requests
        .where((request) => request.isPending)
        .toList();
    final upcoming = _upcomingMeetingsOf(requests);
    final overdue = _overdueMeetingsOf(requests);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AFTER FORM SUBMISSION',
                      style: context.text.labelSmall?.copyWith(
                        color: context.tokens.muted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Introductory Meeting Settings',
                      style: context.text.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      enabled
                          ? 'Applicants can request '
                                '${leadForm.introductoryMeetingTitle.isNotEmpty ? leadForm.introductoryMeetingTitle : 'an introductory meeting'}. '
                                'Every request requires your approval.'
                          : 'Applicants currently submit the form without receiving an '
                                'introductory-meeting option.',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: enabled,
                    onChanged:
                        _togglingMeeting || (!enabled && !_hasAvailability)
                        ? null
                        : _toggleIntroMeeting,
                  ),
                  Text(
                    enabled ? 'Enabled' : 'Disabled',
                    style: context.text.labelSmall,
                  ),
                ],
              ),
            ],
          ),
          if (!enabled && !_hasAvailability) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Set your weekly availability first. You can skip this for now '
              'and enable it later.',
              style: context.text.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
            const SizedBox(height: 2),
            TextButton(
              onPressed: () => context.go(Routes.professionalSchedule),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: Alignment.centerLeft,
              ),
              child: const Text('Open scheduling setup'),
            ),
          ],
          if (enabled) ...[
            if (pendingRequests.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Meeting requests (${pendingRequests.length})',
                style: context.text.labelMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final request in pendingRequests)
                _meetingRequestRow(request),
            ],
            const SizedBox(height: AppSpacing.md),
            _meetingRuleGrid(leadForm),
            const SizedBox(height: AppSpacing.md),
            Text('Next introductory meetings', style: context.text.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            if (upcoming.isEmpty)
              const EmptyState(message: 'No upcoming introductory meetings.')
            else
              for (final meeting in upcoming) _upcomingMeetingRow(meeting),
            if (overdue.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text('Overdue follow-up', style: context.text.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              for (final meeting in overdue) _overdueMeetingRow(meeting),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: () => _editMeetingSettings(leadForm),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: Text(
              enabled
                  ? 'Edit meeting settings'
                  : 'Set up introductory meetings',
            ),
          ),
        ],
      ),
    );
  }

  Widget _meetingRequestRow(LeadMeetingRequest request) {
    final busy = _reviewingMeetingRequestId == request.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.applicantName,
                        style: context.text.titleSmall,
                      ),
                      Text(
                        request.requestedStart.isNotEmpty
                            ? dateTimeLabel(request.requestedStart)
                            : '—',
                        style: context.text.bodySmall,
                      ),
                      if (request.referenceId.isNotEmpty ||
                          request.contactEmail.isNotEmpty)
                        Text(
                          [
                            request.referenceId,
                            request.contactEmail,
                          ].where((value) => value.isNotEmpty).join(' · '),
                          style: context.text.bodySmall?.copyWith(
                            color: context.tokens.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                StatusPill(
                  label: titleCase(request.status),
                  tone: switch (request.status) {
                    'accepted' => PillTone.good,
                    'declined' => PillTone.bad,
                    'expired' => PillTone.neutral,
                    _ => PillTone.warn,
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: busy
                        ? null
                        : () => _reviewMeetingRequest(request, 'accept'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, AppSize.buttonHeightSm),
                    ),
                    child: Text(busy ? 'Working…' : 'Accept and send invite'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _reviewMeetingRequest(request, 'decline'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.error,
                    side: BorderSide(color: context.colors.error),
                    minimumSize: const Size(0, AppSize.buttonHeightSm),
                  ),
                  child: const Text('Decline'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meetingRuleGrid(LeadForm leadForm) {
    return KpiGrid(
      children: [
        KpiTile(
          label: 'Duration',
          value: '${leadForm.introductoryMeetingDurationMinutes} min',
        ),
        KpiTile(
          label: 'Minimum notice',
          value: '${leadForm.introductoryMeetingMinNoticeHours} hrs',
        ),
        KpiTile(
          label: 'Booking window',
          value: '${leadForm.introductoryMeetingMaxAdvanceDays} days',
        ),
        KpiTile(
          label: 'Buffer',
          value: '${leadForm.introductoryMeetingBufferMinutes} min',
        ),
      ],
    );
  }

  Widget _upcomingMeetingRow(LeadMeetingRequest meeting) {
    return RowItem(
      title: meeting.applicantName,
      subtitle: meeting.requestedStart.isNotEmpty
          ? dateTimeLabel(meeting.requestedStart)
          : null,
      trailing: meeting.meetingUrl.isEmpty
          ? null
          : TextButton(
              onPressed: () => _shareLink(meeting.meetingUrl, 'Meeting link'),
              child: const Text('Open'),
            ),
    );
  }

  Widget _overdueMeetingRow(LeadMeetingRequest meeting) {
    final controller = _followupControllerFor(meeting.id);
    final sending = _sendingFollowupId == meeting.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(meeting.applicantName, style: context.text.titleSmall),
            Text(
              [
                if (meeting.requestedStart.isNotEmpty)
                  dateTimeLabel(meeting.requestedStart),
                if (meeting.contactEmail.isNotEmpty) meeting.contactEmail,
              ].join(' · '),
              style: context.text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Follow-up message',
                hintText:
                    'Sorry we missed our meeting. Please reply with a suitable '
                    'time so we can reschedule.',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: sending || controller.text.trim().isEmpty
                    ? null
                    : () => _sendMeetingFollowup(meeting),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppSize.buttonHeightSm),
                ),
                child: Text(sending ? 'Sending…' : 'Send email'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----- Form Requests panel -----

  /// A separate section below the lead panel — a month filter, Pending /
  /// Approved / Deleted sub-tabs with counts, and the submissions list.
  /// Scoped to whichever form is selected above; "All forms" tags each row
  /// with its source form instead.
  Widget _formRequestsPanel(List<LeadForm> forms) {
    final formId = _showingAllForms ? null : _selectedLeadForm?.id;
    final pending = _requestSubmissionsFor(SubmissionView.pending, formId);
    final approved = _requestSubmissionsFor(SubmissionView.approved, formId);
    final deleted = _requestSubmissionsFor(SubmissionView.deleted, formId);
    final current = switch (_submissionView) {
      SubmissionView.pending => pending,
      SubmissionView.approved => approved,
      SubmissionView.deleted => deleted,
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Form Requests', style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _monthFilter,
            decoration: const InputDecoration(labelText: 'Filter by month'),
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: '', child: Text('Last 6 months')),
              for (final month in _monthOptions)
                DropdownMenuItem(value: month.value, child: Text(month.label)),
            ],
            onChanged: (value) => setState(() => _monthFilter = value ?? ''),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<SubmissionView>(
              segments: [
                ButtonSegment(
                  value: SubmissionView.pending,
                  label: Text('Pending (${pending.length})'),
                ),
                ButtonSegment(
                  value: SubmissionView.approved,
                  label: Text('Approved (${approved.length})'),
                ),
                ButtonSegment(
                  value: SubmissionView.deleted,
                  label: Text('Deleted (${deleted.length})'),
                ),
              ],
              selected: {_submissionView},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  setState(() => _submissionView = s.first),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (current.isEmpty)
            EmptyState(message: 'No ${_submissionView.name} forms found.')
          else
            for (final submission in current)
              _requestRow(submission, showFormTag: _showingAllForms),
        ],
      ),
    );
  }

  /// [formId] null means "every form" (the "All forms" dropdown mode).
  List<LeadSubmission> _requestSubmissionsFor(
    SubmissionView view,
    int? formId,
  ) {
    final overview = _overview;
    if (overview == null) return const [];
    final all = switch (view) {
      SubmissionView.pending => overview.pendingForms,
      SubmissionView.approved => overview.approvedForms,
      SubmissionView.deleted => overview.deletedForms,
    };
    final scoped = _submissionsForForm(all, formId);

    if (_monthFilter.isEmpty) {
      final accessibleMonths = _monthOptions
          .map((month) => month.value)
          .toSet();
      return scoped
          .where(
            (submission) => accessibleMonths.contains(
              submission.submittedAt.length >= 7
                  ? submission.submittedAt.substring(0, 7)
                  : '',
            ),
          )
          .toList();
    }
    return scoped
        .where((submission) => submission.submittedAt.startsWith(_monthFilter))
        .toList();
  }

  /// One request row: applicant, email, submitted date, reference id, the
  /// group it was converted into (or "Not assigned"), and its action —
  /// View Profile once converted, otherwise Review/View details; Delete
  /// only applies to pending requests.
  Widget _requestRow(LeadSubmission submission, {required bool showFormTag}) {
    final hasClient = submission.clientAccess != null;
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
                    submission.applicantName,
                    style: context.text.titleSmall,
                  ),
                ),
                if (submission.referenceId.isNotEmpty)
                  StatusPill(label: submission.referenceId),
              ],
            ),
            const SizedBox(height: 2),
            Text(submission.email, style: context.text.bodySmall),
            const SizedBox(height: 4),
            Text(
              'Submitted ${shortDate(submission.submittedAt)}',
              style: context.text.bodySmall?.copyWith(
                color: context.tokens.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (showFormTag && submission.leadFormTitle.isNotEmpty)
                  StatusPill(
                    label: submission.leadFormTitle,
                    tone: PillTone.info,
                  ),
                StatusPill(
                  label: hasClient
                      ? submission.clientAccess!.groupName
                      : 'Not assigned',
                  tone: hasClient ? PillTone.good : PillTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (hasClient) {
                        context.go(
                          '${Routes.professionalClients}/${submission.clientAccess!.id}',
                        );
                      } else if (_submissionView == SubmissionView.pending) {
                        _openRequest(submission);
                      } else {
                        _viewSubmissionDetails(submission);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, AppSize.buttonHeightSm),
                    ),
                    child: Text(
                      hasClient
                          ? 'View Profile'
                          : (_submissionView == SubmissionView.pending
                                ? 'Review request'
                                : 'View details'),
                    ),
                  ),
                ),
                if (_submissionView == SubmissionView.pending) ...[
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: () => _deletePending(submission),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.error,
                      side: BorderSide(color: context.colors.error),
                      minimumSize: const Size(0, AppSize.buttonHeightSm),
                    ),
                    child: const Text('Delete'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Read-only viewer for an already-resolved (approved/deleted) submission
  /// — the approve/reject flow in [_openRequest] only applies to pending
  /// ones, so this just shows what was submitted.
  Future<void> _viewSubmissionDetails(LeadSubmission submission) {
    final sourceForm = _leadForms
        .where((form) => form.id == submission.leadForm)
        .firstOrNull;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SubmissionDetailSheet(
        submission: submission,
        leadFormFields:
            sourceForm?.fields ?? _overview?.leadForm?.fields ?? const [],
      ),
    );
  }

  /// Editing is a destination, not an inline swap: the builder opens as a
  /// full-screen dialog with its own Cancel / Save in the app bar, so the
  /// professional always knows they are in an unsaved draft and Save is in a
  /// fixed place rather than below however many fields they have added.
  ///
  /// Field state lives on the page ([_customFields], [_formMandatory]) but
  /// the dialog is a separate route, so edits rebuild through the local
  /// [StatefulBuilder] setter rather than the page's own `setState`.
  Future<void> _openFormEditor() async {
    final creating = _editingFormId == null;
    // Local, because the page's own setState does not rebuild a separate route.
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (dialogContext, setLocal) {
            Future<void> save() async {
              setLocal(() => saving = true);
              final saved = await _saveForm();
              if (!dialogContext.mounted) return;
              if (saved) {
                Navigator.of(dialogContext).pop();
              } else {
                setLocal(() => saving = false);
              }
            }

            return Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel',
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                ),
                title: Text(creating ? 'Create lead form' : 'Edit lead form'),
                actions: [
                  TextButton(
                    onPressed: saving ? null : save,
                    child: Text(saving ? 'Saving…' : 'Save'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ),
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.screen),
                  children: [
                    TextField(
                      controller: _formTitle,
                      decoration: const InputDecoration(
                        labelText: 'Form title',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Core fields (name, email, phone) are always included and '
                      'are not editable. Add your own below.',
                      style: context.text.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Your fields (${_customFields.length})',
                            style: context.text.titleSmall,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              setLocal(() => _customFields.add(_DraftField())),
                          icon: const Icon(Icons.add, size: AppSize.iconRow),
                          label: const Text('Add field'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, AppSize.buttonHeightSm),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (_customFields.isEmpty)
                      Text(
                        'No extra fields yet — the form will collect name, '
                        'email and phone only.',
                        style: context.text.bodySmall?.copyWith(
                          color: context.tokens.muted,
                        ),
                      )
                    else
                      for (var i = 0; i < _customFields.length; i++)
                        _FieldEditor(
                          field: _customFields[i],
                          onChanged: () => setLocal(() {}),
                          onRemove: () =>
                              setLocal(() => _customFields.removeAt(i)),
                        ),
                    const SizedBox(height: AppSpacing.md),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Require before adding a client'),
                      subtitle: const Text(
                        'Clients must complete this form first',
                      ),
                      value: _formMandatory,
                      onChanged: (value) =>
                          setLocal(() => _formMandatory = value),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _groupsTab() {
    final overview = _overview;
    final groups = overview?.groups ?? const <ProfessionalGroup>[];

    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Groups used',
                      style: context.text.labelMedium?.copyWith(
                        color: context.tokens.muted,
                      ),
                    ),
                    Text(
                      '${groups.length} / ${overview?.maxGroups ?? '—'}',
                      style: context.text.displaySmall,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: overview?.atGroupLimit ?? false
                    ? null
                    : () => setState(() => _showGroupForm = !_showGroupForm),
                icon: Icon(
                  _showGroupForm ? Icons.close : Icons.add,
                  size: AppSize.iconRow,
                ),
                label: Text(_showGroupForm ? 'Close' : 'New group'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppSize.buttonHeightSm),
                ),
              ),
            ],
          ),
        ),
        if (overview?.atGroupLimit ?? false)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Group limit reached on your plan.',
              style: context.text.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ),

        if (_showGroupForm) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: [
                TextField(
                  controller: _groupName,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Group name'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _groupDescription,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _isSavingGroup || _groupName.text.trim().isEmpty
                      ? null
                      : _createGroup,
                  child: Text(_isSavingGroup ? 'Creating…' : 'Create group'),
                ),
              ],
            ),
          ),
        ],

        SectionHeader(
          title: 'Active groups',
          infoBody:
              'Active groups are live: their clients can sign in and '
              'everything inside the group works normally.\n\n'
              'Your plan sets how many groups can be active at once. Groups '
              'fill those slots from the top of this list down.\n\n'
              'Drag a group by its handle to change that order. Whatever sits '
              'highest keeps its slot, so if you ever go over your plan the '
              'groups you dragged to the bottom are the ones that lock — you '
              'choose which, not us.',
        ),
        if (groups.isEmpty)
          const EmptyState(message: 'No groups yet.')
        else ...[
          if (_canReorderGroups) ...[
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // Rows are tappable, so an explicit handle keeps a tap from
              // being read as the start of a drag.
              buildDefaultDragHandles: false,
              itemCount: _activeGroups.length,
              onReorderItem: _reorderGroups,
              itemBuilder: (context, index) {
                final group = _activeGroups[index];
                return _groupRow(
                  group,
                  key: ValueKey(group.id),
                  dragIndex: index,
                );
              },
            ),
          ] else
            for (final group in _activeGroups)
              _groupRow(group, key: ValueKey(group.id)),

          if (_lockedGroups.isNotEmpty) ...[
            SectionHeader(
              title: 'Locked groups',
              infoBody:
                  'These groups are past your plan\'s group limit, so '
                  'they are on hold.\n\n'
                  'Nothing has been deleted. Every client, form, and record '
                  'inside them is still here exactly as you left it.\n\n'
                  'While a group is locked, its clients cannot sign in to '
                  'their portal.\n\n'
                  'To unlock one: drag it higher in Active groups so it takes '
                  'a slot ahead of another group, or upgrade your plan for '
                  'more slots. It comes back intact either way.',
            ),
            for (final group in _lockedGroups)
              _groupRow(
                group,
                key: ValueKey('locked-${group.id}'),
                locked: true,
              ),
          ],
        ],
      ],
    );
  }

  /// One group row. [dragIndex] adds the reorder handle (active rows inside
  /// the reorderable list only); [locked] renders the plan-lock variant, which
  /// cannot be opened until it unlocks.
  Widget _groupRow(
    ProfessionalGroup group, {
    required Key key,
    int? dragIndex,
    bool locked = false,
  }) {
    return RowItem(
      key: key,
      title: group.name,
      subtitle: group.description.isNotEmpty
          ? group.description
          : (group.hasRegistrationForm
                ? 'Registration link active'
                : 'No registration form'),
      leading: dragIndex == null
          ? null
          : ReorderableDragStartListener(
              index: dragIndex,
              child: Icon(
                Icons.drag_indicator,
                size: AppSize.iconRow,
                color: context.tokens.muted,
              ),
            ),
      trailing: locked
          ? const StatusPill(label: 'Locked', tone: PillTone.warn)
          : group.hasRegistrationForm
          ? const StatusPill(label: 'Form', tone: PillTone.good)
          : null,
      onTap: locked
          ? null
          : () => context.go('${Routes.professionalGroups}/${group.id}'),
    );
  }
}

/// What the form-request sheet did, so the page can reload and either show the
/// one-time credentials or run its own delete confirmation.
class _RequestOutcome {
  const _RequestOutcome.approved(this.username, this.password)
    : rejected = false;
  const _RequestOutcome.rejected()
    : rejected = true,
      username = '',
      password = '';

  final bool rejected;
  final String username;
  final String password;
}

/// Form request detail — the applicant's submitted answers with the approve /
/// reject actions, replacing the blind convert. Port of
/// frontend/src/app/pages/studio/professional/professional-form-request-detail.
class _FormRequestSheet extends ConsumerStatefulWidget {
  const _FormRequestSheet({
    required this.submission,
    required this.groups,
    required this.leadFormFields,
  });

  final LeadSubmission submission;
  final List<ProfessionalGroup> groups;

  /// Used only to turn answer keys into the labels the applicant saw.
  final List<DynamicField> leadFormFields;

  @override
  ConsumerState<_FormRequestSheet> createState() => _FormRequestSheetState();
}

class _FormRequestSheetState extends ConsumerState<_FormRequestSheet> {
  final _username = TextEditingController();
  final _password = TextEditingController();

  int _groupId = 0;
  bool _sendCredentials = true;
  bool _isSaving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    // The web defaults to the only group, or to the first one that can actually
    // take a client (the backend rejects a group with no registration form).
    final defaultGroup = widget.groups.length == 1
        ? widget.groups.first
        : widget.groups.where((group) => group.hasRegistrationForm).firstOrNull;
    _groupId = defaultGroup?.id ?? 0;
    _username.text =
        '${widget.submission.firstName}.${widget.submission.lastName}'
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9.-]+'), '');
    _password.text = _generatePassword();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  String _generatePassword() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    final value = List.generate(
      10,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
    return '${value.substring(0, 8)}!${value.substring(8)}';
  }

  /// Answer key -> the label the applicant actually saw, falling back to the
  /// humanised key for answers whose field was since removed.
  String _labelFor(String key) {
    for (final field in widget.leadFormFields) {
      if (field.key == key) return field.label;
    }
    return key.replaceAll('_', ' ');
  }

  /// The web's fillRegistrationAnswers: identity fields plus every registration
  /// field the applicant already answered, matched on key or on label.
  Map<String, String> _registrationAnswers(ProfessionalGroup group) {
    final submission = widget.submission;
    final byKey = submission.answers;
    final byLabel = <String, String>{};

    for (final field in widget.leadFormFields) {
      final matched = field.key.isEmpty ? null : byKey[field.key];
      if (matched != null && matched.isNotEmpty) {
        byLabel[field.label.trim().toLowerCase()] = matched;
      }
    }

    final answers = <String, String>{
      'first_name': submission.firstName,
      'last_name': submission.lastName,
      'email': submission.email,
    };

    for (final field
        in group.registrationForm?.fields ?? const <DynamicField>[]) {
      final key = field.answerKey;
      if (answers.containsKey(key)) continue;

      final matched =
          (field.key.isNotEmpty ? byKey[field.key] : null) ??
          byLabel[field.label.trim().toLowerCase()];

      if (matched != null && matched.isNotEmpty) answers[key] = matched;
    }

    return answers;
  }

  Future<void> _approve() async {
    final group = widget.groups
        .where((item) => item.id == _groupId)
        .firstOrNull;

    if (group == null) {
      setState(() => _error = 'Select a group for this client.');
      return;
    }
    if (_username.text.trim().isEmpty) {
      setState(() => _error = 'Enter a client username.');
      return;
    }
    if (_password.text.trim().length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = '';
    });

    final password = _password.text.trim();
    final username = _username.text.trim();

    try {
      await ref
          .read(formsGroupsApiProvider)
          .createClientAccess(
            widget.submission.id,
            ClientAccessPayload(
              groupId: group.id,
              username: username,
              password: password,
              confirmPassword: password,
              registrationAnswers: _registrationAnswers(group),
              sendCredentials: _sendCredentials,
            ),
          );
      if (mounted) {
        Navigator.of(context).pop(_RequestOutcome.approved(username, password));
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final submission = widget.submission;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screen,
        right: AppSpacing.screen,
        top: AppSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    submission.applicantName,
                    style: context.text.titleMedium,
                  ),
                ),
                if (submission.referenceId.isNotEmpty)
                  StatusPill(label: submission.referenceId),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${submission.email} · submitted '
              '${dateTimeLabel(submission.submittedAt)}',
              style: context.text.bodySmall,
            ),

            const SectionHeader(
              title: 'Submitted answers',
              topSpace: AppSpacing.lg,
            ),
            if (submission.answers.isEmpty)
              const EmptyState(message: 'This request has no answers.')
            else
              for (final entry in submission.answers.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _labelFor(entry.key),
                        style: context.text.labelSmall?.copyWith(
                          color: context.tokens.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.value.trim().isEmpty
                            ? 'Not added'
                            : entry.value.trim(),
                        style: context.text.bodyMedium,
                      ),
                    ],
                  ),
                ),

            const SectionHeader(
              title: 'Create client access',
              topSpace: AppSpacing.lg,
            ),
            Text(
              'Matching details are auto-filled from what the applicant '
              'submitted. The client confirms the rest from their own profile.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<int>(
              initialValue: _groupId > 0 ? _groupId : null,
              decoration: const InputDecoration(labelText: 'Group'),
              hint: const Text('Choose a group'),
              items: widget.groups
                  .map(
                    (group) => DropdownMenuItem(
                      value: group.id,
                      enabled: group.hasRegistrationForm,
                      child: Text(
                        group.hasRegistrationForm
                            ? group.name
                            : '${group.name} (no registration form)',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _groupId = value ?? 0),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _username,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _password,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Temporary password',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: OutlinedButton(
                    onPressed: () =>
                        setState(() => _password.text = _generatePassword()),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(88, AppSize.buttonHeightSm),
                    ),
                    child: const Text('Generate'),
                  ),
                ),
              ],
            ),
            InkWell(
              onTap: () => setState(() => _sendCredentials = !_sendCredentials),
              child: Row(
                children: [
                  Checkbox(
                    value: _sendCredentials,
                    onChanged: (value) =>
                        setState(() => _sendCredentials = value ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      'Email the credentials to the client',
                      style: context.text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              ErrorNote(message: _error),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _isSaving ? null : _approve,
              child: Text(
                _isSaving ? 'Creating…' : 'Approve and create client',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: _isSaving
                  ? null
                  : () => Navigator.of(
                      context,
                    ).pop(const _RequestOutcome.rejected()),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.error,
                side: BorderSide(color: context.colors.error),
              ),
              child: const Text('Reject request'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only viewer for an already-resolved (approved/deleted) submission —
/// just the submitted answers and outcome, no approve/reject actions.
class _SubmissionDetailSheet extends StatelessWidget {
  const _SubmissionDetailSheet({
    required this.submission,
    required this.leadFormFields,
  });

  final LeadSubmission submission;

  /// Used only to turn answer keys into the labels the applicant saw.
  final List<DynamicField> leadFormFields;

  String _labelFor(String key) {
    for (final field in leadFormFields) {
      if (field.key == key) return field.label;
    }
    return key.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screen,
        right: AppSpacing.screen,
        top: AppSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    submission.applicantName,
                    style: context.text.titleMedium,
                  ),
                ),
                if (submission.referenceId.isNotEmpty)
                  StatusPill(label: submission.referenceId),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${submission.email} · submitted ${dateTimeLabel(submission.submittedAt)}',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            StatusPill(
              label: submission.clientAccess != null
                  ? 'Converted to ${submission.clientAccess!.groupName}'
                  : titleCase(submission.status),
              tone: submission.clientAccess != null
                  ? PillTone.good
                  : PillTone.neutral,
            ),
            const SectionHeader(
              title: 'Submitted answers',
              topSpace: AppSpacing.lg,
            ),
            if (submission.answers.isEmpty)
              const EmptyState(message: 'This request has no answers.')
            else
              for (final entry in submission.answers.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _labelFor(entry.key),
                        style: context.text.labelSmall?.copyWith(
                          color: context.tokens.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.value.trim().isEmpty
                            ? 'Not added'
                            : entry.value.trim(),
                        style: context.text.bodyMedium,
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldEditor extends StatelessWidget {
  const _FieldEditor({
    required this.field,
    required this.onChanged,
    required this.onRemove,
  });

  final _DraftField field;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surfaceSoft,
        borderRadius: AppRadius.tileAll,
      ),
      child: Column(
        children: [
          TextFormField(
            initialValue: field.label,
            onChanged: (value) {
              field.label = value;
              onChanged();
            },
            decoration: const InputDecoration(labelText: 'Label'),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: field.fieldType,
            decoration: const InputDecoration(labelText: 'Type'),
            items: DynamicFieldType.all
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(DynamicFieldType.label(t)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              field.fieldType = value ?? DynamicFieldType.shortText;
              onChanged();
            },
          ),
          if (DynamicFieldType.withOptions.contains(field.fieldType)) ...[
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              initialValue: field.options.join(', '),
              onChanged: (value) {
                field.options = value
                    .split(',')
                    .map((o) => o.trim())
                    .where((o) => o.isNotEmpty)
                    .toList();
              },
              decoration: const InputDecoration(
                labelText: 'Options',
                helperText: 'Comma separated',
              ),
            ),
          ],
          Row(
            children: [
              Checkbox(
                value: field.required,
                onChanged: (value) {
                  field.required = value ?? false;
                  onChanged();
                },
                visualDensity: VisualDensity.compact,
              ),
              Text('Required', style: context.text.bodySmall),
              const Spacer(),
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: AppSize.iconRow),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.error,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
