import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../services/weather_service.dart';
import 'widgets/admin_bottom_nav.dart';
import 'widgets/admin_glass_layout.dart';

class AdminWeatherForecastScreen extends StatefulWidget {
  const AdminWeatherForecastScreen({super.key});

  @override
  State<AdminWeatherForecastScreen> createState() =>
      _AdminWeatherForecastScreenState();
}

class _WeatherDetailsSection extends StatelessWidget {
  const _WeatherDetailsSection({
    required this.now,
    required this.hourly,
  });

  final WeatherNow now;
  final List<WeatherHourlyForecast> hourly;

  void _showDetailSheet(
    BuildContext context, {
    required String title,
    required Widget content,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                ),
                const SizedBox(height: 10),
                content,
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final nowLabel = _formatTime(DateTime.now());

    final precipNext24 = _computePrecipitationNext24h(hourly);
    final popAvg = _computeAveragePop(hourly);

    final windKmh = now.windSpeedMs != null
        ? (now.windSpeedMs! * 3.6).round()
        : null;

    final cards = <Widget>[
      _TemperatureDetailCard(
        tempC: now.temperatureC,
        condition: now.condition,
        onTap: () {
          _showDetailSheet(
            context,
            title: 'Temperature',
            content: Text(
              'Current temperature: ${now.temperatureC.toStringAsFixed(1)}°C',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        },
      ),
      _FeelsLikeDetailCard(
        feelsLikeC: now.feelsLikeC,
        tempC: now.temperatureC,
        humidity: now.humidity,
        onTap: () {
          _showDetailSheet(
            context,
            title: 'Feels like',
            content: Text(
              now.feelsLikeC != null
                  ? 'Feels like: ${now.feelsLikeC!.toStringAsFixed(1)}°C\nHumidity: ${now.humidity ?? '--'}%'
                  : 'Feels-like data is not available for this location.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        },
      ),
      _CloudCoverDetailCard(
        condition: now.condition,
        popAvg: popAvg,
        onTap: () {
          _showDetailSheet(
            context,
            title: 'Cloud cover',
            content: Text(
              'Cloud cover value is not included in the current weather request used by this screen.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        },
      ),
      _PrecipitationDetailCard(
        precipNext24Mm: precipNext24,
        popAvg: popAvg,
        onTap: () {
          _showDetailSheet(
            context,
            title: 'Precipitation',
            content: Text(
              precipNext24 != null
                  ? 'Estimated rain (next 24h): ${precipNext24.toStringAsFixed(1)} mm\nAverage chance: ${popAvg != null ? (popAvg * 100).round() : '--'}%'
                  : 'No hourly precipitation data available.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        },
      ),
      _WindDetailCard(
        windKmh: windKmh,
        windDeg: now.windDeg,
        onTap: () {
          _showDetailSheet(
            context,
            title: 'Wind',
            content: Text(
              'Wind speed: ${windKmh ?? '--'} km/h\nDirection: ${now.windDeg ?? '--'}°',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        },
      ),
      _HumidityDetailCard(
        humidity: now.humidity,
        onTap: () {
          _showDetailSheet(
            context,
            title: 'Humidity',
            content: Text(
              now.humidity != null
                  ? 'Relative humidity: ${now.humidity}%'
                  : 'Humidity data is not available.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        },
      ),
      _SimpleValueDetailCard(
        title: 'Visibility',
        value: now.visibilityKm != null
            ? '${now.visibilityKm!.toStringAsFixed(0)} km'
            : '--',
        subtitle: 'Visibility distance',
        tint: const Color(0xFF16A34A),
        onTap: () {
          _showDetailSheet(
            context,
            title: 'Visibility',
            content: Text(
              now.visibilityKm != null
                  ? 'Visibility: ${now.visibilityKm!.toStringAsFixed(1)} km'
                  : 'Visibility data is not available.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        },
      ),
      _SimpleValueDetailCard(
        title: 'Pressure',
        value: now.pressureMb != null ? '${now.pressureMb} mb' : '--',
        subtitle: 'Sea-level pressure',
        tint: const Color(0xFF8B5CF6),
        onTap: () {
          _showDetailSheet(
            context,
            title: 'Pressure',
            content: Text(
              now.pressureMb != null
                  ? 'Pressure: ${now.pressureMb} mb'
                  : 'Pressure data is not available.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        },
      ),
      _SunDetailCard(
        sunrise: now.sunrise,
        sunset: now.sunset,
        onTap: () {
          _showDetailSheet(
            context,
            title: 'Sun',
            content: Text(
              (now.sunrise != null && now.sunset != null)
                  ? 'Sunrise: ${_formatTime(now.sunrise!.toLocal())}\nSunset: ${_formatTime(now.sunset!.toLocal())}'
                  : 'Sunrise/sunset data is not available.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        },
      ),
    ];

    return GlassCard(
      color: Colors.white,
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Weather details  $nowLabel',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  _showDetailSheet(
                    context,
                    title: 'Suggestions for your day',
                    content: Text(
                      'Based on current conditions, plan accordingly (hydration, sun protection, and rain readiness).',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF334155),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text(
                    'SUGGESTIONS FOR YOUR DAY  ›',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF334155),
                        ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final cols = w >= 640 ? 3 : 1;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: cols == 3 ? 1.55 : 1.45,
                children: cards,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DetailCardShell extends StatelessWidget {
  const _DetailCardShell({
    required this.title,
    required this.onTap,
    required this.child,
  });

  final String title;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFC9DBF8)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                    ),
              ),
              const SizedBox(height: 10),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemperatureDetailCard extends StatelessWidget {
  const _TemperatureDetailCard({
    required this.tempC,
    required this.condition,
    required this.onTap,
  });

  final double tempC;
  final String condition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tempC.clamp(-5, 45);
    final fraction = ((t + 5) / 50).clamp(0.0, 1.0);

    return _DetailCardShell(
      title: 'Temperature',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFEF4444).withValues(alpha: 0.18),
                    const Color(0xFFEF4444).withValues(alpha: 0.05),
                  ],
                ),
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  final x = 16 + (c.maxWidth - 32) * fraction;
                  return Stack(
                    children: [
                      Positioned(
                        left: 16,
                        right: 16,
                        top: 14,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        top: 14,
                        child: Container(
                          height: 6,
                          width: (c.maxWidth - 32) * fraction,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Positioned(
                        left: x - 7,
                        top: 10,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 16,
                        bottom: 12,
                        child: Text(
                          '${tempC.round()}°',
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF0F172A),
                              ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            condition.isNotEmpty ? condition : '—',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF334155),
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Tap for details',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                ),
          ),
        ],
      ),
    );
  }
}

class _FeelsLikeDetailCard extends StatelessWidget {
  const _FeelsLikeDetailCard({
    required this.feelsLikeC,
    required this.tempC,
    required this.humidity,
    required this.onTap,
  });

  final double? feelsLikeC;
  final double tempC;
  final int? humidity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = feelsLikeC ?? tempC;
    final t = value.clamp(-5, 45);
    final fraction = ((t + 5) / 50).clamp(0.0, 1.0);

    return _DetailCardShell(
      title: 'Feels like',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 92,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFFEF4444).withValues(alpha: 0.14),
                  const Color(0xFFEF4444).withValues(alpha: 0.04),
                ],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final x = 16 + (c.maxWidth - 32) * fraction;
                return Stack(
                  children: [
                    Positioned(
                      left: 16,
                      right: 16,
                      top: 14,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      top: 14,
                      child: Container(
                        height: 6,
                        width: (c.maxWidth - 32) * fraction,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Positioned(
                      left: x - 7,
                      top: 10,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: 10,
                      child: Text(
                        feelsLikeC != null ? '${feelsLikeC!.round()}°' : '--',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F172A),
                            ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            humidity != null ? 'Dominant factor: humidity' : 'Humidity affects comfort',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Feels like:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF64748B),
                        ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    feelsLikeC != null ? '${feelsLikeC!.round()}°' : '--',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Temperature:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF64748B),
                        ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${tempC.round()}°',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CloudCoverDetailCard extends StatelessWidget {
  const _CloudCoverDetailCard({
    required this.condition,
    required this.popAvg,
    required this.onTap,
  });

  final String condition;
  final double? popAvg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = condition.isNotEmpty ? condition : '—';
    final percent = popAvg != null ? (popAvg! * 100).round() : null;
    final iconSpec = _conditionToIconSpec(condition);

    return _DetailCardShell(
      title: 'Cloud cover',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Center(
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: const Color(0xFFBFDBFE).withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFC9DBF8)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(iconSpec.icon, color: iconSpec.color, size: 28),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            percent != null ? '$label ($percent%)' : 'Not provided by current API',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF334155),
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Tap for details',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                ),
          ),
        ],
      ),
    );
  }
}

class _PrecipitationDetailCard extends StatelessWidget {
  const _PrecipitationDetailCard({
    required this.precipNext24Mm,
    required this.popAvg,
    required this.onTap,
  });

  final double? precipNext24Mm;
  final double? popAvg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mm = precipNext24Mm ?? 0.0;
    final fraction = (mm / 20.0).clamp(0.0, 1.0);
    final label = precipNext24Mm == null ? '--' : '${mm.toStringAsFixed(1)} mm';

    return _DetailCardShell(
      title: 'Precipitation',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Center(
              child: SizedBox(
                width: 110,
                height: 110,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: fraction,
                      strokeWidth: 10,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFF59E0B),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          precipNext24Mm == null ? '--' : mm.toStringAsFixed(0),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF0F172A),
                              ),
                        ),
                        Text(
                          'mm',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF64748B),
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'In next 24h',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF64748B),
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            precipNext24Mm == null ? 'No precipitation data' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
          ),
          const SizedBox(height: 2),
          Text(
            popAvg != null ? 'Chance: ${(popAvg! * 100).round()}%' : 'Tap for details',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                ),
          ),
        ],
      ),
    );
  }
}

class _WindDetailCard extends StatelessWidget {
  const _WindDetailCard({
    required this.windKmh,
    required this.windDeg,
    required this.onTap,
  });

  final int? windKmh;
  final int? windDeg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final deg = (windDeg ?? 0) % 360;
    final dir = _windDirectionLabel(deg);

    return _DetailCardShell(
      title: 'Wind',
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: Center(
              child: CustomPaint(
                size: const Size(92, 92),
                painter: _WindCompassPainter(deg: deg.toDouble()),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  windDeg != null ? 'From $dir ($deg°)' : 'Direction: —',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF334155),
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  windKmh != null ? '${windKmh!}' : '--',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                ),
                Text(
                  'km/h  Wind Speed',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap for details',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HumidityDetailCard extends StatelessWidget {
  const _HumidityDetailCard({
    required this.humidity,
    required this.onTap,
  });

  final int? humidity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = humidity ?? 0;
    final filled = ((h / 100) * 10).round().clamp(0, 10);

    return _DetailCardShell(
      title: 'Humidity',
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(10, (i) {
                final on = i < filled;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      height: 70,
                      decoration: BoxDecoration(
                        color: on
                            ? const Color(0xFF2563EB).withValues(alpha: 0.65)
                            : const Color(0xFFCBD5E1).withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  humidity != null ? '$humidity%' : '--',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                ),
                Text(
                  'Relative Humidity',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tap for details',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleValueDetailCard extends StatelessWidget {
  const _SimpleValueDetailCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.tint,
    required this.onTap,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DetailCardShell(
      title: title,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 84,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tint.withValues(alpha: 0.14),
                  tint.withValues(alpha: 0.04),
                ],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                return Stack(
                  children: [
                    Positioned(
                      left: 10,
                      right: 10,
                      top: 14,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 14,
                      child: Container(
                        height: 6,
                        width: (c.maxWidth - 20) * 0.55,
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.70),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10 + (c.maxWidth - 20) * 0.55 - 7,
                      top: 10,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: tint,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 10,
                      child: Text(
                        value,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F172A),
                            ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF334155),
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Tap for details',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                ),
          ),
        ],
      ),
    );
  }
}

class _SunDetailCard extends StatelessWidget {
  const _SunDetailCard({
    required this.sunrise,
    required this.sunset,
    required this.onTap,
  });

  final DateTime? sunrise;
  final DateTime? sunset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final has = sunrise != null && sunset != null;

    return _DetailCardShell(
      title: 'Sun',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 84,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: CustomPaint(
              painter: _SunArcPainter(
                active: has,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      has ? _formatTime(sunrise!.toLocal()) : '--',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                    ),
                    Text(
                      'Sunrise',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF64748B),
                          ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      has ? _formatTime(sunset!.toLocal()) : '--',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                    ),
                    Text(
                      'Sunset',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF64748B),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WindCompassPainter extends CustomPainter {
  const _WindCompassPainter({required this.deg});

  final double deg;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.46;

    final ringPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(center, radius, ringPaint);

    final labelStyle = const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w900,
      color: Color(0xFF64748B),
    );
    void drawLabel(String text, Offset pos) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    drawLabel('N', center + Offset(0, -radius - 10));
    drawLabel('E', center + Offset(radius + 10, 0));
    drawLabel('S', center + Offset(0, radius + 10));
    drawLabel('W', center + Offset(-radius - 10, 0));

    final arrowPaint = Paint()
      ..color = const Color(0xFF60A5FA)
      ..style = PaintingStyle.fill;

    final radians = (deg - 90) * math.pi / 180.0;
    final tip = center +
        Offset(radius * 0.70 * math.cos(radians), radius * 0.70 * math.sin(radians));
    final left = center +
        Offset(radius * 0.20 * math.cos(radians + 2.3), radius * 0.20 * math.sin(radians + 2.3));
    final right = center +
        Offset(radius * 0.20 * math.cos(radians - 2.3), radius * 0.20 * math.sin(radians - 2.3));
    final path = ui.Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, arrowPaint);

    final dotPaint = Paint()..color = const Color(0xFF2563EB);
    canvas.drawCircle(center, 5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _WindCompassPainter oldDelegate) => oldDelegate.deg != deg;
}

class _SunArcPainter extends CustomPainter {
  const _SunArcPainter({required this.active});

  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = active ? const Color(0xFFDC2626) : const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(14, 14, size.width - 28, size.height * 1.2);
    canvas.drawArc(rect, 3.141592653589793, 3.141592653589793, false, basePaint);
    canvas.drawArc(rect, 3.141592653589793, 3.141592653589793 * 0.60, false, activePaint);

    final dotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(22, size.height - 22), 6, dotPaint);
    canvas.drawCircle(Offset(size.width - 22, size.height - 22), 6, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _SunArcPainter oldDelegate) => oldDelegate.active != active;
}

String _windDirectionLabel(int deg) {
  const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  final idx = ((deg % 360) / 45).round() % 8;
  return dirs[idx];
}

double? _computePrecipitationNext24h(List<WeatherHourlyForecast> hourly) {
  if (hourly.isEmpty) return null;
  final now = DateTime.now();
  final until = now.add(const Duration(hours: 24));
  var sum = 0.0;
  var has = false;
  for (final h in hourly) {
    if (h.dateTime.isBefore(now) || h.dateTime.isAfter(until)) continue;
    if (h.rainMm != null) {
      sum += h.rainMm!;
      has = true;
    }
  }
  return has ? sum : null;
}

double? _computeAveragePop(List<WeatherHourlyForecast> hourly) {
  if (hourly.isEmpty) return null;
  final now = DateTime.now();
  final until = now.add(const Duration(hours: 24));
  var sum = 0.0;
  var count = 0;
  for (final h in hourly) {
    if (h.dateTime.isBefore(now) || h.dateTime.isAfter(until)) continue;
    if (h.pop != null) {
      sum += h.pop!.clamp(0.0, 1.0);
      count++;
    }
  }
  return count == 0 ? null : (sum / count);
}

class _AdminWeatherForecastScreenState
    extends State<AdminWeatherForecastScreen> {
  static const Color _bg = Color(0xFFDCEBFF);
  static const Color _surface = Color(0xFFF5F9FF);
  static const Color _tile = Color(0xFFEAF2FF);
  static const Color _tileBorder = Color(0xFFC9DBF8);
  static const Color _text = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _accent = Color(0xFFFACC15);

  final TextEditingController _cityController =
      TextEditingController(text: 'Manila, PH');

  Future<_WeatherScreenData>? _future;
  int _selectedHourlyTab = 0;
  WeatherMapLayer _selectedMapLayer = WeatherMapLayer.temperature;
  int _selectedMonthIndex = DateTime.now().month - 1;
  DateTime? _selectedCalendarDate;
  final Map<String, Future<List<WeatherDailyForecast>>> _monthlyCache = {};

  @override
  void initState() {
    super.initState();
    _future = _loadWeather(_normalizeCity(_cityController.text));
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  String _normalizeCity(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 'Manila,PH';
    return v.replaceAll(', ', ',').replaceAll(' ,', ',');
  }

  void _reload() {
    final city = _normalizeCity(_cityController.text);
    setState(() {
      _future = _loadWeather(city);
      _selectedHourlyTab = 0;
      _monthlyCache.clear();
    });
  }

  Future<List<WeatherDailyForecast>> _getMonthlyForecast(
    String city,
    int year,
    int month,
  ) {
    final key = '$city|$year|$month';
    return _monthlyCache.putIfAbsent(
      key,
      () => WeatherService.instance.getMonthlyForecastByCity(
        city: city,
        year: year,
        month: month,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminGlassScaffold(
      title: 'Weather Forecast',
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none),
          onPressed: () => context.push(RouteNames.notifications),
        ),
        IconButton(
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.push(RouteNames.profile),
        ),
      ],
      bottomNavigationBar: const AdminBottomNavBar(
        current: AdminNavItem.dashboard,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(14),
        child: FutureBuilder<_WeatherScreenData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Failed to load weather forecast',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppTheme.errorRed),
                ),
              );
            }

            final data = snapshot.data;
            if (data == null) {
              return Center(
                child: Text(
                  'No weather data available.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppTheme.mediumGray),
                ),
              );
            }

            final hourly = _selectedHourlyTab == 1
                ? data.hourlyTomorrow
                : data.hourlyToday;

            final nowDt = DateTime.now();
            final monthDate = DateTime(nowDt.year, _selectedMonthIndex + 1);
            final cityKey = _normalizeCity(_cityController.text);
            final monthlyFuture =
                _getMonthlyForecast(cityKey, monthDate.year, monthDate.month);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SearchField(
                        controller: _cityController,
                        onSubmitted: (_) => _reload(),
                        onSearch: _reload,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 980;

                    final left = _CurrentWeatherCard(
                      cityLabel: data.cityLabel,
                      now: data.now,
                      today: data.today,
                    );
                    final right = _WeeklyForecastCard(
                      daily: data.daily,
                    );

                    if (isNarrow) {
                      return Column(
                        children: [
                          left,
                          const SizedBox(height: 12),
                          right,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: left),
                        const SizedBox(width: 12),
                        Expanded(flex: 7, child: right),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _tileBorder),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Hourly Forecast',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: _text,
                                  ),
                            ),
                          ),
                          _TabChip(
                            label: 'Today',
                            selected: _selectedHourlyTab == 0,
                            chipBg: _tile,
                            chipSelected: _accent,
                            onTap: () => setState(() => _selectedHourlyTab = 0),
                          ),
                          const SizedBox(width: 8),
                          _TabChip(
                            label: 'Tomorrow',
                            selected: _selectedHourlyTab == 1,
                            chipBg: _tile,
                            chipSelected: _accent,
                            onTap: () => setState(() => _selectedHourlyTab = 1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 130,
                        child: hourly.isEmpty
                            ? Center(
                                child: Text(
                                  'No hourly data available.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: _muted,
                                      ),
                                ),
                              )
                            : ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemBuilder: (context, index) {
                                  return _HourlyCard(forecast: hourly[index]);
                                },
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 10),
                                itemCount: hourly.length,
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _WeatherMapsPanel(
                  cityLabel: data.cityLabel,
                  lat: data.now.lat,
                  lon: data.now.lon,
                  selectedLayer: _selectedMapLayer,
                  onSelectLayer: (v) => setState(() => _selectedMapLayer = v),
                ),
                const SizedBox(height: 12),
                _WeatherDetailsSection(now: data.now, hourly: hourly),
                const SizedBox(height: 12),
                _TrendsPanel(daily: data.daily),
                const SizedBox(height: 12),
                _MonthlyPanel(
                  monthDate: monthDate,
                  selectedMonthIndex: _selectedMonthIndex,
                  onSelectMonthIndex: (idx) {
                    setState(() => _selectedMonthIndex = idx);
                    final newMonthDate =
                        DateTime(DateTime.now().year, idx + 1);
                    _getMonthlyForecast(
                      cityKey,
                      newMonthDate.year,
                      newMonthDate.month,
                    );
                  },
                  selectedDate: _selectedCalendarDate,
                  onSelectDate: (d) => setState(() => _selectedCalendarDate = d),
                  monthlyForecast: monthlyFuture,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<_WeatherScreenData> _loadWeather(String city) async {
    final now = await WeatherService.instance.getCurrentWeatherByCity(city);
    final daily = await WeatherService.instance.get7DayForecastByCity(city);

    final nowKey = DateTime.now();
    final todayDate = DateTime(nowKey.year, nowKey.month, nowKey.day);
    final tomorrowDate = todayDate.add(const Duration(days: 1));

    WeatherDailyForecast? today;
    WeatherDailyForecast? tomorrow;
    for (final f in daily) {
      final key = DateTime(f.date.year, f.date.month, f.date.day);
      if (today == null && key == todayDate) today = f;
      if (tomorrow == null && key == tomorrowDate) tomorrow = f;
    }

    today ??= daily.isNotEmpty ? daily.first : null;
    tomorrow ??= daily.length >= 2 ? daily[1] : null;

    final hourlyToday = await WeatherService.instance
        .getHourlyForecastByCityAndDate(city, todayDate);
    final hourlyTomorrow = await WeatherService.instance
        .getHourlyForecastByCityAndDate(city, tomorrowDate);

    return _WeatherScreenData(
      cityLabel: city,
      now: now,
      daily: daily,
      today: today,
      tomorrow: tomorrow,
      hourlyToday: hourlyToday,
      hourlyTomorrow: hourlyTomorrow,
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onSubmitted,
    required this.onSearch,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      color: Colors.white,
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.search, color: const Color(0xFF64748B)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                  ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search city (e.g. Manila,PH)',
                hintStyle: TextStyle(color: Color(0xFF64748B)),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
            ),
          ),
          IconButton(
            onPressed: onSearch,
            icon: const Icon(Icons.arrow_forward, color: Color(0xFF0F172A)),
            tooltip: 'Search',
          ),
        ],
      ),
    );
  }
}

class _CurrentWeatherCard extends StatelessWidget {
  const _CurrentWeatherCard({
    required this.cityLabel,
    required this.now,
    required this.today,
  });

  final String cityLabel;
  final WeatherNow now;
  final WeatherDailyForecast? today;

  @override
  Widget build(BuildContext context) {
    final min = today?.minTempC;
    final max = today?.maxTempC;
    final iconSpec = _conditionToIconSpec(now.condition);

    return GlassCard(
      color: Colors.white,
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        cityLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  (now.condition).isEmpty ? '—' : now.condition,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF334155),
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${now.temperatureC.toStringAsFixed(0)}°C',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _MiniInfo(
                      label: 'H',
                      value: max == null ? '—' : max.toStringAsFixed(0),
                    ),
                    _MiniInfo(
                      label: 'L',
                      value: min == null ? '—' : min.toStringAsFixed(0),
                    ),
                    _MiniInfo(
                      label: '',
                      value: (now.description).isEmpty
                          ? '—'
                          : now.description,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            height: 110,
            child: Icon(
              iconSpec.icon,
              size: 96,
              color: iconSpec.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            '$label: ',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _WeeklyForecastCard extends StatelessWidget {
  const _WeeklyForecastCard({
    required this.daily,
  });

  final List<WeatherDailyForecast> daily;

  @override
  Widget build(BuildContext context) {
    final visible = daily.take(7).toList();

    return GlassCard(
      color: Colors.white,
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '7-Day Forecast',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: const Color(0xFF64748B),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      'No forecast data.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      return _DailyChip(forecast: visible[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DailyChip extends StatelessWidget {
  const _DailyChip({
    required this.forecast,
  });

  final WeatherDailyForecast forecast;

  @override
  Widget build(BuildContext context) {
    final dt = forecast.date;
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final label = days[dt.weekday % 7];
    final iconSpec = _conditionToIconSpec(forecast.condition);

    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC9DBF8)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF334155),
                ),
          ),
          const SizedBox(height: 6),
          Icon(
            iconSpec.icon,
            size: 22,
            color: iconSpec.color,
          ),
          const SizedBox(height: 6),
          Text(
            '${forecast.minTempC.toStringAsFixed(0)}°/${forecast.maxTempC.toStringAsFixed(0)}°',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
          ),
        ],
      ),
    );
  }
}

class _HourlyCard extends StatelessWidget {
  const _HourlyCard({
    required this.forecast,
  });

  final WeatherHourlyForecast forecast;

  @override
  Widget build(BuildContext context) {
    final hour = forecast.dateTime.hour;
    final isAm = hour < 12;
    final hour12 = (hour % 12) == 0 ? 12 : (hour % 12);
    final label = '$hour12 ${isAm ? 'AM' : 'PM'}';
    final iconSpec = _conditionToIconSpec(forecast.condition);

    return Container(
      width: 92,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC9DBF8)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF334155),
                ),
          ),
          const SizedBox(height: 8),
          Icon(
            iconSpec.icon,
            size: 28,
            color: iconSpec.color,
          ),
          const SizedBox(height: 10),
          Text(
            '${forecast.tempC.toStringAsFixed(0)}°',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.chipBg,
    required this.chipSelected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color chipBg;
  final Color chipSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? chipSelected : chipBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xFFFACC15)
                : const Color(0xFFC9DBF8),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: selected
                    ? Colors.black.withValues(alpha: 0.85)
                    : const Color(0xFF0F172A),
              ),
        ),
      ),
    );
  }
}

class _TrendsPanel extends StatelessWidget {
  const _TrendsPanel({required this.daily});

