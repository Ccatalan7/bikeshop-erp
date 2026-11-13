import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/weather_forecast.dart';
import '../../models/weather_outlook.dart';
import '../../services/weather_forecast_service.dart';
import '../../themes/vinabike_theme_roles.dart';
import '../briefing_section_header.dart';
import '../vb_segmented.dart';
import 'weather_glyph.dart';
import 'weather_hour_strip.dart';
import 'weather_meteogram.dart';

enum _WeatherView { hours, days }

/// The shop's weather inside the daily briefing: what it is like now, what
/// the next hours and days bring, and the one sentence that matters for the
/// day (when it rains).
///
/// It reads [WeatherForecastService], which answers from hand while the
/// server's forecast is current, so mounting this every time the briefing
/// opens costs nothing. [now] is the briefing's own clock: each of its ticks
/// is a chance to refresh, and nothing is asked while nobody looks.
class BriefingWeatherSection extends StatefulWidget {
  const BriefingWeatherSection({
    super.key,
    required this.now,
    this.padding = EdgeInsets.zero,
    this.detailed = false,
    this.service,
    this.onOpenIntegrations,
  });

  final DateTime now;

  /// Room around the section while it has something to show. With nothing to
  /// show it takes no room at all, so the briefing keeps no empty gap.
  final EdgeInsetsGeometry padding;

  /// The weather on its own tab: never folded, today first hour by hour
  /// (temperature, rain and wind of each hour) and the next days under it.
  final bool detailed;

  /// Defaults to the shared service.
  final WeatherForecastService? service;

  /// Opens the screen where the shop's Google listing is connected: its
  /// coordinates are the place of the forecast.
  final VoidCallback? onOpenIntegrations;

  @override
  State<BriefingWeatherSection> createState() => _BriefingWeatherSectionState();
}

class _BriefingWeatherSectionState extends State<BriefingWeatherSection> {
  static const _viewKey = 'briefing_weather_view';
  static const _collapsedKey = 'briefing_weather_collapsed';
  static const _placeKey = 'briefing_weather_place';

  /// Days first (owner, 2026-11-13); hours when the person chose them.
  _WeatherView _view = _WeatherView.days;
  bool _collapsed = false;
  bool _adding = false;
  int? _selected;

