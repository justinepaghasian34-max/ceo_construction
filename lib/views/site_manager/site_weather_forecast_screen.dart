import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/site_weather_provider.dart';
import '../../services/auth_service.dart';
import '../../services/weather_service.dart';
import 'widgets/site_manager_card.dart';
import 'widgets/site_manager_bottom_nav.dart';

/// Full weather detail screen for the Resident Engineer.
/// Shows current conditions, 7-day forecast, and an interactive map
/// centred on the assigned project site.
class SiteWeatherForecastScreen extends ConsumerStatefulWidget {
  const SiteWeatherForecastScreen({super.key});

  @override
  ConsumerState<SiteWeatherForecastScreen> createState() =>
      _SiteWeatherForecastScreenState();
}

class _SiteWeatherForecastScreenState
    extends ConsumerState<SiteWeatherForecastScreen> {
  final MapController _mapController = MapController();
  WeatherMapLayer _layer = WeatherMapLayer.precipitation;
  List<WeatherDailyForecast>? _forecast;
  bool _forecastLoading = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadForecast(double lat, double lon) async {
    if (_forecastLoading) return;
    setState(() => _forecastLoading = true);
    try {
      final f = await WeatherService.instance
          .getHourlyForecastByCoordinatesAndDate(
        lat: lat,
        lon: lon,
        date: DateTime.now(),
      );
      // Convert hourly to daily summaries (group by date).
      final Map<DateTime, List<WeatherHourlyForecast>> byDay = {};
      for (final h in f) {
        final d = DateTime(h.dateTime.year, h.dateTime.month, h.dateTime.day);
        byDay.putIfAbsent(d, () => []).add(h);
      }
      final daily = byDay.entries.take(7).map((e) {
        final temps = e.value.map((h) => h.tempC).toList();
        final minT = temps.reduce((a, b) => a < b ? a : b);
        final maxT = temps.reduce((a, b) => a > b ? a : b);
        final cond = e.value.first.condition;
        return WeatherDailyForecast(
          date: e.key,
          minTempC: minT,
          maxTempC: maxT,
          condition: cond,
        );
      }).toList();
      if (mounted) setState(() => _forecast = daily);
    } catch (_) {
      // forecast unavailable — silently ignore
    } finally {
      if (mounted) setState(() => _forecastLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final projectId =
        (user?.assignedProjects.isNotEmpty == true)
            ? user!.assignedProjects.first
            : null;

    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      appBar: AppBar(
        title: const Text('Site Weather'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      bottomNavigationBar: const SiteManagerBottomNav(currentIndex: 0),
      body: projectId == null
          ? const _NoProject()
          : _WeatherBody(
              projectId: projectId,
              mapController: _mapController,
              layer: _layer,
              forecast: _forecast,
              forecastLoading: _forecastLoading,
              onLayerChanged: (l) => setState(() => _layer = l),
              onWeatherLoaded: _loadForecast,
            ),
    );
  }
}

// ── Body ────────────────────────────────────────────────────────────────────

class _WeatherBody extends ConsumerWidget {
  const _WeatherBody({
    required this.projectId,
    required this.mapController,
    required this.layer,
    required this.forecast,
    required this.forecastLoading,
    required this.onLayerChanged,
    required this.onWeatherLoaded,
  });

  final String projectId;
  final MapController mapController;
  final WeatherMapLayer layer;
  final List<WeatherDailyForecast>? forecast;
  final bool forecastLoading;
  final ValueChanged<WeatherMapLayer> onLayerChanged;
  final Future<void> Function(double lat, double lon) onWeatherLoaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherAsync = ref.watch(singleSiteWeatherProvider(projectId));

    return weatherAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load weather data.\n$e',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (siteWeather) {
        if (siteWeather == null) {
          return const _NoLocation();
        }

        // Kick off forecast load once.
        Future.microtask(
            () => onWeatherLoaded(siteWeather.lat, siteWeather.lon));

        final w = siteWeather.weather;
        final isRaining = siteWeather.isRaining;
        final isCloudy = siteWeather.isCloudy;
        final accentColor = isRaining
            ? const Color(0xFF3B82F6)
            : isCloudy
                ? AppTheme.mediumGray
                : AppTheme.warningOrange;
        final weatherIcon = isRaining
            ? Icons.grain
            : isCloudy
                ? Icons.cloud_outlined
                : Icons.wb_sunny_outlined;

        return ListView(
          padding: EdgeInsets.only(
            bottom: 24 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            // ── Hero current conditions ──────────────────────────────────
            _CurrentConditionsHero(
              siteWeather: siteWeather,
              accentColor: accentColor,
              weatherIcon: weatherIcon,
            ),
            const SizedBox(height: 16),

            // ── Detail chips ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _DetailsRow(weather: w),
            ),
            const SizedBox(height: 16),

            // ── Rain alert ───────────────────────────────────────────────
            if (isRaining)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _RainAlertBanner(projectName: siteWeather.projectName),
              ),
            if (isRaining) const SizedBox(height: 16),

            // ── Interactive map ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _MapCard(
                lat: siteWeather.lat,
                lon: siteWeather.lon,
                projectName: siteWeather.projectName,
                location: siteWeather.location,
                mapController: mapController,
                layer: layer,
                onLayerChanged: onLayerChanged,
                accentColor: accentColor,
                weatherIcon: weatherIcon,
              ),
            ),
            const SizedBox(height: 16),

            // ── 7-day forecast ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ForecastCard(
                forecast: forecast,
                loading: forecastLoading,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Current conditions hero ─────────────────────────────────────────────────

class _CurrentConditionsHero extends StatelessWidget {
  const _CurrentConditionsHero({
    required this.siteWeather,
    required this.accentColor,
    required this.weatherIcon,
  });

  final ProjectSiteWeather siteWeather;
  final Color accentColor;
  final IconData weatherIcon;

  @override
  Widget build(BuildContext context) {
    final w = siteWeather.weather;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.85),
            accentColor.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      siteWeather.projectName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (siteWeather.location.isNotEmpty)
                      Text(
                        siteWeather.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(weatherIcon, color: Colors.white, size: 52),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${w.temperatureC.toStringAsFixed(0)}°C',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 52,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            siteWeather.conditionLabel +
                (w.description.isNotEmpty ? ' · ${w.description}' : ''),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (w.feelsLikeC != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Feels like ${w.feelsLikeC!.toStringAsFixed(0)}°C',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.80),
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Detail chips row ────────────────────────────────────────────────────────

class _DetailsRow extends StatelessWidget {
  const _DetailsRow({required this.weather});
  final WeatherNow weather;

  @override
  Widget build(BuildContext context) {
    final windKmh = weather.windSpeedMs != null
        ? '${(weather.windSpeedMs! * 3.6).round()} km/h'
        : null;
    final vis = weather.visibilityKm != null
        ? '${weather.visibilityKm!.toStringAsFixed(0)} km'
        : null;

    final chips = <_Chip>[
      if (weather.humidity != null)
        _Chip(
            icon: Icons.water_drop_outlined,
            label: 'Humidity',
            value: '${weather.humidity}%',
            color: const Color(0xFF60A5FA)),
      if (windKmh != null)
        _Chip(
            icon: Icons.air_outlined,
            label: 'Wind',
            value: windKmh,
            color: AppTheme.mediumGray),
      if (vis != null)
        _Chip(
            icon: Icons.visibility_outlined,
            label: 'Visibility',
            value: vis,
            color: AppTheme.softGreen),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return SiteManagerCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        children: chips
            .map((c) => _ChipWidget(chip: c))
            .toList(),
      ),
    );
  }
}

class _Chip {
  const _Chip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
}

class _ChipWidget extends StatelessWidget {
  const _ChipWidget({required this.chip});
  final _Chip chip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: chip.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: chip.color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(chip.icon, size: 16, color: chip.color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chip.label,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.mediumGray),
              ),
              Text(
                chip.value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: chip.color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Rain alert banner ────────────────────────────────────────────────────────

class _RainAlertBanner extends StatelessWidget {
  const _RainAlertBanner({required this.projectName});
  final String projectName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.grain, color: Color(0xFF3B82F6), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rain Alert',
                  style: TextStyle(
                    color: Color(0xFF1D4ED8),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Rain has been detected at $projectName. '
                  'The admin has been notified automatically.',
                  style: const TextStyle(
                    color: Color(0xFF1D4ED8),
                    fontSize: 12,
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

// ── Map card ─────────────────────────────────────────────────────────────────

class _MapCard extends StatelessWidget {
  const _MapCard({
    required this.lat,
    required this.lon,
    required this.projectName,
    required this.location,
    required this.mapController,
    required this.layer,
    required this.onLayerChanged,
    required this.accentColor,
    required this.weatherIcon,
  });

  final double lat;
  final double lon;
  final String projectName;
  final String location;
  final MapController mapController;
  final WeatherMapLayer layer;
  final ValueChanged<WeatherMapLayer> onLayerChanged;
  final Color accentColor;
  final IconData weatherIcon;

  @override
  Widget build(BuildContext context) {
    final tileUrl =
        WeatherService.instance.getWeatherTileUrlTemplate(layer);

    return SiteManagerCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.map_outlined,
                    size: 16, color: AppTheme.residentBlue),
                const SizedBox(width: 8),
                Text(
                  'Project Site Map',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
                // Layer toggle
                _LayerChip(
                  label: 'Rain',
                  active: layer == WeatherMapLayer.precipitation,
                  onTap: () => onLayerChanged(WeatherMapLayer.precipitation),
                ),
                const SizedBox(width: 6),
                _LayerChip(
                  label: 'Clouds',
                  active: layer == WeatherMapLayer.clouds,
                  onTap: () => onLayerChanged(WeatherMapLayer.clouds),
                ),
                const SizedBox(width: 6),
                _LayerChip(
                  label: 'Temp',
                  active: layer == WeatherMapLayer.temperature,
                  onTap: () => onLayerChanged(WeatherMapLayer.temperature),
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(22),
            ),
            child: SizedBox(
              height: 260,
              child: FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: LatLng(lat, lon),
                  initialZoom: 13,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    tileProvider: CancellableNetworkTileProvider(),
                    userAgentPackageName:
                        'com.ceoconstruction.monitoring',
                  ),
                  TileLayer(
                    urlTemplate: tileUrl,
                    tileProvider: CancellableNetworkTileProvider(),
                    userAgentPackageName:
                        'com.ceoconstruction.monitoring',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(lat, lon),
                        width: 56,
                        height: 70,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: accentColor,
                                boxShadow: [
                                  BoxShadow(
                                    color: accentColor.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(weatherIcon,
                                  color: Colors.white, size: 20),
                            ),
                            // Pin tail
                            Container(
                              width: 2,
                              height: 14,
                              color: accentColor,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Address label under map
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: AppTheme.mediumGray),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    location.isNotEmpty ? location : projectName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.mediumGray,
                          fontWeight: FontWeight.w600,
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
}

class _LayerChip extends StatelessWidget {
  const _LayerChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.residentBlue
              : AppTheme.residentBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppTheme.residentBlue,
          ),
        ),
      ),
    );
  }
}

// ── 7-day forecast card ─────────────────────────────────────────────────────

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.forecast, required this.loading});
  final List<WeatherDailyForecast>? forecast;
  final bool loading;

  static const _days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  Widget build(BuildContext context) {
    return SiteManagerCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '7-Day Forecast',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              ),
            )
          else if (forecast == null || forecast!.isEmpty)
            Text(
              'Forecast data unavailable.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.mediumGray),
            )
          else
            ...forecast!.map((day) => _ForecastRow(day: day, days: _days)),
        ],
      ),
    );
  }
}

