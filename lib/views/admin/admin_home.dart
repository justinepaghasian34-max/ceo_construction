import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/hive_service.dart';
import '../../services/firebase_service.dart';
import '../../services/archive_service.dart';
import '../../services/weather_service.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/motion_widgets.dart';
import '../../widgets/common/storage_network_image.dart';
import 'widgets/admin_bottom_nav.dart';
import 'widgets/admin_glass_layout.dart';

String _formatPeso(double value) {
  if (value <= 0) return '—';
  final digits = value.round().toString();
  final buffer = StringBuffer();
  var count = 0;
  for (var i = digits.length - 1; i >= 0; i--) {
    buffer.write(digits[i]);
    count++;
    if (count == 3 && i != 0) {
      buffer.write(',');
      count = 0;
    }
  }
  return '${AppConstants.currencySymbol}${buffer.toString().split('').reversed.join()}';
}

String _prettyName(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return value;
  return value.split(RegExp(r'\s+')).map((word) {
    if (word.isEmpty) return word;
    if (word.length <= 4) return word.toUpperCase();
    return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
  }).join(' ');
}

String _prettyStatus(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '—';
  return _prettyName(value);
}

Future<({WeatherNow weather, String site})?> _loadPinnedSiteWeather() async {
  final snap = await FirebaseService.instance.projectsCollection.get();
  WeatherNow? worst;
  var site = '';
  var worstRank = -1;

  int rank(WeatherNow weather) {
    final condition = weather.condition.toLowerCase();
    if (condition.contains('thunder') || condition.contains('storm')) return 3;
    if (condition.contains('rain') || condition.contains('drizzle')) return 2;
    return 0;
  }

  for (final doc in snap.docs) {
    final data = (doc.data() as Map?)?.cast<String, dynamic>() ?? {};
    if (ArchiveService.isArchived(data)) continue;
    final lat = (data['latitude'] as num?)?.toDouble();
    final lon = (data['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
      continue;
    }
    try {
      final weather = await WeatherService.instance.getCurrentWeatherByCoordinates(
        lat: lat,
        lon: lon,
      );
      final name = (data['name'] ?? data['geoAddress'] ?? 'Project').toString();
      final score = rank(weather);
      if (worst == null || score > worstRank) {
        worst = weather;
        worstRank = score;
        site = name;
      }
    } catch (_) {}
  }

  if (worst == null) return null;
  return (weather: worst, site: site);
}

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    final hive = HiveService.instance;

    return AdminGlassScaffold(
      title: 'Executive Dashboard',
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none),
          onPressed: () => context.push(RouteNames.notifications),
        ),
        IconButton(
          icon: const Icon(Icons.fact_check_outlined),
          onPressed: () => context.push(RouteNames.adminAuditTrail),
        ),
        IconButton(
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.push(RouteNames.profile),
        ),
      ],
      bottomNavigationBar: const AdminBottomNavBar(
        current: AdminNavItem.dashboard,
      ),
      child: StaggerColumn(
        interval: const Duration(milliseconds: 150),
        itemDuration: const Duration(milliseconds: 820),
        children: [
          _buildSmartInsightCard(context),
          const SizedBox(height: 14),
          _buildKpiRow(context, hive),
          const SizedBox(height: 14),
          _buildSiteWeatherMapCard(context),
          const SizedBox(height: 14),
          _buildProjectActivityCard(context),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSmartInsightCard(BuildContext context) {
    return const SmartInsightCard(
      title: 'Smart Insight',
      message:
          'Based on current SPI of 1.05, Project Alpha will complete 4 days ahead.\nReallocate 2 idle team members to Project Beta?',
    );
  }

  Widget _buildKpiRow(BuildContext context, HiveService hive) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 1000;
        const kpiHeight = 172.0;

        final List<Widget> cards = [
          _KpiCard(
            title: 'Net Margin',
            value: '18.2%',
            accent: const Color(0xFF2DD4BF),
            icon: Icons.trending_up_rounded,
            onTap: () => context.push(RouteNames.adminFinancialMonitoring),
          ),
          _KpiCard(
            title: 'Cost Performance Index (CPI)',
            value: '1.10',
            badgeText: 'On Track',
            badgeColor: const Color(0xFF22C55E),
            accent: const Color(0xFF22C55E),
            icon: Icons.account_balance_wallet_outlined,
            onTap: () => context.push(RouteNames.adminFinancialMonitoring),
          ),
          _KpiCard(
            title: 'Schedule Performance Index (SPI)',
            value: '0.05',
            accent: const Color(0xFFF97316),
            icon: Icons.schedule_rounded,
            onTap: () => context.push(RouteNames.adminProgressReports),
          ),
        ];

        Widget wrapKpiCard(Widget child) {
          return SizedBox(height: kpiHeight, child: child);
        }

        final weatherCard = wrapKpiCard(_buildWeatherRiskCard(context, hive));

        if (isNarrow) {
          return Column(
            children: [
              ...cards.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: wrapKpiCard(c),
                ),
              ),
              weatherCard,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: wrapKpiCard(cards[0])),
            const SizedBox(width: 12),
            Expanded(child: wrapKpiCard(cards[1])),
            const SizedBox(width: 12),
            Expanded(child: wrapKpiCard(cards[2])),
            const SizedBox(width: 12),
            Expanded(child: weatherCard),
          ],
        );
      },
    );
  }

  Widget _buildWeatherRiskCard(BuildContext context, HiveService hive) {
    const borderRadius = 16.0;
    final card = GlassCard(
      borderRadius: borderRadius,
      padding: const EdgeInsets.all(14),
      child: FutureBuilder<({WeatherNow weather, String site})?>(
        future: _loadPinnedSiteWeather(),
        builder: (context, snapshot) {
          final waiting = snapshot.connectionState == ConnectionState.waiting;
          final weather = snapshot.data?.weather;
          final site = snapshot.data?.site ?? '';
          final failed = !waiting && (snapshot.hasError || weather == null);
          final temp = weather?.temperatureC;
          final condition = (weather?.condition ?? '').toLowerCase();
          final raining = condition.contains('rain') ||
              condition.contains('drizzle') ||
              condition.contains('thunder') ||
              condition.contains('storm');

          late final int workHours;
          late final String riskLabel;
          late final Color barColor;
          if (waiting) {
            workHours = 0;
            riskLabel = 'Loading…';
            barColor = const Color(0xFF2DD4BF);
          } else if (failed || temp == null) {
            workHours = 0;
            riskLabel = 'Pin the project site first';
            barColor = AppTheme.mediumGray;
          } else if (raining) {
            workHours = condition.contains('thunder') ? 3 : 4;
            riskLabel = condition.contains('thunder')
                ? 'High storm risk'
                : 'Rain risk';
            barColor = const Color(0xFFF97316);
          } else if (temp >= 33) {
            workHours = 6;
            riskLabel = 'Heat risk';
            barColor = const Color(0xFFF97316);
          } else if (temp <= 26) {
            workHours = 9;
            riskLabel = 'Low weather risk';
            barColor = const Color(0xFF2DD4BF);
          } else if (temp <= 30) {
            workHours = 8;
            riskLabel = 'Low weather risk';
            barColor = const Color(0xFF2DD4BF);
          } else {
            workHours = 7;
            riskLabel = 'Moderate heat';
            barColor = const Color(0xFFFACC15);
          }

          final icon = raining
              ? Icons.thunderstorm_outlined
              : Icons.wb_sunny_outlined;
          final tempLabel = waiting
              ? '…'
              : (temp == null ? '—' : '${temp.toStringAsFixed(0)}°C');
          final detail = weather?.description.trim();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weather Risk',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    icon,
                    color: Colors.black.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tempLabel,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                detail != null && detail.isNotEmpty
                    ? '$riskLabel · $detail${site.isNotEmpty ? ' · $site' : ''}'
                    : (site.isNotEmpty ? '$riskLabel · $site' : riskLabel),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                failed ? 'Tap to open forecast' : 'Workable Hours: $workHours / 10',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: waiting ? null : (workHours / 10).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Colors.black.withValues(alpha: 0.06),
                  color: barColor,
                ),
              ),
            ],
          );
        },
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(RouteNames.adminWeatherForecast),
          borderRadius: BorderRadius.circular(borderRadius),
          child: card,
        ),
      ),
    );
  }

  Widget _buildSiteWeatherMapCard(BuildContext context) {
    const borderRadius = 16.0;

    final card = GlassCard(
      borderRadius: borderRadius,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.thunderstorm_outlined,
                    size: 18, color: Color(0xFF3B82F6)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Site Weather Map',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.softGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Live',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.softGreen,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'View live weather conditions at all project sites on an '
            'interactive map. Rain alerts are sent automatically.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.mediumGray,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _WeatherConditionDot(
                  color: AppTheme.warningOrange, label: 'Sunny'),
              const SizedBox(width: 12),
              _WeatherConditionDot(
                  color: AppTheme.mediumGray, label: 'Cloudy'),
              const SizedBox(width: 12),
              _WeatherConditionDot(
                  color: const Color(0xFF3B82F6), label: 'Raining'),
              const Spacer(),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: AppTheme.mediumGray.withValues(alpha: 0.5),
              ),
            ],
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(RouteNames.adminSiteWeatherMap),
          borderRadius: BorderRadius.circular(borderRadius),
          child: card,
        ),
      ),
    );
  }

  Widget _buildProjectActivityCard(BuildContext context) {
    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: _buildActivityProjectSummaryCard(context),
    );
  }

  Future<List<Map<String, dynamic>>> _loadProjectActivitySummary() async {
    final firebase = FirebaseService.instance;

    final projectsSnap = await firebase.projectsCollection.get();
    final disbursementsSnap = await firebase.disbursementsCollection.get();

    final Map<String, double> expensesByProject = {};
    for (final doc in disbursementsSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final projectId = (data['projectId'] ?? '').toString();
      if (projectId.isEmpty) continue;
      final rawAmount = data['amount'];
      double amount;
      if (rawAmount is num) {
        amount = rawAmount.toDouble();
      } else if (rawAmount is String) {
        final cleaned =
            rawAmount.replaceAll(',', '').replaceAll('₱', '').trim();
        amount = double.tryParse(cleaned) ?? 0.0;
      } else {
        amount = 0.0;
      }
      expensesByProject[projectId] =
          (expensesByProject[projectId] ?? 0) + amount;
    }

    final coverByProjectId = <String, String>{};
    final coverByProjectName = <String, String>{};
    final latestAt = <String, DateTime>{};
    try {
      final reportsSnap = await firebase.aiAnalysisCollection
          .where(
            'kind',
            whereIn: const <String>[
              'govtrack_progress_report',
              'govtrack_image_progress_submit',
            ],
          )
          .get();
      for (final report in reportsSnap.docs) {
        final reportData = (report.data() as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        final images = ProgressReportImages.extract(reportData);
        if (images.isEmpty) continue;
        final projectId = (reportData['projectId'] ?? '').toString();
        final projectName = (reportData['projectName'] ?? '').toString();
        DateTime created = DateTime.fromMillisecondsSinceEpoch(0);
        final rawCreated = reportData['createdAt'];
        if (rawCreated is Timestamp) created = rawCreated.toDate();
        if (rawCreated is DateTime) created = rawCreated;
        if (projectId.isNotEmpty) {
          final prev = latestAt[projectId];
          if (prev == null || created.isAfter(prev)) {
            latestAt[projectId] = created;
            coverByProjectId[projectId] = images.first;
          }
        }
        if (projectName.isNotEmpty) {
          final key = 'name:$projectName';
          final prev = latestAt[key];
          if (prev == null || created.isAfter(prev)) {
            latestAt[key] = created;
            coverByProjectName[projectName] = images.first;
          }
        }
      }
    } catch (_) {}

    final List<Map<String, dynamic>> summaries = [];
    for (final doc in projectsSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (ArchiveService.isArchived(data)) continue;
      final projectId = doc.id;

      final name = (data['name'] ?? 'Untitled').toString();
      final status = (data['status'] ?? 'unknown').toString();
      final siteManagerName = (data['siteManagerName'] ?? '').toString();
      final progressRaw = data['progressPercentage'];
      final double progress;
      if (progressRaw is num) {
        progress = progressRaw.toDouble();
      } else if (progressRaw is String) {
        final cleaned = progressRaw.replaceAll('%', '').trim();
        progress = double.tryParse(cleaned) ?? 0.0;
      } else {
        progress = 0.0;
      }

      final budgetRaw = data['contractAmount'] ?? data['approvedBudget'];
      final double budget;
      if (budgetRaw is num) {
        budget = budgetRaw.toDouble();
      } else if (budgetRaw is String) {
        final cleaned =
            budgetRaw.replaceAll(',', '').replaceAll('₱', '').trim();
        budget = double.tryParse(cleaned) ?? 0.0;
      } else {
        budget = 0.0;
      }
      final expenses = expensesByProject[projectId] ?? 0.0;

      summaries.add({
        'id': projectId,
        'name': name,
        'status': status,
        'progress': progress,
        'budget': budget,
        'expenses': expenses,
        'siteManagerName': siteManagerName,
        'coverImage': coverByProjectId[projectId] ??
            coverByProjectName[name] ??
            '',
      });
    }

    return summaries;
  }

  Widget _buildActivityProjectSummaryCard(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadProjectActivitySummary(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Row(
            children: [
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Loading activity project summary…',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          );
        }

        if (snapshot.hasError) {
          return AppCard(
            child: Text(
              'Failed to load activity project summary.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.errorRed),
            ),
          );
        }

        final summaries = snapshot.data ?? const <Map<String, dynamic>>[];
        if (summaries.isEmpty) {
          return AppCard(
            child: Text(
              'No projects found yet.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.mediumGray),
            ),
          );
        }

        final visible = summaries.take(5).toList();
        final remaining = summaries.length - visible.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Project Activity Summary',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Progress, spend, and health for each active site',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.mediumGray,
                            ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      _showFullProjectActivityTable(context, summaries),
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final item in visible)
              _ProjectActivityRowCard(item: item),
            if (remaining > 0)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Showing ${visible.length} of ${summaries.length} projects',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mediumGray,
                      ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showFullProjectActivityTable(
    BuildContext context,
    List<Map<String, dynamic>> summaries,
  ) {
    final size = MediaQuery.of(context).size;
    final width = math.min(size.width * 0.92, 920.0);
    final height = math.min(size.height * 0.88, 860.0);

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close all projects activity',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      pageBuilder: (dialogContext, _, __) {
        return Center(
          child: Material(
            color: Colors.white,
            elevation: 18,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              height: height,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.apartment_rounded,
                            color: AppTheme.deepBlue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'All projects activity',
                            style: Theme.of(dialogContext)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      itemCount: summaries.length,
                      itemBuilder: (context, index) {
                        return _ProjectActivityRowCard(
                          item: summaries[index],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}


class _ProjectActivityRowCard extends StatelessWidget {
  const _ProjectActivityRowCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final name = _prettyName((item['name'] ?? 'Untitled').toString());
    final engineerRaw = (item['siteManagerName'] ?? '').toString().trim();
    final engineer =
        engineerRaw.isEmpty ? 'Unassigned' : _prettyName(engineerRaw);
    final status = _prettyStatus((item['status'] ?? '').toString());
    final progress = (item['progress'] is num)
        ? (item['progress'] as num).toDouble()
        : 0.0;
    final budget = (item['budget'] is num)
        ? (item['budget'] as num).toDouble()
        : 0.0;
    final expenses = (item['expenses'] is num)
        ? (item['expenses'] as num).toDouble()
        : 0.0;
    final cover = (item['coverImage'] ?? '').toString();

    final statusLower = status.toLowerCase();
    final Color statusColor;
    if (statusLower == 'ongoing') {
      statusColor = AppTheme.softGreen;
    } else if (statusLower == 'completed') {
      statusColor = AppTheme.primaryBlue;
    } else if (statusLower == 'pending') {
      statusColor = AppTheme.warningOrange;
    } else {
      statusColor = AppTheme.mediumGray;
    }

    final spentRatio = budget <= 0 ? 0.0 : (expenses / budget).clamp(0.0, 1.0);
    final spentPercent =
        budget <= 0 ? 0.0 : ((expenses / budget) * 100).clamp(0.0, 999.0);

    late final String healthLabel;
    late final Color healthColor;
    if (budget <= 0 && expenses <= 0) {
      healthLabel = 'No data';
      healthColor = AppTheme.mediumGray;
    } else if (budget > 0 && expenses / budget > 1.0) {
      healthLabel = 'Over budget';
      healthColor = AppTheme.errorRed;
    } else if (budget > 0 && expenses / budget > 0.7) {
      healthLabel = 'Watch';
      healthColor = AppTheme.warningOrange;
    } else {
      healthLabel = 'Healthy';
      healthColor = AppTheme.softGreen;
    }

    final progressColor = progress <= 0
        ? AppTheme.mediumGray
        : progress < 50
            ? AppTheme.deepBlue
            : AppTheme.softGreen;
    final spendColor = budget <= 0
        ? AppTheme.mediumGray
        : expenses / budget > 1
            ? AppTheme.errorRed
            : expenses / budget > 0.7
                ? AppTheme.warningOrange
                : AppTheme.softGreen;

    Widget chip(String label, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
        ),
      );
    }

    Widget metric({
      required String label,
      required Widget child,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.mediumGray,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProjectCoverThumb(source: cover, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.engineering_outlined,
                          size: 14,
                          color: AppTheme.mediumGray,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            engineer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.mediumGray,
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        chip(status, statusColor),
                        chip(healthLabel, healthColor),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 560;
              final progressMetric = metric(
                label: 'Progress',
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: (progress / 100).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: Colors.black.withValues(alpha: 0.06),
                          color: progressColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${progress.clamp(0, 999).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                    ),
                  ],
                ),
              );
              final budgetMetric = metric(
                label: 'Budget',
                child: Text(
                  _formatPeso(budget),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                ),
              );
              final spendMetric = metric(
                label: 'Spent',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      budget <= 0
                          ? _formatPeso(expenses)
                          : '${_formatPeso(expenses)}  ·  ${spentPercent.toStringAsFixed(0)}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: spendColor,
                          ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: spentRatio,
                        minHeight: 6,
                        backgroundColor: Colors.black.withValues(alpha: 0.06),
                        color: spendColor,
                      ),
                    ),
                  ],
                ),
              );

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    progressMetric,
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: budgetMetric),
                        const SizedBox(width: 16),
                        Expanded(child: spendMetric),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: progressMetric),
                  const SizedBox(width: 16),
                  Expanded(child: budgetMetric),
                  const SizedBox(width: 16),
                  Expanded(child: spendMetric),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.accent,
    required this.icon,
    this.badgeText,
    this.badgeColor,
    this.onTap,
  });

  final String title;
  final String value;
  final Color accent;
  final IconData icon;
  final String? badgeText;
  final Color? badgeColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const borderRadius = 16.0;
    final card = GlassCard(
      borderRadius: borderRadius,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const Spacer(),
              if (badgeText != null && badgeText!.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? accent).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badgeText!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: badgeColor ?? accent,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.mediumGray,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: 0.72,
              minHeight: 4,
              backgroundColor: accent.withValues(alpha: 0.12),
              color: accent,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: card,
        ),
      ),
    );
  }
}

