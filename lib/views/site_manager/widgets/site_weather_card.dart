import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/site_weather_provider.dart';
import '../../../services/weather_notification_service.dart';
import '../../site_manager/widgets/site_manager_card.dart';

/// Full-width weather card shown on the RE home screen below the active
/// project card. Fetches live weather for the assigned project site,
/// publishes a snapshot (+ rain alert) to Firestore, and lets the RE tap
/// to open the detailed forecast map.
class SiteWeatherCard extends ConsumerWidget {
  const SiteWeatherCard({
    super.key,
    required this.projectId,
  });

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherAsync = ref.watch(singleSiteWeatherProvider(projectId));

    return weatherAsync.when(
      loading: () => _WeatherCardShell(
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Loading site weather…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mediumGray,
                  ),
            ),
          ],
        ),
      ),
      error: (_, __) => _WeatherCardShell(
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 18, color: AppTheme.mediumGray),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Weather unavailable. Check connection.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            ),
          ],
        ),
      ),
      data: (siteWeather) {
        if (siteWeather == null) {
          // Project has no coordinates yet — show a gentle placeholder.
          return _WeatherCardShell(
            child: Row(
              children: [
                const Icon(Icons.location_off_outlined,
                    size: 18, color: AppTheme.mediumGray),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No site location set for this project.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.mediumGray,
                        ),
                  ),
                ),
              ],
            ),
          );
        }

        // Fire-and-forget: publish snapshot + rain alert to Firestore.
        WeatherNotificationService.instance
            .publishSiteWeather(siteWeather)
            .ignore();

        return _SiteWeatherContent(siteWeather: siteWeather);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Internal widgets
// ---------------------------------------------------------------------------

class _WeatherCardShell extends StatelessWidget {
  const _WeatherCardShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SiteManagerCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: child,
    );
  }
}

class _SiteWeatherContent extends StatelessWidget {
  const _SiteWeatherContent({required this.siteWeather});
  final ProjectSiteWeather siteWeather;

  @override
  Widget build(BuildContext context) {
    final isRaining = siteWeather.isRaining;
    final isCloudy = siteWeather.isCloudy;

    final Color accentColor = isRaining
        ? const Color(0xFF3B82F6)   // blue
        : isCloudy
            ? AppTheme.mediumGray
            : AppTheme.warningOrange; // sunny/orange

    final IconData weatherIcon = isRaining
        ? Icons.grain
        : isCloudy
            ? Icons.cloud_outlined
            : Icons.wb_sunny_outlined;

    final String conditionText = siteWeather.conditionLabel;
    final String tempText = siteWeather.tempLabel;
    final humidity = siteWeather.weather.humidity;
    final windMs = siteWeather.weather.windSpeedMs;
    final windKmh = windMs != null ? (windMs * 3.6).round() : null;

    return SiteManagerCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      onTap: () => context.push(RouteNames.siteManagerWeatherForecast),
      child: Column(
        children: [
          // ── Header strip ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(weatherIcon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Site Weather',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.mediumGray,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        siteWeather.location.isNotEmpty
                            ? siteWeather.location
                            : siteWeather.projectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.darkGray,
                            ),
                      ),
                    ],
                  ),
                ),
                // Rain alert badge
                if (isRaining)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 12, color: Color(0xFF3B82F6)),
                        const SizedBox(width: 4),
                        Text(
                          'Rain Alert',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: const Color(0xFF3B82F6),
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── Metrics row ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                // Temperature (large)
                _MetricTile(
                  label: 'Temperature',
                  value: tempText,
                  valueColor: accentColor,
                  icon: weatherIcon,
                  iconColor: accentColor,
                ),
                const _Divider(),
                // Condition
                _MetricTile(
                  label: 'Condition',
                  value: conditionText,
                  icon: isRaining
                      ? Icons.umbrella_outlined
                      : Icons.thermostat_outlined,
                ),
                if (humidity != null) ...[
                  const _Divider(),
                  _MetricTile(
                    label: 'Humidity',
                    value: '$humidity%',
                    icon: Icons.water_drop_outlined,
                    iconColor: const Color(0xFF60A5FA),
                  ),
                ],
                if (windKmh != null) ...[
                  const _Divider(),
                  _MetricTile(
                    label: 'Wind',
                    value: '$windKmh km/h',
                    icon: Icons.air_outlined,
                    iconColor: AppTheme.mediumGray,
                  ),
                ],
                const Spacer(),
                // Tap to open detail
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.mediumGray.withValues(alpha: 0.5),
                  size: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
    this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: iconColor ?? AppTheme.mediumGray),
        const SizedBox(width: 5),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.mediumGray,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? AppTheme.darkGray,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: AppTheme.mediumGray.withValues(alpha: 0.15),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact inline weather badge (used inside the active project card header)
// ---------------------------------------------------------------------------

/// A small pill badge that shows the current weather for the project.
/// Replaces the hard-coded "Sunny 30°C" badge in site_manager_home.dart.
class SiteWeatherBadge extends ConsumerWidget {
  const SiteWeatherBadge({
    super.key,
    required this.projectId,
  });

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherAsync = ref.watch(singleSiteWeatherProvider(projectId));

    return weatherAsync.when(
      loading: () => _badge(
        context,
        icon: Icons.cloud_outlined,
        iconColor: AppTheme.mediumGray,
        label: '—',
      ),
      error: (_, __) => _badge(
        context,
        icon: Icons.cloud_off_outlined,
        iconColor: AppTheme.mediumGray,
        label: 'N/A',
      ),
      data: (siteWeather) {
        if (siteWeather == null) {
          return _badge(
            context,
            icon: Icons.location_off_outlined,
            iconColor: AppTheme.mediumGray,
            label: 'No location',
          );
        }
        final isRaining = siteWeather.isRaining;
        final isCloudy = siteWeather.isCloudy;
        final color = isRaining
            ? const Color(0xFF3B82F6)
            : isCloudy
                ? AppTheme.mediumGray
                : AppTheme.warningOrange;
        final icon = isRaining
            ? Icons.grain
            : isCloudy
                ? Icons.cloud_outlined
                : Icons.wb_sunny_outlined;

        return _badge(
          context,
          icon: icon,
          iconColor: color,
          label: siteWeather.summaryLine,
        );
      },
    );
  }

  Widget _badge(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.lightGray,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTheme.residentBlue.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.darkGray,
                ),
          ),
        ],
      ),
    );
  }
}