  final List<WeatherDailyForecast> daily;

  @override
  Widget build(BuildContext context) {
    final series = daily.take(7).toList();
    final maxValues = <double>[];
    final minValues = <double>[];
    for (final d in series) {
      maxValues.add(d.maxTempC);
      minValues.add(d.minTempC);
    }

    final all = <double>[...maxValues, ...minValues];
    final minY = all.isEmpty ? 0.0 : (all.reduce((a, b) => a < b ? a : b) - 2);
    final maxY = all.isEmpty ? 40.0 : (all.reduce((a, b) => a > b ? a : b) + 2);

    return GlassCard(
      color: Colors.white,
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trends',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: series.isEmpty
                ? Center(
                    child: Text(
                      'No trend data.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minY: minY,
                      maxY: maxY,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 5,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: const Color(0xFFC9DBF8),
                            strokeWidth: 1,
                          );
                        },
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: const Color(0xFFC9DBF8)),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            interval: 5,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                value.toInt().toString(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: const Color(0xFF64748B),
                                      fontWeight: FontWeight.w800,
                                    ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= series.length) {
                                return const SizedBox.shrink();
                              }
                              const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
                              final d = series[i].date;
                              final label = days[d.weekday % 7];
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: const Color(0xFF334155),
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < series.length; i++)
                              FlSpot(i.toDouble(), series[i].maxTempC),
                          ],
                          isCurved: true,
                          barWidth: 3,
                          color: const Color(0xFFFACC15),
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: const Color(0xFFFACC15)
                                .withValues(alpha: 0.12),
                          ),
                        ),
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < series.length; i++)
                              FlSpot(i.toDouble(), series[i].minTempC),
                          ],
                          isCurved: true,
                          barWidth: 3,
                          color: const Color(0xFF0EA5E9),
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: const Color(0xFF0EA5E9)
                                .withValues(alpha: 0.10),
                          ),
                        ),
                      ],
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => Colors.white,
                          tooltipBorder: const BorderSide(
                            color: Color(0xFFC9DBF8),
                          ),
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((s) {
                              final isMax = s.barIndex == 0;
                              final prefix = isMax ? 'H' : 'L';
                              return LineTooltipItem(
                                '$prefix ${s.y.round()}°',
                                Theme.of(context).textTheme.labelSmall!.copyWith(
                                      color: const Color(0xFF0F172A),
                                      fontWeight: FontWeight.w900,
                                    ),
                              );
                            }).toList();
                          },
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