class _HorizontalProjectStrip extends StatefulWidget {
  const _HorizontalProjectStrip({required this.summaries});

  final List<Map<String, dynamic>> summaries;

  @override
  State<_HorizontalProjectStrip> createState() =>
      _HorizontalProjectStripState();
}

class _HorizontalProjectStripState extends State<_HorizontalProjectStrip> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final next = _scroll.offset + event.scrollDelta.dy + event.scrollDelta.dx;
    _scroll.jumpTo(
      next.clamp(0.0, _scroll.position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = math.min(
          constraints.maxHeight - 36,
          math.max(420.0, constraints.maxWidth * 0.42),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.summaries.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  'Scroll left or right to see every site',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mediumGray,
                      ),
                ),
              ),
            Expanded(
              child: Listener(
                onPointerSignal: _onPointerSignal,
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.summaries.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      return _ProjectActivityTile(
                        item: widget.summaries[index],
                        size: tileSize,
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProjectCoverThumb extends StatelessWidget {
  const _ProjectCoverThumb({required this.source, this.size = 48});

  final String source;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size,
        height: size,
        child: source.trim().isEmpty
            ? ColoredBox(
                color: AppTheme.lightGray,
                child: Icon(
                  Icons.apartment_outlined,
                  size: size * 0.42,
                  color: AppTheme.mediumGray,
                ),
              )
            : StorageNetworkImage(source: source, fit: BoxFit.cover),
      ),
    );
  }
}

