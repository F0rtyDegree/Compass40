import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gps_info/gps_info.dart';
import '../log_entry.dart';

class GpsSection extends StatefulWidget {
  final ValueNotifier<GpsData> gpsDataNotifier;
  final ValueNotifier<double> accuracyNotifier;
  final ValueNotifier<double?> distanceToTarget;
  final ValueNotifier<double?> bearingToTarget;
  final ValueNotifier<double?> distanceToWaypoint;
  final ValueNotifier<double?> bearingToWaypoint;
  final GpsData? waypoint;
  final Map<String, double>? target;
  final List<LogItem> logItems;
  final double magneticDeclination;

  const GpsSection({
    super.key,
    required this.gpsDataNotifier,
    required this.accuracyNotifier,
    required this.distanceToTarget,
    required this.bearingToTarget,
    required this.distanceToWaypoint,
    required this.bearingToWaypoint,
    required this.waypoint,
    required this.target,
    required this.logItems,
    required this.magneticDeclination,
  });

  @override
  State<GpsSection> createState() => _GpsSectionState();
}

class _GpsSectionState extends State<GpsSection> {
  bool _isCoordinatesCopied = false;

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyLarge;
    final iconColor = Theme.of(context).colorScheme.primary;

    return ValueListenableBuilder<GpsData>(
      valueListenable: widget.gpsDataNotifier,
      builder: (context, gps, _) {
        return ValueListenableBuilder<double>(
          valueListenable: widget.accuracyNotifier,
          builder: (context, acc, _) {
            final speedKmh = (gps.speed ?? 0) * 3.6;
            final decl = widget.magneticDeclination;

            final coordsText = (gps.latitude != null && gps.longitude != null)
                ? '${gps.latitude!.toStringAsFixed(6)},${gps.longitude!.toStringAsFixed(6)}'
                : '--,--';

            final copied = _isCoordinatesCopied;
            final inverted = Theme.of(context).scaffoldBackgroundColor;
            final origColor = baseStyle?.color ??
                (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : Colors.black87);

            final coordsWidget = GestureDetector(
              onTap: () {
                if (gps.latitude != null && gps.longitude != null) {
                  Clipboard.setData(ClipboardData(text: coordsText));
                  if (!mounted) return;
                  setState(() => _isCoordinatesCopied = true);
                  Timer(const Duration(milliseconds: 200), () {
                    if (mounted) setState(() => _isCoordinatesCopied = false);
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: copied ? origColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: _buildIconValue(
                  context,
                  Icons.location_on,
                  coordsText,
                  copied
                      ? baseStyle?.copyWith(color: inverted)
                      : baseStyle,
                  copied ? inverted : iconColor,
                ),
              ),
            );

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                children: [
                  _buildTargetInfo(),
                  _buildWaypointInfo(),
                  const Divider(),
                  _buildIconValue(
                    context,
                    Icons.speed,
                    '${speedKmh.toStringAsFixed(1)} km/h',
                    baseStyle?.copyWith(
                      fontSize: (baseStyle.fontSize ?? 18) * 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                    iconColor,
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildIconValue(
                        context,
                        Icons.satellite_alt,
                        '${gps.satellitesUsed ?? 0}/${gps.satellitesInView ?? 0}',
                        baseStyle,
                        iconColor,
                      ),
                      _buildIconValue(
                        context,
                        Icons.track_changes,
                        '${gps.accuracy?.toStringAsFixed(1)} m',
                        baseStyle,
                        iconColor,
                      ),
                      _buildIconValue(
                        context,
                        Icons.height,
                        '${gps.mslAltitude?.toStringAsFixed(1)} m',
                        baseStyle,
                        iconColor,
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildIconValue(
                        context,
                        Icons.explore,
                        '${decl.toStringAsFixed(1)}°',
                        baseStyle,
                        iconColor,
                      ),
                      coordsWidget,
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTargetInfo() {
    const minH = 48.0;
    if (widget.distanceToTarget.value == null || widget.target == null) {
      return const SizedBox(height: minH);
    }
    return ValueListenableBuilder<double?>(
      valueListenable: widget.distanceToTarget,
      builder: (context, dist, _) {
        return ValueListenableBuilder<double?>(
          valueListenable: widget.bearingToTarget,
          builder: (context, bear, _) {
            if (bear == null || dist == null) return const SizedBox(height: minH);
            final distText =
                dist > 1000 ? '${(dist / 1000).toStringAsFixed(2)} km' : '${dist.round()} m';
            final text =
                'ДО ЦЕЛИ: -> $distText, ${bear.round().toString()}°';
            return Container(
              height: minH,
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWaypointInfo() {
    const minH = 48.0;
    if (widget.waypoint == null) return const SizedBox(height: minH);
    return ValueListenableBuilder<double?>(
      valueListenable: widget.distanceToWaypoint,
      builder: (context, dist, _) {
        return ValueListenableBuilder<double?>(
          valueListenable: widget.bearingToWaypoint,
          builder: (context, bear, _) {
            if (dist == null || bear == null) return const SizedBox(height: minH);
            final n = widget.logItems.whereType<LogEntry>().length + 1;
            final distText =
                dist > 1000 ? '${(dist / 1000).toStringAsFixed(2)} km' : '${dist.round()} m';
            final text = 'ОТ КП$n: -> $distText, ${bear.round()}°';
            return Container(
              height: minH,
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(text,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: Colors.orange, fontWeight: FontWeight.bold)),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildIconValue(
      BuildContext c, IconData icon, String val, TextStyle? st, Color? clr) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: clr, size: 28),
        const SizedBox(width: 8),
        Flexible(child: Text(val, style: st, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
