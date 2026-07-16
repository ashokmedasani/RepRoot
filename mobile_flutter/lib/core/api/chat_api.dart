import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Trainer-side chat with a client.
/// 1:1 port of mobile/src/app/core/api/chat-api.service.ts.
class ChatMessageRecord {
  const ChatMessageRecord({
    required this.id,
    required this.sender,
    required this.text,
    required this.createdAt,
  });

  final int id;

  /// 'trainer' | 'client'
  final String sender;
  final String text;
  final String createdAt;

  bool get isTrainer => sender == 'trainer';

  factory ChatMessageRecord.fromJson(Map<String, dynamic> json) =>
      ChatMessageRecord(
        id: json['id'] as int? ?? 0,
        sender: json['sender'] as String? ?? '',
        text: json['text'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
      );
}

class TrainerUnreadSummary {
  const TrainerUnreadSummary({required this.unreadCount, required this.byClient});

  final int unreadCount;

  /// client id (as string) -> unread count
  final Map<String, int> byClient;

  int forClient(int clientId) => byClient['$clientId'] ?? 0;

  factory TrainerUnreadSummary.fromJson(Map<String, dynamic> json) =>
      TrainerUnreadSummary(
        unreadCount: json['unread_count'] as int? ?? 0,
        byClient: (json['by_client'] as Map<dynamic, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
        ),
      );
}

class ChatApi {
  ChatApi(this._dio);

  final Dio _dio;

  static final _auth = authOptions(AuthScheme.trainer);

  /// [afterId] polls only for messages newer than the last one seen.
  Future<List<ChatMessageRecord>> getTrainerMessages(
    int clientId, {
    int? afterId,
  }) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/trainer/clients/$clientId/chat/',
        queryParameters: afterId != null && afterId > 0 ? {'after': '$afterId'} : null,
        options: _auth,
      );
      return (res.data?['messages'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ChatMessageRecord.fromJson)
          .toList();
    });
  }

  Future<ChatMessageRecord> sendTrainerMessage(int clientId, String text) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trainer/clients/$clientId/chat/',
        data: {'text': text},
        options: _auth,
      );
      final message = res.data?['chat_message'];
      return ChatMessageRecord.fromJson(
        message is Map<String, dynamic> ? message : {},
      );
    });
  }

  Future<TrainerUnreadSummary> getTrainerUnreadCounts() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/trainer/chat/unread/',
        options: _auth,
      );
      return TrainerUnreadSummary.fromJson(res.data ?? {});
    });
  }
}

final chatApiProvider = Provider<ChatApi>((ref) => ChatApi(ref.watch(dioProvider)));
