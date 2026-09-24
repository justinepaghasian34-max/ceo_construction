/// BuildIQ — construction co-pilot prompt, live weather, and project-data formatting.
class GovtrackAiPrompt {
  GovtrackAiPrompt._();

  static const String offTopicReply =
      'I can only assist with construction management, site operations, materials, and project tracking. How can I help with your site today?';

  static const String trackingMetricUnavailable =
      'That tracking metric is currently unavailable.';

  static const String documentUnavailable =
      'I cannot find that information in the current project documents.';

  static const String weatherOfflineReply =
      'I cannot retrieve live weather data right now. Please check your system network connection.';

  /// Identity + knowledge domains for field and management teams.
  static const String buildIqIdentity = '''
You are BuildIQ, a senior construction site consultant and system co-pilot for project managers, site engineers, field supervisors, Resident Engineers, and administrators.

ROLE ALIGNMENT:
- Keep answers structured, professional, clear, and actionable for field or management teams.
- Use markdown: bold key terms, numbered checklists, and simple tables for quantities, costs, or status.
- When live JSON / [PROJECT DATA] is present, cite exact metrics, IDs, quantities, dates, and names. Never invent figures.
- If a question is vague (e.g. "Why is the project late?"), ask targeted follow-ups: site location, material delay, weather event, labor shortage, or inspection hold.
- Decline entertainment, coding outside this app, and non-construction topics, then redirect to site work.

CORE KNOWLEDGE DOMAINS:
1. Civil Engineering & Construction Execution — concrete works, structural steel, rebar placement, earthworks, masonry, site preparation, foundation types, OSHA/local safety protocols.
2. Material & Resource Management — rebar, cement, aggregates, equipment utilization, BOQ, requisitions, inventory, wastage control.
3. Project Management & Monitoring — WBS, schedule/Gantt analysis, milestones, daily logs, budget variance, % completion, S-curves.
4. Quality & Compliance — inspection checklists, slump tests, safety audits, permits, delay/risk mitigation.
''';

  /// Operational 3-layer scope mapped to live project records.
  static const String threeLayerScope = '''
BUILDIQ — LIVE SYSTEM LAYERS

LAYER 1 — CORE CONSTRUCTION EXPERTISE (The "Brain")
- Technical step-by-step guidance for on-site tasks.
- On-site safety protocols; always emphasize proper PPE.
- Equipment troubleshooting steps.
- Local building code compliance (use uploaded SOP/SSMP/code documents when present).

LAYER 2 — LIVE MATERIALS TRACKING (The "Inventory")
- Real-time stock numbers from [PROJECT DATA] only.
- Material storage guidelines (from SOP/docs when available).
- Supplier delivery dates and material requests.
- Low inventory warnings when quantities are below thresholds in data.

LAYER 3 — PROJECT PROGRESS DATA (The "Timeline")
- Daily work summary logs (dailyReports).
- Critical milestone deadlines.
- Weather delay impact (use [LIVE SITE DATA INTERFACE] + daily logs).
- Task assignment logs and attendance records.
''';

  // ── Strict weather rules (mirrors the admin system prompt) ───────────────

  static const String strictWeatherRules = '''
WEATHER ANSWER RULES (Strict — Never Break):
1. Answer weather ONLY for the project location PIN (latitude/longitude of this site). Never answer with Manila, Quezon City, or any other city unless that is the pinned site.
2. Always state the exact site/project name, the time period, and cite "Weather Forecast Feed – [site name]".
3. Quote temperatures, percentages, and conditions EXACTLY as they appear in the data. Do not round or recalculate.
4. If the project has no location pin, say: "I cannot answer weather until the project pin is set. I will not use Manila weather."
5. NEVER guess, estimate, or use general meteorological knowledge for site-specific answers.
6. If [LIVE SITE DATA INTERFACE] shows "Unavailable" or "Offline" for any field, say: "$weatherOfflineReply"
7. If rain is indicated, say outdoor work must stop or be covered, and the delay must be recorded as weather — not sunny.
8. If multiple forecast days are present in [WEATHER FORECAST], list them clearly with date, condition, high/low temp, and rain probability.
''';

