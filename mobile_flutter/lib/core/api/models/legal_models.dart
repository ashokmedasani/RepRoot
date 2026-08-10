/// Legal-document models — ported from the `LegalConfigurationResponse` and
/// `ProfessionalProfileStatusResponse` interfaces in
/// mobile/src/app/core/api/professional-auth-api.service.ts.
/// Field names match the Django payloads exactly; do not rename them.
library;

/// What goes in `client_timezone` on an acceptance record.
///
/// The web sends an IANA zone name (`Intl.DateTimeFormat().resolvedOptions()
/// .timeZone`). Dart cannot produce one without a timezone package, so this
/// sends the platform abbreviation with the UTC offset — e.g. "IST (UTC+05:30)".
/// The backend stores it as an opaque string truncated at 80 chars
/// (ProfessionalLegalAcceptanceView / ClientLegalAcceptanceView), so any label
/// is accepted; this one stays human-readable in an audit.
String localTimezoneLabel() {
  final now = DateTime.now();
  final offset = now.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hours = offset.inHours.abs().toString().padLeft(2, '0');
  final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  final name = now.timeZoneName.trim();
  final label = name.isEmpty
      ? 'UTC$sign$hours:$minutes'
      : '$name (UTC$sign$hours:$minutes)';
  return label.length > 80 ? label.substring(0, 80) : label;
}

/// Public metadata about the currently published legal documents.
/// GET /api/accounts/legal/configuration/ (AllowAny — see LegalConfigurationView).
class LegalConfiguration {
  const LegalConfiguration({
    required this.effectiveDate,
    required this.professionalVersion,
    required this.clientVersion,
  });

  /// `settings.REPROOT_LEGAL_EFFECTIVE_DATE`, an ISO date string.
  final String effectiveDate;

  /// `settings.REPROOT_PROFESSIONAL_LEGAL_VERSION`.
  final String professionalVersion;

  /// `settings.REPROOT_CLIENT_LEGAL_VERSION`.
  final String clientVersion;

  factory LegalConfiguration.fromJson(Map<String, dynamic> json) {
    final professional = json['professional'] as Map<String, dynamic>? ?? {};
    final client = json['client'] as Map<String, dynamic>? ?? {};
    return LegalConfiguration(
      effectiveDate: json['effective_date'] as String? ?? '',
      professionalVersion: professional['version'] as String? ?? '',
      clientVersion: client['version'] as String? ?? '',
    );
  }
}

/// One row of `legal_acceptance_history` — an immutable acceptance record
/// (backend/accounts/models.py, LegalAcceptanceRecord).
class LegalAcceptanceEntry {
  const LegalAcceptanceEntry({
    required this.legalDocumentVersion,
    required this.acceptedAt,
    required this.clientTimezone,
  });

  final String legalDocumentVersion;
  final String acceptedAt;
  final String clientTimezone;

  factory LegalAcceptanceEntry.fromJson(Map<String, dynamic> json) =>
      LegalAcceptanceEntry(
        legalDocumentVersion: json['legal_document_version'] as String? ?? '',
        acceptedAt: json['accepted_at']?.toString() ?? '',
        clientTimezone: json['client_timezone'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'legal_document_version': legalDocumentVersion,
    'accepted_at': acceptedAt,
    'client_timezone': clientTimezone,
  };

  static List<LegalAcceptanceEntry> listFrom(dynamic raw) =>
      (raw as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(LegalAcceptanceEntry.fromJson)
          .toList();
}

/// GET /api/accounts/professional/profile/status/ — the flag the web portal
/// routes on right after login (`routeAfterLogin()` in
/// professional-login.component.ts).
class ProfessionalProfileStatus {
  const ProfessionalProfileStatus({
    required this.profileSetupCompleted,
    required this.legalAcceptanceRequired,
    required this.currentLegalDocumentVersion,
  });

  final bool profileSetupCompleted;

  /// True when terms/privacy are unaccepted *or* accepted against an older
  /// published version — the backend computes it in
  /// ProfessionalProfileStatusSerializer.get_legal_acceptance_required.
  final bool legalAcceptanceRequired;
  final String currentLegalDocumentVersion;

  factory ProfessionalProfileStatus.fromJson(Map<String, dynamic> json) =>
      ProfessionalProfileStatus(
        profileSetupCompleted:
            json['profile_setup_completed'] as bool? ?? false,
        legalAcceptanceRequired:
            json['legal_acceptance_required'] as bool? ?? false,
        currentLegalDocumentVersion:
            json['current_legal_document_version'] as String? ?? '',
      );
}
