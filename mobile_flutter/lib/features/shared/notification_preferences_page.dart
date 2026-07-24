import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/client_api.dart';
import '../../core/api/models/notification_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';

/// Per-category notification channel matrix (in-app / email / digest
/// frequency), matching the web's professional-account-settings
/// notification-preferences table. Previously missing on mobile entirely.
class NotificationPreferencesPage extends ConsumerStatefulWidget {
  const NotificationPreferencesPage({super.key, required this.professional});
  final bool professional;

  @override
  ConsumerState<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends ConsumerState<NotificationPreferencesPage> {
  List<NotificationPreferenceRow> _rows = [];
  bool _loading = true;
  String _message = '';
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = '';
    });
    try {
      final rows = widget.professional
          ? await ref.read(professionalAuthApiProvider).getNotificationPreferences()
          : await ref.read(clientApiProvider).getNotificationPreferences();
      // Guarantee every known category has a row, even if the backend hasn't
      // written a preference record for it yet (defaults apply server-side).
      final byCategory = {for (final r in rows) r.category: r};
      final merged = [
        for (final category in NotificationCategory.all)
          byCategory[category] ??
              NotificationPreferenceRow(
                category: category,
                inAppEnabled: true,
                emailEnabled: false,
                pushEnabled: true,
                digestFrequency: 'immediate',
                mandatoryInApp: NotificationCategory.mandatoryInApp.contains(category),
              ),
      ];
      if (mounted) setState(() { _rows = merged; _loading = false; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Could not load notification preferences.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _update(
    NotificationPreferenceRow row, {
    bool? inAppEnabled,
    bool? emailEnabled,
    String? digestFrequency,
  }) async {
    if (_saving.contains(row.category)) return;
    setState(() => _saving.add(row.category));
    try {
      final updated = widget.professional
          ? await ref.read(professionalAuthApiProvider).updateNotificationPreference(
                row.category,
                inAppEnabled: inAppEnabled,
                emailEnabled: emailEnabled,
                digestFrequency: digestFrequency,
              )
          : await ref.read(clientApiProvider).updateNotificationPreference(
                row.category,
                inAppEnabled: inAppEnabled,
                emailEnabled: emailEnabled,
                digestFrequency: digestFrequency,
              );
      if (mounted) {
        setState(() =>
            _rows = _rows.map((r) => r.category == row.category ? updated : r).toList());
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not update ${NotificationCategory.label(row.category)}.');
    }
    if (mounted) setState(() => _saving.remove(row.category));
  }

  /// Sets every non-mandatory category's in-app + email channels at once —
  /// mirrors the web's "set all channel" bulk action.
  Future<void> _setAll({bool? inAppEnabled, bool? emailEnabled}) async {
    for (final row in _rows) {
      if (row.mandatoryInApp && inAppEnabled == false) continue;
      await _update(row, inAppEnabled: inAppEnabled, emailEnabled: emailEnabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification preferences'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'all_on':
                  _setAll(inAppEnabled: true, emailEnabled: true);
                case 'email_off':
                  _setAll(emailEnabled: false);
                case 'app_off':
                  _setAll(inAppEnabled: false);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'all_on', child: Text('Enable everything')),
              PopupMenuItem(value: 'email_off', child: Text('Turn off all email')),
              PopupMenuItem(value: 'app_off', child: Text('Turn off optional in-app')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : PagePad(
              onRefresh: _load,
              children: [
                if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
                Text(
                  'Choose how you\'re notified for each category. Account, '
                  'security, storage, and system alerts always stay on in-app.',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                for (final row in _rows) _PreferenceCard(
                  row: row,
                  saving: _saving.contains(row.category),
                  onInAppChanged: row.mandatoryInApp
                      ? null
                      : (value) => _update(row, inAppEnabled: value),
                  onEmailChanged: (value) => _update(row, emailEnabled: value),
                  onDigestChanged: (value) => _update(row, digestFrequency: value),
                ),
              ],
            ),
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({
    required this.row,
    required this.saving,
    required this.onInAppChanged,
    required this.onEmailChanged,
    required this.onDigestChanged,
  });

  final NotificationPreferenceRow row;
  final bool saving;
  final ValueChanged<bool>? onInAppChanged;
  final ValueChanged<bool> onEmailChanged;
  final ValueChanged<String> onDigestChanged;

  @override
  Widget build(BuildContext context) {
    final emailOn = row.emailEnabled && row.digestFrequency != 'none';

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
                    NotificationCategory.label(row.category),
                    style: context.text.titleSmall,
                  ),
                ),
                if (saving)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (row.mandatoryInApp)
                  const StatusPill(label: 'Required', tone: PillTone.neutral),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Website / in-app'),
              value: row.inAppEnabled,
              onChanged: saving ? null : onInAppChanged,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Email'),
              value: emailOn,
              onChanged: saving ? null : onEmailChanged,
            ),
            if (row.emailEnabled) ...[
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<String>(
                initialValue: DigestFrequency.all.contains(row.digestFrequency)
                    ? row.digestFrequency
                    : 'immediate',
                decoration: const InputDecoration(labelText: 'Email frequency'),
                items: [
                  for (final freq in DigestFrequency.all)
                    DropdownMenuItem(value: freq, child: Text(DigestFrequency.label(freq))),
                ],
                onChanged: saving ? null : (value) {
                  if (value != null) onDigestChanged(value);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