  WeatherForecastService get _service =>
      widget.service ?? WeatherForecastService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_restorePreferences());
    unawaited(_service.ensureFresh());
  }

  @override
  void didUpdateWidget(covariant BriefingWeatherSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.now != widget.now || oldWidget.service != widget.service) {
      unawaited(_service.ensureFresh());
    }
  }

  Future<void> _restorePreferences() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      final view = preferences.getString(_viewKey);
      final collapsed = preferences.getBool(_collapsedKey) ?? false;
      // The place this device was left on; the shop's own when it has none.
      final place = preferences.getString(_placeKey);
      if (widget.detailed && place != null && place.isNotEmpty) {
        _service.select(place);
      }
      if (view == _WeatherView.hours.name || collapsed) {
        setState(() {
          _view = view == _WeatherView.hours.name
              ? _WeatherView.hours
              : _WeatherView.days;
          _collapsed = collapsed;
        });
      }
    } catch (_) {
      // A preference that cannot be read leaves the defaults.
    }
  }

  Future<void> _remember(void Function(SharedPreferences) write) async {
    try {
      write(await SharedPreferences.getInstance());
    } catch (_) {
      // The choice still holds for this session.
    }
  }

  void _setView(_WeatherView view) {
    if (view == _view) return;
    setState(() {
      _view = view;
      _selected = null;
    });
    unawaited(_remember((p) => p.setString(_viewKey, view.name)));
  }

  void _toggleCollapsed() {
    final collapsed = !_collapsed;
    setState(() {
      _collapsed = collapsed;
      _selected = null;
    });
    unawaited(_remember((p) => p.setBool(_collapsedKey, collapsed)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final service = _service;
        final snapshot = service.snapshot;
        final now = snapshot?.forecast.nowAt(widget.now);
        final roles = VinabikeThemeRoles.maybeOf(context);
        final theme = Theme.of(context);
        final accent = roles?.avatarA ?? theme.colorScheme.primary;

        if (snapshot == null || now == null) {
          // Nobody signed in, or a first read that has not started: nothing
          // to say yet, and no empty frame to say it in.
          if (!service.loading &&
              !service.failed &&
              !service.locationMissing &&
              snapshot == null) {
            return const SizedBox.shrink();
          }
          return _framed(
            title: 'Clima',
            accent: accent,
            trailing: null,
            header: widget.detailed ? _placeHeader(service, accent) : null,
            child: _unavailable(theme, service, exhausted: snapshot != null),
          );
        }

        final forecast = snapshot.forecast;
        final place = forecast.place.name;
        final collapsed = !widget.detailed && _collapsed;
        return _framed(
          title: place == null ? 'Clima' : 'Clima en $place',
          accent: accent,
          header: widget.detailed ? _placeHeader(service, accent) : null,
          trailing: widget.detailed
              ? null
              : _CollapseControl(
                  collapsed: collapsed,
                  moment: now,
                  onToggle: _toggleCollapsed,
                ),
          child: AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: collapsed
                ? const SizedBox(width: double.infinity)
                : _expanded(theme, roles, snapshot, now),
          ),
        );
      },
    );
  }

  void _rememberPlace() {
    final place = _service.selectedPlaceId;
    unawaited(
      _remember((preferences) {
        if (place == null) {
          preferences.remove(_placeKey);
        } else {
          preferences.setString(_placeKey, place);
        }
      }),
    );
  }

  /// The heading of the tab: its name and, on the same line, the places as
  /// plain text tabs. Adding one opens a search right under it: nothing
  /// floats over the panel (owner, 2026-11-13).
  Widget _placeHeader(WeatherForecastService service, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlaceBar(
          service: service,
          accent: accent,
          adding: _adding,
          onToggleAdd: () => setState(() => _adding = !_adding),
          onChanged: _rememberPlace,
        ),
        if (_adding)
          _AddPlaceInline(
            service: service,
            onAdded: () {
              setState(() => _adding = false);
              _rememberPlace();
            },
          ),
      ],
    );
  }

  Widget _framed({
    required String title,
    required Color accent,
    required Widget? trailing,
    required Widget child,
    Widget? header,
  }) {
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header ??
              BriefingSectionHeader(
                title: title,
                accent: accent,
                trailing: trailing,
              ),
          child,
        ],
      ),
    );
  }

  Widget _unavailable(
    ThemeData theme,
    WeatherForecastService service, {
    required bool exhausted,
  }) {
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (service.locationMissing) {
      return Padding(
        padding: const EdgeInsets.only(top: 9),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'El pronóstico usa la ubicación de la ficha de Google del '
                'local, y todavía no hay una conectada.',
                style: muted,
              ),
            ),
            if (widget.onOpenIntegrations != null)
              TextButton(
                onPressed: widget.onOpenIntegrations,
                child: const Text('Conectar ficha'),
              ),
          ],
        ),
      );
    }
    if (service.loading && !service.failed && !exhausted) {
      return Padding(
        padding: const EdgeInsets.only(top: 9),
        child: Semantics(
          label: 'Cargando el clima',
          child: const LinearProgressIndicator(minHeight: 2),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No se pudo cargar el clima.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: service.loading
                ? null
                : () => unawaited(service.ensureFresh(force: true)),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _expanded(
    ThemeData theme,
    VinabikeThemeRoles? roles,
    WeatherSnapshot snapshot,
    WeatherMoment now,
  ) {
    final forecast = snapshot.forecast;
    final outlook = WeatherOutlook.of(forecast, widget.now);
    final hours = forecast.hoursFrom(widget.now);
    final days = forecast.daysAfter(widget.now, count: widget.detailed ? 8 : 6);
    final view = _view == _WeatherView.days && days.length >= 2
        ? _view
        : _WeatherView.hours;
    final water = roles?.avatarA ?? theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    final wet = outlook.kind != WeatherOutlookKind.dry;

    final String readout;
    final selected = _selected;
    if (selected == null) {
      readout = '';
    } else if (view == _WeatherView.hours && selected < hours.length) {
      readout = _hourReadout(hours[selected], forecast.place.zone);
    } else if (view == _WeatherView.days && selected < days.length) {
      readout = _dayReadout(days[selected]);
    } else {
      readout = '';
    }

    final headline = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            wet ? Icons.water_drop : Icons.water_drop_outlined,
            size: 16,
            color: wet ? water : muted,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                outlook.headline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              if (outlook.note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    outlook.note!,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    if (widget.detailed) {
      // The day itself comes first (owner, 2026-11-13): how it is now and how
      // each of the next hours will be. The other days matter less, and go
      // under it.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          _NowBlock(moment: now, forecast: forecast, clock: widget.now),
          const SizedBox(height: 12),
          headline,
          const SizedBox(height: 16),
          WeatherHourStrip(
            // The closing point only ends a line: its hour is not shown.
            hours: hours.take(24).toList(),
            zone: forecast.place.zone,
            measured: now,
          ),
          if (days.length >= 2) ...[
            const SizedBox(height: 18),
            Semantics(
              container: true,
              header: true,
              child: Text(
                'Próximos días',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _DailyTable(days: days),
          ],
          const SizedBox(height: 8),
          _Footer(
            readout: '',
            forecast: forecast,
            confirmedAt: snapshot.confirmedAt,
            clock: widget.now,
            failed: _service.failed,
            onRetry: () => unawaited(_service.ensureFresh(force: true)),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        _NowBlock(moment: now, forecast: forecast, clock: widget.now),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (days.length < 2) return headline;
            // The control grows with the reader's text size.
            final controlWidth = MediaQuery.textScalerOf(context).scale(124);
            final control = SizedBox(
              width: math.min(controlWidth, constraints.maxWidth),
              child: VbSegmented<_WeatherView>(
                groupLabel: 'Pronóstico por horas o por días',
                value: view,
                onChanged: _setView,
                options: const [
                  VbSegmentedOption(value: _WeatherView.hours, label: 'Horas'),
                  VbSegmentedOption(value: _WeatherView.days, label: 'Días'),
                ],
              ),
            );
            // Side by side while the sentence keeps room for a few words.
            if (constraints.maxWidth - controlWidth - 10 >= 170) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: headline),
                  const SizedBox(width: 10),
                  control,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [headline, const SizedBox(height: 8), control],
            );
          },
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          child: KeyedSubtree(
            key: ValueKey(view),
            child: view == _WeatherView.hours
                ? _hoursChart(hours, now, forecast.place.zone)
                : _daysChart(days),
          ),
        ),
        const SizedBox(height: 6),
        _Footer(
          readout: readout,
          forecast: forecast,
          confirmedAt: snapshot.confirmedAt,
          clock: widget.now,
          failed: _service.failed,
          onRetry: () => unawaited(_service.ensureFresh(force: true)),
        ),
      ],
    );
  }

  Widget _hoursChart(
    List<WeatherHour> hours,
    WeatherMoment now,
    WeatherZone zone,
  ) {
    // The chart starts at «now»: when that was measured, its first sky is
    // the measured one, not the model's for the same hour.
    final measuredSky = now.measurement == null ? null : now.condition;
    var lowest = hours.first;
    var highest = hours.first;
    var rain = 0.0;
    var peak = 0.0;
    for (final hour in hours) {
      if (hour.temperature < lowest.temperature) lowest = hour;
      if (hour.temperature > highest.temperature) highest = hour;
    }
    // The closing point only ends the line: its hour is not in the chart.
    for (final hour in hours.take(math.max(0, hours.length - 1))) {
      if (hour.precipitation < WeatherOutlook.rainPerHour) continue;
      rain += hour.precipitation;
      peak = math.max(peak, hour.precipitation);
    }
    return WeatherMeteogram(
      columns: false,
      markEvery: 3,
      // Two millimetres an hour is steady rain: below that a bar is short.
      rainScale: math.max(2, peak),
      rainFloor: WeatherOutlook.rainPerHour,
      selected: _selected,
      onSelected: (slot) {
        if (slot != _selected) setState(() => _selected = slot);
      },
      semanticLabel: 'Próximas ${hours.length - 1} horas: entre '
          '${weatherDegrees(lowest.temperature)} a las '
          '${weatherShopClock(lowest.time, zone)} y '
          '${weatherDegrees(highest.temperature)} a las '
          '${weatherShopClock(highest.time, zone)}; '
          '${rain <= 0 ? 'sin lluvia' : 'lluvia, ${weatherMillimetres(rain)}'}.',
      slots: [
        for (final (index, hour) in hours.indexed)
          MeteogramSlot(
            high: hour.temperature,
            rain: hour.precipitation,
            axisLabel: zone.local(hour.time).hour.toString().padLeft(2, '0'),
            condition:
                index == 0 ? measuredSky ?? hour.condition : hour.condition,
            daylight: hour.daylight,
            night: !hour.daylight,
          ),
      ],
    );
  }

  Widget _daysChart(List<WeatherDay> days) {
    return WeatherMeteogram(
      columns: true,
      rainScale: 10,
      rainFloor: WeatherOutlook.rainPerDay,
      selected: _selected,
      onSelected: (slot) {
        if (slot != _selected) setState(() => _selected = slot);
      },
      semanticLabel: 'Próximos ${days.length} días. ${[
        for (final day in days)
          '${weatherWeekday(day.date)}: '
              '${weatherDegrees(day.minTemperature)} a '
              '${weatherDegrees(day.maxTemperature)}'
              '${day.condition == null ? '' : ', ${day.condition!.label.toLowerCase()}'}'
              '${day.precipitation < WeatherOutlook.rainPerDay ? '' : ', ${weatherMillimetres(day.precipitation)} de lluvia'}',
      ].join('; ')}.',
      slots: [
        for (final day in days)
          MeteogramSlot(
            high: day.maxTemperature,
            low: day.minTemperature,
            rain: day.precipitation,
            axisLabel: weatherWeekdayShort(day.date),
            condition: day.condition,
          ),
      ],
    );
  }

  String _hourReadout(WeatherHour hour, WeatherZone zone) {
    final today = zone.local(widget.now);
    final then = zone.local(hour.time);
    final sameDay = then.day == today.day && then.month == today.month;
    final wind = hour.windKilometresPerHour;
    final from = hour.windFromDirection;
    return [
      '${sameDay ? '' : '${weatherWeekdayShort(then)} '}'
          '${weatherShopClock(hour.time, zone)}',
      weatherDegrees(hour.temperature),
      if (hour.condition != null) hour.condition!.label,
      if (hour.precipitation >= WeatherOutlook.rainPerHour)
        _millimetres(hour.precipitation),
      if (wind != null)
        'viento ${from == null ? '' : '${weatherCompass(from)} '}'
            '${wind.round()} km/h',
    ].join(' · ');
  }

  String _dayReadout(WeatherDay day) {
    return [
      '${weatherWeekdayShort(day.date)} ${day.date.day}',
      '${weatherDegrees(day.minTemperature)} a '
          '${weatherDegrees(day.maxTemperature)}',
      if (day.condition != null) day.condition!.label,
      if (day.precipitation >= WeatherOutlook.rainPerDay)
        _millimetres(day.precipitation),
    ].join(' · ');
  }

  /// One decimal under ten millimetres, with the comma Chile writes.
  static String _millimetres(double value) => value < 10
      ? '${value.toStringAsFixed(1).replaceAll('.', ',')} mm'
      : '${value.round()} mm';
}

