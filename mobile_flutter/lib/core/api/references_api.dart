import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Professional reference library (categories + references).
/// 1:1 port of mobile/src/app/core/api/references-api.service.ts.

/// 'video_link' | 'pdf' | 'image' | 'text_note'
class ReferenceType {
  const ReferenceType._();

  static const videoLink = 'video_link';
  static const pdf = 'pdf';
  static const image = 'image';
  static const textNote = 'text_note';

  static const all = [videoLink, pdf, image, textNote];

  static String label(String type) => switch (type) {
        videoLink => 'Video link',
        pdf => 'PDF',
        image => 'Image',
        textNote => 'Text note',
        _ => type,
      };
}

class ReferenceCategoryRecord {
  const ReferenceCategoryRecord({
    required this.id,
    required this.name,
    required this.description,
    required this.subcategories,
    required this.referenceCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String description;
  final List<String> subcategories;
  final int referenceCount;
  final String createdAt;
  final String updatedAt;

  factory ReferenceCategoryRecord.fromJson(Map<String, dynamic> json) =>
      ReferenceCategoryRecord(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        subcategories: (json['subcategories'] as List<dynamic>? ?? [])
            .map((s) => s.toString())
            .toList(),
        referenceCount: json['reference_count'] as int? ?? 0,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class ProfessionalReferenceRecord {
  const ProfessionalReferenceRecord({
    required this.id,
    required this.category,
    required this.categoryName,
    required this.subcategory,
    required this.title,
    required this.referenceType,
    required this.description,
    required this.link,
    required this.fileUrl,
    required this.fileName,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int category;
  final String categoryName;
  final String subcategory;
  final String title;
  final String referenceType;
  final String description;
  final String link;
  final String fileUrl;
  final String fileName;
  final List<String> tags;
  final String createdAt;
  final String updatedAt;

  factory ProfessionalReferenceRecord.fromJson(Map<String, dynamic> json) =>
      ProfessionalReferenceRecord(
        id: json['id'] as int? ?? 0,
        category: json['category'] as int? ?? 0,
        categoryName: json['category_name'] as String? ?? '',
        subcategory: json['subcategory'] as String? ?? '',
        title: json['title'] as String? ?? '',
        referenceType: json['reference_type'] as String? ?? '',
        description: json['description'] as String? ?? '',
        link: json['link'] as String? ?? '',
        fileUrl: json['file_url'] as String? ?? '',
        fileName: json['file_name'] as String? ?? '',
        tags: (json['tags'] as List<dynamic>? ?? []).map((t) => t.toString()).toList(),
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class ReferenceUsage {
  const ReferenceUsage({required this.used, required this.limit});

  final int used;

  /// null means unlimited.
  final int? limit;

  bool get atLimit => limit != null && used >= limit!;

  factory ReferenceUsage.fromJson(Map<String, dynamic> json) => ReferenceUsage(
        used: json['used'] as int? ?? 0,
        limit: json['limit'] as int?,
      );
}

class ReferenceListResponse {
  const ReferenceListResponse({required this.references, required this.usage});

  final List<ProfessionalReferenceRecord> references;
  final ReferenceUsage usage;
}

class ReferencePayload {
  const ReferencePayload({
    required this.category,
    required this.subcategory,
    required this.title,
    required this.referenceType,
    this.description = '',
    this.link = '',
    this.tags = const [],
    this.filePath,
    this.fileName,
  });

  final int category;
  final String subcategory;
  final String title;
  final String referenceType;
  final String description;
  final String link;
  final List<String> tags;

  /// Local path of a picked file; null keeps the existing upload on update.
  final String? filePath;
  final String? fileName;

  Future<FormData> toFormData() async {
    final map = <String, dynamic>{
      'category': '$category',
      'subcategory': subcategory,
      'title': title,
      'reference_type': referenceType,
      'description': description,
      'link': link,
      // The backend expects a comma-joined string, not a list.
      'tags': tags.join(','),
    };
    if (filePath != null && filePath!.isNotEmpty) {
      map['file'] = await MultipartFile.fromFile(filePath!, filename: fileName);
    }
    return FormData.fromMap(map);
  }
}

class ReferencesApi {
  ReferencesApi(this._dio);

  final Dio _dio;

  static final _auth = authOptions(AuthScheme.professional);

  Future<List<ReferenceCategoryRecord>> getCategories() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/references/categories/',
        options: _auth,
      );
      return (res.data?['categories'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ReferenceCategoryRecord.fromJson)
          .toList();
    });
  }

  Future<ReferenceCategoryRecord> createCategory(
    String name,
    String description,
    List<String> subcategories,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/references/categories/',
        data: {
          'name': name,
          'description': description,
          'subcategories': subcategories,
        },
        options: _auth,
      );
      return ReferenceCategoryRecord.fromJson(
        res.data?['category'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<ReferenceCategoryRecord> updateCategory(
    int categoryId,
    String name,
    String description,
    List<String> subcategories,
  ) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/references/categories/$categoryId/',
        data: {
          'name': name,
          'description': description,
          'subcategories': subcategories,
        },
        options: _auth,
      );
      return ReferenceCategoryRecord.fromJson(
        res.data?['category'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<String> deleteCategory(int categoryId) {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/professional/references/categories/$categoryId/',
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  Future<ReferenceListResponse> getReferences() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/references/',
        options: _auth,
      );
      return ReferenceListResponse(
        references: (res.data?['references'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ProfessionalReferenceRecord.fromJson)
            .toList(),
        usage: ReferenceUsage.fromJson(
          res.data?['usage'] as Map<String, dynamic>? ?? {},
        ),
      );
    });
  }

  Future<ProfessionalReferenceRecord> createReference(ReferencePayload payload) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/references/',
        data: await payload.toFormData(),
        options: _auth,
      );
      return ProfessionalReferenceRecord.fromJson(
        res.data?['reference'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<ProfessionalReferenceRecord> updateReference(
    int referenceId,
    ReferencePayload payload,
  ) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/references/$referenceId/',
        data: await payload.toFormData(),
        options: _auth,
      );
      return ProfessionalReferenceRecord.fromJson(
        res.data?['reference'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<String> deleteReference(int referenceId) {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/professional/references/$referenceId/',
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }
}

final referencesApiProvider =
    Provider<ReferencesApi>((ref) => ReferencesApi(ref.watch(dioProvider)));
