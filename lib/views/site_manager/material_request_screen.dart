import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/geo_tag_service.dart';
import '../../services/firebase_service.dart';
import '../../services/hive_service.dart';
import '../../services/audit_log_service.dart';
import '../../services/sync_service.dart';

class MaterialRequestScreen extends StatefulWidget {
  const MaterialRequestScreen({super.key});

  @override
  State<MaterialRequestScreen> createState() => _MaterialRequestScreenState();
}

class _MaterialRequestScreenState extends State<MaterialRequestScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _materialNameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _purposeController = TextEditingController();
  final _dateNeededController = TextEditingController();

  final _materialFocus = FocusNode();
  final _quantityFocus = FocusNode();
  final _purposeFocus = FocusNode();

  bool _isSubmitting = false;

  DateTime? _dateNeeded;
  String _priority = 'normal';

  bool _submitPressed = false;
  bool _submitHover = false;

  String? _projectId;
  String? _projectName;

  String? _selectedAllocationId;
  String? _selectedAllocationUnit;
  double? _selectedAllocationRemaining;
  double? _selectedAllocationUnitPrice;

  late final AnimationController _pageAnim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void dispose() {
    _materialNameController.dispose();
    _quantityController.dispose();
    _purposeController.dispose();
    _dateNeededController.dispose();
    _materialFocus.dispose();
    _quantityFocus.dispose();
    _purposeFocus.dispose();
    _pageAnim.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _pageAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fade = CurvedAnimation(parent: _pageAnim, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(
      CurvedAnimation(parent: _pageAnim, curve: Curves.easeOutCubic),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pageAnim.forward();
    });

    _loadProjectInfo();
  }

  Future<void> _loadProjectInfo() async {
    // Best-effort refresh so assignedProjects stays in sync with Firestore.
    await AuthService.instance.refreshUserData();

    final user = AuthService.instance.currentUser;
    final firebaseUser = AuthService.instance.currentFirebaseUser;

    String? projectId =
        user?.assignedProjects.isNotEmpty == true ? user!.assignedProjects.first : null;

    // Fallback: if assignedProjects is empty/outdated, derive from projects where
    // this user is the current site manager.
    if ((projectId == null || projectId.isEmpty) && firebaseUser != null) {
      try {
        final snap = await FirebaseService.instance.projectsCollection
            .where('siteManagerId', isEqualTo: firebaseUser.uid)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          projectId = snap.docs.first.id;
        }
      } catch (_) {
        // ignore
      }
    }

    if (projectId == null || projectId.isEmpty) return;
    _projectId = projectId;

    try {
      final projectDoc =
          await FirebaseService.instance.projectsCollection.doc(projectId).get();
      if (!projectDoc.exists) return;
      final data = projectDoc.data() as Map<String, dynamic>?;
      final name = (data?['name'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() {
        _projectName = name.isEmpty ? projectId : name;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _projectName = projectId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxWidth = media.size.width >= 900 ? 640.0 : 560.0;

    final projectId = _projectId;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Material Request',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: _slide,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Request Details',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.residentBlue,
                                    ),
                              ),
                              if (projectId != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Project: ${(_projectName ?? projectId).toString().trim().isEmpty ? projectId : (_projectName ?? projectId).toString().trim()} (${projectId.toString()})',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppTheme.mediumGray,
                                        fontWeight: FontWeight.w700,
                                      ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 14),
                              if (projectId == null)
                                Text(
                                  'No assigned project found for this user',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: AppTheme.errorRed,
                                        fontWeight: FontWeight.w700,
                                      ),
                                )
                              else
                                StreamBuilder(
                                  stream: FirebaseService.instance
                                      .materialAllocationsCollection(projectId)
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    final docs = snapshot.data?.docs ?? const [];
                                    final allocations = docs
                                        .map(
                                          (d) => <String, dynamic>{
                                            ...(d.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
                                            'id': d.id,
                                          },
                                        )
                                        .toList();

                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                      return const SizedBox(
                                        height: 56,
                                        child: Center(child: CircularProgressIndicator()),
                                      );
                                    }

                                    if (snapshot.hasError) {
                                      return Text(
                                        'Failed to load assigned materials: ${snapshot.error}',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: AppTheme.errorRed,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      );
                                    }

                                    allocations.sort((a, b) {
                                      final an = (a['materialName'] ?? '').toString();
                                      final bn = (b['materialName'] ?? '').toString();
                                      return an.compareTo(bn);
                                    });

                                    if (allocations.isEmpty) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            'No budget materials are assigned to this project yet. You can still request by typing the material name. Material Monitoring will review it.',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: AppTheme.warningOrange,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 12),
                                          _FocusField(
                                            focusNode: _materialFocus,
                                            builder: (focused) {
                                              return TextFormField(
                                                controller: _materialNameController,
                                                focusNode: _materialFocus,
                                                textInputAction: TextInputAction.next,
                                                decoration: const InputDecoration(
                                                  labelText: 'Material name',
                                                  hintText: 'e.g. Cement, Rebar, Tiles',
                                                  prefixIcon: Icon(Icons.inventory_2_outlined),
                                                ),
                                                validator: (value) {
                                                  if ((value ?? '').trim().isEmpty) {
                                                    return 'Please enter the material name';
                                                  }
                                                  return null;
                                                },
                                              );
                                            },
                                          ),
                                        ],
                                      );
                                    }

                                    double readNum(dynamic v) {
                                      if (v is num) return v.toDouble();
                                      return double.tryParse((v ?? '').toString().replaceAll(',', '')) ?? 0.0;
                                    }

                                    String readString(dynamic v) => (v ?? '').toString().trim();

                                    double remainingFor(Map<String, dynamic> a) {
                                      final required = readNum(
                                        a['requiredQuantity'] ?? a['budgetQuantity'],
                                      );
                                      final used = readNum(a['usedQuantity']);
                                      return (required - used).clamp(0.0, double.infinity);
                                    }

                                    double unitPriceFor(Map<String, dynamic> a) {
                                      final raw = a['unitPrice'] ?? a['price'];
                                      if (raw is num) return raw.toDouble();
                                      return double.tryParse(
                                            (raw ?? '')
                                                .toString()
                                                .replaceAll(',', '')
                                                .replaceAll('₱', '')
                                                .trim(),
                                          ) ??
                                          0.0;
                                    }

                                    if (_selectedAllocationId == null && allocations.isNotEmpty) {
                                      final first = allocations.first;
                                      final firstId = readString(first['id']);
                                      final firstUnit = readString(first['unit']);
                                      final firstName = readString(first['materialName']);
                                      final firstUnitPrice = unitPriceFor(first);
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        if (!mounted) return;
                                        setState(() {
                                          _selectedAllocationId = firstId;
                                          _selectedAllocationUnit = firstUnit;
                                          _selectedAllocationRemaining = remainingFor(first);
                                          _selectedAllocationUnitPrice = firstUnitPrice > 0 ? firstUnitPrice : null;
                                          _materialNameController.text = firstName;
                                        });
                                      });
                                    }

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        DropdownButtonFormField<String>(
                                          key: ValueKey<String?>(_selectedAllocationId),
                                          initialValue: _selectedAllocationId,
                                          isExpanded: true,
                                          menuMaxHeight: 340,
                                          items: [
                                            for (final a in allocations)
                                              () {
                                                final id = readString(a['id']);
                                                final name = readString(a['materialName']);
                                                final unit = readString(a['unit']);
                                                final rem = remainingFor(a);
                                                return DropdownMenuItem<String>(
                                                  value: id,
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          '$name (Remaining: ${rem.toStringAsFixed(1)} $unit)',
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }(),
                                          ],
                                          decoration: const InputDecoration(
                                            labelText: 'Material (Assigned)',
                                            prefixIcon: Icon(Icons.inventory_2_outlined),
                                          ),
                                          onChanged: (value) {
                                            final selected = allocations.firstWhere(
                                              (a) => readString(a['id']) == (value ?? ''),
                                              orElse: () => <String, dynamic>{},
                                            );
                                            if (selected.isEmpty) return;
                                            final up = unitPriceFor(selected);
                                            setState(() {
                                              _selectedAllocationId = value;
                                              _selectedAllocationUnit = readString(selected['unit']);
                                              _selectedAllocationRemaining = remainingFor(selected);
                                              _selectedAllocationUnitPrice = up > 0 ? up : null;
                                              _materialNameController.text = readString(selected['materialName']);
                                            });
                                          },
                                          validator: (value) {
                                            if ((value ?? '').trim().isEmpty) {
                                              return 'Please select a material';
                                            }
                                            return null;
                                          },
                                        ),
                                        if ((_selectedAllocationUnit ?? '').trim().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Text(
                                              'Unit: ${(_selectedAllocationUnit ?? '').trim()}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(color: AppTheme.mediumGray),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              const SizedBox(height: 12),
                              _FocusField(
                                focusNode: _quantityFocus,
                                builder: (focused) {
                                  return TextFormField(
                                    controller: _quantityController,
                                    focusNode: _quantityFocus,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Quantity',
                                      hintText: 'e.g. 100',
                                      prefixIcon: Icon(Icons.numbers_outlined),
                                    ),
                                    validator: (value) {
                                      final v = value?.trim() ?? '';
                                      if (v.isEmpty) return 'Please enter the quantity';
                                      final parsed = double.tryParse(v.replaceAll(',', ''));
                                      if (parsed == null || parsed <= 0) {
                                        return 'Enter a valid quantity';
                                      }

                                      final rem = _selectedAllocationRemaining;
                                      if (rem != null && rem > 0 && parsed > rem) {
                                        return 'Requested quantity exceeds remaining allocation (${rem.toStringAsFixed(1)}).';
                                      }
                                      if (_selectedAllocationId != null && rem != null && rem <= 0) {
                                        return 'No remaining allocation for this material.';
                                      }
                                      return null;
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              _FocusField(
                                focusNode: _purposeFocus,
                                builder: (focused) {
                                  return TextFormField(
                                    controller: _purposeController,
                                    focusNode: _purposeFocus,
                                    minLines: 3,
                                    maxLines: 5,
                                    decoration: const InputDecoration(
                                      labelText: 'Purpose / Justification',
                                      hintText: 'Explain why this material is needed',
                                      prefixIcon: Icon(Icons.description_outlined),
                                      alignLabelWithHint: true,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _dateNeededController,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Date Needed',
                                  hintText: 'Select date',
                                  prefixIcon: Icon(Icons.calendar_month_outlined),
                                ),
                                validator: (_) {
                                  if (_dateNeeded == null) return 'Please select the date needed';
                                  return null;
                                },
                                onTap: () async {
                                  final now = DateTime.now();
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _dateNeeded ?? now,
                                    firstDate: DateTime(now.year, now.month, now.day),
                                    lastDate: DateTime(now.year + 2),
                                  );
                                  if (picked == null) return;
                                  final text =
                                      '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                  if (!mounted) return;
                                  setState(() {
                                    _dateNeeded = picked;
                                    _dateNeededController.text = text;
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Priority',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.residentBlue,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              LayoutBuilder(
                                builder: (context, c) {
                                  final selected = _priority == 'urgent' ? 1 : 0;
                                  return SegmentedButton<int>(
                                    segments: const <ButtonSegment<int>>[
                                      ButtonSegment<int>(
                                        value: 0,
                                        label: Text('Normal'),
                                        icon: Icon(Icons.check_circle_outline),
                                      ),
                                      ButtonSegment<int>(
                                        value: 1,
                                        label: Text('Urgent'),
                                        icon: Icon(Icons.priority_high),
                                      ),
                                    ],
                                    selected: <int>{selected},
                                    onSelectionChanged: (s) {
                                      final v = s.isEmpty ? 0 : s.first;
                                      setState(() {
                                        _priority = v == 1 ? 'urgent' : 'normal';
                                      });
                                    },
                                    style: ButtonStyle(
                                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                                        if (states.contains(WidgetState.selected)) {
                                          return AppTheme.residentBlue;
                                        }
                                        return Colors.transparent;
                                      }),
                                      foregroundColor: WidgetStateProperty.resolveWith((states) {
                                        if (states.contains(WidgetState.selected)) {
                                          return Colors.white;
                                        }
                                        return AppTheme.residentBlue;
                                      }),
                                      side: WidgetStateProperty.all(
                                        BorderSide(color: AppTheme.residentBlue.withValues(alpha: 0.35)),
                                      ),
                                      padding: WidgetStateProperty.all(
                                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      ),
                                      shape: WidgetStateProperty.all(
                                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _AnimatedSubmitButton(
                          isLoading: _isSubmitting,
                          hover: _submitHover,
                          pressed: _submitPressed,
                          onHover: (v) => setState(() => _submitHover = v),
                          onPressedChanged: (v) => setState(() => _submitPressed = v),
                          onPressed: _isSubmitting ? null : _submit,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = AuthService.instance.currentUser;
    final projectId = _projectId ?? (user?.assignedProjects.isNotEmpty == true ? user!.assignedProjects.first : null);

    if (projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No assigned project found for this user'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final now = DateTime.now().toIso8601String();
      final materialName = _materialNameController.text.trim();
      if (materialName.isEmpty) {
        throw Exception('Please enter the material name.');
      }

      final quantityText = _quantityController.text.trim();
      final parsedQuantity =
          double.tryParse(quantityText.replaceAll(',', ''));
      final purpose = _purposeController.text.trim();

      final allocationId = (_selectedAllocationId ?? '').trim();

      final requestId =
          'mr_${projectId}_${DateTime.now().millisecondsSinceEpoch.toString()}';

      final projectName = (_projectName ?? projectId).trim().isEmpty ? projectId : (_projectName ?? projectId).trim();
      final subject = 'Material Request: $materialName – $projectName';

      final payload = <String, dynamic>{
        'id': requestId,
        'subject': subject,
        'details': purpose,
        'materialName': materialName,
        if (allocationId.isNotEmpty) 'allocationId': allocationId,
        'unit': (_selectedAllocationUnit ?? '').toString(),
        if ((_selectedAllocationUnitPrice ?? 0) > 0)
          'unitPriceAtRequest': _selectedAllocationUnitPrice,
        'requestedQuantity': parsedQuantity,
        'requestedQuantityText': quantityText,
        'purpose': purpose,
        'dateNeeded': _dateNeeded?.toIso8601String(),
        'priority': _priority,
        'status': AppConstants.materialRequestPending,
        'projectId': projectId,
        'projectName': projectName,
        'createdBy': user?.id ?? user?.email,
        'createdByName': user?.displayName ?? '',
        'createdAt': now,
        'syncStatus': AppConstants.syncStatusPending,
        'geoTag': await GeoTagService.instance.captureGeoTag(),
      };

      await HiveService.instance.saveMaterialRequest(requestId, payload);

      final syncResult = await SyncService.instance.syncPendingData();

      final updated = HiveService.instance.getMaterialRequest(requestId);
      final status = (updated?['syncStatus']?.toString() ?? '').toLowerCase();
      final isSynced = status == AppConstants.syncStatusCompleted;

      await AuditLogService.instance.logAction(
        action: 'material_request_submitted',
        projectId: projectId,
        details: {
          'subject': subject,
          'materialName': materialName,
          'requestedQuantity': parsedQuantity,
          'priority': _priority,
          'projectName': projectName,
          'requestId': requestId,
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isSynced
              ? 'Material request submitted successfully'
              : (syncResult.message.isNotEmpty
                  ? syncResult.message
                  : 'Material request queued for sync when online')),
          backgroundColor:
              isSynced ? AppTheme.softGreen : AppTheme.warningOrange,
        ),
      );

      setState(() {
        _materialNameController.clear();
        _quantityController.clear();
        _purposeController.clear();
        _dateNeeded = null;
        _dateNeededController.clear();
        _priority = 'normal';
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit request: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
}

class _FocusField extends StatefulWidget {
  const _FocusField({
    required this.focusNode,
    required this.builder,
  });

  final FocusNode focusNode;
  final Widget Function(bool focused) builder;

  @override
  State<_FocusField> createState() => _FocusFieldState();
}

class _FocusFieldState extends State<_FocusField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _FocusField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      _focused = widget.focusNode.hasFocus;
      widget.focusNode.addListener(_onFocus);
    }
  }

  void _onFocus() {
    if (!mounted) return;
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _focused ? 1.01 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: widget.builder(_focused),
    );
  }
}

class _AnimatedSubmitButton extends StatelessWidget {
  const _AnimatedSubmitButton({
    required this.isLoading,
    required this.hover,
    required this.pressed,
    required this.onHover,
    required this.onPressedChanged,
    required this.onPressed,
  });

  final bool isLoading;
  final bool hover;
  final bool pressed;
  final ValueChanged<bool> onHover;
  final ValueChanged<bool> onPressedChanged;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final baseColor = const Color(0xFF16A34A);
    final effectiveColor = enabled
        ? (hover ? const Color(0xFF15803D) : baseColor)
        : baseColor.withValues(alpha: 0.55);

    final scale = pressed ? 0.98 : 1.0;

    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => onPressedChanged(true) : null,
        onTapCancel: () => onPressedChanged(false),
        onTapUp: (_) => onPressedChanged(false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: effectiveColor,
                foregroundColor: Colors.white,
                elevation: enabled ? 3 : 0,
                shadowColor: Colors.black.withValues(alpha: 0.18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(
                isLoading ? 'Submitting…' : 'Submit Request',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
