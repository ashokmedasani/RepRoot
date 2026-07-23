/// Template/entry models shared by professional and client screens.
/// 1:1 port of mobile/src/app/core/api/templates-api.service.ts.
/// Field names match the Django payloads exactly; do not rename them.
library;

import '../../../shared/charts/analytics_types.dart';

/// 'number' | 'short_text' | 'long_text' | 'yes_no' | 'dropdown' | 'rating'
class TemplateFieldType {
  const TemplateFieldType._();

  static const number = 'number';
  static const shortText = 'short_text';
  static const longText = 'long_text';
  static const yesNo = 'yes_no';
  static const dropdown = 'dropdown';
  static const rating = 'rating';

  static const all = [number, shortText, longText, yesNo, dropdown, rating];

  static String label(String type) => switch (type) {
        number => 'Number',
        shortText => 'Short text',
        longText => 'Long text',
        yesNo => 'Yes / No',
        dropdown => 'Dropdown',
        rating => 'Rating',
        _ => type,
      };
}

/// 'daily' | 'weekly' | 'monthly'
class TemplateCadence {
  const TemplateCadence._();

  static const daily = 'daily';
  static const weekly = 'weekly';
  static const monthly = 'monthly';

  static const all = [daily, weekly, monthly];

  static String label(String cadence) =>
      cadence.isEmpty ? '' : cadence[0].toUpperCase() + cadence.substring(1);
}

class TemplateField {
  const TemplateField({
    this.key = '',
    required this.label,
    required this.fieldType,
    this.placeholder = '',
    this.options = const [],
    this.scale,
  });

  final String key;
  final String label;
  final String fieldType;
  final String placeholder;
  final List<String> options;
  final int? scale;

  /// The engine keys answers by `key || label` — same rule as the TS.
  String get answerKey => key.isNotEmpty ? key : label;

  /// Bridges to the graph engine's field shape.
  FieldLike toFieldLike() => FieldLike(
        key: key,
        label: label,
        fieldType: fieldType,
        options: options,
        scale: scale,
      );

  TemplateField copyWith({
    String? key,
    String? label,
    String? fieldType,
    String? placeholder,
    List<String>? options,
    int? scale,
    bool clearScale = false,
  }) =>
      TemplateField(
        key: key ?? this.key,
        label: label ?? this.label,
        fieldType: fieldType ?? this.fieldType,
        placeholder: placeholder ?? this.placeholder,
        options: options ?? this.options,
        scale: clearScale ? null : (scale ?? this.scale),
      );