String _formatTime(DateTime d) {
  final hour = d.hour;
  final minute = d.minute.toString().padLeft(2, '0');
  final isAm = hour < 12;
  final hour12 = (hour % 12) == 0 ? 12 : (hour % 12);
  final suffix = isAm ? 'AM' : 'PM';
  return '$hour12:$minute $suffix';
}

class _MonthlyPanel extends StatelessWidget {
  const _MonthlyPanel({
    required this.monthDate,
    required this.selectedMonthIndex,
    required this.onSelectMonthIndex,
    required this.selectedDate,
    required this.onSelectDate,
    required this.monthlyForecast,
  });

  final DateTime monthDate;
  final int selectedMonthIndex;
  final ValueChanged<int> onSelectMonthIndex;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelectDate;
  final Future<List<WeatherDailyForecast>> monthlyForecast;

  static const Color _navy = Colors.white;
  static const Color _panel = Color(0xFFF5F9FF);
  static const Color _tileBorder = Color(0xFFC9DBF8);
  static const Color _text = Color(0xFF0F172A);

  @override
  Widget build(BuildContext context) {
    final monthName = _monthLabel(selectedMonthIndex);
    final monthDays = _buildCalendarDays(monthDate);

    return FutureBuilder<List<WeatherDailyForecast>>(
      future: monthlyForecast,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <WeatherDailyForecast>[];
        final byDay = <String, WeatherDailyForecast>{
          for (final d in data) _ymdKey(d.date): d,
        };

        final availableStart = data.isEmpty ? null : data.first.date;
        final availableEnd = data.isEmpty ? null : data.last.date;
        final availableLabel = (availableStart != null && availableEnd != null)
            ? '${_monthLabel(availableStart.month - 1)} ${availableStart.day} – ${_monthLabel(availableEnd.month - 1)} ${availableEnd.day}'
            : null;

        final monthForecast = data.where((d) {
          return d.date.year == monthDate.year && d.date.month == monthDate.month;
        }).toList();

        final (sunnyCount, rainyCount, avgHigh, avgLow) =
            _computeMonthlyStats(monthForecast);

        final hasMonthData = monthForecast.isNotEmpty;

        final String note;
        if (snapshot.connectionState == ConnectionState.waiting) {
          note = 'Loading monthly forecast…';
        } else if (snapshot.hasError) {
          final err = snapshot.error;
          if (err is StateError) {
            if (err.message.contains('VISUAL_CROSSING_API_KEY')) {
              note = 'Monthly forecast unavailable (API key not set).';
            } else {
              note = err.message;
            }
          } else {
            note =
                'Monthly forecast unavailable. Please check your internet connection.';
          }
        } else if (hasMonthData) {
          note = availableLabel != null
              ? 'Based on ${monthForecast.length} days. Range: $availableLabel'
              : 'Based on ${monthForecast.length} days.';
        } else {
          note = availableLabel != null
              ? 'No data for this month. Available: $availableLabel'
              : 'No data for this month.';
        }

        return GlassCard(
          color: _navy,
          borderRadius: 18,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Monthly',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: _text,
                    ),
              ),
              const SizedBox(height: 12),
              _MonthTabs(
                selectedMonthIndex: selectedMonthIndex,
                onSelectMonthIndex: onSelectMonthIndex,
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _tileBorder),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        note,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF334155),
                            ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: const [
                        Expanded(child: _WeekdayLabel('Sun')),
                        Expanded(child: _WeekdayLabel('Mon')),
                        Expanded(child: _WeekdayLabel('Tue')),
                        Expanded(child: _WeekdayLabel('Wed')),
                        Expanded(child: _WeekdayLabel('Thu')),
                        Expanded(child: _WeekdayLabel('Fri')),
                        Expanded(child: _WeekdayLabel('Sat')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.10,
                      ),
                      itemCount: monthDays.length,
                      itemBuilder: (context, index) {
                        final day = monthDays[index];
                        final forecast = byDay[_ymdKey(day)];
                        final isInMonth = day.month == monthDate.month;
                        final isSelected = selectedDate != null &&
                            _ymdKey(selectedDate!) == _ymdKey(day);

                        return _CalendarDayCell(
                          date: day,
                          isInMonth: isInMonth,
                          isSelected: isSelected,
                          forecast: forecast,
                          onTap: () => onSelectDate(day),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _WeatherOverviewCard(
                monthLabel: monthName,
                year: monthDate.year,
                sunnyOrCloudyDays: hasMonthData ? sunnyCount : 0,
                rainyOrSnowDays: hasMonthData ? rainyCount : 0,
                averageHighC: hasMonthData ? avgHigh : null,
                averageLowC: hasMonthData ? avgLow : null,
                note: note,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MonthTabs extends StatelessWidget {
  const _MonthTabs({
    required this.selectedMonthIndex,
    required this.onSelectMonthIndex,
  });

  final int selectedMonthIndex;
  final ValueChanged<int> onSelectMonthIndex;

  @override
  Widget build(BuildContext context) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, idx) {
          final selected = idx == selectedMonthIndex;
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelectMonthIndex(idx),
            child: Container(
              width: 66,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFFACC15)
                    : const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFFACC15)
                      : const Color(0xFFC9DBF8),
                ),
              ),
              child: Text(
                months[idx],
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: selected
                          ? Colors.black.withValues(alpha: 0.85)
                          : const Color(0xFF334155),
                    ),
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: months.length,
      ),
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: const Color(0xFF64748B),
          ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.isInMonth,
    required this.isSelected,
    required this.forecast,
    required this.onTap,
  });

  final DateTime date;
  final bool isInMonth;
  final bool isSelected;
  final WeatherDailyForecast? forecast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = isInMonth;
    final hasData = forecast != null;
    final bg = isSelected
        ? const Color(0xFFFACC15).withValues(alpha: 0.12)
        : const Color(0xFFEAF2FF);

    final borderColor = isSelected
        ? const Color(0xFFFACC15)
        : const Color(0xFFC9DBF8);
    final borderWidth = isSelected ? 2.0 : 1.0;

    final popPct = forecast?.pop != null ? (forecast!.pop! * 100).round() : null;
    final humidity = forecast?.humidity;
    final windKmh = forecast?.windSpeedMs != null
        ? (forecast!.windSpeedMs! * 3.6).round()
        : null;

    final textColor = enabled
        ? (hasData
            ? const Color(0xFF0F172A)
            : const Color(0xFF64748B))
        : const Color(0xFF334155);

    final iconAlpha = enabled ? 1.0 : 0.35;

    Widget child = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? onTap : null,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${date.day}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: textColor,
                  ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: forecast == null
                  ? Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        '--',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF475569),
                            ),
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Opacity(
                            opacity: iconAlpha,
                            child: _WeatherGlyph(condition: forecast!.condition),
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${forecast!.maxTempC.round()}°',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: textColor,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${forecast!.minTempC.round()}°',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF64748B),
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );

    if (enabled && forecast != null) {
      final tooltipLines = <String>[
        'Chance: ${popPct != null ? '$popPct%' : '--'}',
        'High/Low: ${forecast!.maxTempC.round()}° / ${forecast!.minTempC.round()}°',
        'Humidity: ${humidity != null ? '$humidity%' : '--'}',
        'Wind: ${windKmh != null ? '$windKmh km/h' : '--'}',
      ];

      child = Tooltip(
        waitDuration: const Duration(milliseconds: 120),
        showDuration: const Duration(seconds: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
        message: tooltipLines.join('\n'),
        child: child,
      );
    }

    return child;
  }
}

