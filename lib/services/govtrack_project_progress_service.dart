import 'firebase_service.dart';

class ProjectProgressSnapshot {
  const ProjectProgressSnapshot({
    required this.overallPercent,
    required this.foundation,
    required this.structural,
    required this.electrical,
    required this.finishing,
  });

  final double overallPercent;
  final double foundation;
  final double structural;
  final double electrical;
  final double finishing;
}

class GovtrackProjectProgressService {
  static Future<ProjectProgressSnapshot> load(String projectId) async {
    final projectSnap = await FirebaseService.instance.projectsCollection.doc(projectId).get();
    final projectData = (projectSnap.data() as Map<String, dynamic>?) ?? {};

    double overall = _readPercent(projectData['progressPercentage'] ?? projectData['progress']);

    double foundation = 0;
    double structural = 0;
    double electrical = 0;
    double finishing = 0;

    try {
      final aiSnap = await FirebaseService.instance.aiAnalysisCollection
          .where('projectId', isEqualTo: projectId)
          .where('kind', isEqualTo: 'govtrack_progress_report')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (aiSnap.docs.isNotEmpty) {
        final ai = (aiSnap.docs.first.data() as Map<String, dynamic>?) ?? {};
        final pct = ai['progressPercent'];
        if (pct is num) {
          overall = pct.toDouble().clamp(0, 100);
        }

        final analysis = (ai['analysis'] as Map?)?.cast<String, dynamic>() ?? {};
        final stage = (analysis['stageProgress'] as Map?)?.cast<String, dynamic>()
            ?? (ai['stageProgress'] as Map?)?.cast<String, dynamic>();

        if (stage != null) {
          foundation = _readPercent(stage['foundation']);
          structural = _readPercent(stage['structural']);
          electrical = _readPercent(stage['electrical'] ?? stage['walls']);
          finishing = _readPercent(stage['finishing'] ?? stage['roofing']);
        }
      }
    } catch (_) {
      // Fallback when composite index missing: scan without orderBy
      final fallback = await FirebaseService.instance.aiAnalysisCollection
          .where('projectId', isEqualTo: projectId)
          .where('kind', isEqualTo: 'govtrack_progress_report')
          .limit(5)
          .get();
      if (fallback.docs.isNotEmpty) {
        final ai = (fallback.docs.first.data() as Map<String, dynamic>?) ?? {};
        final pct = ai['progressPercent'];
        if (pct is num) overall = pct.toDouble().clamp(0, 100);
      }
    }

    if (foundation == 0 && structural == 0 && electrical == 0 && finishing == 0 && overall > 0) {
      structural = (overall * 0.75).clamp(0, 100);
      foundation = overall >= 30 ? 100 : (overall * 2).clamp(0, 100);
      electrical = (overall * 0.45).clamp(0, 100);
      finishing = (overall * 0.30).clamp(0, 100);
    }

    return ProjectProgressSnapshot(
      overallPercent: overall,
      foundation: foundation,
      structural: structural,
      electrical: electrical,
      finishing: finishing,
    );
  }

  static double _readPercent(dynamic raw) {
    if (raw is num) return raw.toDouble().clamp(0, 100);
    return double.tryParse(raw?.toString().replaceAll('%', '').trim() ?? '') ?? 0;
  }
}
