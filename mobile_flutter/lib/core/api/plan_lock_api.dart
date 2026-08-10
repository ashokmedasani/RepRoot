import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Plan-limit lock system (backend accounts/plan_lock_status.py +
/// PlanLockStatusView / PlanLockReorderView).
/// 1:1 port of frontend/src/app/core/api/plan-lock-api.service.ts.
///
/// A group / lead form / template / category / resource that sits past the
/// current plan's count limit is *locked*, never deleted: it stays in the
/// account, just excluded from the active set until the professional upgrades
/// or frees a slot. Only currently-ACTIVE items can be reordered — the
/// backend rejects any submitted order that smuggles in a locked id or drops
/// an active one (see plan_lock_status.reorder_active_items).
class PlanLockModelKey {
  const PlanLockModelKey._();

  static const groups = 'groups';
  static const leadForms = 'lead_forms';
  static const templates = 'templates';
  static const categories = 'categories';
  static const resources = 'resources';
}

/// One model's split between what is live and what is locked. `activeIds` is
/// in priority (rank) order and is the single source of truth for display
/// order — never a separately tracked local list, so a drag can't drift out
/// of sync with what the backend believes the order is.
class PlanLockSection {
  const PlanLockSection({this.activeIds = const [], this.lockedIds = const []});

  final List<int> activeIds;
  final List<int> lockedIds;

  bool isLocked(int id) => lockedIds.contains(id);

  PlanLockSection copyWith({List<int>? activeIds, List<int>? lockedIds}) =>
      PlanLockSection(
        activeIds: activeIds ?? this.activeIds,
        lockedIds: lockedIds ?? this.lockedIds,
      );

  factory PlanLockSection.fromJson(Map<String, dynamic> json) =>
      PlanLockSection(
        activeIds: (json['active_ids'] as List<dynamic>? ?? [])
            .map((id) => (id as num).toInt())
            .toList(),
        lockedIds: (json['locked_ids'] as List<dynamic>? ?? [])
            .map((id) => (id as num).toInt())
            .toList(),
      );
}

class PlanLockStatus {
  const PlanLockStatus({this.sections = const {}});

  final Map<String, PlanLockSection> sections;

  /// Missing keys read as "nothing known yet", so a screen that renders
  /// before the status call lands simply shows no lock badges instead of
  /// throwing.
  PlanLockSection section(String modelKey) =>
      sections[modelKey] ?? const PlanLockSection();

  PlanLockStatus withSection(String modelKey, PlanLockSection section) =>
      PlanLockStatus(sections: {...sections, modelKey: section});

  factory PlanLockStatus.fromJson(Map<String, dynamic> json) => PlanLockStatus(
    sections: json.map(
      (key, value) => MapEntry(
        key.toString(),
        PlanLockSection.fromJson(
          (value as Map<dynamic, dynamic>? ?? {}).cast<String, dynamic>(),
        ),
      ),
    ),
  );
}

class PlanLockApi {
  PlanLockApi(this._dio);

  final Dio _dio;

  static final _auth = authOptions(AuthScheme.professional);

  Future<PlanLockStatus> getLockStatus() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/plan-lock/status/',
        options: _auth,
      );
      return PlanLockStatus.fromJson(
        (res.data?['lock_status'] as Map<dynamic, dynamic>? ?? {})
            .cast<String, dynamic>(),
      );
    });
  }

  /// [orderedIds] must be exactly the professional's current active ids for
  /// [modelKey], just permuted. The response carries the freshly recomputed
  /// lock status, which is what the caller should adopt.
  Future<PlanLockStatus> reorder(String modelKey, List<int> orderedIds) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/plan-lock/reorder/',
        data: {'model_key': modelKey, 'ordered_ids': orderedIds},
        options: _auth,
      );
      return PlanLockStatus.fromJson(
        (res.data?['lock_status'] as Map<dynamic, dynamic>? ?? {})
            .cast<String, dynamic>(),
      );
    });
  }
}

final planLockApiProvider = Provider<PlanLockApi>(
  (ref) => PlanLockApi(ref.watch(dioProvider)),
);