class _CollapseControl extends StatelessWidget {
  const _CollapseControl({
    required this.collapsed,
    required this.moment,
    required this.onToggle,
  });

  final bool collapsed;
  final WeatherMoment moment;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final condition = moment.condition;
    final summary = '${weatherDegrees(moment.temperature)}'
        '${condition == null ? '' : ', ${condition.label.toLowerCase()}'}';
    return Semantics(
      container: true,
      button: true,
      expanded: !collapsed,
      label: collapsed
          ? 'Mostrar el clima. Ahora $summary'
          : 'Ocultar el detalle del clima',
      onTap: onToggle,
      excludeSemantics: true,
      child: Tooltip(
        message: collapsed ? 'Mostrar el clima' : 'Ocultar',
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 3, 2, 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (collapsed) ...[
                    if (condition != null) ...[
                      WeatherGlyph(
                        condition: condition,
                        daylight: moment.daylight,
                        size: 18,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      weatherDegrees(moment.temperature),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                  Icon(
                    collapsed
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NowBlock extends StatelessWidget {
  const _NowBlock({
    required this.moment,
    required this.forecast,
    required this.clock,
  });

  final WeatherMoment moment;
  final WeatherForecast forecast;
  final DateTime clock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final condition = moment.condition;
    final measurement = moment.measurement;
    final apparent = moment.apparentTemperature;
    final wind = moment.windKilometresPerHour;
    final from = moment.windFromDirection;
    final gust = moment.windGust;
    final uv = moment.uvIndex;
    final sun = forecast.sunOn(clock);
    final sunset = sun.sunset;
    final sunrise = sun.sunrise;

    // A felt temperature that rounds to the same degree says nothing new.
    final feels = apparent != null &&
            weatherDegrees(apparent) != weatherDegrees(moment.temperature)
        ? apparent
        : null;
    final zone = forecast.place.zone;
    final parts = [
      // Another place lives on another clock: say which hour it is there.
      if (forecast.place.id != null)
        'hora local ${weatherShopClock(clock, zone)}',
      if (feels != null) 'sensación ${weatherDegrees(feels)}',
      if (measurement != null)
        'medido a las ${weatherShopClock(measurement.time, zone)}',
    ].join(' · ');
    final meta =
        parts.isEmpty ? '' : '${parts[0].toUpperCase()}${parts.substring(1)}';

    final spoken = [
      'Ahora ${weatherDegrees(moment.temperature)}',
      if (condition != null) condition.label.toLowerCase(),
      if (feels != null) 'sensación ${weatherDegrees(feels)}',
      if (wind != null)
        wind < 2
            ? 'sin viento'
            : 'viento${from == null ? '' : ' del ${weatherCompassWords(from)}'} '
                'a ${wind.round()} kilómetros por hora',
      if (measurement != null)
        'medido a las ${weatherShopClock(measurement.time, forecast.place.zone)} en el aeródromo '
            '${measurement.station}',
    ].join(', ');

    final facts = <Widget>[
      if (wind != null)
        _Fact(
          icon: wind < 2 || from == null
              ? const Icon(Icons.air_rounded)
              // The arrow flies with the wind: it points where it blows to.
              : Transform.rotate(
                  angle: (from + 180) * math.pi / 180,
                  child: const Icon(Icons.navigation_rounded),
                ),
          text: wind < 2
              ? 'Sin viento'
              : '${from == null ? 'Viento' : weatherCompass(from)} '
                  '${wind.round()} km/h'
                  '${gust != null && gust * 3.6 >= wind + 10 ? ' · ráfagas ${(gust * 3.6).round()}' : ''}',
        ),
      if (moment.humidity != null)
        _Fact(
          icon: const Icon(Icons.water_drop_outlined),
          text: 'Humedad ${moment.humidity!.round()} %',
        ),
      if (moment.daylight && uv != null && uv >= 2.5)
        _Fact(
          icon: const Icon(Icons.wb_sunny_outlined),
          text: 'UV ${uv.round()} · ${weatherUvBand(uv)}',
        ),
      if (moment.daylight && sunset != null)
        _Fact(
          icon: const Icon(Icons.wb_twilight_rounded),
          text: 'Atardece ${weatherShopClock(sunset, forecast.place.zone)}',
        )
      else if (!moment.daylight && sunrise != null)
        _Fact(
          icon: const Icon(Icons.wb_twilight_rounded),
          text: 'Amanece ${weatherShopClock(sunrise, forecast.place.zone)}',
        ),
    ];

    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (condition != null) ...[
                  WeatherGlyph(
                    condition: condition,
                    daylight: moment.daylight,
                    size: 44,
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  weatherDegrees(moment.temperature),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        condition?.label ?? 'Sin dato del cielo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            meta,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (facts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 16, runSpacing: 6, children: facts),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final Widget icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTheme.merge(
          data: IconThemeData(
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          child: icon,
        ),
        const SizedBox(width: 5),
        // Never wider than the section, however large the reader's text.
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// What the chart's selection says, or who the readings come from.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.readout,
    required this.forecast,
    required this.confirmedAt,
    required this.clock,
    required this.failed,
    required this.onRetry,
  });

  final String readout;
  final WeatherForecast forecast;
  final DateTime confirmedAt;
  final DateTime clock;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final faint = roles?.faintForeground ?? theme.colorScheme.onSurfaceVariant;
    final caption = theme.textTheme.labelSmall?.copyWith(color: faint);

    if (readout.isNotEmpty) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 24),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            readout,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    // A forecast nobody could confirm for hours says so, with its hour.
    final old =
        clock.toUtc().difference(confirmedAt) > const Duration(hours: 2);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 24),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                if (failed || old)
                  Text(
                    'Sin actualizar desde las ${weatherShopClock(confirmedAt)} ·',
                    style: caption?.copyWith(
                      color: roles?.warning.accent ?? theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ExcludeSemantics(child: Text('Fuentes:', style: caption)),
                for (final (index, credit) in forecast.credits.indexed) ...[
                  if (index > 0)
                    ExcludeSemantics(child: Text('·', style: caption)),
                  _CreditLink(credit: credit, style: caption),
                ],
              ],
            ),
          ),
          if (failed)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Reintentar'),
            ),
        ],
      ),
    );
  }
}

