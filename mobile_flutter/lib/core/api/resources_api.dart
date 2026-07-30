import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Professional resource library (categories + resources).
/// 1:1 port of mobile/src/app/core/api/resources-api.service.ts.

/// 'video_link' | 'pdf' | 'image' | 'text_note'
class ResourceType {
  const ResourceType._();

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

class ResourceCategoryRecord {
  const ResourceCategoryRecord({
    required this.id,
    required this.name,
    required this.description,
    required this.subcategories,
    required this.resourceCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String description;
  final List<String> subcategories;
  final int resourceCount;
  final String createdAt;
  final String updatedAt;

  factory ResourceCategoryRecord.fromJson(Map<String, dynamic> json) =>
      ResourceCategoryRecord(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        subcategories: (json['subcategories'] as List<dynamic>? ?? [])
            .map((s) => s.toString())
            .toList(),
        resourceCount: json['resource_count'] as int? ?? 0,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class ProfessionalResourceRecord {
  const ProfessionalResourceRecord({
    required this.id,
    required this.category,
    required this.categoryName,
    required this.subcategory,
    required this.title,
    required this.resourceType,
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
  final String resourceType;
  final String description;
  final String link;
  final String fileUrl;
  final String fileName;
  final List<String> tags;
  final String createdAt;
  final String updatedAt;

  factory ProfessionalResourceRecord.fromJson(Map<String, dynamic> json) =>
      ProfessionalResourceRecord(
        id: json['id'] as int? ?? 0,
        category: json['category'] as int? ?? 0,
        categoryName: json['category_name'] as String? ?? '',
        subcategory: json['subcategory'] as String? ?? '',
        title: json['title'] as String? ?? '',
        resourceType: json['resource_type'] as String? ?? '',
        description: json['description'] as String? ?? '',
        link: json['link'] as String? ?? '',
        fileUrl: json['file_url'] as String? ?? '',
        fileName: json['file_name'] as String? ?? '',
        tags: (json['tags'] as List<dynamic>? ?? []).map((t) => t.toString()).toList(),
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class ResourceUsage {
  const ResourceUsage({required this.used, required this.limit});

  final int used;

  /// null means unlimited.
  final int? limit;

  bool get atLimit => limit != null && used >= limit!;

  factory ResourceUsage.fromJson(Map<String, dynamic> json) => ResourceUsage(
        used: json['used'] as int? ?? 0,
        limit: json['limit'] as int?,
      );
}

class ResourceListResponse {
  const ResourceListResponse({required this.resources, required this.usage});

  final List<ProfessionalResourceRecord> resources;
  final ResourceUsage usage;
}

class ResourcePayload {
  const ResourcePayload({
    required this.category,
    required this.subcategory,
    required this.title,
    required this.resourceType,
    this.description = '',
    this.link = '',
    this.tags = const [],
    this.filePath,
    this.fileName,
  });

  final int category;
  final String subcategory;
  final String title;
  final String resourceType;
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
      'resource_type': resourceType,
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

class ResourcesApi {
  ResourcesApi(this._dio);

  final Dio _dio;

  static final _auth = authOptions(AuthScheme.professional);

  Future<List<ResourceCategoryRecord>> getCategories() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/resources/categories/',
        options: _auth,
      );
      return (res.data?['categories'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ResourceCategoryRecord.fromJson)
          .toList();
    });
  }

  Future<ResourceCategoryRecord> createCategory(
    String name,
    String description,
    List<String> subcategories,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/resources/categories/',
        data: {
          'name': name,
          'description': description,
          'subcategories': subcategories,
        },
        options: _auth,
      );
      return ResourceCategoryRecord.fromJson(
        res.data?['category'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<ResourceCategoryRecord> updateCategory(
    int categoryId,
    String name,
    String description,
    List<String> subcategories,
  ) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/resources/categories/$categoryId/',
        data: {
          'name': name,
          'description': description,
          'subcategories': subcategories,
        },
        options: _auth,
      );
      return ResourceCategoryRecord.fromJson(
        res.data?['category'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<String> deleteCategory(int categoryId) {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/professional/resources/categories/$categoryId/',
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  Future<ResourceListResponse> getResources() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/resources/',
        options: _auth,
      );
      return ResourceListResponse(
        resources: (res.data?['resources'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ProfessionalResourceRecord.fromJson)
            .toList(),
        usage: ResourceUsage.fromJson(
          res.data?['usage'] as Map<String, dynamic>? ?? {},
        ),
      );
    });
  }

  Future<ProfessionalResourceRecord> createResource(ResourcePayload payload) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/resources/',
        data: await payload.toFormData(),
        options: _auth,
      );
      return ProfessionalResourceRecord.fromJson(
        res.data?['resource'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<ProfessionalResourceRecord> updateResource(
    int resourceId,
    ResourcePayload payload,
  ) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/resources/$resourceId/',
        data: await payload.toFormData(),
        options: _auth,
      );
      return ProfessionalResourceRecord.fromJson(
        res.data?['resource'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<String> deleteResource(int resourceId) {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/professional/resources/$resourceId/',
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }
}

final resourcesApiProvider =
    Provider<ResourcesApi>((ref) => ResourcesApi(ref.watch(dioProvider)));