class _WeatherOverviewCard extends StatelessWidget {
  const _WeatherOverviewCard({
    required this.monthLabel,
    required this.year,
    required this.sunnyOrCloudyDays,
    required this.rainyOrSnowDays,
    required this.averageHighC,
    required this.averageLowC,
    this.note,
  });

  final String monthLabel;
  final int year;
  final int sunnyOrCloudyDays;
  final int rainyOrSnowDays;
  final int? averageHighC;
  final int? averageLowC;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final total = sunnyOrCloudyDays + rainyOrSnowDays;
    final sunnyValue = total == 0 ? 1.0 : sunnyOrCloudyDays.toDouble();
    final rainyValue = total == 0 ? 1.0 : rainyOrSnowDays.toDouble();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F9FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC9DBF8)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weather overview',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 0,
                        centerSpaceRadius: 42,
                        startDegreeOffset: -90,
                        sections: [
                          PieChartSectionData(
                            value: sunnyValue,
                            color: const Color(0xFFF59E0B),
                            showTitle: false,
                            radius: 18,
                          ),
                          PieChartSectionData(
                            value: rainyValue,
                            color: const Color(0xFF0EA5E9),
                            showTitle: false,
                            radius: 18,
                          ),
                        ],
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$year',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF64748B),
                                ),
                          ),
                          Text(
                            monthLabel,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF0F172A),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OverviewRow(
                      color: const Color(0xFFF59E0B),
                      label: 'Sunny/Cloudy days',
                      value: '$sunnyOrCloudyDays',
                    ),
                    const SizedBox(height: 10),
                    _OverviewRow(
                      color: const Color(0xFF0EA5E9),
                      label: 'Rain/Snow days',
                      value: '$rainyOrSnowDays',
                    ),
                    const SizedBox(height: 10),
                    _OverviewRow(
                      color: const Color(0xFF94A3B8),
                      label: 'Average high',
                      value: averageHighC != null ? '${averageHighC!}°' : '--',
                    ),
                    const SizedBox(height: 10),
                    _OverviewRow(
                      color: const Color(0xFF94A3B8),
                      label: 'Average low',
                      value: averageLowC != null ? '${averageLowC!}°' : '--',
                    ),
                    if (note != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        note!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF64748B),
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  const _OverviewRow({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF334155),
                ),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F172A),
              ),
        ),
      ],
    );
  }
}

