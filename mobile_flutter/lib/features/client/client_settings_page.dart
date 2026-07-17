import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/client_api.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import '../../shared/widgets/password_field.dart';
import '../trainer/trainer_format.dart';

/// Client settings — profile, trainer-approved edit requests, password, and
/// account deletion requests.
/// Replica of mobile/src/app/pages/client/settings/client-settings.page.ts.
class ClientSettingsPage extends ConsumerStatefulWidget {
  const ClientSettingsPage({super.key});

  @override
  ConsumerState<ClientSettingsPage> createState() => _ClientSettingsPageState();
}

class _ClientSettingsPageState extends ConsumerState<ClientSettingsPage> {
  ClientMeResponse? _me;
  ClientDetailChangeRequest? _pendingRequest;
  ClientDetailChangeRequest? _deletionRequest;
  bool _loading = true;

  bool _isEditing = false;
  bool _isSubmittingEdit = false;
  final Map<String, TextEditingController> _draft = {};
  final _editNote = TextEditingController();

  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _isChangingPassword = false;

  String _message = '';
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _draft.values) {
      c.dispose();
    }
    _editNote.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String get _initials {
    final client = _me?.client;
    final first = client?.firstName ?? '';
    final last = client?.lastName ?? '';
    final letters =
        '${first.isNotEmpty ? first[0] : ''}${last.isNotEmpty ? last[0] : ''}'
            .toUpperCase();
    return letters.isEmpty ? 'C' : letters;
  }

  /// Core identity fields plus the group's custom registration fields.
  List<({String key, String label})> get _editableFields {
    final custom = (_me?.registrationFields ?? [])
        .where((field) => !field.isCore)
        .map((field) => (key: field.answerKey, label: field.label));
    return [
      (key: 'first_name', label: 'First name'),
      (key: 'last_name', label: 'Last name'),
      (key: 'email', label: 'Email'),
      ...custom,
    ];
  }

  /// Answered custom fields for the read-only view — identity is shown above.
  List<({String label, String value})> get _answeredFields {
    final answers = _me?.client.registrationAnswers ?? const {};
    const skip = {'first_name', 'last_name', 'email'};
    final fields = _me?.registrationFields ?? const <DynamicField>[];

    return answers.entries
        .where((e) => !skip.contains(e.key) && e.value.trim().isNotEmpty)
        .map((e) {
      final field = fields.where((f) => f.answerKey == e.key).firstOrNull;
      return (
        label: field?.label ?? e.key.replaceAll('_', ' '),
        value: e.value,
      );
    }).toList();
  }

  Future<void> _load() async {
    final api = ref.read(clientApiProvider);
    try {
      final me = await api.getMe();
      if (mounted) setState(() => _me = me);
    } catch (_) {
      _setMessage('Could not load your profile.', true);
    }
    try {
      final request = await api.getDetailChangeRequest();
      if (mounted) {
        // Only a pending request is actionable; approved/rejected are history.
        setState(() =>
            _pendingRequest = request?.status == 'pending' ? request : null);
      }
    } catch (_) {}
    try {
      final deletion = await api.getAccountDeletionRequest();
      if (mounted) setState(() => _deletionRequest = deletion);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _setMessage(String text, bool isError) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = isError;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _message = '');
    });
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1000,
      imageQuality: 85,
    );
    if (picked == null) return;

    try {
      // The endpoint takes a data URL, same as the TS FileReader result.
      final bytes = await File(picked.path).readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';

      final client = await ref.read(clientApiProvider).updatePhoto(dataUrl);
      if (!mounted) return;
      setState(() {
        final me = _me;
        if (me != null) {
          _me = ClientMeResponse(
            client: client,
            group: me.group,
            registrationFields: me.registrationFields,
            sharedAdditionalInfo: me.sharedAdditionalInfo,
            trainerProfile: me.trainerProfile,
          );
        }
      });
      _setMessage('Photo updated.', false);
    } on ApiException catch (error) {
      _setMessage(error.message, true);
    } catch (_) {
      _setMessage('Photo could not be updated.', true);
    }
  }

  void _startEdit() {
    final client = _me?.client;
    final answers = client?.registrationAnswers ?? const {};

    for (final c in _draft.values) {
      c.dispose();
    }
    _draft.clear();

    for (final field in _editableFields) {
      final value = switch (field.key) {
        'first_name' => client?.firstName ?? '',
        'last_name' => client?.lastName ?? '',
        'email' => client?.email ?? '',
        _ => answers[field.key] ?? '',
      };
      _draft[field.key] = TextEditingController(text: value);
    }
    _editNote.clear();
    setState(() => _isEditing = true);
  }

  Future<void> _submitEdit() async {
    setState(() => _isSubmittingEdit = true);
    final proposed = {
      for (final entry in _draft.entries) entry.key: entry.value.text,
    };

    try {
      final request = await ref
          .read(clientApiProvider)
          .submitDetailChangeRequest(proposed, note: _editNote.text.trim());
      if (!mounted) return;
      setState(() {
        _pendingRequest = request;
        _isSubmittingEdit = false;
        _isEditing = false;
      });
      _setMessage('Edit request sent to your trainer.', false);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isSubmittingEdit = false);
      _setMessage(error.message, true);
    }
  }

  bool get _canChangePassword =>
      !_isChangingPassword &&
      _currentPassword.text.isNotEmpty &&
      _newPassword.text.length >= 8 &&
      _newPassword.text == _confirmPassword.text;

  Future<void> _changePassword() async {
    setState(() => _isChangingPassword = true);
    final api = ref.read(clientApiProvider);
    try {
      final response = await api.changePassword(
        _currentPassword.text,
        _newPassword.text,
        _confirmPassword.text,
      );
      // The backend rotates the token — store the fresh one or the session dies.
      final client = response.client;
      if (response.token.isNotEmpty && client != null) {
        await api.storeSession(response.token, client);
      }
      if (!mounted) return;
      setState(() {
        _isChangingPassword = false;
        _currentPassword.clear();
        _newPassword.clear();
        _confirmPassword.clear();
      });
      _setMessage('Password updated.', false);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isChangingPassword = false);
      _setMessage(error.message, true);
    }
  }

  Future<void> _requestDeletion() async {
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request account deletion?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your trainer will review this request. Your data stays until it '
              'is approved.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: note,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note to your trainer (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Request deletion'),
          ),
        ],
      ),
    );

    final text = note.text.trim();
    note.dispose();
    if (confirmed != true) return;

    try {
      final request = await ref
          .read(clientApiProvider)
          .requestAccountDeletion(note: text);
      if (mounted) setState(() => _deletionRequest = request);
      _setMessage('Deletion request sent.', false);
    } on ApiException catch (error) {
      _setMessage(error.message, true);
    }
  }

  Future<void> _withdrawDeletion() async {
    try {
      await ref.read(clientApiProvider).withdrawAccountDeletionRequest();
      if (mounted) setState(() => _deletionRequest = null);
      _setMessage('Deletion request withdrawn.', false);
    } on ApiException catch (error) {
      _setMessage(error.message, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const PagePad(children: [SkeletonBox(height: 110), SkeletonBox(height: 200)]),
      );
    }

    final client = _me?.client;
    final tokens = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: BackButton(onPressed: () => context.go(Routes.clientMore)),
      ),
      body: PagePad(
        onRefresh: _isEditing ? null : _load,
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
                    color: _messageIsError ? context.colors.error : tokens.success,
                  ),
                ),
              ),
            ),

          AppCard(
            child: Row(
              children: [
                AppAvatar(
                  initials: _initials,
                  imageUrl: Env.mediaUrl(client?.photo ?? ''),
                  size: 56,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        client?.displayName ?? '',
                        style: context.text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(client?.username ?? '', style: context.text.bodySmall),
                      const SizedBox(height: AppSpacing.xs),
                      OutlinedButton.icon(
                        onPressed: _pickPhoto,
                        icon: const Icon(Icons.photo_camera_outlined,
                            size: AppSize.iconRow),
                        label: const Text('Change photo'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, AppSize.buttonHeightSm),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_pendingRequest != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              color: tokens.primarySoft,
              child: Row(
                children: [
                  Icon(Icons.hourglass_top_outlined,
                      size: 20, color: context.colors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Your edit request is waiting for your trainer to review.',
                      style: context.text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (!_isEditing) ...[
            SectionHeader(
              title: 'Your details',
              actionLabel: _pendingRequest == null ? 'Request edit' : null,
              onAction: _pendingRequest == null ? _startEdit : null,
            ),
            AppCard(
              child: Column(
                children: [
                  _kv('Name', client?.displayName ?? ''),
                  _kv('Email', client?.email ?? ''),
                  _kv('Username', client?.username ?? ''),
                  _kv('Group', client?.groupName ?? ''),
                  for (final field in _answeredFields) _kv(field.label, field.value),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Changes to your details need your trainer to approve them.',
                style: context.text.bodySmall,
              ),
            ),
          ] else ...[
            const SectionHeader(title: 'Request an edit'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your trainer reviews these changes before they apply.',
                    style: context.text.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final field in _editableFields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: TextField(
                        controller: _draft[field.key],
                        decoration: InputDecoration(labelText: field.label),
                      ),
                    ),
                  TextField(
                    controller: _editNote,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Note to your trainer (optional)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _isSubmittingEdit ? null : _submitEdit,
                          child: Text(
                            _isSubmittingEdit ? 'Sending…' : 'Send request',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      TextButton(
                        onPressed: () => setState(() => _isEditing = false),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SectionHeader(title: 'Password'),
          AppCard(
            child: Column(
              children: [
                PasswordField(
                  controller: _currentPassword,
                  label: 'Current password',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
                PasswordField(
                  controller: _newPassword,
                  label: 'New password',
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: AppSpacing.md),
                PasswordField(
                  controller: _confirmPassword,
                  label: 'Confirm new password',
                  autofillHints: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _canChangePassword ? _changePassword : null,
                  child: Text(
                    _isChangingPassword ? 'Updating…' : 'Change password',
                  ),
                ),
              ],
            ),
          ),

          const SectionHeader(title: 'Account'),
          AppCard(
            child: _deletionRequest != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.hourglass_top_outlined,
                              size: 20, color: context.colors.error),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Deletion requested ${shortDate(_deletionRequest!.createdAt)}',
                              style: context.text.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Your trainer is reviewing it. Your data stays until '
                        'they approve.',
                        style: context.text.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton(
                        onPressed: _withdrawDeletion,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, AppSize.buttonHeightSm),
                        ),
                        child: const Text('Withdraw request'),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Delete your account', style: context.text.titleSmall),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Your trainer reviews the request. Nothing is removed '
                        'until they approve it.',
                        style: context.text.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton(
                        onPressed: _requestDeletion,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.colors.error,
                          side: BorderSide(color: context.colors.error),
                          minimumSize: const Size(0, AppSize.buttonHeightSm),
                        ),
                        child: const Text('Request deletion'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: context.text.bodySmall)),
          Expanded(
            flex: 3,
            child: Text(
              value.trim().isEmpty ? '—' : value,
              style: context.text.titleSmall,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
