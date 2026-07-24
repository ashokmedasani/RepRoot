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
        'premium_unlimited' => 'Premium (Unlimited)',
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

  List<String> get upgradeTiers =>
      availableUpgrades.entries.where((e) => e.value).map((e) => e.key).toList();

  factory ProfessionalBillingStatus.fromJson(Map<String, dynamic> json) {
    final plan = json['plan'] as Map<String, dynamic>? ?? {};
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
    );
  }
}

/// 'chat_message' | 'reference' | 'client_account'
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
