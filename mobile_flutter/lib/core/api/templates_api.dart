import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models/template_models.dart';

/// Tracking templates, assignments, and entries.
/// 1:1 port of mobile/src/app/core/api/templates-api.service.ts.
class TemplateListResponse {
  const TemplateListResponse({
    required this.templates,
    required this.maxTemplates,
  });

  final List<TrackingTemplateRecord> templates;
  final int maxTemplates;

  bool get atLimit => maxTemplates > 0 && templates.length >= maxTemplates;
}

class TemplatesApi {
  TemplatesApi(this._dio);

  final Dio _dio;

  static final _auth = authOptions(AuthScheme.professional);

  Future<TemplateListResponse> getTemplates() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/templates/',
        options: _auth,
      );
      return TemplateListResponse(
        templates: (res.data?['templates'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(TrackingTemplateRecord.fromJson)
            .toList(),
        maxTemplates: res.data?['max_templates'] as int? ?? 0,
      );
    });
  }

  Future<TrackingTemplateRecord> getTemplate(int templateId) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/templates/$templateId/',
        options: _auth,
      );
      return TrackingTemplateRecord.fromJson(
        res.data?['template'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<List<StandardTemplateRecord>> getStandardTemplates() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/templates/standard/',
        options: _auth,
      );
      return (res.data?['standard_templates'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(StandardTemplateRecord.fromJson)
          .toList();
    });
  }

  Future<TrackingTemplateRecord> adoptStandardTemplate(String key) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/templates/adopt-standard/',
        data: {'key': key},
        options: _auth,
      );
      return TrackingTemplateRecord.fromJson(
        res.data?['template'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<TrackingTemplateRecord> createTemplate(TemplatePayload payload) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/templates/',
        data: payload.toJson(),
        options: _auth,
      );
      return TrackingTemplateRecord.fromJson(
        res.data?['template'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<TrackingTemplateRecord> updateTemplate(
    int templateId,
    TemplatePayload payload,
  ) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/templates/$templateId/',
        data: payload.toJson(),
        options: _auth,
      );
      return TrackingTemplateRecord.fromJson(
        res.data?['template'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<String> deleteTemplate(int templateId) {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/professional/templates/$templateId/',
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  // ----- assignments -----

  Future<List<TemplateAssignmentRecord>> getAssignments(int clientId) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/assignments/',
        options: _auth,
      );
      return (res.data?['assignments'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(TemplateAssignmentRecord.fromJson)
          .toList();
    });
  }

  Future<TemplateAssignmentRecord> assignTemplate(
    int clientId,
    int templateId, {
    List<int> referenceIds = const [],
    String clientAccessLevel = 'editable',
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/assignments/',
        data: {
          'template_id': templateId,
          'reference_ids': referenceIds,
          'client_access_level': clientAccessLevel,
        },
        options: _auth,
      );
      return TemplateAssignmentRecord.fromJson(
        res.data?['assignment'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  /// 'private' | 'view_only' | 'editable' — controls whether the client can
  /// see and edit their own entries for this assignment.
  Future<TemplateAssignmentRecord> updateAssignmentAccessLevel(
    int clientId,
    int assignmentId,
    String clientAccessLevel,
  ) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/assignments/$assignmentId/',
        data: {'client_access_level': clientAccessLevel},
        options: _auth,
      );
      return TemplateAssignmentRecord.fromJson(
        res.data?['assignment'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<TemplateAssignmentRecord> updateAssignmentReferences(
    int clientId,
    int assignmentId,
    List<int> referenceIds,
  ) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/assignments/$assignmentId/',
        data: {'reference_ids': referenceIds},
        options: _auth,
      );
      return TemplateAssignmentRecord.fromJson(
        res.data?['assignment'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<String> unassignTemplate(int clientId, int assignmentId) {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/assignments/$assignmentId/',
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  // ----- entries -----

  Future<List<TrackingEntryRecord>> getClientEntries(
    int clientId, {
    EntryFilters filters = const EntryFilters(),
  }) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/entries/',
        queryParameters: filters.toQuery(),
        options: _auth,
      );
      return (res.data?['entries'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(TrackingEntryRecord.fromJson)
          .toList();
    });
  }

  Future<TrackingEntryRecord> createClientEntry(
    int clientId, {
    required int templateId,
    required String entryDate,
    required Map<String, String> answers,
    String note = '',
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/entries/',
        data: {
          'template_id': templateId,
          'entry_date': entryDate,
          'answers': answers,
          'note': note,
        },
        options: _auth,
      );
      return TrackingEntryRecord.fromJson(
        res.data?['entry'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  /// Note the different route: entries are edited at `/professional/entries/{id}/`,
  /// not under the client path.
  Future<TrackingEntryRecord> updateEntry(
    int entryId, {
    required Map<String, String> answers,
    required String note,
    String? entryDate,
    String? entryTime,
  }) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/entries/$entryId/',
        data: {
          'answers': answers,
          'note': note,
          'entry_date': ?entryDate,
          'entry_time': ?entryTime,
        },
        options: _auth,
      );
      return TrackingEntryRecord.fromJson(
        res.data?['entry'] as Map<String, dynamic>? ?? {},
      );
    });
  }
}

final templatesApiProvider = Provider<TemplatesApi>(
  (ref) => TemplatesApi(ref.watch(dioProvider)),
);
