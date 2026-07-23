/// Categories for project files linked to GovTrack AI (Firestore `projects/{id}/documents`).
class GovtrackDocumentCategories {
  GovtrackDocumentCategories._();

  static const planningProgress = 'planning_progress';
  static const materialsInventory = 'materials_inventory';
  static const engineeringTechnical = 'engineering_technical';
  static const safetyCompliance = 'safety_compliance';

  static const all = <String>[
    planningProgress,
    materialsInventory,
    engineeringTechnical,
    safetyCompliance,
  ];

  static const labels = <String, String>{
    planningProgress: 'Project planning & progress',
    materialsInventory: 'Materials & inventory',
    engineeringTechnical: 'Engineering & technical',
    safetyCompliance: 'Safety & compliance',
  };

  /// Recommended file types per category (for admin upload guidance).
  static const recommendedFiles = <String, List<String>>{
    planningProgress: [
      'Master project schedule (Gantt, MS Project, Primavera export)',
      'Daily construction logs',
      'Scope of work (SOW)',
    ],
    materialsInventory: [
      'Bill of quantities (BOQ)',
      'Purchase orders & delivery receipts',
      'Material inventory sheets',
    ],
    engineeringTechnical: [
      'Approved blueprints / CAD drawings',
      'Material safety data sheets (MSDS/SDS)',
      'Technical specifications (mix designs, steel grades, etc.)',
    ],
    safetyCompliance: [
      'Site safety management plan (SSMP)',
      'Local building codes & regulations',
    ],
  };
}