class _ProjectActivityTile extends StatelessWidget {
  const _ProjectActivityTile({
    required this.item,
    this.size = 260,
  });

  final Map<String, dynamic> item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final name = (item['name'] ?? 'Untitled').toString();
    final siteManagerName = (item['siteManagerName'] ?? '').toString();
    final status = (item['status'] ?? '').toString();
    final progress = (item['progress'] is num)
        ? (item['progress'] as num).toDouble()
        : 0.0;
    final budget = (item['budget'] is num)
        ? (item['budget'] as num).toDouble()
        : 0.0;
    final expenses = (item['expenses'] is num)
        ? (item['expenses'] as num).toDouble()
        : 0.0;
    final cover = (item['coverImage'] ?? '').toString();
    final formattedStatus = status.isEmpty
        ? '—'
        : status[0].toUpperCase() + status.substring(1);

    return Material(
      elevation: 5,
      shadowColor: Colors.black26,
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: cover.isEmpty
                  ? ColoredBox(
                      color: AppTheme.lightGray,
                      child: Icon(
                        Icons.apartment_outlined,
                        size: 42,
                        color: AppTheme.mediumGray,
                      ),
                    )
                  : StorageNetworkImage(source: cover, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _prettyName(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    siteManagerName.isEmpty
                        ? 'Unassigned'
                        : _prettyName(siteManagerName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.mediumGray,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.softGreen.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          formattedStatus,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.softGreen,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${progress.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    budget <= 0
                        ? 'Budget: —'
                        : 'Budget: ${_formatPeso(budget)}  ·  Expense: ${_formatPeso(expenses)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.mediumGray,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherConditionDot extends StatelessWidget {
  const _WeatherConditionDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTheme.mediumGray,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
