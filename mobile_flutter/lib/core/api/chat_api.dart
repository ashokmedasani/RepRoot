import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Professional-side chat with a client.
/// 1:1 port of mobile/src/app/core/api/chat-api.service.ts.
class ChatMessageRecord {
  const ChatMessageRecord({
    required this.id,
    required this.sender,
    required this.text,
    required this.createdAt,
  });

  final int id;

  /// 'professional' | 'client'
  final String sender;
  final String text;
  final String createdAt;

  bool get isProfessional => sender == 'professional';

  factory ChatMessageRecord.fromJson(Map<String, dynamic> json) =>
      ChatMessageRecord(
        id: json['id'] as int? ?? 0,
        sender: json['sender'] as String? ?? '',
        text: json['text'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
      );
}

class ProfessionalUnreadSummary {
  const ProfessionalUnreadSummary({
    required this.unreadCount,
    required this.byClient,
    this.lastUnreadAt = const {},
  });

  final int unreadCount;

  /// client id (as string) -> unread count
  final Map<String, int> byClient;

  /// client id (as string) -> newest unread message time, for ordering waiting
  /// chats. Only holds clients that appear in [byClient].
  final Map<String, DateTime> lastUnreadAt;

  int forClient(int clientId) => byClient['$clientId'] ?? 0;

  DateTime? lastUnreadFor(int clientId) => lastUnreadAt['$clientId'];

  factory ProfessionalUnreadSummary.fromJson(Map<String, dynamic> json) =>
      ProfessionalUnreadSummary(
        unreadCount: json['unread_count'] as int? ?? 0,
        byClient: (json['by_client'] as Map<dynamic, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
        ),
        lastUnreadAt: {
          for (final entry
              in (json['last_unread_at'] as Map<dynamic, dynamic>? ?? {}).entries)
            // The `?` drops the entry when the timestamp won't parse, so one bad
            // row can't take the whole ordering down with it.
            entry.key.toString(): ?DateTime.tryParse('${entry.value}'),
        },
      );
}

class ChatApi {
  ChatApi(this._dio);

  final Dio _dio;

  static final _auth = authOptions(AuthScheme.professional);

  /// [afterId] polls only for messages newer than the last one seen.
  Future<List<ChatMessageRecord>> getProfessionalMessages(
    int clientId, {
    int? afterId,
  }) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/clients/$clientId/chat/',
        queryParameters: afterId != null && afterId > 0 ? {'after': '$afterId'} : null,
        options: _auth,
      );
      return (res.data?['messages'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ChatMessageRecord.fromJson)
          .toList();
    });
  }

  Future<ChatMessageRecord> sendProfessionalMessage(int clientId, String text) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/clients/$clientId/chat/',
        data: {'text': text},
        options: _auth,
      );
      final message = res.data?['chat_message'];
      return ChatMessageRecord.fromJson(
        message is Map<String, dynamic> ? message : {},
      );
    });
  }

  Future<ProfessionalUnreadSummary> getProfessionalUnreadCounts() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/chat/unread/',
        options: _auth,
      );
      return ProfessionalUnreadSummary.fromJson(res.data ?? {});
    });
  }
}

final chatApiProvider = Provider<ChatApi>((ref) => ChatApi(ref.watch(dioProvider)));
