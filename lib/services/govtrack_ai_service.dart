import 'dart:convert';

import 'package:dio/dio.dart';

class GovTrackAiService {
  GovTrackAiService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String defaultBaseUrl = 'http://127.0.0.1:11434';
  static const String defaultModel = 'llama3';

  Future<Map<String, dynamic>> generateGovTrackReport({
    required String projectId,
    required String projectName,
    required Map<String, dynamic> projectData,
    required List<Map<String, dynamic>> recentDailyReports,
    String baseUrl = defaultBaseUrl,
    String model = defaultModel,
  }) async {
    final payload = <String, dynamic>{
      'projectId': projectId,
      'projectName': projectName,
      'project': projectData,
      'recentDailyReports': recentDailyReports,
    };

    final systemPrompt = '''You are GovTrack AI. Generate a concise construction monitoring report.
Return STRICT JSON ONLY (no markdown) with keys:
- summary (string)
- confidence (number 0..1)
- pass (boolean)
- schedule (object {deltaPercent:string, status:string, notes:string})
- budget (object {deltaPercent:string, status:string, notes:string})
- risks (array of strings)
- recommendations (array of strings)
- labels (array of short strings)
Use available data only; if unknown, write notes as "Insufficient data".
Keep summary under 120 words.''';

    final res = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/chat',
      options: Options(
        headers: const <String, dynamic>{
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.json,
      ),
      data: <String, dynamic>{
        'model': model,
        'stream': false,
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{'role': 'system', 'content': systemPrompt},
          <String, dynamic>{
            'role': 'user',
            'content': 'Generate the report for this data:\n${jsonEncode(payload)}',
          },
        ],
      },
    );

    final data = res.data ?? <String, dynamic>{};
    final message = (data['message'] as Map?)?.cast<String, dynamic>();
    final content = (message?['content'] ?? '').toString().trim();

    if (content.isEmpty) {
      throw Exception('Ollama returned an empty response.');
    }

    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw Exception('Ollama response was not a JSON object.');
    }

    return decoded.cast<String, dynamic>();
  }
}
