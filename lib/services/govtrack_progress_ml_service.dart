import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'firebase_service.dart';

/// Predefined ML pipeline: Cloud Vision OCR + Gemini Vision via Cloud Functions.
class GovtrackProgressMlService {
  GovtrackProgressMlService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<String?> _idToken({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken(forceRefresh);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> estimateSingleImage({
    required String projectId,
    required String? projectName,
    required String imageUrl,
    required String storagePath,
    required String fileName,
  }) async {
    final idToken = await _idToken(forceRefresh: true);
    final callable = _functions.httpsCallable('estimateProgressPercent');
    final res = await callable.call(<String, dynamic>{
      'projectId': projectId,
      'projectName': projectName,
      'imageUrl': imageUrl,
      'storagePath': storagePath,
      'fileName': fileName,
      'idToken': idToken,
    });
    return (res.data as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> verifySingleImage({
    required String projectId,
    required String? projectName,
    required String imageUrl,
    required String fileName,
  }) async {
    final callable = _functions.httpsCallable('verifyProgressImage');
    final res = await callable.call(<String, dynamic>{
      'imageUrl': imageUrl,
      'projectId': projectId,
      'projectName': projectName,
      'fileName': fileName,
    });
    return (res.data as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  }

  /// Runs predefined ML on up to 10 site photos; returns aggregated progress + per-image results.
  Future<GovtrackMlAnalysisResult> analyzeSitePhotos({
    required String projectId,
    required String? projectName,
    required List<Uint8List> imageBytesList,
    required List<String> imageNames,
    void Function(int index, int total)? onImageProcessed,
  }) async {
    if (imageBytesList.isEmpty) {
      throw ArgumentError('At least one image is required.');
    }
    if (imageBytesList.length > 10) {
      throw ArgumentError('Maximum 10 images allowed.');
    }

    final urls = <String>[];
    final perImage = <Map<String, dynamic>>[];
    final progressValues = <double>[];
    final labelsUnion = <String>{};
    final objectsUnion = <String>{};
    final stageTotals = <String, double>{
      'foundation': 0,
      'structural': 0,
      'roofing': 0,
      'walls': 0,
    };
    var stageCount = 0;

    for (var i = 0; i < imageBytesList.length; i++) {
      onImageProcessed?.call(i + 1, imageBytesList.length);
      final now = DateTime.now().millisecondsSinceEpoch;
      final rawName = (i < imageNames.length && imageNames[i].trim().isNotEmpty)
          ? imageNames[i]
          : 'site_photo_${i + 1}.jpg';
      final safeFileName = rawName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final storagePath = 'ai_verifications/${now}_${i + 1}_$safeFileName';

      final downloadUrl = await FirebaseService.instance.uploadFile(
        storagePath,
        imageBytesList[i],
        contentType: _guessContentType(rawName),
      );
      urls.add(downloadUrl);

      final results = await Future.wait<dynamic>([
        verifySingleImage(
          projectId: projectId,
          projectName: projectName,
          imageUrl: downloadUrl,
          fileName: rawName,
        ),
        estimateSingleImage(
          projectId: projectId,
          projectName: projectName,
          imageUrl: downloadUrl,
          storagePath: storagePath,
          fileName: rawName,
        ),
      ]);

      final verifyMap = results[0] as Map<String, dynamic>;
      final estimateMap = results[1] as Map<String, dynamic>;

      final verifyLabels = (verifyMap['labels'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
      final verifyObjects = (verifyMap['objects'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
      labelsUnion.addAll(verifyLabels);
      objectsUnion.addAll(verifyObjects);

      final stageProgress = (verifyMap['stageProgress'] as Map?)?.cast<String, dynamic>()
          ?? (estimateMap['stageProgress'] as Map?)?.cast<String, dynamic>();
      if (stageProgress != null && stageProgress.isNotEmpty) {
        double readNum(dynamic v) {
          if (v is num) return v.toDouble();
          return double.tryParse(v?.toString() ?? '') ?? 0.0;
        }
        for (final key in stageTotals.keys) {
          stageTotals[key] = (stageTotals[key] ?? 0) + readNum(stageProgress[key]);
        }
        stageCount++;
      }

      final ocrPct = estimateMap['progressPercent'];
      double? pct;
      if (ocrPct is num) {
        pct = ocrPct.toDouble().clamp(0, 100);
      }
      if (pct != null) progressValues.add(pct);

      perImage.add({
        'imageUrl': downloadUrl,
        'fileName': rawName,
        'storagePath': storagePath,
        'verify': verifyMap,
        'ml': estimateMap,
        'progressPercent': pct,
        'method': estimateMap['method'],
      });
    }

    final avg = progressValues.isEmpty
        ? null
        : progressValues.reduce((a, b) => a + b) / progressValues.length;

    Map<String, double>? aggregatedStage;
    if (stageCount > 0) {
      aggregatedStage = {
        for (final k in stageTotals.keys)
          k: ((stageTotals[k] ?? 0) / stageCount).clamp(0, 100),
      };
    }

    double? overall = avg;
    if (overall == null && aggregatedStage != null && aggregatedStage.isNotEmpty) {
      overall = aggregatedStage.values.reduce((a, b) => a + b) / aggregatedStage.length;
    }

    return GovtrackMlAnalysisResult(
      overallProgressPercent: overall,
      stageProgress: aggregatedStage,
      imageUrls: urls,
      perImageResults: perImage,
      labels: labelsUnion.toList(),
      objects: objectsUnion.toList(),
    );
  }

  static String _guessContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg';
  }

  static bool _isImageFile(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  /// Uploads a blueprint / site photo and runs the predefined Vision + Gemini ML pipeline.
  Future<ProjectPlanAnalysisResult> analyzeProjectPlan({
    required String projectId,
    required String? projectName,
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    final safeFileName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final storagePath =
        'projects/$projectId/project_plans/${DateTime.now().millisecondsSinceEpoch}_$safeFileName';

    final downloadUrl = await FirebaseService.instance.uploadFile(
      storagePath,
      fileBytes,
      contentType: _guessContentType(fileName),
    );

    if (!_isImageFile(fileName)) {
      return ProjectPlanAnalysisResult(
        planUrl: downloadUrl,
        storagePath: storagePath,
        fileName: fileName,
        isImage: false,
        mlSkipped: true,
        summary:
            'Document stored. Upload a blueprint or site photo (JPG/PNG) for AI analysis.',
      );
    }

    final verifyMap = await verifySingleImage(
      projectId: projectId,
      projectName: projectName,
      imageUrl: downloadUrl,
      fileName: fileName,
    );
    final estimateMap = await estimateSingleImage(
      projectId: projectId,
      projectName: projectName,
      imageUrl: downloadUrl,
      storagePath: storagePath,
      fileName: fileName,
    );

    final labels = (verifyMap['labels'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final objects = (verifyMap['objects'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];

    final rawPct = estimateMap['progressPercent'];
    double? progressPercent;
    if (rawPct is num) {
      progressPercent = rawPct.toDouble().clamp(0, 100);
    }

    final blueprintHints = [
      'blueprint',
      'diagram',
      'plan',
      'drawing',
      'architecture',
      'floor plan',
      'schematic',
    ];
    final joined = '${labels.join(' ')} ${objects.join(' ')}'.toLowerCase();
    final isBlueprint =
        blueprintHints.any((hint) => joined.contains(hint)) ||
            fileName.toLowerCase().contains('blueprint') ||
            fileName.toLowerCase().contains('plan');

    final docType = isBlueprint ? 'blueprint' : 'site_photo';
    final summary = isBlueprint
        ? 'Blueprint detected. ML extracted plan metadata and stage hints.'
        : 'Site photo analyzed. ML estimated visual progress from the image.';

    return ProjectPlanAnalysisResult(
      planUrl: downloadUrl,
      storagePath: storagePath,
      fileName: fileName,
      isImage: true,
      mlSkipped: false,
      isBlueprint: isBlueprint,
      docType: docType,
      progressPercent: progressPercent,
      labels: labels,
      objects: objects,
      verify: verifyMap,
      estimate: estimateMap,
      summary: summary,
    );
  }
}

class ProjectPlanAnalysisResult {
  const ProjectPlanAnalysisResult({
    required this.planUrl,
    required this.storagePath,
    required this.fileName,
    required this.isImage,
    required this.mlSkipped,
    this.isBlueprint = false,
    this.docType,
    this.progressPercent,
    this.labels = const [],
    this.objects = const [],
    this.verify,
    this.estimate,
    this.summary,
  });

  final String planUrl;
  final String storagePath;
  final String fileName;
  final bool isImage;
  final bool mlSkipped;
  final bool isBlueprint;
  final String? docType;
  final double? progressPercent;
  final List<String> labels;
  final List<String> objects;
  final Map<String, dynamic>? verify;
  final Map<String, dynamic>? estimate;
  final String? summary;

  Map<String, dynamic> toFirestoreMap() {
    return {
      'planUrl': planUrl,
      'storagePath': storagePath,
      'fileName': fileName,
      'isImage': isImage,
      'mlSkipped': mlSkipped,
      'isBlueprint': isBlueprint,
      if (docType != null) 'docType': docType,
      if (progressPercent != null) 'progressPercent': progressPercent,
      'labels': labels,
      'objects': objects,
      if (summary != null) 'summary': summary,
      'pipeline': 'predefined_ml_vision_gemini',
      'analyzedAt': DateTime.now().toIso8601String(),
      if (verify != null) 'verify': verify,
      if (estimate != null) 'estimate': estimate,
    };
  }
}

class GovtrackMlAnalysisResult {
  const GovtrackMlAnalysisResult({
    required this.overallProgressPercent,
    required this.stageProgress,
    required this.imageUrls,
    required this.perImageResults,
    required this.labels,
    required this.objects,
  });

  final double? overallProgressPercent;
  final Map<String, double>? stageProgress;
  final List<String> imageUrls;
  final List<Map<String, dynamic>> perImageResults;
  final List<String> labels;
  final List<String> objects;

  Map<String, dynamic> toAnalysisMap() {
    return {
      'progressPercent': overallProgressPercent,
      if (stageProgress != null) 'stageProgress': stageProgress,
      'labels': labels,
      'objects': objects,
      'perImage': perImageResults,
      'pipeline': 'predefined_ml_vision_gemini',
    };
  }
}