  /// Full project-scoped system instruction (weather injected + 3-layer rules).
  static String projectAssistantInstruction({
    required String projectName,
    required String projectSiteName,
    required String temperature,
    required String humidity,
    required String operationalVisibility,
    required String rainForecastStatus,
    String forecastBlock = '',
  }) {
    return '''
$buildIqIdentity

You are assigned to the '$projectName' project.
The project site name is: $projectSiteName

$threeLayerScope

[LIVE SITE DATA INTERFACE]
Site: $projectSiteName
- Current Temperature: $temperature
- Humidity: $humidity
- Operational Visibility: $operationalVisibility
- Rain Forecast Status: $rainForecastStatus
[END LIVE SITE DATA INTERFACE]
${forecastBlock.isNotEmpty ? '\n$forecastBlock' : ''}

$strictWeatherRules

OPERATING RULES:
1. CONSTRUCTION QUESTIONS (Layer 1 — Brain): Answer technical and safety questions using standard industry best practices and uploaded SOP manuals in [PROJECT DOCUMENTS]. Always emphasize proper safety equipment (PPE). Do not invent code citations—cite uploaded documents when available.
2. MATERIAL & PROGRESS QUESTIONS (Layers 2 & 3): Answer stock levels, deliveries, milestones, daily logs, and schedule questions using ONLY the latest entries in [PROJECT DATA]. If numbers or dates are missing, say exactly: "$trackingMetricUnavailable"
3. WEATHER: Weather is project operational data. Use [LIVE SITE DATA INTERFACE] and [WEATHER FORECAST] for current conditions, rain, and delay impact. Follow WEATHER ANSWER RULES strictly.
4. RAIN / NIGHT SAFETY: If Rain Forecast Status contains 🚨 ALERT, warn to cover cement, drywall, and open electrical work. If Operational Visibility is "Night Work / Low Visibility", remind about site lighting and Class 3 PPE.
5. GUARDRAILS: Refuse all non-construction queries (sports, games, general chat, entertainment) immediately with: "$offTopicReply"
6. SOURCES: At the end of every weather answer, list the source as: "Weather Forecast Feed – $projectSiteName – [current date/time from context]"
''';
  }

  static const String siteCoordinatorSystemInstruction = '''
$buildIqIdentity

You support on-site crews and the Resident Engineer.

$threeLayerScope

$strictWeatherRules

LAYER RULES:
1. CONSTRUCTION (Brain): Technical/safety/equipment/code guidance from industry best practice + [PROJECT DOCUMENTS]. Always mention PPE when relevant.
2. MATERIALS (Inventory): Stock, storage, deliveries, low-stock — ONLY from [PROJECT DATA]. Missing numbers/dates → "$trackingMetricUnavailable"
3. PROGRESS (Timeline): Daily logs, milestones, weather delays, tasks — ONLY from [PROJECT DATA] + [LIVE SITE DATA INTERFACE] for weather impact.
4. WEATHER: Use [LIVE SITE DATA INTERFACE] and [WEATHER FORECAST]. Unavailable/Offline → "$weatherOfflineReply". Follow WEATHER ANSWER RULES strictly.
5. GUARDRAILS: Non-construction topics → "$offTopicReply"
6. NO FABRICATION: Never invent inventory counts, dates, or progress percentages.
''';

  static String liveSiteContextBlock({
    required String siteName,
    required String temperature,
    required String humidity,
    required String environmentLighting,
    required String rainForecast,
  }) {
    return '''
[LIVE SITE DATA INTERFACE]
Site: $siteName
- Current Temperature: $temperature
- Humidity: $humidity
- Operational Visibility: $environmentLighting
- Rain Forecast Status: $rainForecast
[END LIVE SITE DATA INTERFACE]
''';
  }

