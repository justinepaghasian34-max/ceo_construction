import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/hive_service.dart';
import '../services/local_notification_service.dart';
import '../services/push_alert_service.dart';

class MaterialRequestAlertListener extends StatefulWidget {
  const MaterialRequestAlertListener({super.key, required this.child});

  final Widget child;

  @override
  State<MaterialRequestAlertListener> createState() =>
      _MaterialRequestAlertListenerState();
}

class _MaterialRequestAlertListenerState
    extends State<MaterialRequestAlertListener> {
  static const _seenKey = 'seen_material_request_ids';

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reqSub;
  bool _dialogOpen = false;
  final Set<String> _queuedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      _bindRequestStream();
      unawaited(PushAlertService.instance.ensureRegistered());
    });
    _bindRequestStream();
    unawaited(PushAlertService.instance.ensureRegistered());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _reqSub?.cancel();
    super.dispose();
  }

  List<String> _loadSeen() {
    try {
      final raw = HiveService.instance.getSetting(_seenKey);
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _saveSeen(Iterable<String> ids) async {
    final next = {..._loadSeen(), ...ids}.toList();
    await HiveService.instance.saveSetting(_seenKey, next);
  }

  void _bindRequestStream() {
    _reqSub?.cancel();
    _reqSub = null;

    final user = AuthService.instance.currentUser;
    if (user == null || !(user.isAdmin || user.isMaterials)) {
      return;
    }

    _reqSub = FirebaseFirestore.instance
        .collectionGroup('material_requests')
        .where('status', isEqualTo: AppConstants.materialRequestPending)
        .snapshots()
        .listen(_onRequests, onError: (_) {});
  }

  Future<void> _onRequests(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (!mounted) return;
    final user = AuthService.instance.currentUser;
    if (user == null || !(user.isAdmin || user.isMaterials)) return;

    final seen = _loadSeen().toSet();
    final unseenDocs = snapshot.docs.where((d) => !seen.contains(d.id)).toList();
    if (unseenDocs.isEmpty) return;

    unseenDocs.sort((a, b) {
      final aUrgent =
          (a.data()['priority'] ?? '').toString().toLowerCase() == 'urgent'
              ? 0
              : 1;
      final bUrgent =
          (b.data()['priority'] ?? '').toString().toLowerCase() == 'urgent'
              ? 0
              : 1;
      return aUrgent.compareTo(bUrgent);
    });

    await _saveSeen(unseenDocs.map((d) => d.id));

    final latest = unseenDocs.first;
    final data = latest.data();
    final materialName =
        (data['materialName'] ?? data['subject'] ?? 'Material').toString();
    final projectName =
        (data['projectName'] ?? data['projectId'] ?? 'a project').toString();
    final engineer = (data['createdByName'] ?? data['createdBy'] ?? '')
        .toString()
        .trim();
    final qty = (data['requestedQuantity'] ?? '').toString();
    final unit = (data['unit'] ?? '').toString();
    final urgent =
        (data['priority'] ?? '').toString().toLowerCase() == 'urgent';
    final qtyLabel = [
      if (qty.trim().isNotEmpty) qty.trim(),
      if (unit.trim().isNotEmpty) unit.trim(),
    ].join(' ');
    final title = urgent
        ? 'Urgent material request'
        : unseenDocs.length > 1
            ? '${unseenDocs.length} new material requests'
            : 'New material request';
    final who = engineer.isEmpty ? '' : ' · $engineer';
    final body = qtyLabel.isEmpty
        ? '$materialName for project $projectName$who'
        : '$materialName ($qtyLabel) for project $projectName$who';

    if (!kIsWeb) {
      unawaited(
        LocalNotificationService.instance.showMaterialRequestAlert(
          id: latest.id.hashCode.abs() % 100000,
          title: title,
          body: body,
        ),
      );
    }

    _queuedIds.addAll(unseenDocs.map((d) => d.id));
    if (_dialogOpen) return;
    _showPopup(
      title: title,
      body: body,
      urgent: urgent,
      extraCount: unseenDocs.length - 1,
    );
  }

  void _showPopup({
    required String title,
    required String body,
    required bool urgent,
    required int extraCount,
  }) {
    final ctx = context;
    if (!ctx.mounted) return;
    _dialogOpen = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _dialogOpen = false;
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  urgent ? Icons.priority_high_rounded : Icons.inventory_2_outlined,
                  color: urgent ? AppTheme.errorRed : AppTheme.deepBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(body),
                if (extraCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '+ $extraCount more pending request${extraCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: AppTheme.mediumGray,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  final role = AuthService.instance.currentUser?.role;
                  if (role == AppConstants.roleMaterials) {
                    context.go(RouteNames.materialsHome);
                  } else {
                    context.go(RouteNames.adminMaterialMonitoring);
                  }
                },
                child: const Text('Open requests'),
              ),
            ],
          );
        },
      );
      _dialogOpen = false;
      _queuedIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
