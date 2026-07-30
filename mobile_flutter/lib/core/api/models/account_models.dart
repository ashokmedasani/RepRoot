/// Professional account: billing/plan + recycle bin.
/// Ported from the interfaces in
/// mobile/src/app/core/api/professional-auth-api.service.ts.
/// Field names match the Django payloads exactly; do not rename them.
library;

/// 'pro' | 'premium_unlimited'
class ProfessionalUpgradeTier {
  const ProfessionalUpgradeTier._();
  static const pro = 'pro';
  static const premiumUnlimited = 'premium_unlimited';

  static String label(String tier) => switch (tier) {
        'pro' => 'Pro',
        'premium_unlimited' => 'Premium',
        _ => tier,
      };
}

class ProfessionalBillingStatus {
  const ProfessionalBillingStatus({
    required this.planCode,
    required this.planName,
    required this.planRenewsAt,
    required this.hasBillingAccount,
    required this.billingConfigured,
    required this.testMode,
    required this.availableUpgrades,
    required this.catalog,
    required this.billingCurrency,
    required this.billingRegion,
    required this.cancellationEffectiveAt,
    required this.downgradeEligible,
    required this.freeStoragePercent,
    required this.storageDowngradeEligible,
    required this.downgradeLocks,
    required this.categoryCascadeResourceCount,
    required this.clientsLosingAccess,
    required this.supportEmail,
  });

  final String planCode;
  final String planName;
  final String? planRenewsAt;
  final bool hasBillingAccount;
  final bool billingConfigured;

  /// True while real Stripe pricing isn't wired for every tier — "Update plan"
  /// applies the tier directly with no charge.
  final bool testMode;

  /// Tiers the professional can move to, e.g. {'pro': true, ...}.
  final Map<String, bool> availableUpgrades;
  final Map<String, dynamic> catalog;
  final String billingCurrency;
  final String billingRegion;
  final String? cancellationEffectiveAt;
  // Never blocked by the plan-limit lock system -- only genuine storage
  // overage (storageDowngradeEligible) can block self-serve cancellation.
  // Nothing over the Free plan's counted limits is ever deleted; it locks.
  final bool downgradeEligible;
  final double freeStoragePercent;
  final bool storageDowngradeEligible;
  final Map<String, Map<String, dynamic>> downgradeLocks;
  final int categoryCascadeResourceCount;
  final List<Map<String, dynamic>> clientsLosingAccess;
  final String supportEmail;

  List<String> get upgradeTiers =>
      availableUpgrades.entries.where((e) => e.value).map((e) => e.key).toList();

  factory ProfessionalBillingStatus.fromJson(Map<String, dynamic> json) {
    final plan = json['plan'] as Map<String, dynamic>? ?? {};
    final assessment = json['downgrade_assessment'] as Map<String, dynamic>? ?? {};
    final storage = assessment['storage'] as Map<String, dynamic>? ?? {};
    return ProfessionalBillingStatus(
      planCode: plan['code']?.toString() ?? '',
      planName: plan['name']?.toString() ?? '',
      planRenewsAt: json['plan_renews_at'] as String?,
      hasBillingAccount: json['has_billing_account'] as bool? ?? false,
      billingConfigured: json['billing_configured'] as bool? ?? false,
      testMode: json['test_mode'] as bool? ?? false,
      availableUpgrades:
          (json['available_upgrades'] as Map<dynamic, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k.toString(), v == true),
      ),
      catalog: Map<String, dynamic>.from(
        json['catalog'] as Map<dynamic, dynamic>? ?? {},
      ),
      billingCurrency: json['billing_currency']?.toString() ?? 'USD',
      billingRegion: json['billing_region']?.toString() ?? 'International',
      cancellationEffectiveAt: json['cancellation_effective_at'] as String?,
      downgradeEligible: assessment['eligible'] as bool? ?? true,
      freeStoragePercent: (storage['free_tier_percent'] as num?)?.toDouble() ?? 0,
      storageDowngradeEligible: storage['eligible'] as bool? ?? true,
      downgradeLocks: (assessment['locks'] as Map<dynamic, dynamic>? ?? {}).map(
        (key, value) => MapEntry(
          key.toString(),
          Map<String, dynamic>.from(value as Map<dynamic, dynamic>? ?? {}),
        ),
      ),
      categoryCascadeResourceCount:
          (assessment['category_cascade_resource_count'] as num?)?.toInt() ?? 0,
      clientsLosingAccess: (assessment['clients_losing_access'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>? ?? {}))
          .toList(),
      supportEmail: assessment['support_email']?.toString() ?? '',
    );
  }
}

/// 'chat_message' | 'resource' | 'client_account'
class RecycleBinItem {
  const RecycleBinItem({
    required this.id,
    required this.category,
    required this.categoryLabel,
    required this.title,
    required this.deletedByLabel,
    required this.deletedAt,
    required this.expiresAt,
    required this.daysRemaining,
  });

  final int id;
  final String category;
  final String categoryLabel;
  final String title;
  final String deletedByLabel;
  final String deletedAt;
  final String expiresAt;
  final int daysRemaining;

  factory RecycleBinItem.fromJson(Map<String, dynamic> json) => RecycleBinItem(
        id: (json['id'] as num?)?.toInt() ?? 0,
        category: json['category']?.toString() ?? '',
        categoryLabel: json['category_label']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        deletedByLabel: json['deleted_by_label']?.toString() ?? '',
        deletedAt: json['deleted_at']?.toString() ?? '',
        expiresAt: json['expires_at']?.toString() ?? '',
        daysRemaining: (json['days_remaining'] as num?)?.toInt() ?? 0,
      );
}
