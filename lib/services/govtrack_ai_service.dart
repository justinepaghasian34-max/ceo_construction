import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';

class GovTrackAiService {
  GovTrackAiService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Map<String, dynamic> _sanitizeAnalysis(Map<String, dynamic> analysis) {
    String readString(dynamic v) => (v ?? '').toString().trim();

    List<Map<String, dynamic>> readMapList(dynamic value) {
      final raw = value is List ? value : const <dynamic>[];
      return raw
          .map((e) => (e as Map?)?.cast<String, dynamic>())
          .whereType<Map<String, dynamic>>()
          .toList();
    }

    List<Map<String, dynamic>> keepWithEvidence(List<Map<String, dynamic>> items) {
      return items.where((e) => readString(e['evidence']).isNotEmpty).toList();
    }

    final confidenceRaw = analysis['confidence'];
    final confidence = (confidenceRaw is num ? confidenceRaw.toDouble() : 0.0).clamp(0.0, 1.0);

    final summary = readString(analysis['summary']);
    final schedule = (analysis['schedule'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final budget = (analysis['budget'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    final tasks = keepWithEvidence(readMapList(analysis['tasks']));
    final delaySignals = keepWithEvidence(readMapList(analysis['delaySignals']));
    final materialShortages = keepWithEvidence(readMapList(analysis['materialShortages']));
    final risks = keepWithEvidence(readMapList(analysis['risks']));
    final recommendations = keepWithEvidence(readMapList(analysis['recommendations']));

    return <String, dynamic>{
      ...analysis,
      'summary': summary.isEmpty ? 'Insufficient data' : summary,
      'confidence': confidence,
      'pass': analysis['pass'] == true,
      'schedule': <String, dynamic>{
        ...schedule,
        'deltaPercent': readString(schedule['deltaPercent']),
        'status': readString(schedule['status']),
        'notes': readString(schedule['notes']).isEmpty ? 'Insufficient data' : readString(schedule['notes']),
      },
      'budget': <String, dynamic>{
        ...budget,
        'deltaPercent': readString(budget['deltaPercent']),
        'status': readString(budget['status']),
        'notes': readString(budget['notes']).isEmpty ? 'Insufficient data' : readString(budget['notes']),
      },
      'risks': risks,
      'recommendations': recommendations,
      'labels': (analysis['labels'] is List) ? analysis['labels'] : const <dynamic>[],
      'tasks': tasks,
      'delaySignals': delaySignals,
      'materialShortages': materialShortages,
    };
  }

  Map<String, dynamic> _decodeModelJsonObject(String content) {
    dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      final start = content.indexOf('{');
      final end = content.lastIndexOf('}');
      if (start < 0 || end < 0 || end <= start) {
        rethrow;
      }
      final candidate = content.substring(start, end + 1);
      decoded = jsonDecode(candidate);
    }

    if (decoded is! Map) {
      throw Exception('Ollama response was not a JSON object.');
    }
    return decoded.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> generateGovTrackReport({
    required String projectId,
    required String projectName,
    required Map<String, dynamic> projectData,
    required List<Map<String, dynamic>> recentDailyReports,
  }) async {
    final callable = _functions.httpsCallable('generateGovTrackReportGemini');
    final res = await callable.call(<String, dynamic>{
      'projectId': projectId,
      'projectName': projectName,
      'projectData': projectData,
      'recentDailyReports': recentDailyReports,
    });

    final data = (res.data as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final analysis = (data['analysis'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    if (analysis.isEmpty) {
      throw Exception('Gemini returned empty analysis.');
    }

    return _sanitizeAnalysis(analysis);
  }
}