class _CreditLink extends StatelessWidget {
  const _CreditLink({required this.credit, required this.style});

  final WeatherCredit credit;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final url = Uri.tryParse(credit.url ?? '');
    final text = Text(
      credit.name,
      style: style?.copyWith(
        decoration: url == null ? null : TextDecoration.underline,
        decorationColor: style?.color,
      ),
    );
    if (url == null || !url.hasScheme) return text;
    return Semantics(
      link: true,
      label: 'Fuente: ${credit.name}',
      onTap: () => unawaited(_open(url)),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => unawaited(_open(url)),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: text,
        ),
      ),
    );
  }

  static Future<void> _open(Uri url) async {
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // A browser that does not open is not worth an alarm in a footer.
    }
  }
}

/// One line of a detail table: a fixed lead, the sky, and what follows.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.lead,
    required this.condition,
    required this.daylight,
    required this.cells,
    required this.spoken,
  });

  final String lead;
  final WeatherCondition? condition;
  final bool daylight;
  final List<Widget> cells;
  final String spoken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: MediaQuery.textScalerOf(context).scale(52),
                child: Text(
                  lead,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 26,
                child: condition == null
                    ? null
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: WeatherGlyph(
                          condition: condition!,
                          daylight: daylight,
                          size: 20,
                        ),
                      ),
              ),
              ...cells,
            ],
          ),
        ),
      ),
    );
  }
}

