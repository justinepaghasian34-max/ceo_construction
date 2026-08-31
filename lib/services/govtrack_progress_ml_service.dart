                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    import 'dart:convert';

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

      Map<String, dynamic> verifyMap = const {};
      Map<String, dynamic> estimateMap = const {};
      try {
        estimateMap = await estimateSingleImage(
          projectId: projectId,
          projectName: projectName,
          imageUrl: downloadUrl,
          storagePath: storagePath,
          fileName: rawName,
        );
      } catch (e) {
        debugPrint('estimateSingleImage failed: $e');
      }
      try {
        verifyMap = await verifySingleImage(
          projectId: projectId,
          projectName: projectName,
          imageUrl: downloadUrl,
          fileName: rawName,
        );
      } catch (e) {
        debugPrint('verifySingleImage failed: $e');
      }

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

  static Map<String, List<String>> _blueprintMetaFromMaps({
    required Map<String, dynamic> verifyMap,
    required Map<String, dynamic> estimateMap,
  }) {
    final allLabels = [
      ...(verifyMap['labels'] as List? ?? []).map((e) => e.toString()),
      ...(verifyMap['objects'] as List? ?? []).map((e) => e.toString()),
    ];
    const yellowKeywords = [
      'yellow', 'highlight', 'highlighted', 'marked', 'marker',
      'annotation', 'annotated', 'zone', 'focused', 'focus area',
    ];
    const scopeKeywords = [
      'blueprint', 'floor plan', 'plan', 'drawing', 'schematic',
      'elevation', 'section', 'architectural', 'structural',
      'building', 'storey', 'story', 'layout', 'column', 'beam',
      'wall', 'room', 'area', 'site', 'construction',
    ];
    final yellowZones = allLabels
        .where((l) => yellowKeywords.any((k) => l.toLowerCase().contains(k)))
        .toSet()
        .toList();
    final scopeItems = allLabels
        .where((l) => scopeKeywords.any((k) => l.toLowerCase().contains(k)))
        .toSet()
        .toList();
    final stageProgress =
        (estimateMap['stageProgress'] as Map?)?.cast<String, dynamic>() ?? {};
    final phaseHints = stageProgress.keys.where((k) {
      final v = stageProgress[k];
      return v is num && v > 0;
    }).toList();
    return {
      'yellowZones': yellowZones,
      'scopeItems': scopeItems,
      'phaseHints': phaseHints,
    };
  }

  // ── Blueprint analysis ────────────────────────────────────────────────────

  /// Uploads a single blueprint image and extracts scope + yellow-zone data.
  Future<BlueprintAnalysisResult> analyzeBlueprint({
    required String projectId,
    required String? projectName,
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    final safeFileName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final storagePath =
        'projects/$projectId/blueprints/${DateTime.now().millisecondsSinceEpoch}_$safeFileName';

    final downloadUrl = await FirebaseService.instance.uploadFile(
      storagePath,
      fileBytes,
      contentType: _guessContentType(fileName),
    );

    final results = await Future.wait<dynamic>([
      verifySingleImage(
        projectId: projectId,
        projectName: projectName,
        imageUrl: downloadUrl,
        fileName: fileName,
      ),
      estimateSingleImage(
        projectId: projectId,
        projectName: projectName,
        imageUrl: downloadUrl,
        storagePath: storagePath,
        fileName: fileName,
      ),
    ]);

    final verifyMap = results[0] as Map<String, dynamic>;
    final estimateMap = results[1] as Map<String, dynamic>;
    final meta = _blueprintMetaFromMaps(
      verifyMap: verifyMap,
      estimateMap: estimateMap,
    );

    return BlueprintAnalysisResult(
      planUrl: downloadUrl,
      storagePath: storagePath,
      fileName: fileName,
      scopeItems: meta['scopeItems'] ?? const [],
      yellowZones: meta['yellowZones'] ?? const [],
      phaseHints: meta['phaseHints'] ?? const [],
      rawVerify: verifyMap,
      rawEstimate: estimateMap,
    );
  }

  // ── Combined blueprint + site photo analysis ──────────────────────────────

  /// Runs blueprint analysis on each blueprint image, then runs site photo
  /// analysis, and returns a [GovtrackMlAnalysisResult] that includes both
  /// blueprint scope metadata and visual progress from site photos.
  Future<GovtrackMlAnalysisResult> analyzeCombined({
    required String projectId,
    required String? projectName,
    required List<Uint8List> blueprintBytes,
    required List<String> blueprintNames,
    required List<Uint8List> sitePhotoBytes,
    required List<String> sitePhotoNames,
    void Function(String stage, int done, int total)? onProgress,
  }) async {
    if (blueprintBytes.isEmpty && sitePhotoBytes.isEmpty) {
      throw ArgumentError('Upload at least one blueprint or site photo.');
    }

    // ── Step 1: analyse blueprints ─────────────────────────────────────────
    final blueprintResults = <BlueprintAnalysisResult>[];
    for (var i = 0; i < blueprintBytes.length; i++) {
      onProgress?.call('blueprint', i + 1, blueprintBytes.length);
      final result = await analyzeBlueprint(
        projectId: projectId,
        projectName: projectName,
        fileBytes: blueprintBytes[i],
        fileName:
            i < blueprintNames.length ? blueprintNames[i] : 'blueprint_${i + 1}.jpg',
      );
      blueprintResults.add(result);
    }

    final allBlueprintScopes =
        blueprintResults.expand((r) => r.scopeItems).toSet().toList();
    final allYellowZones =
        blueprintResults.expand((r) => r.yellowZones).toSet().toList();
    final allPhaseHints =
        blueprintResults.expand((r) => r.phaseHints).toSet().toList();
    final blueprintUrls = blueprintResults.map((r) => r.planUrl).toList();

    // ── Step 2: analyse site photos ────────────────────────────────────────
    GovtrackMlAnalysisResult? siteResult;
    if (sitePhotoBytes.isNotEmpty) {
      onProgress?.call('site_photos', 0, sitePhotoBytes.length);
      siteResult = await analyzeSitePhotos(
        projectId: projectId,
        projectName: projectName,
        imageBytesList: sitePhotoBytes,
        imageNames: sitePhotoNames,
        onImageProcessed: (idx, total) =>
            onProgress?.call('site_photos', idx, total),
      );
    }

    // ── Step 3: build cross-reference narrative ────────────────────────────
    final narrative = _buildCrossReferenceNarrative(
      projectName: projectName,
      blueprintScopes: allBlueprintScopes,
      yellowZones: allYellowZones,
      phaseHints: allPhaseHints,
      siteResult: siteResult,
    );

    // Blueprint match % = ratio of blueprint phases confirmed in site photos.
    double? matchPercent;
    if (siteResult != null && allPhaseHints.isNotEmpty) {
      final siteLabels = siteResult.labels.join(' ').toLowerCase();
      final confirmed = allPhaseHints.where(
        (p) => siteLabels.contains(p.toLowerCase()),
      );
      matchPercent =
          (confirmed.length / allPhaseHints.length * 100).clamp(0, 100);
    }

    return GovtrackMlAnalysisResult(
      overallProgressPercent: siteResult?.overallProgressPercent,
      stageProgress: siteResult?.stageProgress,
      imageUrls: siteResult?.imageUrls ?? const [],
      perImageResults: siteResult?.perImageResults ?? const [],
      labels: siteResult?.labels ?? const [],
      objects: siteResult?.objects ?? const [],
      blueprintUrls: blueprintUrls,
      blueprintScopes: allBlueprintScopes,
      yellowZones: allYellowZones,
      crossReferenceNarrative: narrative,
      blueprintMatchPercent: matchPercent,
    );
  }

  static String _buildCrossReferenceNarrative({
    required String? projectName,
    required List<String> blueprintScopes,
    required List<String> yellowZones,
    required List<String> phaseHints,
    required GovtrackMlAnalysisResult? siteResult,
  }) {
    final buf = StringBuffer();
    final name = projectName ?? 'this project';

    if (blueprintScopes.isNotEmpty) {
      buf.writeln(
          'Blueprint scope for $name includes: ${blueprintScopes.take(6).join(', ')}.');
    }
    if (yellowZones.isNotEmpty) {
      buf.writeln(
          'Yellow-highlighted focus areas in the blueprint: '
          '${yellowZones.take(6).join(', ')}. '
          'These represent the budgeted/priority zones for current construction.');
    } else {
      buf.writeln(
          'No yellow highlight zones were detected in the uploaded blueprints. '
          'The blueprint may show the full site layout without phase highlighting.');
    }
    if (phaseHints.isNotEmpty) {
      buf.writeln(
          'Construction phases visible in blueprint: ${phaseHints.join(', ')}.');
    }

    if (siteResult != null) {
      final pct = siteResult.overallProgressPercent;
      if (pct != null) {
        buf.writeln(
            'Site photos show an estimated ${pct.toStringAsFixed(0)}% overall visual progress.');
      }
      if (siteResult.labels.isNotEmpty) {
        buf.writeln(
            'Visual elements confirmed in site photos: '
            '${siteResult.labels.take(8).join(', ')}.');
      }
    } else {
      buf.writeln(
          'No site photos were uploaded for cross-reference. '
          'Upload interior and exterior site photos to compare against the blueprint.');
    }

    return buf.toString().trim();
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
    double? approvedBudget,
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
    final meta = _blueprintMetaFromMaps(
      verifyMap: verifyMap,
      estimateMap: estimateMap,
    );
    final summary = isBlueprint
        ? 'Blueprint saved to this project. Resident Engineer progress photos will be compared against this drawing. Funded scope follows the approved budget — areas on the sheet that are not funded stay out of %. '
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
      yellowZones: meta['yellowZones'] ?? const [],
      scopeItems: meta['scopeItems'] ?? const [],
      phaseHints: meta['phaseHints'] ?? const [],
      approvedBudget: approvedBudget,
      verify: verifyMap,
      estimate: estimateMap,
      summary: summary,
    );
  }

  /// Resident Engineer path: site photos vs the blueprint saved at project create.
  /// % complete is of the **funded** footprint, not the entire drawing.
  Future<GovtrackMlAnalysisResult> analyzeProgressAgainstSavedPlan({
    required String projectId,
    required String? projectName,
    required List<Uint8List> sitePhotoBytes,
    required List<String> sitePhotoNames,
    String? planUrl,
    List<String> extraBlueprintUrls = const [],
    List<String> referencePhotoUrls = const [],
    Map<String, dynamic>? planAnalysis,
    double? approvedBudget,
    void Function(String stage, int done, int total)? onProgress,
  }) async {
    if (sitePhotoBytes.isEmpty) {
      throw ArgumentError('Upload at least one site photo.');
    }

    onProgress?.call('site_photos', 0, sitePhotoBytes.length);
    final uploaded = <Map<String, dynamic>>[];
    for (var i = 0; i < sitePhotoBytes.length; i++) {
      onProgress?.call('site_photos', i + 1, sitePhotoBytes.length);
      final rawName =
          (i < sitePhotoNames.length && sitePhotoNames[i].trim().isNotEmpty)
              ? sitePhotoNames[i]
              : 'site_photo_${i + 1}.jpg';
      final safeFileName = rawName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final storagePath =
          'ai_verifications/${DateTime.now().millisecondsSinceEpoch}_${i + 1}_$safeFileName';
      final downloadUrl = await FirebaseService.instance.uploadFile(
        storagePath,
        sitePhotoBytes[i],
        contentType: _guessContentType(rawName),
      );
      uploaded.add({
        'imageUrl': downloadUrl,
        'storagePath': storagePath,
        'fileName': rawName,
      });
    }

    onProgress?.call('blueprint', 1, 1);
    final combined = await _analyzeUploadedAgainstPlan(
      projectId: projectId,
      projectName: projectName,
      approvedBudget: approvedBudget,
      planUrl: planUrl,
      extraBlueprintUrls: extraBlueprintUrls,
      planAnalysis: planAnalysis,
      uploaded: uploaded,
    );
    if (combined != null) return combined;

    final siteResult = await analyzeSitePhotos(
      projectId: projectId,
      projectName: projectName,
      imageBytesList: sitePhotoBytes,
      imageNames: sitePhotoNames,
      onImageProcessed: (idx, total) =>
          onProgress?.call('site_photos', idx, total),
    );

    final scope = await _budgetScopeFromGemini(
          projectId: projectId,
          projectName: projectName,
          approvedBudget: approvedBudget,
          planUrl: planUrl,
          planAnalysis: planAnalysis,
          siteResult: siteResult,
        ) ??
        _heuristicBudgetScope(
          approvedBudget: approvedBudget,
          planAnalysis: planAnalysis,
          siteResult: siteResult,
        );

    final budgetedPct = _asDouble(scope['budgetedProgressPercent']) ??
        siteResult.overallProgressPercent;
    final included = _asStringList(scope['includedInBudget']);
    final excluded = _asStringList(scope['excludedFromBudget']);
    final sequence = _asStringList(scope['workSequence']);
    final firstWork = (scope['firstWorkArea'] ?? '').toString().trim();
    final rationale = (scope['rationale'] ?? '').toString().trim();

    final narrative = _buildBudgetedNarrative(
      projectName: projectName,
      planUrl: planUrl,
      approvedBudget: approvedBudget,
      planAnalysis: planAnalysis,
      siteResult: siteResult,
      budgetedPercent: budgetedPct,
      firstWorkArea: firstWork,
      workSequence: sequence,
      included: included,
      excluded: excluded,
      rationale: rationale,
    );

    return GovtrackMlAnalysisResult(
      overallProgressPercent: budgetedPct,
      stageProgress: siteResult.stageProgress,
      imageUrls: siteResult.imageUrls,
      perImageResults: siteResult.perImageResults,
      labels: siteResult.labels,
      objects: siteResult.objects,
      blueprintUrls: {
        if (planUrl != null && planUrl.isNotEmpty) planUrl,
        ...extraBlueprintUrls,
      }.toList(),
      blueprintScopes: included.isNotEmpty
          ? included
          : _asStringList(planAnalysis?['scopeItems']),
      yellowZones: _asStringList(planAnalysis?['yellowZones']),
      crossReferenceNarrative: narrative,
      blueprintMatchPercent: budgetedPct,
      budgetedProgressPercent: budgetedPct,
      firstWorkArea: firstWork.isEmpty ? null : firstWork,
      workSequence: sequence,
      includedInBudget: included,
      excludedFromBudget: excluded,
      approvedBudget: approvedBudget,
    );
  }

  Future<GovtrackMlAnalysisResult?> _analyzeUploadedAgainstPlan({
    required String projectId,
    required String? projectName,
    required double? approvedBudget,
    required String? planUrl,
    required List<String> extraBlueprintUrls,
    required Map<String, dynamic>? planAnalysis,
    required List<Map<String, dynamic>> uploaded,
  }) async {
    if (uploaded.isEmpty) return null;
    final idToken = await _idToken(forceRefresh: true);
    try {
      final callable = _functions.httpsCallable(
        'analyzeSiteProgressAgainstPlan',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
      );
      final storagePath = (planAnalysis?['storagePath'] ?? '').toString().trim();
      final res = await callable.call(<String, dynamic>{
        'projectId': projectId,
        'projectName': projectName,
        'approvedBudget': approvedBudget,
        'images': uploaded,
        if (planUrl != null && planUrl.isNotEmpty) 'blueprintUrl': planUrl,
        if (storagePath.isNotEmpty) 'blueprintStoragePath': storagePath,
        if (extraBlueprintUrls.isNotEmpty) 'extraBlueprintUrls': extraBlueprintUrls,
        if (idToken != null) 'idToken': idToken,
      });
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['ok'] != true && data['progressPercent'] == null) return null;

      final urls = uploaded
          .map((e) => (e['imageUrl'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
      final stageRaw = (data['stageProgress'] as Map?)?.cast<String, dynamic>();
      Map<String, double>? stageProgress;
      if (stageRaw != null && stageRaw.isNotEmpty) {
        stageProgress = {
          for (final e in stageRaw.entries)
            e.key: (_asDouble(e.value) ?? 0).clamp(0, 100),
        };
      }

      final perImage = <Map<String, dynamic>>[];
      final rawPer = data['perImage'];
      if (rawPer is List) {
        for (final item in rawPer) {
          if (item is Map) perImage.add(item.cast<String, dynamic>());
        }
      }
      if (perImage.isEmpty) {
        perImage.addAll(uploaded);
      }

      final pct = _asDouble(data['budgetedProgressPercent']) ??
          _asDouble(data['progressPercent']);
      final reasoning = (data['analysisReasoning'] ?? '').toString().trim();
      final rationale = (data['rationale'] ?? '').toString().trim();
      final firstWork = (data['firstWorkArea'] ?? '').toString().trim();
      final included = _asStringList(data['includedInBudget']);
      final excluded = _asStringList(data['excludedFromBudget']);
      final sequence = _asStringList(data['workSequence']);
      final labels = _asStringList(data['labels']);
      final objects = _asStringList(data['objects']);

      final siteResult = GovtrackMlAnalysisResult(
        overallProgressPercent: pct,
        stageProgress: stageProgress,
        imageUrls: urls,
        perImageResults: perImage,
        labels: labels,
        objects: objects,
      );
      final narrative = _buildBudgetedNarrative(
        projectName: projectName,
        planUrl: planUrl,
        approvedBudget: approvedBudget,
        planAnalysis: planAnalysis,
        siteResult: siteResult,
        budgetedPercent: pct,
        firstWorkArea: firstWork,
        workSequence: sequence,
        included: included,
        excluded: excluded,
        rationale: [
          if (reasoning.isNotEmpty) reasoning,
          if (rationale.isNotEmpty) rationale,
        ].join(' '),
      );

      return GovtrackMlAnalysisResult(
        overallProgressPercent: pct,
        stageProgress: stageProgress,
        imageUrls: urls,
        perImageResults: perImage,
        labels: labels,
        objects: objects,
        blueprintUrls: {
          if (planUrl != null && planUrl.isNotEmpty) planUrl,
          ...extraBlueprintUrls,
        }.toList(),
        blueprintScopes: included.isNotEmpty
            ? included
            : _asStringList(planAnalysis?['scopeItems']),
        yellowZones: _asStringList(planAnalysis?['yellowZones']),
        crossReferenceNarrative: narrative,
        blueprintMatchPercent: pct,
        budgetedProgressPercent: pct,
        firstWorkArea: firstWork.isEmpty ? null : firstWork,
        workSequence: sequence,
        includedInBudget: included,
        excludedFromBudget: excluded,
        approvedBudget: approvedBudget,
      );
    } catch (e) {
      debugPrint('analyzeSiteProgressAgainstPlan failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _budgetScopeFromGemini({
    required String projectId,
    required String? projectName,
    required double? approvedBudget,
    required String? planUrl,
    required Map<String, dynamic>? planAnalysis,
    required GovtrackMlAnalysisResult siteResult,
  }) async {
    if (planUrl == null || planUrl.isEmpty) return null;
    final idToken = await _idToken(forceRefresh: true);
    if (idToken == null) return null;

    final budgetStr = approvedBudget == null
        ? 'not provided'
        : approvedBudget.toStringAsFixed(0);
    final instruction = '''
You are a civil engineer scoping a funded construction project.

HARD RULES:
1. The saved blueprint is the FULL drawing. It is NOT automatically the project.
2. The real project is only what the approved budget can build.
3. Areas drawn on the blueprint but not funded are OUT OF SCOPE. Do not count them in %.
4. Yellow / highlighted / annotated zones (if any) are the current funded footprint.
5. Percent complete = progress of the FUNDED footprint only, compared with site photos.
6. First work must be a specific SIDE or ZONE of the blueprint (e.g. "left wing foundation / grid A–C"), following construction order: foundation → structural → walls → roofing, but only inside funded areas.

APPROVED BUDGET: $budgetStr
BLUEPRINT URL: $planUrl
BLUEPRINT LABELS: ${(planAnalysis?['labels'] as List?)?.join(', ') ?? 'none'}
YELLOW / FOCUS ZONES: ${(planAnalysis?['yellowZones'] as List?)?.join(', ') ?? 'none marked'}
SCOPE HINTS: ${(planAnalysis?['scopeItems'] as List?)?.join(', ') ?? 'none'}
PHASE HINTS: ${(planAnalysis?['phaseHints'] as List?)?.join(', ') ?? 'none'}

SITE PHOTO EVIDENCE:
visualProgressPercent: ${siteResult.overallProgressPercent ?? 'unknown'}
stageProgress: ${siteResult.stageProgress}
photoLabels: ${siteResult.labels.take(12).join(', ')}
photoObjects: ${siteResult.objects.take(12).join(', ')}

Return STRICT JSON only:
{
  "budgetedProgressPercent": <number 0 to 100>,
  "firstWorkArea": "specific side or zone to work first",
  "workSequence": ["step 1", "step 2", "step 3"],
  "includedInBudget": ["funded areas"],
  "excludedFromBudget": ["drawn but not funded"],
  "rationale": "one short paragraph"
}
''';

    try {
      final callable = _functions.httpsCallable('govtrackChatGemini');
      final storagePath = (planAnalysis?['storagePath'] ?? '').toString().trim();
      final res = await callable.call(<String, dynamic>{
        // Backend ignores custom systemInstruction; put rules in the user message
        // and attach the saved blueprint so Vision + Gemini actually read it.
        'message': instruction,
        'idToken': idToken,
        'projectId': projectId,
        'projectName': projectName,
        'imageUrl': planUrl,
        if (storagePath.isNotEmpty) 'storagePath': storagePath,
      }).timeout(const Duration(seconds: 90));
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      final raw = (data['reply'] ?? data['message'] ?? '').toString();
      return _parseJsonObject(raw);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _heuristicBudgetScope({
    required double? approvedBudget,
    required Map<String, dynamic>? planAnalysis,
    required GovtrackMlAnalysisResult siteResult,
  }) {
    const order = ['foundation', 'structural', 'walls', 'roofing'];
    const labels = {
      'foundation':
          'Foundation and ground-level grids on the funded side of the blueprint',
      'structural':
          'Structural frame (columns/beams) within the funded footprint',
      'walls': 'Masonry walls inside the budgeted area of the plan',
      'roofing': 'Roofing and finishing on the funded wing only',
    };
    final stages = siteResult.stageProgress ?? const <String, double>{};
    var first = labels['foundation']!;
    for (final key in order) {
      if ((stages[key] ?? 0) < 75) {
        first = labels[key]!;
        break;
      }
    }

    final yellow = _asStringList(planAnalysis?['yellowZones']);
    final scopes = _asStringList(planAnalysis?['scopeItems']);
    final included = yellow.isNotEmpty
        ? yellow
        : (scopes.isNotEmpty
            ? scopes
            : ['Funded footprint limited by the approved budget']);
    final excluded = yellow.isNotEmpty
        ? [
            'Remainder of the full blueprint beyond highlighted / funded zones',
          ]
        : [
            'Any wing, floor, or annex on the drawing that the approved budget cannot cover',
          ];

    return {
      'budgetedProgressPercent': siteResult.overallProgressPercent,
      'firstWorkArea': first,
      'workSequence': [
        'Start on the funded $first',
        'Complete structural work inside the budgeted footprint before expanding',
        'Do not open areas that are drawn on the blueprint but not funded',
      ],
      'includedInBudget': included,
      'excludedFromBudget': excluded,
      'rationale': approvedBudget == null
          ? 'No approved budget on file. Treat highlighted blueprint zones as current scope; the rest of the sheet is reference only.'
          : 'Progress is measured against the funded footprint (budget ${approvedBudget.toStringAsFixed(0)}), not the entire drawing.',
    };
  }

  static String _buildBudgetedNarrative({
    required String? projectName,
    required String? planUrl,
    required double? approvedBudget,
    required Map<String, dynamic>? planAnalysis,
    required GovtrackMlAnalysisResult siteResult,
    required double? budgetedPercent,
    required String firstWorkArea,
    required List<String> workSequence,
    required List<String> included,
    required List<String> excluded,
    required String rationale,
  }) {
    final buf = StringBuffer();
    final name = projectName ?? 'this project';
    if (planUrl == null || planUrl.isEmpty) {
      buf.writeln(
          'No project blueprint is on file yet. Percent is from site photos only. Ask Admin to upload the plan so analysis can follow funded scope.');
    } else {
      buf.writeln(
          'Site photos for $name were compared with the blueprint saved when the project was created.');
      buf.writeln(
          'The full drawing is not the project. Only budgeted areas count toward %.');
    }
    if (approvedBudget != null) {
      buf.writeln('Approved budget used for scope: ${approvedBudget.toStringAsFixed(0)}.');
    }
    if (budgetedPercent != null) {
      buf.writeln(
          'Funded-scope progress: ${budgetedPercent.toStringAsFixed(0)}%.');
    }
    if (firstWorkArea.isNotEmpty) {
      buf.writeln('Work first: $firstWorkArea.');
    }
    if (included.isNotEmpty) {
      buf.writeln('In budget: ${included.take(6).join(', ')}.');
    }
    if (excluded.isNotEmpty) {
      buf.writeln('Drawn but not funded: ${excluded.take(6).join(', ')}.');
    }
    if (workSequence.isNotEmpty) {
      buf.writeln('Sequence: ${workSequence.take(4).join(' → ')}.');
    }
    if (rationale.isNotEmpty) buf.writeln(rationale);
    return buf.toString().trim();
  }

  static Map<String, dynamic>? _parseJsonObject(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final decoded = jsonDecode(text.substring(start, end + 1));
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble().clamp(0, 100);
    return double.tryParse(v?.toString() ?? '');
  }

  static List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    return const [];
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
    this.yellowZones = const [],
    this.scopeItems = const [],
    this.phaseHints = const [],
    this.approvedBudget,
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
  final List<String> yellowZones;
  final List<String> scopeItems;
  final List<String> phaseHints;
  final double? approvedBudget;
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
      'yellowZones': yellowZones,
      'scopeItems': scopeItems,
      'phaseHints': phaseHints,
      if (approvedBudget != null) 'approvedBudget': approvedBudget,
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
    // Blueprint cross-reference fields
    this.blueprintUrls = const [],
    this.blueprintScopes = const [],
    this.yellowZones = const [],
    this.crossReferenceNarrative,
    this.blueprintMatchPercent,
    this.budgetedProgressPercent,
    this.firstWorkArea,
    this.workSequence = const [],
    this.includedInBudget = const [],
    this.excludedFromBudget = const [],
    this.approvedBudget,
  });

  final double? overallProgressPercent;
  final Map<String, double>? stageProgress;
  final List<String> imageUrls;
  final List<Map<String, dynamic>> perImageResults;
  final List<String> labels;
  final List<String> objects;

  /// URLs of uploaded blueprint images.
  final List<String> blueprintUrls;

  /// Scope items extracted from blueprints (e.g. "2-storey residential building").
  final List<String> blueprintScopes;

  /// Yellow-highlighted zones detected in blueprints (focused/budgeted areas).
  final List<String> yellowZones;

  /// Gemini narrative comparing blueprint scope vs actual site photo evidence.
  final String? crossReferenceNarrative;

  /// How much of the blueprint scope is visually confirmed in site photos (0–100).
  final double? blueprintMatchPercent;

  /// Progress of the funded footprint only (not the full drawing).
  final double? budgetedProgressPercent;
  final String? firstWorkArea;
  final List<String> workSequence;
  final List<String> includedInBudget;
  final List<String> excludedFromBudget;
  final double? approvedBudget;

  bool get hasBlueprintAnalysis =>
      blueprintUrls.isNotEmpty || yellowZones.isNotEmpty;

  Map<String, dynamic> toAnalysisMap() {
    return {
      'progressPercent': overallProgressPercent,
      if (stageProgress != null) 'stageProgress': stageProgress,
      'labels': labels,
      'objects': objects,
      'perImage': perImageResults,
      'pipeline': 'predefined_ml_vision_gemini',
      if (blueprintUrls.isNotEmpty) 'blueprintUrls': blueprintUrls,
      if (blueprintScopes.isNotEmpty) 'blueprintScopes': blueprintScopes,
      if (yellowZones.isNotEmpty) 'yellowZones': yellowZones,
      if (crossReferenceNarrative != null)
        'crossReferenceNarrative': crossReferenceNarrative,
      if (blueprintMatchPercent != null)
        'blueprintMatchPercent': blueprintMatchPercent,
      if (budgetedProgressPercent != null)
        'budgetedProgressPercent': budgetedProgressPercent,
      if (firstWorkArea != null) 'firstWorkArea': firstWorkArea,
      if (workSequence.isNotEmpty) 'workSequence': workSequence,
      if (includedInBudget.isNotEmpty) 'includedInBudget': includedInBudget,
      if (excludedFromBudget.isNotEmpty)
        'excludedFromBudget': excludedFromBudget,
      if (approvedBudget != null) 'approvedBudget': approvedBudget,
    };
  }
}

// ── Blueprint cross-reference result ────────────────────────────────────────

/// Result of analysing one blueprint image for scope and yellow zones.
class BlueprintAnalysisResult {
  const BlueprintAnalysisResult({
    required this.planUrl,
    required this.storagePath,
    required this.fileName,
    this.scopeItems = const [],
    this.yellowZones = const [],
    this.phaseHints = const [],
    this.rawVerify,
    this.rawEstimate,
  });

  final String planUrl;
  final String storagePath;
  final String fileName;

  /// Plain-text items describing what the blueprint shows
  /// (e.g. "2-storey concrete building", "ground floor plan").
  final List<String> scopeItems;

  /// Yellow-highlighted areas as described by Vision labels/objects
  /// (e.g. "Room A", "Column grid 1-3", "Highlighted zone").
  final List<String> yellowZones;

  /// Construction phase hints inferred from the blueprint.
  final List<String> phaseHints;

  final Map<String, dynamic>? rawVerify;
  final Map<String, dynamic>? rawEstimate;
}