String _ymdKey(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String _monthLabel(int monthIndex) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[monthIndex.clamp(0, 11)];
}

List<DateTime> _buildCalendarDays(DateTime monthDate) {
  final first = DateTime(monthDate.year, monthDate.month, 1);
  final firstWeekday = first.weekday % 7;
  final start = first.subtract(Duration(days: firstWeekday));
  final last = DateTime(monthDate.year, monthDate.month + 1, 0);
  final lastWeekday = last.weekday % 7;
  final end = last.add(Duration(days: 6 - lastWeekday));
  final result = <DateTime>[];
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    result.add(d);
  }
  return result;
}

(int sunnyCount, int rainyCount, int? avgHigh, int? avgLow)
    _computeMonthlyStats(List<WeatherDailyForecast> monthForecast) {
  var sunny = 0;
  var rainy = 0;
  var highSum = 0.0;
  var lowSum = 0.0;

  for (final d in monthForecast) {
    final v = d.condition.toLowerCase();
    if (v.contains('rain') ||
        v.contains('drizzle') ||
        v.contains('thunder') ||
        v.contains('snow')) {
      rainy += 1;
    } else {
      sunny += 1;
    }
    highSum += d.maxTempC;
    lowSum += d.minTempC;
  }

  if (monthForecast.isEmpty) {
    return (0, 0, null, null);
  }

  final avgHigh = (highSum / monthForecast.length).round();
  final avgLow = (lowSum / monthForecast.length).round();
  return (sunny, rainy, avgHigh, avgLow);
}

