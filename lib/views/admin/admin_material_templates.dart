import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../services/archive_service.dart';
import 'widgets/admin_bottom_nav.dart';
import 'widgets/admin_glass_layout.dart';

class AdminMaterialTemplates extends StatefulWidget {
  const AdminMaterialTemplates({super.key});

  @override
  State<AdminMaterialTemplates> createState() => _AdminMaterialTemplatesState();
}

class _AdminMaterialTemplatesState extends State<AdminMaterialTemplates> {
  static const Map<String, String> _defaultUnitByMaterial = {
    'cement': 'bag',
    'rebar': 'pcs',
    'steel': 'kg',
    'sand': 'm³',
    'gravel': 'm³',
    'hollow blocks': 'pcs',
    'concrete': 'm³',
    'nails': 'box',
    'tie wire': 'kg',
    'plywood': 'sheet',
    'lumber': 'pcs',
    'gi sheet': 'sheet',
    'paint': 'gallon',
    'primer': 'gallon',
    'thinner': 'liter',
    'pvc pipe': 'pcs',
    'electrical wire': 'meter',
    'tiles': 'box',
    'adhesive': 'bag',
  };

  String _norm(String s) => s.trim().toLowerCase();

  String? _inferUnit(String name) {
    final key = _norm(name);
    for (final e in _defaultUnitByMaterial.entries) {
      if (key.contains(e.key)) return e.value;
    }

    return null;
  }