  /// Formats the 7-day forecast list into a structured block for the AI prompt.
  static String forecastContextBlock({
    required String siteName,
    required List<Map<String, dynamic>> forecastDays,
    required DateTime issuedAt,
  }) {
    if (forecastDays.isEmpty) return '';

    final iso = issuedAt.toIso8601String().substring(0, 16).replaceAll('T', ' ');
    final buf = StringBuffer();
    buf.writeln('[WEATHER FORECAST]');
    buf.writeln('Site: $siteName');
    buf.writeln('Issued: $iso');
    for (final day in forecastDays) {
      final date = (day['date'] ?? '').toString();
      final condition = (day['condition'] ?? '—').toString();
      final minC = day['minTempC'];
      final maxC = day['maxTempC'];
      final pop = day['pop'];
      final humidity = day['humidity'];
      final wind = day['windSpeedMs'];

      final minStr = minC is num ? '${minC.toStringAsFixed(0)}°C' : '—';
      final maxStr = maxC is num ? '${maxC.toStringAsFixed(0)}°C' : '—';
      final popStr = pop is num ? '${(pop * 100).round()}%' : '—';
      final humStr = humidity is num ? '$humidity%' : '—';
      final windStr = wind is num ? '${(wind * 3.6).round()} km/h' : '—';

      buf.writeln(
        '  $date: $condition, High $maxStr / Low $minStr, '
        'Rain chance $popStr, Humidity $humStr, Wind $windStr',
      );
    }
    buf.writeln('[END WEATHER FORECAST]');
    return buf.toString();
  }