_IconSpec _conditionToIconSpec(String raw) {
  final v = raw.toLowerCase();
  if (v.contains('thunder')) {
    return const _IconSpec(Icons.thunderstorm_outlined, Color(0xFF64748B));
  }
  if (v.contains('rain') || v.contains('drizzle')) {
    return const _IconSpec(Icons.grain_outlined, Color(0xFF3B82F6));
  }
  if (v.contains('snow')) {
    return const _IconSpec(Icons.ac_unit_outlined, Color(0xFF60A5FA));
  }
  if (v.contains('clear') || v.contains('sun')) {
    return const _IconSpec(Icons.wb_sunny_outlined, Color(0xFFF59E0B));
  }
  if (v.contains('cloud')) {
    return const _IconSpec(Icons.wb_cloudy_outlined, Color(0xFF60A5FA));
  }
  if (v.contains('mist') || v.contains('fog') || v.contains('haze')) {
    return const _IconSpec(Icons.blur_on, Color(0xFF94A3B8));
  }
  return const _IconSpec(Icons.wb_cloudy_outlined, Color(0xFF94A3B8));
}

class _WeatherGlyph extends StatelessWidget {
  const _WeatherGlyph({required this.condition});

  final String condition;

  @override
  Widget build(BuildContext context) {
    final v = condition.toLowerCase();
    final isRain = v.contains('rain') || v.contains('drizzle') || v.contains('thunder');
    final isClear = v.contains('clear') || v.contains('sun');
    final isCloud = v.contains('cloud') || v.contains('mist') || v.contains('fog') || v.contains('haze');

    if (isRain) {
      return const SizedBox(
        width: 46,
        height: 46,
        child: _RainGlyph(),
      );
    }

    if (isClear && !isCloud) {
      return const SizedBox(
        width: 46,
        height: 46,
        child: _SunGlyph(),
      );
    }

    if (isClear && isCloud) {
      return const SizedBox(
        width: 46,
        height: 46,
        child: _PartlyCloudyGlyph(),
      );
    }

    return const SizedBox(
      width: 46,
      height: 46,
      child: _CloudGlyph(),
    );
  }
}

class _SunGlyph extends StatelessWidget {
  const _SunGlyph();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
          ),
        ),
      ),
    );
  }
}

class _CloudGlyph extends StatelessWidget {
  const _CloudGlyph();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          left: 7,
          bottom: 14,
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE6F0FF), Color(0xFF9CC2FF)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 18,
          bottom: 18,
          child: Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE6F0FF), Color(0xFF9CC2FF)],
              ),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 15,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE6F0FF), Color(0xFF9CC2FF)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 12,
          child: Container(
            height: 18,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFE6F0FF), Color(0xFF9CC2FF)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PartlyCloudyGlyph extends StatelessWidget {
  const _PartlyCloudyGlyph();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned(
          left: 4,
          top: 6,
          child: SizedBox(width: 28, height: 28, child: _SunGlyph()),
        ),
        const Positioned(
          left: 8,
          right: 0,
          bottom: 0,
          child: SizedBox(width: 46, height: 46, child: _CloudGlyph()),
        ),
      ],
    );
  }
}