  double _readNum(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v ?? '').toString().replaceAll(',', '')) ?? 0.0;
  }

  Future<void> _showTemplateEditor({
    DocumentSnapshot<Map<String, dynamic>>? doc,
  }) async {
    final isEdit = doc != null;
    final data = (doc?.data() ?? <String, dynamic>{}).cast<String, dynamic>();

    final nameController = TextEditingController(text: (data['name'] ?? '').toString());
    final descController = TextEditingController(text: (data['description'] ?? '').toString());

    final List<Map<String, dynamic>> materials =
        ((data['materials'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .map((m) => <String, dynamic>{
                  'material_name': (m['material_name'] ?? m['materialName'] ?? '').toString(),
                  'unit': (m['unit'] ?? '').toString(),
                  'default_quantity': _readNum(m['default_quantity'] ?? m['defaultQuantity'] ?? m['quantity']),
                  'default_unit_price': _readNum(m['default_unit_price'] ?? m['defaultUnitPrice'] ?? m['unitPrice'] ?? m['price']),
                })
            .toList();

    if (materials.isEmpty) {
      materials.add(<String, dynamic>{
        'material_name': '',
        'unit': '',
        'default_quantity': 0.0,
        'default_unit_price': 0.0,
      });
    }

    final formKey = GlobalKey<FormState>();

    final nameCtrls = <TextEditingController>[];
    final unitCtrls = <TextEditingController>[];
    final qtyCtrls = <TextEditingController>[];
    final priceCtrls = <TextEditingController>[];

    void syncControllersFromMaterials() {
      while (nameCtrls.length < materials.length) {
        final idx = nameCtrls.length;
        final m = materials[idx];
        nameCtrls.add(TextEditingController(text: (m['material_name'] ?? '').toString()));
        unitCtrls.add(TextEditingController(text: (m['unit'] ?? '').toString()));
        qtyCtrls.add(TextEditingController(text: _readNum(m['default_quantity']).toString()));
        priceCtrls.add(TextEditingController(text: _readNum(m['default_unit_price']).toString()));
      }
    }

    syncControllersFromMaterials();

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setStateDialog) {
              bool isSaving = false;

              double totalBudget() {
                double total = 0;
                for (final m in materials) {
                  final q = _readNum(m['default_quantity']);
                  final p = _readNum(m['default_unit_price']);
                  if (q > 0 && p > 0) total += q * p;
                }
                return total;
              }

              Future<void> save() async {
                if (isSaving) return;
                if (!formKey.currentState!.validate()) return;
                setStateDialog(() => isSaving = true);

                final name = nameController.text.trim();
                final desc = descController.text.trim();

                final cleaned = <Map<String, dynamic>>[];
                for (final m in materials) {
                  final materialName = (m['material_name'] ?? '').toString().trim();
                  if (materialName.isEmpty) continue;
                  final unit = (m['unit'] ?? '').toString().trim();
                  final q = _readNum(m['default_quantity']);
                  final p = _readNum(m['default_unit_price']);
                  cleaned.add(<String, dynamic>{
                    'material_name': materialName,
                    'unit': unit,
                    'default_quantity': q,
                    'default_unit_price': p,
                  });
                }

                if (cleaned.isEmpty) {
                  setStateDialog(() => isSaving = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please add at least 1 material in the template.'),
                      backgroundColor: AppTheme.errorRed,
                    ),
                  );
                  return;
                }

                final ref = isEdit
                    ? FirebaseService.instance.materialTemplatesCollection.doc(doc.id)
                    : FirebaseService.instance.materialTemplatesCollection.doc();

                final currentUser = AuthService.instance.currentUser;
                final createdByName = (currentUser == null)
                    ? ''
                    : '${currentUser.firstName} ${currentUser.lastName}'.trim();

                final payload = <String, dynamic>{
                  'template_id': ref.id,
                  'name': name,
                  'description': desc,
                  'materials': cleaned,
                  'updatedAt': FieldValue.serverTimestamp(),
                  if (!isEdit) 'createdByName': createdByName,
                  if (!isEdit) 'createdAt': FieldValue.serverTimestamp(),
                };

                try {
                  await ref.set(payload, SetOptions(merge: true));
                  if (!mounted) return;
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEdit ? 'Template updated' : 'Template created'),
                      backgroundColor: AppTheme.softGreen,
                    ),
                  );
                } catch (e) {
                  setStateDialog(() => isSaving = false);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to save template: $e'),
                      backgroundColor: AppTheme.errorRed,
                    ),
                  );
                }
              }

              return Dialog(
                insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                backgroundColor: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Material(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Form(
                          key: formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      isEdit ? 'Edit Material Template' : 'Create Material Template',
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: nameController,
                                enabled: !isSaving,
                                decoration: const InputDecoration(
                                  labelText: 'Template name',
                                  prefixIcon: Icon(Icons.category_outlined),
                                ),
                                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter template name' : null,
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: descController,
                                enabled: !isSaving,
                                minLines: 2,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  labelText: 'Description',
                                  prefixIcon: Icon(Icons.description_outlined),
                                ),
                              ),
                              const SizedBox(height: 14),
                              GlassCard(
                                borderRadius: 16,
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Materials',
                                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: isSaving
                                              ? null
                                              : () {
                                                  setStateDialog(() {
                                                    materials.add(<String, dynamic>{
                                                      'material_name': '',
                                                      'unit': '',
                                                      'default_quantity': 0.0,
                                                      'default_unit_price': 0.0,
                                                    });

                                                    nameCtrls.add(TextEditingController(text: ''));
                                                    unitCtrls.add(TextEditingController(text: ''));
                                                    qtyCtrls.add(TextEditingController(text: '0.0'));
                                                    priceCtrls.add(TextEditingController(text: '0.0'));
                                                  });
                                                },
                                          icon: const Icon(Icons.add),
                                          label: const Text('Add row'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxHeight: 360),
                                      child: ListView.separated(
                                        shrinkWrap: true,
                                        itemCount: materials.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                                        itemBuilder: (context, i) {
                                          syncControllersFromMaterials();
                                          final m = materials[i];
                                          final nameCtrl = nameCtrls[i];
                                          final unitCtrl = unitCtrls[i];
                                          final qtyCtrl = qtyCtrls[i];
                                          final priceCtrl = priceCtrls[i];

                                          return Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                flex: 4,
                                                child: TextFormField(
                                                  controller: nameCtrl,
                                                  enabled: !isSaving,
                                                  decoration: const InputDecoration(
                                                    labelText: 'Material',
                                                  ),
                                                  onChanged: (v) {
                                                    setStateDialog(() {
                                                      m['material_name'] = v;
                                                      final inferred = _inferUnit(v);
                                                      if ((unitCtrl.text.trim().isEmpty) && inferred != null) {
                                                        m['unit'] = inferred;
                                                        unitCtrl.text = inferred;
                                                      }
                                                    });
                                                  },
                                                  validator: (v) {
                                                    if ((v ?? '').trim().isEmpty) return 'Required';
                                                    return null;
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                flex: 2,
                                                child: TextFormField(
                                                  controller: unitCtrl,
                                                  enabled: !isSaving,
                                                  decoration: const InputDecoration(
                                                    labelText: 'Unit',
                                                  ),
                                                  onChanged: (v) => setStateDialog(() => m['unit'] = v),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                flex: 2,
                                                child: TextFormField(
                                                  controller: qtyCtrl,
                                                  enabled: !isSaving,
                                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                  decoration: const InputDecoration(
                                                    labelText: 'Qty',
                                                  ),
                                                  onChanged: (v) => setStateDialog(() => m['default_quantity'] = _readNum(v)),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                flex: 2,
                                                child: TextFormField(
                                                  controller: priceCtrl,
                                                  enabled: !isSaving,
                                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                  decoration: const InputDecoration(
                                                    labelText: 'Unit Price',
                                                  ),
                                                  onChanged: (v) => setStateDialog(() => m['default_unit_price'] = _readNum(v)),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              IconButton(
                                                onPressed: isSaving
                                                    ? null
                                                    : () {
                                                        setStateDialog(() {
                                                          nameCtrls[i].dispose();
                                                          unitCtrls[i].dispose();
                                                          qtyCtrls[i].dispose();
                                                          priceCtrls[i].dispose();
                                                          nameCtrls.removeAt(i);
                                                          unitCtrls.removeAt(i);
                                                          qtyCtrls.removeAt(i);
                                                          priceCtrls.removeAt(i);
                                                          materials.removeAt(i);
                                                          if (materials.isEmpty) {
                                                            materials.add(<String, dynamic>{
                                                              'material_name': '',
                                                              'unit': '',
                                                              'default_quantity': 0.0,
                                                              'default_unit_price': 0.0,
                                                            });
                                                            syncControllersFromMaterials();
                                                          }
                                                        });
                                                      },
                                                tooltip: 'Remove row',
                                                icon: const Icon(Icons.delete_outline, color: AppTheme.errorRed),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.calculate_outlined,
                                          size: 18,
                                          color: AppTheme.mediumGray,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Estimated total budget: ₱${totalBudget().toStringAsFixed(2)}',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: AppTheme.mediumGray,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                                    child: const Text('Cancel'),
                                  ),
                                  const SizedBox(width: 10),
                                  FilledButton(
                                    onPressed: isSaving ? null : save,
                                    child: isSaving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Text('Save Template'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      for (final c in nameCtrls) {
        c.dispose();
      }
      for (final c in unitCtrls) {
        c.dispose();
      }
      for (final c in qtyCtrls) {
        c.dispose();
      }
      for (final c in priceCtrls) {
        c.dispose();
      }
    }
  }

  Future<void> _deleteTemplate(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final name = (doc.data()?['name'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        return AlertDialog(
          title: const Text('Archive template?'),
          content: Text(
            'Archive "$name"? It will be hidden from active lists but kept for audit review.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.errorRed),
              child: const Text('Archive'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    try {
      await ArchiveService.instance.archiveMaterialTemplate(
        templateId: doc.id,
        templateName: name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Template archived — data retained for audit'),
          backgroundColor: AppTheme.softGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to archive template: $e'), backgroundColor: AppTheme.errorRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseService.instance.materialTemplatesCollection
        .orderBy('name')
        .snapshots();

    return AdminGlassScaffold(
      title: 'Material Templates',
      actions: [
        IconButton(
          tooltip: 'Create template',
          icon: const Icon(Icons.add),
          onPressed: () => _showTemplateEditor(),
        ),
        IconButton(
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.push(RouteNames.profile),
        ),
      ],
      bottomNavigationBar: const AdminBottomNavBar(
        current: AdminNavItem.materialInventory,
      ),
      child: GlassCard(
        borderRadius: 18,
        padding: const EdgeInsets.all(14),
        child: StreamBuilder<QuerySnapshot>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Failed to load templates: ${snapshot.error}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.errorRed),
                  textAlign: TextAlign.center,
                ),
              );
            }

            final docs = snapshot.data?.docs
                    .map((d) => d as QueryDocumentSnapshot<Map<String, dynamic>>)
                    .where((d) => !ArchiveService.isArchived(d.data()))
                    .toList() ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

            if (docs.isEmpty) {
              return Center(
                child: Text(
                  'No templates yet. Create one to speed up project materials setup.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.mediumGray),
                  textAlign: TextAlign.center,
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final d = docs[i];
                final data = d.data();
                final name = (data['name'] ?? d.id).toString();
                final mats = ((data['materials'] as List?) ?? const []);

                double total = 0;
                for (final m in mats) {
                  if (m is! Map) continue;
                  final mm = m.cast<String, dynamic>();
                  total += _readNum(mm['default_quantity']) * _readNum(mm['default_unit_price']);
                }

                return GlassCard(
                  borderRadius: 16,
                  padding: const EdgeInsets.all(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AdminMaterialTemplateDetail(templateId: d.id),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _showTemplateEditor(doc: d),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline, color: AppTheme.errorRed),
                              onPressed: () => _deleteTemplate(d),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${mats.length} materials • Estimated total ₱${total.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.mediumGray,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class AdminMaterialTemplateDetail extends StatefulWidget {
  const AdminMaterialTemplateDetail({
    super.key,
    required this.templateId,
  });

  final String templateId;

  @override
  State<AdminMaterialTemplateDetail> createState() => _AdminMaterialTemplateDetailState();
}

class _AdminMaterialTemplateDetailState extends State<AdminMaterialTemplateDetail> {
  double _readNum(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v ?? '').toString().replaceAll(',', '')) ?? 0.0;
  }

  Future<void> _showEditTemplateInfoDialog({
    required DocumentSnapshot<Map<String, dynamic>> doc,
  }) async {
    final data = (doc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    final nameController = TextEditingController(text: (data['name'] ?? '').toString());
    final descController = TextEditingController(text: (data['description'] ?? '').toString());
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            Future<void> save() async {
              if (isSaving) return;
              if (!(formKey.currentState?.validate() ?? false)) return;
              setStateDialog(() => isSaving = true);

              try {
                await doc.reference.set(
                  <String, dynamic>{
                    'name': nameController.text.trim(),
                    'description': descController.text.trim(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  },
                  SetOptions(merge: true),
                );
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Template updated'),
                    backgroundColor: AppTheme.softGreen,
                  ),
                );
              } catch (e) {
                setStateDialog(() => isSaving = false);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to update template: $e'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('Edit Template'),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        enabled: !isSaving,
                        decoration: const InputDecoration(labelText: 'Template name'),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: descController,
                        enabled: !isSaving,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Description'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving ? null : save,
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<Map<String, dynamic>> _readMaterials(Map<String, dynamic> data) {
    final raw = (data['materials'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .map((m) => <String, dynamic>{
              'material_name': (m['material_name'] ?? m['materialName'] ?? '').toString(),
              'unit': (m['unit'] ?? '').toString(),
              'default_quantity': _readNum(m['default_quantity'] ?? m['defaultQuantity'] ?? m['quantity']),
              'default_unit_price': _readNum(m['default_unit_price'] ?? m['defaultUnitPrice'] ?? m['unitPrice'] ?? m['price']),
            })
        .toList();
  }

  Future<void> _upsertMaterials({
    required DocumentSnapshot<Map<String, dynamic>> doc,
    required List<Map<String, dynamic>> materials,
  }) async {
    final cleaned = <Map<String, dynamic>>[];
    for (final m in materials) {
      final name = (m['material_name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      cleaned.add(<String, dynamic>{
        'material_name': name,
        'unit': (m['unit'] ?? '').toString().trim(),
        'default_quantity': _readNum(m['default_quantity']),
        'default_unit_price': _readNum(m['default_unit_price']),
      });
    }

    await doc.reference.set(
      <String, dynamic>{
        'materials': cleaned,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _showMaterialEditor({
    required DocumentSnapshot<Map<String, dynamic>> doc,
    int? index,
  }) async {
    final data = (doc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    final materials = _readMaterials(data);

    final isEdit = index != null && index >= 0 && index < materials.length;
    final current = isEdit ? materials[index] : <String, dynamic>{};

    final nameController = TextEditingController(text: (current['material_name'] ?? '').toString());
    final unitController = TextEditingController(text: (current['unit'] ?? '').toString());
    final qtyController = TextEditingController(text: _readNum(current['default_quantity']).toString());
    final priceController = TextEditingController(text: _readNum(current['default_unit_price']).toString());

    bool isSaving = false;
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            Future<void> save() async {
              if (isSaving) return;
              if (!formKey.currentState!.validate()) return;
              setStateDialog(() => isSaving = true);

              final name = nameController.text.trim();
              final unit = unitController.text.trim();
              final q = double.tryParse(qtyController.text.trim().replaceAll(',', '')) ?? 0.0;
              final p = double.tryParse(priceController.text.trim().replaceAll(',', '')) ?? 0.0;
              final newItem = <String, dynamic>{
                'material_name': name,
                'unit': unit,
                'default_quantity': q,
                'default_unit_price': p,
              };

              if (isEdit) {
                materials[index] = newItem;
              } else {
                materials.add(newItem);
              }

              try {
                await _upsertMaterials(doc: doc, materials: materials);
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isEdit ? 'Material updated' : 'Material added'),
                    backgroundColor: AppTheme.softGreen,
                  ),
                );
              } catch (e) {
                setStateDialog(() => isSaving = false);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to save material: $e'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
              }
            }

            return AlertDialog(
              title: Text(isEdit ? 'Edit Material' : 'Add Material'),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        enabled: !isSaving,
                        decoration: const InputDecoration(labelText: 'Material name'),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: unitController,
                              enabled: !isSaving,
                              decoration: const InputDecoration(labelText: 'Unit'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: qtyController,
                              enabled: !isSaving,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Estimated quantity'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: priceController,
                        enabled: !isSaving,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Unit price (₱)'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving ? null : save,
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteMaterial({
    required DocumentSnapshot<Map<String, dynamic>> doc,
    required int index,
  }) async {
    final data = (doc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    final materials = _readMaterials(data);
    if (index < 0 || index >= materials.length) return;
    final name = (materials[index]['material_name'] ?? '').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete material?'),
        content: Text('Delete "$name" from this template?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    materials.removeAt(index);

    try {
      await _upsertMaterials(doc: doc, materials: materials);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material removed'), backgroundColor: AppTheme.softGreen),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove material: $e'), backgroundColor: AppTheme.errorRed),
      );
    }
  }

  Future<void> _exportCsv({
    required String templateName,
    required List<Map<String, dynamic>> materials,
  }) async {
    final lines = <String>['Material Name|Unit|Quantity|Price'];
    for (final m in materials) {
      final name = (m['material_name'] ?? '').toString().replaceAll('|', ' ');
      final unit = (m['unit'] ?? '').toString().replaceAll('|', ' ');
      final q = _readNum(m['default_quantity']);
      final p = _readNum(m['default_unit_price']);
      lines.add('$name|$unit|$q|$p');
    }
    final csv = lines.join('\n');
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Export copied to clipboard (${templateName.trim().isEmpty ? 'template' : templateName}).'),
        backgroundColor: AppTheme.softGreen,
      ),
    );
  }

  List<Map<String, dynamic>> _parseCsv(String input) {
    final lines = input
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return <Map<String, dynamic>>[];

    final out = <Map<String, dynamic>>[];
    for (final line in lines) {
      if (line.toLowerCase().startsWith('material')) continue;
      final parts = line.contains('|') ? line.split('|') : line.split(',');
      if (parts.length < 4) continue;
      final name = parts[0].trim();
      final unit = parts[1].trim();
      final qty = double.tryParse(parts[2].trim().replaceAll(',', '')) ?? 0.0;
      final price = double.tryParse(parts[3].trim().replaceAll(',', '')) ?? 0.0;
      if (name.isEmpty) continue;
      out.add(<String, dynamic>{
        'material_name': name,
        'unit': unit,
        'default_quantity': qty,
        'default_unit_price': price,
      });
    }
    return out;
  }

  Future<void> _showImportCsv({
    required DocumentSnapshot<Map<String, dynamic>> doc,
  }) async {
    final controller = TextEditingController();
    List<Map<String, dynamic>> preview = const [];
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            Future<void> save() async {
              if (isSaving) return;
              setStateDialog(() => isSaving = true);

              final data = (doc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
              final materials = _readMaterials(data);
              materials.addAll(preview);

              try {
                await _upsertMaterials(doc: doc, materials: materials);
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Imported ${preview.length} materials.'),
                    backgroundColor: AppTheme.softGreen,
                  ),
                );
              } catch (e) {
                setStateDialog(() => isSaving = false);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to import: $e'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
              }
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Import CSV',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: controller,
                        enabled: !isSaving,
                        minLines: 6,
                        maxLines: 10,
                        decoration: const InputDecoration(
                          hintText: 'Material Name|Unit|Quantity|Price\nCement (40kg)|bag|500|250\nSand (Washed)|m³|30|1200',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          setStateDialog(() {
                            preview = _parseCsv(v);
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Preview (${preview.length} rows)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.mediumGray,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: SingleChildScrollView(
                          child: GlassDataTableTheme(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('#')),
                                DataColumn(label: Text('Material')),
                                DataColumn(label: Text('Unit')),
                                DataColumn(label: Text('Qty')),
                                DataColumn(label: Text('Price')),
                              ],
                              rows: [
                                for (int i = 0; i < preview.length; i++)
                                  () {
                                    final m = preview[i];
                                    final q = _readNum(m['default_quantity']);
                                    final p = _readNum(m['default_unit_price']);
                                    return DataRow(
                                      cells: [
                                        DataCell(Text('${i + 1}')),
                                        DataCell(Text((m['material_name'] ?? '').toString())),
                                        DataCell(Text((m['unit'] ?? '').toString())),
                                        DataCell(Text(q.toStringAsFixed(2))),
                                        DataCell(Text(p.toStringAsFixed(2))),
                                      ],
                                    );
                                  }(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: (isSaving || preview.isEmpty) ? null : save,
                            child: isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Import'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteTemplate(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final name = (doc.data()?['name'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        return AlertDialog(
          title: const Text('Archive template?'),
          content: Text(
            'Archive "$name"? It will be hidden from active lists but kept for audit review.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.errorRed),
              child: const Text('Archive'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    try {
      await ArchiveService.instance.archiveMaterialTemplate(
        templateId: doc.id,
        templateName: name,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Template archived — data retained for audit'),
          backgroundColor: AppTheme.softGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to archive template: $e'), backgroundColor: AppTheme.errorRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final docRef = FirebaseService.instance.materialTemplatesCollection
        .doc(widget.templateId)
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snap, _) => (snap.data() ?? <String, dynamic>{}),
          toFirestore: (data, _) => data,
        );

    return AdminGlassScaffold(
      title: 'Material Templates',
      actions: [
        IconButton(
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.push(RouteNames.profile),
        ),
      ],
      bottomNavigationBar: const AdminBottomNavBar(
        current: AdminNavItem.materialInventory,
      ),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load template: ${snapshot.error}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.errorRed),
                textAlign: TextAlign.center,
              ),
            );
          }

          final doc = snapshot.data;
          if (doc == null || !doc.exists) {
            return Center(
              child: Text(
                'Template not found.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.mediumGray),
              ),
            );
          }

          final data = (doc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
          final templateName = (data['name'] ?? '').toString();
          final desc = (data['description'] ?? '').toString();
          final createdBy = (data['createdByName'] ?? '').toString();
          final createdAt = data['createdAt'];
          final updatedAt = data['updatedAt'];

          String fmtTs(dynamic v) {
            if (v is Timestamp) {
              return v.toDate().toString();
            }
            return '';
          }

          final materials = _readMaterials(data);
          double totalBudget = 0;
          for (final m in materials) {
            totalBudget += _readNum(m['default_quantity']) * _readNum(m['default_unit_price']);
          }

          return GlassCard(
            borderRadius: 18,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        templateName.isEmpty ? 'Material Template' : templateName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back to Templates'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: () => _showEditTemplateInfoDialog(doc: doc),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit Template'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: () => _showMaterialEditor(doc: doc, index: null),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Material'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                GlassCard(
                  borderRadius: 16,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Template Information',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 22,
                        runSpacing: 10,
                        children: [
                          SizedBox(
                            width: 340,
                            child: _InfoField(label: 'Template Name', value: templateName),
                          ),
                          SizedBox(
                            width: 340,
                            child: _InfoField(label: 'Created By', value: createdBy),
                          ),
                          SizedBox(
                            width: 340,
                            child: _InfoField(label: 'Created At', value: fmtTs(createdAt)),
                          ),
                          SizedBox(
                            width: 340,
                            child: _InfoField(label: 'Updated At', value: fmtTs(updatedAt)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _InfoField(label: 'Description', value: desc),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Materials List (${materials.length} items)',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showImportCsv(doc: doc),
                      icon: const Icon(Icons.upload_file_outlined, size: 18),
                      label: const Text('Import CSV'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () => _exportCsv(templateName: templateName, materials: materials),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Export'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                GlassCard(
                  borderRadius: 16,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 520),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 980),
                            child: GlassDataTableTheme(
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('#')),
                                  DataColumn(label: Text('Material Name')),
                                  DataColumn(label: Text('Unit')),
                                  DataColumn(label: Text('Estimated Quantity')),
                                  DataColumn(label: Text('Unit Price (₱)')),
                                  DataColumn(label: Text('Total (₱)')),
                                  DataColumn(label: Text('Actions')),
                                ],
                                rows: [
                                  for (int i = 0; i < materials.length; i++)
                                    () {
                                      final m = materials[i];
                                      final q = _readNum(m['default_quantity']);
                                      final p = _readNum(m['default_unit_price']);
                                      final t = q * p;
                                      return DataRow(
                                        cells: [
                                          DataCell(Text('${i + 1}')),
                                          DataCell(Text((m['material_name'] ?? '').toString())),
                                          DataCell(Text((m['unit'] ?? '').toString())),
                                          DataCell(Text(q.toStringAsFixed(2))),
                                          DataCell(Text(p.toStringAsFixed(2))),
                                          DataCell(Text(t.toStringAsFixed(2))),
                                          DataCell(
                                            Row(
                                              children: [
                                                IconButton(
                                                  tooltip: 'Edit',
                                                  onPressed: () => _showMaterialEditor(doc: doc, index: i),
                                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                                ),
                                                IconButton(
                                                  tooltip: 'Delete',
                                                  onPressed: () => _deleteMaterial(doc: doc, index: i),
                                                  icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.errorRed),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                    }(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Spacer(),
                          Text(
                            'TOTAL ESTIMATED BUDGET:',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black.withValues(alpha: 0.70),
                                ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '₱${totalBudget.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.primaryBlue,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Note: Quantities are estimated. You can update actual quantities when using this template for a specific project.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _deleteTemplate(doc),
                      icon: const Icon(Icons.delete_outline, color: AppTheme.errorRed, size: 18),
                      label: const Text('Delete Template', style: TextStyle(color: AppTheme.errorRed)),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoField extends StatelessWidget {
  const _InfoField({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.mediumGray,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value.trim().isEmpty ? '-' : value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