class _ForecastRow extends StatelessWidget {
  const _ForecastRow({required this.day, required this.days});
  final WeatherDailyForecast day;
  final List<String> days;

  Color _conditionColor(String c) {
    final l = c.toLowerCase();
    if (l.contains('rain') || l.contains('thunder') || l.contains('drizzle')) {
      return const Color(0xFF3B82F6);
    }
    if (l.contains('cloud')) { return AppTheme.mediumGray; }
    return AppTheme.warningOrange;
  }

  IconData _conditionIcon(String c) {
    final l = c.toLowerCase();
    if (l.contains('rain') || l.contains('thunder') || l.contains('drizzle')) {
      return Icons.grain;
    }
    if (l.contains('cloud')) { return Icons.cloud_outlined; }
    return Icons.wb_sunny_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final color = _conditionColor(day.condition);
    final icon = _conditionIcon(day.condition);
    final dayLabel = days[day.date.weekday % 7];
    final isToday = day.date.day == DateTime.now().day &&
        day.date.month == DateTime.now().month;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              isToday ? 'Today' : dayLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isToday ? AppTheme.residentBlue : AppTheme.darkGray,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              day.condition.isEmpty ? '—' : day.condition,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            '${day.minTempC.toStringAsFixed(0)}° / '
            '${day.maxTempC.toStringAsFixed(0)}°C',
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

// ── Error states ─────────────────────────────────────────────────────────────

class _NoProject extends StatelessWidget {
  const _NoProject();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined,
                size: 56,
                color: AppTheme.mediumGray.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'No project assigned.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.mediumGray,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask your admin to assign you to a project first.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.mediumGray),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoLocation extends StatelessWidget {
  const _NoLocation();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_outlined,
                size: 56,
                color: AppTheme.mediumGray.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'No site location set.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.mediumGray,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'The admin needs to pin the project location '
              'on the weather map before weather data is available.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.mediumGray),
            ),
          ],
        ),
      ),
    );
  }
}