class _RainGlyph extends StatelessWidget {
  const _RainGlyph();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: _CloudGlyph(),
          ),
        ),
        Positioned(
          left: 16,
          bottom: 4,
          child: _drop(),
        ),
        Positioned(
          left: 24,
          bottom: 2,
          child: _drop(),
        ),
        Positioned(
          left: 32,
          bottom: 4,
          child: _drop(),
        ),
      ],
    );
  }

  Widget _drop() {
    return Container(
      width: 7,
      height: 10,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
        ),
      ),
    );
  }
}

class _IconSpec {
  const _IconSpec(this.icon, this.color);

  final IconData icon;
  final Color color;
}

class _WeatherScreenData {
  _WeatherScreenData({
    required this.cityLabel,
    required this.now,
    required this.daily,
    required this.today,
    required this.tomorrow,
    required this.hourlyToday,
    required this.hourlyTomorrow,
  });

  final String cityLabel;
  final WeatherNow now;
  final List<WeatherDailyForecast> daily;
  final WeatherDailyForecast? today;
  final WeatherDailyForecast? tomorrow;
  final List<WeatherHourlyForecast> hourlyToday;
  final List<WeatherHourlyForecast> hourlyTomorrow;
}

class _WeatherMapsPanel extends StatefulWidget {
  const _WeatherMapsPanel({
    required this.cityLabel,
    required this.lat,
    required this.lon,
    required this.selectedLayer,
    required this.onSelectLayer,
  });

  final String cityLabel;
  final double? lat;
  final double? lon;
  final WeatherMapLayer selectedLayer;
  final ValueChanged<WeatherMapLayer> onSelectLayer;

  @override
  State<_WeatherMapsPanel> createState() => _WeatherMapsPanelState();
}

