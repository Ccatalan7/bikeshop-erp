import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/weather_forecast.dart';
import '../../models/weather_outlook.dart';
import '../../services/weather_forecast_service.dart';
import '../../themes/vinabike_theme_roles.dart';
import '../../utils/shop_time.dart';
import '../briefing_section_header.dart';
import '../vb_segmented.dart';
import 'weather_glyph.dart';
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
    this.service,
    this.onOpenIntegrations,
  });

  final DateTime now;

  /// Room around the section while it has something to show. With nothing to
  /// show it takes no room at all, so the briefing keeps no empty gap.
  final EdgeInsetsGeometry padding;

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

  _WeatherView _view = _WeatherView.hours;
  bool _collapsed = false;
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
      if (view == _WeatherView.days.name || collapsed) {
        setState(() {
          _view = view == _WeatherView.days.name
              ? _WeatherView.days
              : _WeatherView.hours;
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
            child: _unavailable(theme, service, exhausted: snapshot != null),
          );
        }

        final forecast = snapshot.forecast;
        final place = forecast.place.name;
        final collapsed = _collapsed;
        return _framed(
          title: place == null ? 'Clima' : 'Clima en $place',
          accent: accent,
          trailing: _CollapseControl(
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

  Widget _framed({
    required String title,
    required Color accent,
    required Widget? trailing,
    required Widget child,
  }) {
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
    final days = forecast.daysAfter(widget.now, count: 6);
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
      readout = _hourReadout(hours[selected]);
    } else if (view == _WeatherView.days && selected < days.length) {
      readout = _dayReadout(days[selected]);
    } else {
      readout = '';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        _NowBlock(moment: now, forecast: forecast, clock: widget.now),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
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
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
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
                ? _hoursChart(hours, now)
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

  Widget _hoursChart(List<WeatherHour> hours, WeatherMoment now) {
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
          '${weatherShopClock(lowest.time)} y '
          '${weatherDegrees(highest.temperature)} a las '
          '${weatherShopClock(highest.time)}; '
          '${rain <= 0 ? 'sin lluvia' : 'lluvia, ${weatherMillimetres(rain)}'}.',
      slots: [
        for (final (index, hour) in hours.indexed)
          MeteogramSlot(
            high: hour.temperature,
            rain: hour.precipitation,
            axisLabel: shopTime(hour.time).hour.toString().padLeft(2, '0'),
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

  String _hourReadout(WeatherHour hour) {
    final today = shopTime(widget.now);
    final then = shopTime(hour.time);
    final sameDay = then.day == today.day && then.month == today.month;
    final wind = hour.windKilometresPerHour;
    final from = hour.windFromDirection;
    return [
      '${sameDay ? '' : '${weatherWeekdayShort(then)} '}'
          '${weatherShopClock(hour.time)}',
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
    final meta = [
      if (feels != null) 'Sensación ${weatherDegrees(feels)}',
      if (measurement != null)
        '${feels == null ? 'Medido' : 'medido'} a las '
            '${weatherShopClock(measurement.time)}',
    ].join(' · ');

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
        'medido a las ${weatherShopClock(measurement.time)} en el aeródromo '
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
          text: 'Atardece ${weatherShopClock(sunset)}',
        )
      else if (!moment.daylight && sunrise != null)
        _Fact(
          icon: const Icon(Icons.wb_twilight_rounded),
          text: 'Amanece ${weatherShopClock(sunrise)}',
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