Widget _rainCell(
  BuildContext context,
  double millimetres,
  double floor, {
  bool whole = false,
}) {
  final theme = Theme.of(context);
  final roles = VinabikeThemeRoles.maybeOf(context);
  final wet = millimetres >= floor;
  return SizedBox(
    width: MediaQuery.textScalerOf(context).scale(64),
    child: Text(
      wet
          ? millimetres < 10 && !whole
              ? '${millimetres.toStringAsFixed(1).replaceAll('.', ',')} mm'
              : '${millimetres.round()} mm'
          : '—',
      textAlign: TextAlign.right,
      maxLines: 1,
      style: theme.textTheme.bodySmall?.copyWith(
        color: wet
            ? roles?.avatarA ?? theme.colorScheme.primary
            : roles?.faintForeground ?? theme.colorScheme.onSurfaceVariant,
        fontWeight: wet ? FontWeight.w700 : FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}

/// The next days, one per line.
class _DailyTable extends StatelessWidget {
  const _DailyTable({required this.days});

  final List<WeatherDay> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final hairline = roles?.hairline ?? theme.colorScheme.outlineVariant;
    // In the narrowest panel the drawing alone says the sky.
    return LayoutBuilder(
      builder: (context, constraints) => _build(
        context,
        theme,
        muted,
        hairline,
        constraints.maxWidth >= MediaQuery.textScalerOf(context).scale(300),
      ),
    );
  }

  Widget _build(
    BuildContext context,
    ThemeData theme,
    Color muted,
    Color hairline,
    bool roomy,
  ) {
    Widget range(WeatherDay day) => Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${weatherDegrees(day.minTemperature)} / ',
                style: TextStyle(color: muted),
              ),
              TextSpan(
                text: weatherDegrees(day.maxTemperature),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          maxLines: 1,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _TableCaption(
          lead: 'Día',
          columns: ['Mín. / máx.', 'Lluvia'],
          windy: false,
          wideFirst: true,
        ),
        for (final day in days)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: hairline, width: 0.5)),
            ),
            child: _DetailRow(
              lead: '${weatherWeekdayShort(day.date)} ${day.date.day}',
              condition: day.condition,
              daylight: true,
              spoken: [
                '${weatherWeekday(day.date)} ${day.date.day}',
                if (day.condition != null) day.condition!.label.toLowerCase(),
                'entre ${weatherDegrees(day.minTemperature)} y '
                    '${weatherDegrees(day.maxTemperature)}',
                day.precipitation >= WeatherOutlook.rainPerDay
                    ? 'lluvia, ${weatherMillimetres(day.precipitation)}'
                    : 'sin lluvia',
              ].join(', '),
              cells: [
                if (roomy) ...[
                  Expanded(
                    child: Text(
                      day.condition?.label ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  range(day),
                ] else
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: range(day),
                    ),
                  ),
                _rainCell(
                  context,
                  day.precipitation,
                  WeatherOutlook.rainPerDay,
                  // Whole millimetres, as the chart above writes them.
                  whole: true,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The names of the columns, in the small faint type of a table head.
class _TableCaption extends StatelessWidget {
  const _TableCaption({
    required this.lead,
    required this.columns,
    required this.windy,
    this.wideFirst = false,
  });

  final String lead;
  final List<String> columns;
  final bool windy;
  final bool wideFirst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: roles?.faintForeground ?? theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          children: [
            SizedBox(
              width: scaler.scale(52) + 26,
              child: Text(lead, style: style),
            ),
            Expanded(
              child: Text(
                columns.first,
                textAlign: wideFirst ? TextAlign.right : TextAlign.left,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            SizedBox(
              width: scaler.scale(64),
              child: Text(
                columns[1],
                textAlign: TextAlign.right,
                style: style,
              ),
            ),
            if (windy)
              SizedBox(
                width: scaler.scale(96),
                child: Text(
                  columns[2],
                  textAlign: TextAlign.right,
                  style: style,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// «Clima» and, on the same line, the places as text tabs: the shop's own
/// first, then the ones this person added, then the way to add another.
class _PlaceBar extends StatelessWidget {
  const _PlaceBar({
    required this.service,
    required this.accent,
    required this.adding,
    required this.onToggleAdd,
    required this.onChanged,
  });

  final WeatherForecastService service;
  final Color accent;
  final bool adding;
  final VoidCallback onToggleAdd;

  /// The selection changed: the device remembers it.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final selected = service.selectedPlaceId;
    final messenger = ScaffoldMessenger.maybeOf(context);
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 9),
        Semantics(
          container: true,
          header: true,
          child: Text(
            'Clima',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PlaceTab(
                  key: const ValueKey<String>('weather-place-shop'),
                  label: service.shopName ?? 'El local',
                  selected: selected == null,
                  onTap: () {
                    service.select(null);
                    onChanged();
                  },
                ),
                for (final place in service.places)
                  _PlaceTab(
                    key: ValueKey<String>('weather-place-${place.id}'),
                    label: place.name,
                    selected: selected == place.id,
                    onTap: () {
                      service.select(place.id);
                      onChanged();
                    },
                    onRemove: selected != place.id
                        ? null
                        : () async {
                            final removed = await service.removePlace(place.id);
                            if (removed) {
                              onChanged();
                            } else {
                              messenger?.showSnackBar(
                                const SnackBar(
                                  content: Text('No se pudo quitar el lugar.'),
                                ),
                              );
                            }
                          },
                  ),
                Tooltip(
                  message: adding ? 'Cerrar la búsqueda' : 'Agregar lugar',
                  child: InkWell(
                    key: const ValueKey<String>('weather-place-add'),
                    onTap: onToggleAdd,
                    borderRadius: BorderRadius.circular(6),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      child: Icon(
                        adding ? Icons.close_rounded : Icons.add_rounded,
                        size: 18,
                        color: muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One place of the bar: its name, underlined while it is the one on screen.
class _PlaceTab extends StatelessWidget {
  const _PlaceTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onRemove,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Set on the selected place a person added: takes it off their list.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final remove = onRemove;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          onTap: onTap,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Center(
                  widthFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 2,
                          color: selected
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        label,
                        maxLines: 1,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: selected ? theme.colorScheme.onSurface : muted,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (remove != null)
          Tooltip(
            message: 'Quitar $label',
            child: InkWell(
              onTap: remove,
              borderRadius: BorderRadius.circular(6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 24, minHeight: 32),
                child: Icon(Icons.close_rounded, size: 14, color: muted),
              ),
            ),
          ),
      ],
    );
  }
}

/// Finds a town or a city by name, right under the bar, and adds it to the
/// person's places.
class _AddPlaceInline extends StatefulWidget {
  const _AddPlaceInline({required this.service, required this.onAdded});

  final WeatherForecastService service;
  final VoidCallback onAdded;

  @override
  State<_AddPlaceInline> createState() => _AddPlaceInlineState();
}

class _AddPlaceInlineState extends State<_AddPlaceInline> {
  final _query = TextEditingController();
  List<WeatherPlaceMatch>? _matches;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  // Asked when the person submits, never on each keystroke: the search
  // service's rules forbid type-ahead.
  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.length < 2 || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final matches = await widget.service.search(query);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _matches = matches;
        _message = matches.isEmpty
            ? 'No hay un lugar con ese nombre. Prueba con la ciudad y el país.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message =
            'No se pudo buscar. Revisa la conexión e inténtalo otra vez.';
      });
    }
  }

  Future<void> _add(WeatherPlaceMatch match) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await widget.service.addPlace(match);
    if (!mounted) return;
    switch (result) {
      case WeatherPlaceAdded.added:
        widget.onAdded();
      case WeatherPlaceAdded.tooMany:
        setState(() {
          _busy = false;
          _message = 'Ya tienes el máximo de lugares. Quita uno para agregar '
              'otro.';
        });
      case WeatherPlaceAdded.failed:
        setState(() {
          _busy = false;
          _message = 'No se pudo agregar el lugar. Inténtalo otra vez.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final hairline = roles?.hairline ?? theme.colorScheme.outlineVariant;
    final matches = _matches ?? const <WeatherPlaceMatch>[];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey<String>('weather-place-query'),
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.words,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Ciudad o comuna, y Enter',
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                onPressed: _busy ? null : () => unawaited(_search()),
                icon: const Icon(Icons.search_rounded, size: 18),
              ),
            ),
            onSubmitted: (_) => unawaited(_search()),
          ),
          SizedBox(
            height: 6,
            child: _busy
                ? const Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                : null,
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _message!,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          for (final match in matches)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: hairline, width: 0.5)),
              ),
              child: InkWell(
                onTap: _busy ? null : () => unawaited(_add(match)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, size: 16, color: muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: match.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (match.region != null)
                                TextSpan(
                                  text: '  ${match.region}',
                                  style: TextStyle(color: muted),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_matches != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Búsqueda: © OpenStreetMap',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: roles?.faintForeground ?? muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
