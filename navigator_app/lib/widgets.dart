import 'package:material_ui/material_ui.dart';

import 'instructions_ms.dart';
import 'models.dart';

const Color kNavGreen = Color(0xFF0F7B5F);
const Color kNavGreenDark = Color(0xFF0A5C47);

/// Kad asas dengan bucu bulat, ikut tema siang/malam.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      shadowColor: Colors.black54,
      color: color ?? scheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Butang bulat kecil di atas peta.
class MapRoundButton extends StatelessWidget {
  const MapRoundButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      shape: const CircleBorder(),
      color: active ? scheme.primary : scheme.surface,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        color: active ? scheme.onPrimary : scheme.primary,
        onPressed: onPressed,
      ),
    );
  }
}

/// Kad arahan belokan semasa navigasi (dengan lorong jika ada).
class InstructionCard extends StatelessWidget {
  const InstructionCard({
    super.key,
    required this.step,
    required this.distance,
    this.next,
    this.compact = false,
  });

  final NavStep step;
  final double distance;

  /// Saiz kecil (untuk landscape) supaya tidak menutup peta.
  final bool compact;

  /// Gerakan seterusnya — hanya diberi jika ia sangat dekat.
  final NavStep? next;

  @override
  Widget build(BuildContext context) {
    final showLanes = step.lanes.length > 1 && distance < 1500;
    final iconSize = compact ? 36.0 : 52.0;
    final distSize = compact ? 20.0 : 28.0;
    final textSize = compact ? 14.0 : 17.0;
    return Material(
      elevation: 8,
      color: kNavGreen,
      borderRadius: BorderRadius.circular(compact ? 14 : 20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
                : const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Icon(iconFor(step), color: Colors.white, size: iconSize),
                SizedBox(width: compact ? 8 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatDistance(distance),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: distSize,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        instructionFor(step),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: textSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showLanes)
            LaneStrip(
              lanes: step.lanes,
              modifier: step.modifier,
              iconSize: compact ? 22 : 30,
            ),
          if (next != null)
            Container(
              color: kNavGreenDark,
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 16, vertical: compact ? 4 : 8),
              child: Row(
                children: [
                  const Text('Kemudian',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(width: 8),
                  Icon(iconFor(next!), color: Colors.white, size: 22),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Barisan anak panah lorong: putih = lorong yang patut dimasuki.
class LaneStrip extends StatelessWidget {
  const LaneStrip({
    super.key,
    required this.lanes,
    required this.modifier,
    this.iconSize = 30,
  });

  final List<LaneInfo> lanes;
  final String modifier;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kNavGreenDark,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < lanes.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: iconSize, color: Colors.white24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Icon(
                laneIcon(laneDisplayIndication(lanes[i], modifier)),
                size: iconSize,
                color: lanes[i].valid ? Colors.white : Colors.white30,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Amaran insiden di hadapan.
class IncidentPill extends StatelessWidget {
  const IncidentPill({
    super.key,
    required this.incident,
    required this.distanceAhead,
  });

  final RouteIncident incident;
  final double distanceAhead;

  @override
  Widget build(BuildContext context) {
    final severe = incident.closed ||
        incident.type == 'accident' ||
        incident.type == 'road_closure';
    return Material(
      elevation: 6,
      color: severe ? const Color(0xFFD32F2F) : const Color(0xFFFFA000),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(incidentIcon(incident.type), color: Colors.white),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '${incidentLabel(incident.type)} • ${formatDistance(distanceAhead)} di hadapan',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Laju semasa + had laju.
class SpeedBadge extends StatelessWidget {
  const SpeedBadge({super.key, required this.speedKmh, this.limitKmh});

  final double speedKmh;
  final double? limitKmh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final limit = limitKmh;
    final over = limit != null && speedKmh > limit + 5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (limit != null)
          Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFD32F2F), width: 5),
            ),
            alignment: Alignment.center,
            child: Text(
              limit.round().toString(),
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
        Material(
          elevation: 4,
          shape: const CircleBorder(),
          color: over ? const Color(0xFFD32F2F) : scheme.surface,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  speedKmh.round().toString(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: over ? Colors.white : scheme.onSurface,
                    height: 1,
                  ),
                ),
                Text(
                  'km/j',
                  style: TextStyle(
                    fontSize: 10,
                    color: over ? Colors.white70 : scheme.onSurfaceVariant,
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

/// Status trafik: lancar / sesak (+X min).
class TrafficChip extends StatelessWidget {
  const TrafficChip({super.key, required this.delaySeconds});

  final double delaySeconds;

  @override
  Widget build(BuildContext context) {
    final mins = (delaySeconds / 60).round();
    final Color color;
    final String text;
    if (mins >= 10) {
      color = const Color(0xFFD32F2F);
      text = 'Trafik sesak (+$mins min)';
    } else if (mins >= 3) {
      color = const Color(0xFFF57C00);
      text = 'Trafik perlahan (+$mins min)';
    } else {
      color = const Color(0xFF2E7D32);
      text = 'Trafik lancar';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.traffic, size: 18, color: color),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Ringkasan laluan sebelum mula (destinasi, masa, trafik, insiden).
class RoutePreviewCard extends StatelessWidget {
  const RoutePreviewCard({
    super.key,
    required this.route,
    required this.destinationName,
    required this.remainingDuration,
    required this.remainingDistance,
    required this.onStart,
    required this.onCancel,
    required this.onFuel,
    this.stopName,
    this.onRemoveStop,
    this.loading = false,
  });

  final NavRoute route;
  final String destinationName;
  final String? stopName;
  final double remainingDuration;
  final double remainingDistance;
  final VoidCallback? onStart;
  final VoidCallback onCancel;
  final VoidCallback onFuel;
  final VoidCallback? onRemoveStop;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final eta = DateTime.now().add(Duration(seconds: remainingDuration.round()));
    final types = <String>{for (final i in route.incidents) i.type}.toList();

    return PanelCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.place, color: scheme.error, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  destinationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (stopName != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.local_gas_station,
                      size: 18, color: Color(0xFFF57C00)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Singgah: $stopName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  if (onRemoveStop != null)
                    InkWell(
                      onTap: onRemoveStop,
                      child: Icon(Icons.close,
                          size: 18, color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 12,
            children: [
              Text(
                formatDuration(remainingDuration),
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${formatDistance(remainingDistance)} • Tiba ${formatClock(eta)}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (route.durationTypical != null)
            TrafficChip(delaySeconds: route.trafficDelay),
          if (types.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in types.take(3))
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(incidentIcon(t),
                          size: 16, color: const Color(0xFFF57C00)),
                      label: Text(incidentLabel(t)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: onStart,
                  icon: const Icon(Icons.navigation),
                  label: const Text('Mula',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Stesen minyak di laluan',
                onPressed: onFuel,
                icon: const Icon(Icons.local_gas_station),
              ),
              const SizedBox(width: 4),
              IconButton.outlined(
                tooltip: 'Batal',
                onPressed: onCancel,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bar ringkas semasa navigasi: masa, jarak, waktu tiba + butang.
class TripBar extends StatelessWidget {
  const TripBar({
    super.key,
    required this.remainingDuration,
    required this.remainingDistance,
    required this.voiceOn,
    required this.onToggleVoice,
    required this.onFuel,
    required this.onEnd,
    this.trafficDelay = 0,
    this.compact = false,
  });

  /// Saiz kecil (landscape): butang suara & minyak dipindah ke tepi peta.
  final bool compact;
  final double remainingDuration;
  final double remainingDistance;
  final double trafficDelay;
  final bool voiceOn;
  final VoidCallback onToggleVoice;
  final VoidCallback onFuel;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final eta = DateTime.now().add(Duration(seconds: remainingDuration.round()));
    final delayMin = (trafficDelay / 60).round();
    final timeColor = delayMin >= 10
        ? const Color(0xFFD32F2F)
        : delayMin >= 3
            ? const Color(0xFFF57C00)
            : const Color(0xFF2E9E5B);

    return PanelCard(
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 6, 6, 6)
          : const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDuration(remainingDuration),
                  style: TextStyle(
                    color: timeColor,
                    fontSize: compact ? 19 : 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${formatDistance(remainingDistance)} • Tiba ${formatClock(eta)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: compact ? 12 : 14,
                  ),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            IconButton(
              tooltip: voiceOn ? 'Senyapkan suara' : 'Hidupkan suara',
              onPressed: onToggleVoice,
              icon: Icon(voiceOn ? Icons.volume_up : Icons.volume_off),
            ),
            IconButton(
              tooltip: 'Stesen minyak di laluan',
              onPressed: onFuel,
              icon: const Icon(Icons.local_gas_station),
            ),
          ],
          IconButton.filled(
            tooltip: 'Tamat navigasi',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
            ),
            onPressed: onEnd,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
