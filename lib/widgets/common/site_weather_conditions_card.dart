import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/site_weather_context_service.dart';
import '../../services/weather_service.dart';

/// Weather & site conditions card (current + multi-day forecast).
class SiteWeatherConditionsCard extends StatelessWidget {
  const SiteWeatherConditionsCard({
    super.key,
    this.projectLocation,
    this.latitude,
    this.longitude,
    this.locationLabel,
    this.margin = EdgeInsets.zero,
    this.compact = false,
  });

  final String? projectLocation;
  final double? latitude;
  final double? longitude;
  final String? locationLabel;
  final EdgeInsetsGeometry margin;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SiteWeatherBundle>(
      future: SiteWeatherContextService.instance.load(
        projectLocation: projectLocation,
        latitude: latitude,
        longitude: longitude,
        locationLabel: locationLabel,
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _shell(
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return _shell(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Weather unavailable. Check connection.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
              ),
            ),
          );
        }
        return _shell(child: _Content(bundle: snap.data!, compact: compact));
      },
    );
  }

  Widget _shell({required Widget child}) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.bundle, required this.compact});
  final SiteWeatherBundle bundle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final now = bundle.now;
    final icon = _iconFor(SiteWeatherContextService.iconForCondition(now.condition));

    return Padding(
      padding: EdgeInsets.all(compact ? 14 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  compact ? 'Site weather' : 'Weather & Site Conditions',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Flexible(
                child: Text(
                  compact ? 'View forecast' : bundle.locationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: compact ? AppTheme.residentBlue : AppTheme.mediumGray,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (compact) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18, color: AppTheme.residentBlue),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 40, color: _iconColor(now.condition)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${now.temperatureC.toStringAsFixed(0)}°C',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                    ),
                    Text(
                      _titleCase(now.description.isNotEmpty ? now.description : now.condition),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.mediumGray,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (now.feelsLikeC != null)
                      Text(
                        'Feels like ${now.feelsLikeC!.toStringAsFixed(0)}°C',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.mediumGray),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MetricRow(label: 'Humidity', value: now.humidity != null ? '${now.humidity}%' : '—'),
          _MetricRow(label: 'Wind', value: bundle.windLabel),
          _MetricRow(label: 'Visibility', value: bundle.visibilityLabel),
          const SizedBox(height: 12),
          if (!compact && bundle.forecastDays.isNotEmpty) ...[
            Text(
              'Forecast',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: bundle.forecastDays.length.clamp(0, 7),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => _ForecastDayChip(day: bundle.forecastDays[i], isToday: i == 0),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _adviceColor(bundle.siteAdvice).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _adviceColor(bundle.siteAdvice).withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: _adviceColor(bundle.siteAdvice)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bundle.siteAdvice,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.35,
                      color: _adviceColor(bundle.siteAdvice),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _adviceColor(String advice) {
    if (advice.toLowerCase().contains('good')) return const Color(0xFF16A34A);
    if (advice.toLowerCase().contains('rain') || advice.toLowerCase().contains('wet')) {
      return const Color(0xFFEA580C);
    }
    return const Color(0xFF2563EB);
  }

  static IconData _iconFor(IconKind kind) {
    switch (kind) {
      case IconKind.sun:
        return Icons.wb_sunny_rounded;
      case IconKind.cloud:
        return Icons.cloud_outlined;
      case IconKind.rain:
        return Icons.grain;
      case IconKind.storm:
        return Icons.thunderstorm_outlined;
    }
  }

  static Color _iconColor(String condition) {
    final c = condition.toLowerCase();
    if (c.contains('rain') || c.contains('drizzle')) return const Color(0xFF3B82F6);
    if (c.contains('thunder')) return const Color(0xFF7C3AED);
    if (c.contains('cloud')) return const Color(0xFF64748B);
    return const Color(0xFFF59E0B);
  }

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray)),
          ),
          Text(value, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ForecastDayChip extends StatelessWidget {
  const _ForecastDayChip({required this.day, required this.isToday});
  final WeatherDailyForecast day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final label = days[day.date.weekday - 1];

    return Container(
      width: 68,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: isToday ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isToday ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
          Text(
            '${day.maxTempC.toStringAsFixed(0)}°/${day.minTempC.toStringAsFixed(0)}°',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