class _WeatherMapsPanelState extends State<_WeatherMapsPanel> {
  final MapController _mapController = MapController();
  Timer? _reverseGeocodeDebounce;
  String? _placeLabel;
  bool _geoTagMode = false;
  String? _selectedProjectId;
  String? _selectedProjectName;
  LatLng? _pendingProjectLatLng;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ll = _mapController.camera.center;
      _scheduleReverseGeocode(ll.latitude, ll.longitude);
    });
  }

  @override
  void dispose() {
    _reverseGeocodeDebounce?.cancel();
    super.dispose();
  }

  void _scheduleReverseGeocode(double lat, double lon) {
    _reverseGeocodeDebounce?.cancel();
    _reverseGeocodeDebounce = Timer(const Duration(milliseconds: 650),
        () async {
      try {
        final label = await WeatherService.instance
            .reverseGeocode(lat: lat, lon: lon);
        if (!mounted) return;
        setState(() {
          _placeLabel = label;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _placeLabel = null;
        });
      }
    });
  }

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    _mapController.move(camera.center, camera.zoom + delta);
  }

  double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  Future<void> _saveProjectLocation() async {
    final id = _selectedProjectId;
    final ll = _pendingProjectLatLng;
    if (id == null || ll == null) return;
    try {
      String? label;
      try {
        label = await WeatherService.instance
            .reverseGeocode(lat: ll.latitude, lon: ll.longitude);
      } catch (_) {
        label = _placeLabel;
      }

      await FirebaseService.instance.projectsCollection.doc(id).update({
        'latitude': ll.latitude,
        'longitude': ll.longitude,
        'geoAddress': (label ?? '').trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project location saved.')),
      );
      setState(() {
        _geoTagMode = false;
        _pendingProjectLatLng = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save project location: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const fallbackCenter = LatLng(14.5995, 120.9842);
    final center = (widget.lat != null && widget.lon != null)
        ? LatLng(widget.lat!, widget.lon!)
        : fallbackCenter;

    final overlayUrl =
        WeatherService.instance.getWeatherTileUrlTemplate(widget.selectedLayer);

    final currentUser = AuthService.instance.currentUser;
    final canGeoTag = currentUser?.isAdmin == true;

    return GlassCard(
      color: Colors.white,
      borderRadius: 18,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Weather maps',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                ),
              ),
              _MapLayerButton(
                label: 'Temp',
                selected: widget.selectedLayer == WeatherMapLayer.temperature,
                onTap: () => widget.onSelectLayer(WeatherMapLayer.temperature),
              ),
              const SizedBox(width: 8),
              _MapLayerButton(
                label: 'Precip',
                selected:
                    widget.selectedLayer == WeatherMapLayer.precipitation,
                onTap: () =>
                    widget.onSelectLayer(WeatherMapLayer.precipitation),
              ),
              const SizedBox(width: 8),
              _MapLayerButton(
                label: 'Wind',
                selected: widget.selectedLayer == WeatherMapLayer.wind,
                onTap: () => widget.onSelectLayer(WeatherMapLayer.wind),
              ),
              const SizedBox(width: 8),
              _MapLayerButton(
                label: 'Clouds',
                selected: widget.selectedLayer == WeatherMapLayer.clouds,
                onTap: () => widget.onSelectLayer(WeatherMapLayer.clouds),
              ),
              if (canGeoTag) ...[
                const SizedBox(width: 10),
                IconButton(
                  tooltip: _geoTagMode ? 'Exit geo-tag mode' : 'Geo-tag projects',
                  onPressed: () {
                    final nextMode = !_geoTagMode;
                    final currentCenter = _mapController.camera.center;
                    final target = nextMode
                        ? (_pendingProjectLatLng ?? currentCenter)
                        : null;

                    setState(() {
                      _geoTagMode = nextMode;
                      _pendingProjectLatLng = target;
                    });

                    if (nextMode && target != null) {
                      final zoom = (_mapController.camera.zoom < 14
                              ? 14.0
                              : _mapController.camera.zoom)
                          .clamp(7.0, 16.0);
                      _mapController.move(target, zoom);
                    }
                  },
                  icon: Icon(
                    _geoTagMode ? Icons.gps_off_rounded : Icons.my_location,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ],
          ),
          if (_geoTagMode && canGeoTag) ...[
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.instance.projectsCollection
                  .limit(200)
                  .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? const [];
                final items = docs
                    .map((d) {
                      final data =
                          (d.data() as Map?)?.cast<String, dynamic>() ??
                              <String, dynamic>{};
                      final name = (data['name'] ?? '').toString().trim();
                      if (name.isEmpty) return null;
                      return DropdownMenuItem<String>(
                        value: d.id,
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      );
                    })
                    .whereType<DropdownMenuItem<String>>()
                    .toList();

                if (_selectedProjectId == null && items.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (_selectedProjectId != null) return;
                    final firstDoc = docs.first;
                    final data =
                        (firstDoc.data() as Map?)?.cast<String, dynamic>() ??
                            <String, dynamic>{};
                    final name = (data['name'] ?? '').toString().trim();
                    final lat = _toDouble(data['latitude']);
                    final lon = _toDouble(data['longitude']);
                    final saved = (lat != null && lon != null)
                        ? LatLng(lat, lon)
                        : null;

                    setState(() {
                      _selectedProjectId = firstDoc.id;
                      _selectedProjectName = name;
                      _pendingProjectLatLng = saved ?? _mapController.camera.center;
                    });

                    if (saved != null) {
                      final zoom = (_mapController.camera.zoom < 14
                              ? 14.0
                              : _mapController.camera.zoom)
                          .clamp(7.0, 16.0);
                      _mapController.move(saved, zoom);
                      _scheduleReverseGeocode(saved.latitude, saved.longitude);
                    }
                  });
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: items.any((e) => e.value == _selectedProjectId)
                          ? _selectedProjectId
                          : null,
                      items: items,
                      onChanged: (v) {
                        if (v == null) return;
                        final doc = docs.firstWhere(
                          (e) => e.id == v,
                          orElse: () => docs.first,
                        );
                        final data =
                            (doc.data() as Map?)?.cast<String, dynamic>() ??
                                <String, dynamic>{};
                        final lat = _toDouble(data['latitude']);
                        final lon = _toDouble(data['longitude']);
                        final saved = (lat != null && lon != null)
                            ? LatLng(lat, lon)
                            : null;
                        setState(() {
                          _selectedProjectId = v;
                          _selectedProjectName =
                              (data['name'] ?? '').toString().trim();
                          _pendingProjectLatLng = saved ?? _mapController.camera.center;
                        });

                        if (saved != null) {
                          final zoom = (_mapController.camera.zoom < 14
                                  ? 14.0
                                  : _mapController.camera.zoom)
                              .clamp(7.0, 16.0);
                          _mapController.move(saved, zoom);
                          _scheduleReverseGeocode(saved.latitude, saved.longitude);
                        } else {
                          final c = _mapController.camera.center;
                          _scheduleReverseGeocode(c.latitude, c.longitude);
                        }
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      hint: const Text('Select project to tag'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _pendingProjectLatLng == null
                          ? 'Move the map to the exact spot, then press "Set to map center".'
                          : ((_placeLabel != null && _placeLabel!.trim().isNotEmpty)
                              ? 'Selected: ${_placeLabel!.trim()}'
                              : 'Selected: ${_pendingProjectLatLng!.latitude.toStringAsFixed(5)}, ${_pendingProjectLatLng!.longitude.toStringAsFixed(5)}'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: FilledButton.icon(
                        onPressed: _selectedProjectId == null
                            ? null
                            : () {
                                final c = _mapController.camera.center;
                                setState(() {
                                  _pendingProjectLatLng = c;
                                });
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.center_focus_strong, size: 18),
                        label: const Text(
                          'Set to map center',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: FilledButton(
                        onPressed: (_selectedProjectId != null &&
                                _pendingProjectLatLng != null)
                            ? _saveProjectLocation
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Save location',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 320,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 7,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                      onTap: (tapPos, ll) {
                        if (!_geoTagMode) return;
                        if (_selectedProjectId == null) return;
                        setState(() {
                          _pendingProjectLatLng = ll;
                        });
                        _scheduleReverseGeocode(ll.latitude, ll.longitude);
                      },
                      onLongPress: (tapPos, ll) {
                        if (!_geoTagMode) return;
                        if (_selectedProjectId == null) return;
                        setState(() {
                          _pendingProjectLatLng = ll;
                        });
                        _scheduleReverseGeocode(ll.latitude, ll.longitude);
                      },
                      onMapEvent: (evt) {
                        if (evt is MapEventMoveEnd || evt is MapEventFlingAnimationEnd) {
                          final c = _mapController.camera.center;
                          _scheduleReverseGeocode(c.latitude, c.longitude);
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'coecons',
                        tileProvider: CancellableNetworkTileProvider(),
                      ),
                      TileLayer(
                        urlTemplate: overlayUrl,
                        tileProvider: CancellableNetworkTileProvider(),
                        tileBuilder: (context, widget, tile) {
                          return Opacity(opacity: 0.65, child: widget);
                        },
                      ),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseService.instance.projectsCollection
                            .limit(400)
                            .snapshots(),
                        builder: (context, snap) {
                          final docs = snap.data?.docs ?? const [];
                          final markers = <Marker>[];
                          for (final d in docs) {
                            final data =
                                (d.data() as Map?)?.cast<String, dynamic>() ??
                                    <String, dynamic>{};
                            final lat = _toDouble(data['latitude']);
                            final lon = _toDouble(data['longitude']);
                            if (lat == null || lon == null) continue;
                            final name =
                                (data['name'] ?? 'Project').toString().trim();
                            final addr = (data['geoAddress'] ?? '').toString().trim();
                            markers.add(
                              Marker(
                                point: LatLng(lat, lon),
                                width: 46,
                                height: 46,
                                child: InkWell(
                                  onTap: () async {
                                    _mapController.move(LatLng(lat, lon),
                                        (_mapController.camera.zoom).clamp(7, 13));
                                    String? label = addr;
                                    if (label.isEmpty) {
                                      try {
                                        label = await WeatherService.instance
                                            .reverseGeocode(lat: lat, lon: lon);
                                      } catch (_) {
                                        label = '';
                                      }
                                    }
                                    if (!context.mounted) return;
                                    final msg = (label != null && label.trim().isNotEmpty)
                                        ? '$name\n${label.trim()}'
                                        : name;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(msg),
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  },
                                  child: const Icon(
                                    Icons.location_on,
                                    color: Color(0xFFDC2626),
                                    size: 40,
                                  ),
                                ),
                              ),
                            );
                          }
                          if (_pendingProjectLatLng != null) {
                            markers.add(
                              Marker(
                                point: _pendingProjectLatLng!,
                                width: 46,
                                height: 46,
                                child: const Icon(
                                  Icons.place,
                                  color: Color(0xFF2563EB),
                                  size: 40,
                                ),
                              ),
                            );
                          }
                          if (markers.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return MarkerLayer(markers: markers);
                        },
                      ),
                      RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution(
                            '© OpenStreetMap contributors',
                            onTap: () {},
                          ),
                          TextSourceAttribution(
                            '© OpenWeather',
                            onTap: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Column(
                      children: [
                        _ZoomButton(
                          icon: Icons.add,
                          onTap: () => _zoomBy(1),
                        ),
                        const SizedBox(height: 8),
                        _ZoomButton(
                          icon: Icons.remove,
                          onTap: () => _zoomBy(-1),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFFC9DBF8),
                        ),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 12,
                            color: Colors.black.withValues(alpha: 0.30),
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.place,
                            size: 16,
                            color: const Color(0xFF334155),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            (_placeLabel?.isNotEmpty ?? false)
                                ? _placeLabel!
                                : widget.cityLabel,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF0F172A),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_geoTagMode && _selectedProjectId != null)
                    const Center(
                      child: IgnorePointer(
                        child: Icon(
                          Icons.add_circle_outline,
                          size: 34,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.cityLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC9DBF8)),
            boxShadow: [
              BoxShadow(
                blurRadius: 12,
                color: Colors.black.withValues(alpha: 0.30),
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(icon, color: const Color(0xFF0F172A)),
        ),
      ),
    );
  }
}

class _MapLayerButton extends StatelessWidget {
  const _MapLayerButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFBFDBFE)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: Colors.black.withValues(alpha: 0.70),
              ),
        ),
      ),
    );
  }
}
