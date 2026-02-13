import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../services/hive_service.dart';
import '../../widgets/common/app_card.dart';
import '../../models/daily_report_model.dart';
import '../../models/attendance_model.dart';
import '../../services/sync_service.dart';
import '../../core/constants/app_constants.dart';

class CeoAnalytics extends StatelessWidget {
  const CeoAnalytics({super.key});

  @override
  Widget build(BuildContext context) {
    final hive = HiveService.instance;
    final storageStats = hive.storageStats;
    final reports = hive.getAllDailyReports();
    final attendance = hive.getAllAttendance();
    final materialUsage = hive.getAllMaterialUsage();
    final deliveries = hive.getAllDeliveries();
    final syncQueueItems = hive.getAllSyncQueueItems();
    final syncStats = SyncService.instance.getSyncStats();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Executive Analytics',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Executive analytics',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Deeper trends across reports, attendance, materials, and system health.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.mediumGray,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StatsCard(
                  title: 'Total Offline Records',
                  value: (hive.totalDailyReports + hive.totalAttendanceRecords + hive.totalMaterialUsageRecords + hive.totalDeliveryRecords).toString(),
                  icon: Icons.storage,
                  iconColor: AppTheme.deepBlue,
                  subtitle: 'Data stored on device',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatsCard(
                  title: 'Pending Sync Items',
                  value: hive.pendingSyncItemsCount.toString(),
                  icon: Icons.sync_problem,
                  iconColor: AppTheme.warningOrange,
                  subtitle: 'Risk of data delay',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Data Footprint',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                ...storageStats.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key),
                        Text(entry.value.toString()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Daily Reports Analytics',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          if (reports.isEmpty)
            AppCard(
              child: Text(
                'No daily reports available yet. Analytics will appear after reports are created.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            )
          else ...[
            _buildDailySummaryCard(context, reports),
            const SizedBox(height: 16),
            _buildDailyAccomplishmentChart(context, reports),
            const SizedBox(height: 16),
            _buildQuantityCompletedChart(context, reports),
            const SizedBox(height: 16),
            _buildIssueStatsChart(context, reports),
            const SizedBox(height: 16),
            _buildWeatherImpactChart(context, reports),
            const SizedBox(height: 16),
            _buildAiSummaryCard(context, reports),
          ],
          const SizedBox(height: 24),
          Text(
            'Attendance Analytics',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          if (attendance.isEmpty)
            AppCard(
              child: Text(
                'No attendance records yet. Analytics will appear after attendance is recorded.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            )
          else ...[
            _buildAttendanceSummaryCard(context, attendance),
            const SizedBox(height: 16),
            _buildAttendanceRateChart(context, attendance),
          ],
          const SizedBox(height: 24),
          Text(
            'Material Usage Analytics',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          if (materialUsage.isEmpty)
            AppCard(
              child: Text(
                'No material usage records yet. Analytics will appear after material usage is recorded.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            )
          else ...[
            _buildMaterialUsageSummaryCard(context, materialUsage),
            const SizedBox(height: 16),
            _buildMaterialUsageByMaterialChart(context, materialUsage),
          ],
          const SizedBox(height: 24),
          Text(
            'Material Deliveries Analytics',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          if (deliveries.isEmpty)
            AppCard(
              child: Text(
                'No delivery records yet. Analytics will appear after deliveries are recorded.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            )
          else ...[
            _buildDeliveriesSummaryCard(context, deliveries),
            const SizedBox(height: 16),
            _buildDeliveriesBySupplierChart(context, deliveries),
          ],
          const SizedBox(height: 24),
          Text(
            'Sync Queue Analytics',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          if (syncQueueItems.isEmpty)
            AppCard(
              child: Text(
                'No items in sync queue. All background tasks are up to date.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            )
          else ...[
            _buildSyncQueueSummaryCard(context, syncQueueItems),
            const SizedBox(height: 16),
            _buildSyncQueueStatusChart(context, syncQueueItems),
          ],
          const SizedBox(height: 24),
          Text(
            'System Health Analytics',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          _buildSystemHealthCard(context, storageStats, syncStats),
        ],
      ),
    );
  }

  Widget _buildDailySummaryCard(BuildContext context, List<DailyReportModel> reports) {
    final totalReports = reports.length;
    final totalIssues = reports.fold<int>(0, (prev, r) => prev + r.issues.length);
    final avgAccomplishments = reports.isEmpty
        ? 0.0
        : reports
                .map((r) => r.workAccomplishments.fold<double>(0, (sum, w) => sum + w.quantityAccomplished))
                .fold<double>(0, (sum, value) => sum + value) /
            totalReports;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Daily Reports',
              value: totalReports.toString(),
              icon: Icons.description,
              iconColor: AppTheme.deepBlue,
              subtitle: 'Total in device',
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Total Issues',
              value: totalIssues.toString(),
              icon: Icons.warning_amber_rounded,
              iconColor: AppTheme.warningOrange,
              subtitle: 'Across all reports',
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Avg. Quantity',
              value: avgAccomplishments.toStringAsFixed(1),
              icon: Icons.trending_up,
              iconColor: AppTheme.softGreen,
              subtitle: 'Per report',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyAccomplishmentChart(BuildContext context, List<DailyReportModel> reports) {
    final Map<DateTime, double> quantityByDate = {};
    final Map<DateTime, double> issuesByDate = {};
    final Map<DateTime, double> tempSumByDate = {};
    final Map<DateTime, int> tempCountByDate = {};

    for (final r in reports) {
      final day = DateTime(r.reportDate.year, r.reportDate.month, r.reportDate.day);

      final qty = r.workAccomplishments
          .fold<double>(0, (sum, w) => sum + w.quantityAccomplished);
      quantityByDate[day] = (quantityByDate[day] ?? 0) + qty;

      issuesByDate[day] = (issuesByDate[day] ?? 0) + r.issues.length.toDouble();

      tempSumByDate[day] = (tempSumByDate[day] ?? 0) + r.temperatureC;
      tempCountByDate[day] = (tempCountByDate[day] ?? 0) + 1;
    }

    final dates = <DateTime>{}
      ..addAll(quantityByDate.keys)
      ..addAll(issuesByDate.keys)
      ..addAll(tempSumByDate.keys);

    final sortedDates = dates.toList()
      ..sort((a, b) => a.compareTo(b));

    final labels = sortedDates
        .map((e) => '${e.month}/${e.day}')
        .toList();

    final spotsQuantity = <FlSpot>[];
    final spotsIssues = <FlSpot>[];
    final spotsTemp = <FlSpot>[];

    for (var i = 0; i < sortedDates.length; i++) {
      final day = sortedDates[i];
      final double qty = quantityByDate[day] ?? 0.0;
      final double issues = issuesByDate[day] ?? 0.0;
      final double tempAvg = tempSumByDate.containsKey(day)
          ? (tempSumByDate[day]! / (tempCountByDate[day] ?? 1).toDouble())
          : 0.0;

      spotsQuantity.add(FlSpot(i.toDouble(), qty));
      spotsIssues.add(FlSpot(i.toDouble(), issues));
      spotsTemp.add(FlSpot(i.toDouble(), tempAvg));
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily Accomplishment',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildLineLegendDot(AppTheme.deepBlue),
              const SizedBox(width: 4),
              Text('Quantity', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 12),
              _buildLineLegendDot(AppTheme.warningOrange),
              const SizedBox(width: 4),
              Text('Issues', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 12),
              _buildLineLegendDot(Colors.purpleAccent),
              const SizedBox(width: 4),
              Text('Avg Temp', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.deepBlue,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
            child: SizedBox(
              height: 220,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: value,
                        child: child,
                      ),
                    ),
                  );
                },
                child: LineChart(
                  LineChartData(
                    minY: 0.0,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: spotsQuantity.isEmpty ? 1.0 : null,
                      getDrawingHorizontalLine: (v) => FlLine(
                        color: Colors.white.withAlpha(30),
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) => Text(
                            value.toStringAsFixed(0),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontSize: 10,
                                  color: Colors.white70,
                                ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= labels.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                labels[index],
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontSize: 10,
                                      color: Colors.white70,
                                    ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spotsQuantity,
                        isCurved: true,
                        color: Colors.cyanAccent,
                        barWidth: 3,
                        dotData: FlDotData(show: false),
                      ),
                      LineChartBarData(
                        spots: spotsIssues,
                        isCurved: true,
                        color: Colors.amberAccent,
                        barWidth: 2,
                        dotData: FlDotData(show: false),
                      ),
                      LineChartBarData(
                        spots: spotsTemp,
                        isCurved: true,
                        color: Colors.purpleAccent,
                        barWidth: 2,
                        dotData: FlDotData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityCompletedChart(BuildContext context, List<DailyReportModel> reports) {
    final Map<String, double> byDescription = {};
    for (final r in reports) {
      for (final w in r.workAccomplishments) {
        byDescription[w.description] =
            (byDescription[w.description] ?? 0) + w.quantityAccomplished;
      }
    }

    final entries = byDescription.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topEntries = entries.take(5).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quantity Completed (Top 5 Activities)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= topEntries.length) {
                          return const SizedBox.shrink();
                        }
                        final label = topEntries[index].key;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            label.length > 8 ? '${label.substring(0, 8)}…' : label,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < topEntries.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: topEntries[i].value,
                          color: AppTheme.softGreen,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIssueStatsChart(BuildContext context, List<DailyReportModel> reports) {
    int safety = 0;
    int quality = 0;
    int delay = 0;
    int other = 0;

    for (final r in reports) {
      for (final issue in r.issues) {
        final text = issue.toLowerCase();
        if (text.contains('safety')) {
          safety++;
        } else if (text.contains('quality')) {
          quality++;
        } else if (text.contains('delay')) {
          delay++;
        } else {
          other++;
        }
      }
    }

    final total = safety + quality + delay + other;
    if (total == 0) {
      return AppCard(
        child: Text(
          'No issues recorded in daily reports.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.mediumGray,
              ),
        ),
      );
    }

    final sections = <PieChartSectionData>[
      if (safety > 0)
        PieChartSectionData(
          value: safety.toDouble(),
          title: 'Safety',
          color: AppTheme.errorRed,
          radius: 40,
          titleStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
        ),
      if (quality > 0)
        PieChartSectionData(
          value: quality.toDouble(),
          title: 'Quality',
          color: AppTheme.deepBlue,
          radius: 40,
          titleStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
        ),
      if (delay > 0)
        PieChartSectionData(
          value: delay.toDouble(),
          title: 'Delay',
          color: AppTheme.warningOrange,
          radius: 40,
          titleStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
        ),
      if (other > 0)
        PieChartSectionData(
          value: other.toDouble(),
          title: 'Other',
          color: AppTheme.mediumGray,
          radius: 40,
          titleStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
        ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Issue Types',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: sections,
                sectionsSpace: 2,
                centerSpaceRadius: 40,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _buildLegendItem(context, 'Safety', AppTheme.errorRed, safety),
              _buildLegendItem(context, 'Quality', AppTheme.deepBlue, quality),
              _buildLegendItem(context, 'Delay', AppTheme.warningOrange, delay),
              _buildLegendItem(context, 'Other', AppTheme.mediumGray, other),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherImpactChart(BuildContext context, List<DailyReportModel> reports) {
    final Map<DateTime, double> accomplishmentByDate = {};
    final Map<DateTime, double> weatherByDate = {};

    for (final r in reports) {
      final day = DateTime(r.reportDate.year, r.reportDate.month, r.reportDate.day);
      final accomplished = r.workAccomplishments
          .fold<double>(0, (sum, w) => sum + w.quantityAccomplished);
      accomplishmentByDate[day] = (accomplishmentByDate[day] ?? 0) + accomplished;

      final score = _weatherScore(r.weatherCondition);
      weatherByDate[day] = (weatherByDate[day] ?? 0) + score;
    }

    final dates = accomplishmentByDate.keys.toSet()..addAll(weatherByDate.keys);
    final sortedDates = dates.toList()..sort((a, b) => a.compareTo(b));

    final spotsAccomplishment = <FlSpot>[];
    final spotsWeather = <FlSpot>[];
    final labels = <String>[];

    for (var i = 0; i < sortedDates.length; i++) {
      final day = sortedDates[i];
      labels.add('${day.month}/${day.day}');
      spotsAccomplishment.add(
        FlSpot(i.toDouble(), accomplishmentByDate[day] ?? 0),
      );
      spotsWeather.add(
        FlSpot(i.toDouble(), weatherByDate[day] ?? 0),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weather vs Productivity',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(0),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            labels[index],
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spotsAccomplishment,
                    isCurved: true,
                    color: AppTheme.deepBlue,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: spotsWeather,
                    isCurved: true,
                    color: AppTheme.softGreen,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildLineLegendDot(AppTheme.deepBlue),
              const SizedBox(width: 4),
              Text('Accomplishment', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 12),
              _buildLineLegendDot(AppTheme.softGreen),
              const SizedBox(width: 4),
              Text('Weather score', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceSummaryCard(
      BuildContext context, List<AttendanceModel> attendance) {
    final totalDays = attendance.length;
    final totalPresent =
        attendance.fold<int>(0, (sum, a) => sum + a.presentWorkers);
    final avgRate = attendance.isEmpty
        ? 0.0
        : attendance
                .map((a) => a.attendanceRate)
                .fold<double>(0.0, (sum, r) => sum + r) /
            attendance.length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Attendance Days',
              value: totalDays.toString(),
              icon: Icons.calendar_today,
              iconColor: AppTheme.deepBlue,
              subtitle: 'Records in device',
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Present Workers',
              value: totalPresent.toString(),
              icon: Icons.groups,
              iconColor: AppTheme.softGreen,
              subtitle: 'Across all days',
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Avg. Attendance',
              value: '${avgRate.toStringAsFixed(0)}%',
              icon: Icons.pie_chart_outline,
              iconColor: AppTheme.warningOrange,
              subtitle: 'Average rate',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceRateChart(
      BuildContext context, List<AttendanceModel> attendance) {
    int totalPresent = 0;
    int totalAbsent = 0;
    for (final a in attendance) {
      totalPresent += a.presentWorkers;
      totalAbsent += a.absentWorkers;
    }

    final total = totalPresent + totalAbsent;
    if (total == 0) {
      return AppCard(
        child: Text(
          'No worker attendance recorded yet.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.mediumGray,
              ),
        ),
      );
    }

    final sections = [
      PieChartSectionData(
        value: totalPresent.toDouble(),
        color: AppTheme.softGreen,
        title: 'Present',
        radius: 40,
        titleStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
      PieChartSectionData(
        value: totalAbsent.toDouble(),
        color: AppTheme.errorRed,
        title: 'Absent',
        radius: 40,
        titleStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
    ];

    final rate = totalPresent / total * 100;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance Rate',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: 0.9 + 0.1 * value,
                    child: child,
                  ),
                );
              },
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sections: sections,
                        sectionsSpace: 2,
                        centerSpaceRadius: 36,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${rate.toStringAsFixed(0)}%',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.softGreen,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Average attendance',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: AppTheme.mediumGray,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialUsageSummaryCard(
      BuildContext context, List<Map<String, dynamic>> usages) {
    final totalRecords = usages.length;
    final totalQuantity = usages.fold<double>(
      0.0,
      (sum, u) => sum + (u['quantity'] ?? 0).toDouble(),
    );
    final distinctMaterials = usages
        .map((u) => (u['materialName'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toSet()
        .length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Usage Records',
              value: totalRecords.toString(),
              icon: Icons.inventory_2,
              iconColor: AppTheme.warningOrange,
              subtitle: 'Stored on device',
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Materials',
              value: distinctMaterials.toString(),
              icon: Icons.category_outlined,
              iconColor: AppTheme.deepBlue,
              subtitle: 'Unique items',
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Total Qty',
              value: totalQuantity.toStringAsFixed(1),
              icon: Icons.stacked_bar_chart,
              iconColor: AppTheme.softGreen,
              subtitle: 'All materials',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialUsageByMaterialChart(
      BuildContext context, List<Map<String, dynamic>> usages) {
    final Map<String, double> byMaterial = {};
    for (final u in usages) {
      final name = (u['materialName'] ?? 'Material').toString();
      final qty = (u['quantity'] ?? 0).toDouble();
      byMaterial[name] = (byMaterial[name] ?? 0) + qty;
    }

    final entries = byMaterial.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topEntries = entries.take(5).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Consumption per Material (Top 5)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: value,
                      child: child,
                    ),
                  ),
                );
              },
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: true, reservedSize: 40),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= topEntries.length) {
                            return const SizedBox.shrink();
                          }
                          final label = topEntries[index].key;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              label.length > 8
                                  ? '${label.substring(0, 8)}…'
                                  : label,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontSize: 10,
                                  ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < topEntries.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: topEntries[i].value,
                            color: AppTheme.softGreen,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveriesSummaryCard(
      BuildContext context, List<Map<String, dynamic>> deliveries) {
    final totalRecords = deliveries.length;
    int pending = 0;
    int completed = 0;
    for (final d in deliveries) {
      final status = (d['syncStatus'] ?? AppConstants.syncStatusPending).toString();
      if (status == AppConstants.syncStatusPending) {
        pending++;
      } else if (status == AppConstants.syncStatusCompleted) {
        completed++;
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Delivery Records',
              value: totalRecords.toString(),
              icon: Icons.local_shipping,
              iconColor: AppTheme.deepBlue,
              subtitle: 'Stored on device',
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Pending Deliveries',
              value: pending.toString(),
              icon: Icons.hourglass_top,
              iconColor: AppTheme.warningOrange,
              subtitle: 'Waiting to sync',
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Completed Deliveries',
              value: completed.toString(),
              icon: Icons.check_circle_outline,
              iconColor: AppTheme.softGreen,
              subtitle: 'Synced to cloud',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveriesBySupplierChart(
      BuildContext context, List<Map<String, dynamic>> deliveries) {
    final Map<String, double> bySupplier = {};
    for (final d in deliveries) {
      final supplier = (d['supplier'] ?? 'Supplier').toString();
      bySupplier[supplier] = (bySupplier[supplier] ?? 0) + 1;
    }

    final entries = bySupplier.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topEntries = entries.take(5).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Deliveries per Supplier (Top 5)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: value,
                      child: child,
                    ),
                  ),
                );
              },
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: true, reservedSize: 40),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= topEntries.length) {
                            return const SizedBox.shrink();
                          }
                          final label = topEntries[index].key;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              label.length > 8
                                  ? '${label.substring(0, 8)}…'
                                  : label,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontSize: 10,
                                  ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < topEntries.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: topEntries[i].value,
                            color: AppTheme.softGreen,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncQueueSummaryCard(
      BuildContext context, List<Map<String, dynamic>> items) {
    int pending = 0;
    int failed = 0;

    for (final item in items) {
      final status = (item['status'] ?? AppConstants.syncStatusPending).toString();
      if (status == AppConstants.syncStatusPending) {
        pending++;
      } else if (status == AppConstants.syncStatusFailed) {
        failed++;
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Queue Items',
              value: items.length.toString(),
              icon: Icons.cloud_upload,
              iconColor: AppTheme.deepBlue,
              subtitle: 'Offline tasks',
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Pending Items',
              value: pending.toString(),
              icon: Icons.hourglass_empty,
              iconColor: AppTheme.warningOrange,
              subtitle: 'Waiting to upload',
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: StatsCard(
              title: 'Failed Items',
              value: failed.toString(),
              icon: Icons.error_outline,
              iconColor: AppTheme.errorRed,
              subtitle: 'Needs attention',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncQueueStatusChart(
      BuildContext context, List<Map<String, dynamic>> items) {
    int pending = 0;
    int syncing = 0;
    int completed = 0;
    int failed = 0;

    for (final item in items) {
      final status = (item['status'] ?? AppConstants.syncStatusPending).toString();
      if (status == AppConstants.syncStatusPending) {
        pending++;
      } else if (status == AppConstants.syncStatusSyncing) {
        syncing++;
      } else if (status == AppConstants.syncStatusCompleted) {
        completed++;
      } else if (status == AppConstants.syncStatusFailed) {
        failed++;
      }
    }

    final total = pending + syncing + completed + failed;
    if (total == 0) {
      return AppCard(
        child: Text(
          'No sync activity recorded yet.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.mediumGray,
              ),
        ),
      );
    }

    final sections = <PieChartSectionData>[
      if (pending > 0)
        PieChartSectionData(
          value: pending.toDouble(),
          color: AppTheme.warningOrange,
          title: 'Pending',
          radius: 40,
          titleStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
        ),
      if (syncing > 0)
        PieChartSectionData(
          value: syncing.toDouble(),
          color: AppTheme.deepBlue,
          title: 'Syncing',
          radius: 40,
          titleStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
        ),
      if (completed > 0)
        PieChartSectionData(
          value: completed.toDouble(),
          color: AppTheme.softGreen,
          title: 'Completed',
          radius: 40,
          titleStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
        ),
      if (failed > 0)
        PieChartSectionData(
          value: failed.toDouble(),
          color: AppTheme.errorRed,
          title: 'Failed',
          radius: 40,
          titleStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
        ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sync Status Distribution',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: 0.9 + 0.1 * value,
                    child: child,
                  ),
                );
              },
              child: PieChart(
                PieChartData(
                  sections: sections,
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemHealthCard(
      BuildContext context, Map<String, int> storageStats, SyncStats syncStats) {
    final totalOffline = storageStats.values
        .fold<int>(0, (sum, value) => sum + value);
    final totalPending = syncStats.totalPending;
    final pendingRatio = totalOffline == 0
        ? 0.0
        : (totalPending / totalOffline).clamp(0.0, 1.0);
    final syncLabel = syncStats.isSyncing ? 'Syncing…' : 'Idle';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overall System Health',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Offline records: $totalOffline',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Pending sync items: $totalPending',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pendingRatio,
              minHeight: 8,
              backgroundColor: AppTheme.lightGray,
              valueColor: AlwaysStoppedAnimation<Color>(
                pendingRatio < 0.3
                    ? AppTheme.softGreen
                    : (pendingRatio < 0.7
                        ? AppTheme.warningOrange
                        : AppTheme.errorRed),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                syncStats.isSyncing ? Icons.sync : Icons.check_circle_outline,
                color: syncStats.isSyncing
                    ? AppTheme.warningOrange
                    : AppTheme.softGreen,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                'Sync status: $syncLabel',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAiSummaryCard(BuildContext context, List<DailyReportModel> reports) {
    final totalReports = reports.length;
    if (totalReports == 0) {
      return const SizedBox.shrink();
    }

    final totalIssues = reports.fold<int>(0, (prev, r) => prev + r.issues.length);
    final rainyDays = reports
        .where((r) => r.weatherCondition.toLowerCase().contains('rain'))
        .length;
    final avgTemp = reports
            .map((r) => r.temperatureC)
            .fold<double>(0, (sum, t) => sum + t) /
        totalReports;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.deepBlue.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: AppTheme.softGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'AI-style Productivity Summary',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '• $totalReports daily reports analyzed with an average temperature of ${avgTemp.toStringAsFixed(1)}°C.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '• $totalIssues issues were recorded; focus on clearing blockers to improve productivity.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (rainyDays > 0) ...[
            const SizedBox(height: 4),
            Text(
              '• Weather impacted work on $rainyDays day(s); consider adjusting schedules around heavy rain.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, String label, Color color, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label ($count)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildLineLegendDot(Color color) {
    return Container(
      width: 14,
      height: 4,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  double _weatherScore(String condition) {
    final value = condition.toLowerCase();
    if (value.contains('sun') || value.contains('clear')) {
      return 5;
    }
    if (value.contains('cloud')) {
      return 4;
    }
    if (value.contains('rain')) {
      return 2;
    }
    if (value.contains('storm')) {
      return 1;
    }
    return 3;
  }
}