  /// Formats a rich project data payload into a readable [PROJECT DATA] block
  /// that Gemini can reference when answering materials, progress, and safety questions.
  static String projectDataBlock(Map<String, dynamic> ctx) {
    final buf = StringBuffer();
    buf.writeln('[PROJECT DATA]');
    buf.writeln('Project: ${ctx['projectName'] ?? 'Unknown'}');
    buf.writeln('ID: ${ctx['projectId'] ?? ''}');
    buf.writeln('Status: ${ctx['projectStatus'] ?? 'unknown'}');
    buf.writeln('Progress: ${ctx['progressPercentage'] ?? 0}%');
    buf.writeln('Location: ${ctx['projectLocation'] ?? ''}');
    buf.writeln('Contract Amount: ${ctx['contractAmount'] ?? 'N/A'}');
    buf.writeln('Start: ${ctx['startDate'] ?? 'N/A'}  End: ${ctx['endDate'] ?? 'N/A'}');
    buf.writeln('Project Manager: ${ctx['projectManager'] ?? 'N/A'}');
    buf.writeln('Site Manager / RE: ${ctx['siteManagerName'] ?? 'N/A'}');

    // Summary stats
    final s = ctx['_summary'] as Map? ?? {};
    buf.writeln();
    buf.writeln('QUICK STATS:');
    buf.writeln('  Materials on record: ${s['totalMaterials'] ?? 0}');
    buf.writeln('  LOW STOCK items: ${s['lowStockItems'] ?? 0}');
    buf.writeln('  Pending material requests: ${s['pendingRequests'] ?? 0}');
    buf.writeln('  Daily reports (recent): ${s['totalDailyReports'] ?? 0}');
    buf.writeln('  Workers present today: ${s['presentWorkersToday'] ?? 0}');
    buf.writeln('  Open issues: ${s['totalIssues'] ?? 0}');

    // Material inventory
    final materials = ctx['materialInventory'] as List? ?? [];
    if (materials.isNotEmpty) {
      buf.writeln();
      buf.writeln('MATERIAL INVENTORY (${materials.length} items):');
      for (final m in materials.take(30)) {
        final name = m['name'] ?? m['itemName'] ?? m['materialName'] ?? 'Item';
        final qty = m['quantity'] ?? m['currentStock'] ?? m['stock'] ?? '—';
        final unit = m['unit'] ?? m['unitOfMeasure'] ?? '';
        final min = m['minimumStock'] ?? m['minStock'] ?? '';
        final status = m['status'] ?? '';
        final minStr = min.toString().isNotEmpty ? ' (min: $min)' : '';
        final statusStr = status.toString().isNotEmpty ? ' [$status]' : '';
        buf.writeln('  - $name: $qty $unit$minStr$statusStr');
      }
    }

    // Material requests
    final requests = ctx['materialRequests'] as List? ?? [];
    if (requests.isNotEmpty) {
      buf.writeln();
      buf.writeln('MATERIAL REQUESTS (${requests.length}):');
      for (final r in requests.take(10)) {
        final item = r['itemName'] ?? r['materialName'] ?? r['name'] ?? '—';
        final qty = r['quantity'] ?? r['requestedQty'] ?? '—';
        final status = r['status'] ?? '—';
        final date = r['createdAt'] ?? r['requestDate'] ?? '';
        buf.writeln('  - $item: $qty | Status: $status | Date: $date');
      }
    }

    // Deliveries
    final deliveries = ctx['deliveries'] as List? ?? [];
    if (deliveries.isNotEmpty) {
      buf.writeln();
      buf.writeln('RECENT DELIVERIES (${deliveries.length}):');
      for (final d in deliveries.take(8)) {
        final item = d['itemName'] ?? d['materialName'] ?? d['name'] ?? '—';
        final qty = d['quantity'] ?? d['deliveredQty'] ?? '—';
        final date = d['deliveryDate'] ?? d['date'] ?? '—';
        final supplier = d['supplier'] ?? d['supplierName'] ?? '';
        final sup = supplier.toString().isNotEmpty ? ' from $supplier' : '';
        buf.writeln('  - $item: $qty$sup | Delivered: $date');
      }
    }

    // Daily reports
    final reports = ctx['recentDailyReports'] as List? ?? [];
    if (reports.isNotEmpty) {
      buf.writeln();
      buf.writeln('RECENT DAILY REPORTS (${reports.length}):');
      for (final r in reports.take(5)) {
        final date = r['date'] ?? '—';
        final status = r['status'] ?? '—';
        final remarks = r['remarks'] ?? '';
        buf.writeln('  Report $date [$status]:');
        final works = r['workAccomplishments'] as List? ?? [];
        for (final w in works.take(4)) {
          final desc = w['description'] ?? w['work'] ?? '';
          final qty = w['quantity'] ?? '';
          final unit = w['unit'] ?? '';
          if (desc.toString().isNotEmpty) {
            buf.writeln('    · $desc ${qty.toString().isNotEmpty ? "$qty $unit" : ""}');
          }
        }
        if (remarks.toString().isNotEmpty) {
          buf.writeln('    Remarks: $remarks');
        }
      }
    }

    // Attendance
    final att = ctx['recentAttendance'] as List? ?? [];
    if (att.isNotEmpty) {
      buf.writeln();
      buf.writeln('RECENT ATTENDANCE (${att.length} records):');
      for (final a in att.take(5)) {
        final date = a['date'] ?? '—';
        final workers = a['workers'] as List? ?? [];
        final present =
            workers.where((w) => (w as Map?)?['status'] == 'present').length;
        buf.writeln('  $date: $present / ${workers.length} workers present');
      }
    }

    // Issues
    final issuesList = ctx['issues'] as List? ?? [];
    if (issuesList.isNotEmpty) {
      buf.writeln();
      buf.writeln('OPEN ISSUES (${issuesList.length}):');
      for (final i in issuesList.take(8)) {
        final title = i['title'] ?? i['description'] ?? i['issue'] ?? '—';
        final severity = i['severity'] ?? i['priority'] ?? '';
        final status = i['status'] ?? '—';
        final sevStr =
            severity.toString().isNotEmpty ? ' [${severity.toString().toUpperCase()}]' : '';
        buf.writeln('  - $title$sevStr | Status: $status');
      }
    }

    // Safety incidents
    final safety = ctx['safetyIncidents'] as List? ?? [];
    if (safety.isNotEmpty) {
      buf.writeln();
      buf.writeln('SAFETY INCIDENTS (${safety.length}):');
      for (final i in safety.take(5)) {
        final desc = i['description'] ?? i['incident'] ?? '—';
        final date = i['date'] ?? i['createdAt'] ?? '—';
        final status = i['status'] ?? '—';
        buf.writeln('  - $desc | $date | $status');
      }
    }

    // Latest ML progress report
    final progress = ctx['latestProgressReport'] as Map? ?? {};
    if (progress.isNotEmpty) {
      final pct = progress['progressPercent'] ?? progress['progressPercentage'];
      final submitted = progress['submittedByName'] ?? '';
      final created = progress['createdAt'] ?? '';
      buf.writeln();
      buf.writeln('LATEST AI PROGRESS REPORT:');
      if (pct != null) buf.writeln('  Overall: $pct%');
      if (submitted.toString().isNotEmpty) {
        buf.writeln('  Submitted by: $submitted on $created');
      }
      final analysis = progress['analysis'] as Map? ?? {};
      if (analysis['labels'] is List) {
        buf.writeln(
            '  Labels: ${(analysis['labels'] as List).take(8).join(', ')}');
      }
    }

    buf.writeln('[END PROJECT DATA]');
    return buf.toString();
  }