  factory TemplateField.fromJson(Map<String, dynamic> json) => TemplateField(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        fieldType: json['field_type'] as String? ?? '',
        placeholder: json['placeholder'] as String? ?? '',
        options: (json['options'] as List<dynamic>? ?? [])
            .map((o) => o.toString())
            .toList(),
        scale: (json['scale'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        if (key.isNotEmpty) 'key': key,
        'label': label,
        'field_type': fieldType,
        'placeholder': placeholder,
        if (options.isNotEmpty) 'options': options,
        if (scale != null) 'scale': scale,
      };
}

class TemplateReference {
  const TemplateReference({
    required this.id,
    required this.title,
    required this.referenceType,
    required this.categoryName,
    required this.subcategory,
    required this.description,
    required this.link,
    required this.fileUrl,
    required this.tags,
  });

  final int id;
  final String title;
  final String referenceType;
  final String categoryName;
  final String subcategory;
  final String description;
  final String link;
  final String fileUrl;
  final List<String> tags;

  factory TemplateReference.fromJson(Map<String, dynamic> json) =>
      TemplateReference(
        id: json['id'] as int? ?? 0,
        title: json['title'] as String? ?? '',
        referenceType: json['reference_type'] as String? ?? '',
        categoryName: json['category_name'] as String? ?? '',
        subcategory: json['subcategory'] as String? ?? '',
        description: json['description'] as String? ?? '',
        link: json['link'] as String? ?? '',
        fileUrl: json['file_url'] as String? ?? '',
        tags: (json['tags'] as List<dynamic>? ?? []).map((t) => t.toString()).toList(),
      );
}

class TrackingTemplateRecord {
  const TrackingTemplateRecord({
    required this.id,
    required this.name,
    required this.purpose,
    required this.cadence,
    required this.accent,
    required this.fields,
    required this.standardKey,
    required this.assignedCount,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.assignmentId,
    this.references = const [],
  });

  final int id;
  final String name;
  final String purpose;
  final String cadence;
  final String accent;
  final List<TemplateField> fields;
  final String standardKey;
  final int assignedCount;
  final bool isActive;
  final String createdAt;
  final String updatedAt;
  final int? assignmentId;
  final List<TemplateReference> references;

  factory TrackingTemplateRecord.fromJson(Map<String, dynamic> json) =>
      TrackingTemplateRecord(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        purpose: json['purpose'] as String? ?? '',
        cadence: json['cadence'] as String? ?? '',
        accent: json['accent'] as String? ?? '',
        fields: (json['fields'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(TemplateField.fromJson)
            .toList(),
        standardKey: json['standard_key'] as String? ?? '',
        assignedCount: json['assigned_count'] as int? ?? 0,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
        assignmentId: json['assignment_id'] as int?,
        references: (json['references'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(TemplateReference.fromJson)
            .toList(),
      );
}

class StandardTemplateRecord {
  const StandardTemplateRecord({
    required this.key,
    required this.name,
    required this.purpose,
    required this.cadence,
    required this.accent,
    required this.fields,
    required this.adopted,
  });

  final String key;
  final String name;
  final String purpose;
  final String cadence;
  final String accent;
  final List<TemplateField> fields;
  final bool adopted;

  factory StandardTemplateRecord.fromJson(Map<String, dynamic> json) =>
      StandardTemplateRecord(
        key: json['key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        purpose: json['purpose'] as String? ?? '',
        cadence: json['cadence'] as String? ?? '',
        accent: json['accent'] as String? ?? '',
        fields: (json['fields'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(TemplateField.fromJson)
            .toList(),
        adopted: json['adopted'] as bool? ?? false,
      );
}

class TemplatePayload {
  const TemplatePayload({
    required this.name,
    required this.purpose,
    required this.cadence,
    required this.accent,
    required this.customFields,
  });

  final String name;
  final String purpose;
  final String cadence;
  final String accent;
  final List<TemplateField> customFields;

  Map<String, dynamic> toJson() => {
        'name': name,
        'purpose': purpose,
        'cadence': cadence,
        'accent': accent,
        'custom_fields': customFields.map((f) => f.toJson()).toList(),
      };
}

class TemplateAssignmentRecord {
  const TemplateAssignmentRecord({
    required this.id,
    required this.templateId,
    required this.templateName,
    required this.templateCadence,
    required this.templateAccent,
    required this.references,
    required this.assignedAt,
  });

  final int id;
  final int templateId;
  final String templateName;
  final String templateCadence;
  final String templateAccent;
  final List<TemplateReference> references;
  final String assignedAt;

  factory TemplateAssignmentRecord.fromJson(Map<String, dynamic> json) =>
      TemplateAssignmentRecord(
        id: json['id'] as int? ?? 0,
        templateId: json['template_id'] as int? ?? 0,
        templateName: json['template_name'] as String? ?? '',
        templateCadence: json['template_cadence'] as String? ?? '',
        templateAccent: json['template_accent'] as String? ?? '',
        references: (json['references'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(TemplateReference.fromJson)
            .toList(),
        assignedAt: json['assigned_at'] as String? ?? '',
      );
}

class TrackingEntryRecord {
  const TrackingEntryRecord({
    required this.id,
    required this.client,
    required this.template,
    required this.templateName,
    required this.entryDate,
    required this.entryTime,
    required this.answers,
    required this.note,
    required this.editedByProfessional,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int client;
  final int? template;
  final String templateName;
  final String entryDate;
  final String entryTime;
  final Map<String, String> answers;
  final String note;
  final bool editedByProfessional;
  final String createdAt;
  final String updatedAt;

  /// Bridges to the graph engine's entry shape.
  EntryLike toEntryLike() => EntryLike(
        entryDate: entryDate,
        entryTime: entryTime,
        answers: answers,
        createdAt: createdAt,
      );

  factory TrackingEntryRecord.fromJson(Map<String, dynamic> json) =>
      TrackingEntryRecord(
        id: json['id'] as int? ?? 0,
        client: json['client'] as int? ?? 0,
        template: json['template'] as int?,
        templateName: json['template_name'] as String? ?? '',
        entryDate: json['entry_date'] as String? ?? '',
        entryTime: json['entry_time'] as String? ?? '',
        answers: (json['answers'] as Map<dynamic, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        ),
        note: json['note'] as String? ?? '',
        editedByProfessional: json['edited_by_professional'] as bool? ?? false,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class EntryFilters {
  const EntryFilters({this.template, this.month});

  final int? template;

  /// YYYY-MM
  final String? month;

  Map<String, dynamic>? toQuery() {
    final query = <String, dynamic>{};
    if (template != null && template! > 0) query['template'] = '$template';
    if (month != null && month!.isNotEmpty) query['month'] = month;
    return query.isEmpty ? null : query;
  }
}