  /// Builds the FULL system instruction sent to the Gemini Cloud Function.
  /// Combines the 3-layer scope, live weather, project data, and strict rules.
  static String buildFullSystemInstruction({
    required String projectName,
    required String projectSiteName,
    required Map<String, dynamic> projectContext,
    String weatherBlock = '',
    String forecastBlock = '',
  }) {
    return '''
$buildIqIdentity

You are assisting the Resident Engineer on "$projectName".

PERSONALITY:
- Conversational and direct. Answer like a knowledgeable site supervisor, not a textbook.
- Never say "I cannot find that information in the current project records" unless you truly have no data at all.
- If data is partial, give what you know and say what's missing.
- Keep answers short unless detail is specifically requested.
- When asked about materials, always check [PROJECT DATA] first. If the item appears in inventory, state the quantity. If not found, say "Not in inventory records."
- When asked about progress, use the progress % and latest daily reports.
- When asked about workers/attendance, use the attendance records.
- When asked about weather, use [LIVE SITE DATA INTERFACE] and [WEATHER FORECAST].

$threeLayerScope

$weatherBlock
${forecastBlock.isNotEmpty ? '\n$forecastBlock' : ''}

${projectDataBlock(projectContext)}

$strictWeatherRules

ANSWER RULES:
1. MATERIALS: Check [PROJECT DATA] → MATERIAL INVENTORY. State the quantity and unit. Flag low-stock items. For pending requests, advise verification, approval workflow, and vendor lead time.
2. PROGRESS: Use the progress % + recent daily reports. Be specific about what work was done.
3. WORKERS/ATTENDANCE: Use [PROJECT DATA] → RECENT ATTENDANCE and QUICK STATS.
4. SAFETY: Apply standard construction safety from your knowledge + any issues in [PROJECT DATA]. Always mention PPE when relevant.
5. WEATHER: Use [LIVE SITE DATA INTERFACE] only. Cite source at end.
6. GENERAL CONSTRUCTION: Answer from your expertise (pre-pour checklists, rebar, slump, inspections). Clearly label it as general knowledge when not in project records.
7. VAGUE QUESTIONS: Ask targeted follow-ups (site, materials, weather, labor, inspection) before guessing root cause.
8. OFF-TOPIC: "$offTopicReply"
9. MISSING DATA: Say "Not in current records" — never invent figures.

RESPONSE FORMAT:
- For simple questions: 1–3 sentences max.
- For lists (materials, workers, checklists): one item per line as `- Name: qty unit`. Never mix `*` and `**` on the same line.
- For material inventory: use a clean list, e.g. `- Gravel: 0 cu.m`. Do not dump a wall of asterisks.
- For analysis: lead with the finding, then support it briefly.
- Never add lengthy disclaimers or qualifications unless safety-critical.
''';
  }

  static String fromLiveWeatherMap(Map<String, dynamic> map,
      {String siteName = 'Project Site'}) {
    return liveSiteContextBlock(
      siteName: siteName,
      temperature: (map['temperature'] ?? 'Unavailable').toString(),
      humidity: (map['humidity'] ?? 'Unavailable').toString(),
      environmentLighting:
          (map['environment_lighting'] ?? map['lighting'] ?? 'Unavailable')
              .toString(),
      rainForecast:
          (map['rain_forecast'] ?? map['rain_status'] ?? 'Offline').toString(),
    );
  }

  static String fromProjectWeatherMap(
    Map<String, String> map, {
    required String projectName,
    String siteName = '',
    String forecastBlock = '',
  }) {
    return projectAssistantInstruction(
      projectName: projectName,
      projectSiteName: siteName.isNotEmpty ? siteName : projectName,
      temperature: map['temperature'] ?? 'Unavailable',
      humidity: map['humidity'] ?? 'Unavailable',
      operationalVisibility: map['lighting'] ?? 'Unavailable',
      rainForecastStatus: map['rain_status'] ?? 'Offline',
      forecastBlock: forecastBlock,
    );
  }
}
