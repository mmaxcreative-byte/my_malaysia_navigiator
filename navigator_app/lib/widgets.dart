import 'package:material_ui/material_ui.dart';

import 'instructions_ms.dart';
import 'models.dart';

const Color kNavGreen = Color(0xFF0F7B5F);

/// Warna panel navigasi (gelap, seperti Sygic/Google Maps).
const Color kNavPanel = Color(0xF2192638);

/// Biru papan tanda lebuh raya.
const Color kSignBlue = Color(0xFF1558B0);

/// Biru terang untuk lorong yang patut dimasuki.
const Color kLaneActive = Color(0xFF4FC3F7);

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
      shadowColor: const Color(0x380A2033),
      color: color ?? scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65)),
      ),
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
      shape: CircleBorder(
        side: BorderSide(color: active ? scheme.primary : scheme.outlineVariant),
      ),
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

/// Satu petak untuk setiap lorong, mengikut susunan kiri ke kanan.
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
    final hasPreferred = lanes.any((lane) => lane.valid && lane.active);
    return Container(
      color: const Color(0xFF162D48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < lanes.length; i++)
            Expanded(
              child: _lane(lanes[i], i + 1, hasPreferred),
            ),
        ],
      ),
    );
  }

  Widget _lane(LaneInfo lane, int number, bool hasPreferred) {
    final preferred = lane.valid && (lane.active || !hasPreferred);
    final guidance = preferred
        ? 'disyorkan'
        : lane.valid
            ? 'boleh digunakan'
            : 'tidak sesuai';
    final directions = lane.indications.toSet();
    final recommended = lane.valid && directions.isNotEmpty
        ? laneDisplayIndication(lane, modifier)
        : null;
    return Semantics(
      label: 'Lorong $number: $guidance',
      child: Container(
        height: iconSize + 10,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        decoration: BoxDecoration(
          color: preferred ? const Color(0xFFC8EEFF) : Colors.white10,
          border: Border.all(color: lane.valid ? Colors.white38 : Colors.white12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: directions.isEmpty
              ? Icon(Icons.remove, size: iconSize, color: Colors.white54)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final direction in directions)
                      Icon(
                        laneIcon(direction),
                        size: iconSize,
                        color: preferred
                            ? (direction == recommended
                                ? const Color(0xFF103C68)
                                : const Color(0xFF476684))
                            : (direction == recommended
                                ? Colors.white
                                : Colors.white54),
                      ),
                  ],
                ),
        ),
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
class RouteOptionsSheet extends StatelessWidget {
  const RouteOptionsSheet({
    super.key,
    required this.options,
    required this.selected,
    required this.quotes,
  });

  final List<NavRoute> options;
  final NavRoute? selected;
  final Map<NavRoute, Future<double?>> quotes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Scrollbar(
        child: ListView(
          primary: true,
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Kembali ke carian',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text('Pilihan laluan', style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            if (options.length == 1)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Hanya satu laluan ditemukan untuk destinasi ini.'),
              ),
            const SizedBox(height: 12),
            for (final (index, route) in options.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  tileColor: theme.colorScheme.surfaceContainerHigh,
                  selectedTileColor: theme.colorScheme.primaryContainer,
                  selected: route == selected,
                  leading: Icon(route == selected ? Icons.check_circle : Icons.route),
                  title: Text(route.avoidTolls
                      ? 'Laluan tanpa tol'
                      : route.hasToll
                          ? 'Laluan ${index + 1} · Bertol'
                          : 'Laluan ${index + 1}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${formatDuration(route.duration)} • '
                          '${formatDistance(route.distance)}'),
                      TollLabel(route: route, quote: quotes[route]),
                    ],
                  ),
                  onTap: () => Navigator.pop(context, route),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class TollLabel extends StatelessWidget {
  const TollLabel({super.key, required this.route, this.quote});

  final NavRoute route;
  final Future<double?>? quote;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double?>(
      future: quote,
      builder: (context, snapshot) {
        final amount = route.avoidTolls ? 0.0 : snapshot.data;
        final String label;
        if (amount != null) {
          label = amount == 0
              ? 'Tanpa tol • RM 0.00'
              : 'Anggaran tol kereta • RM ${amount.toStringAsFixed(2)}';
        } else if (snapshot.connectionState == ConnectionState.waiting) {
          label = 'Menyemak anggaran tol…';
        } else {
          label = route.hasToll
              ? 'Bertol • Caj tidak tersedia'
              : 'Maklumat tol tidak tersedia';
        }
        return Text(label);
      },
    );
  }
}

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
    this.tollQuote,
    this.onChooseRoute,
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
  final Future<double?>? tollQuote;
  final VoidCallback? onChooseRoute;

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
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SizedBox.square(
                  dimension: 32,
                  child: Icon(Icons.place, color: scheme.onPrimaryContainer, size: 19),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  destinationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
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
          Row(
            children: [
              Icon(Icons.toll, color: scheme.primary, size: 18),
              const SizedBox(width: 6),
              Expanded(child: TollLabel(route: route, quote: tollQuote)),
              if (onChooseRoute != null)
                TextButton.icon(
                  onPressed: onChooseRoute,
                  icon: const Icon(Icons.alt_route, size: 18),
                  label: const Text('Laluan'),
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

/// Papan tanda arahan di atas (biru, gaya papan tanda lebuh raya)
/// dengan anak panah lorong di sebelahnya.
class ManeuverBanner extends StatelessWidget {
  const ManeuverBanner({
    super.key,
    required this.step,
    required this.distance,
    this.next,
    this.compact = false,
  });

  final NavStep step;
  final double distance;

  /// Gerakan seterusnya — hanya diberi jika ia sangat dekat.
  final NavStep? next;

  /// Saiz kecil (landscape).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final showLanes = step.lanes.isNotEmpty && distance < 1500;
    final hasSignText = step.destinations.isNotEmpty;
    final route = signRoute(step);

    final sign = Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kSignBlue, Color(0xFF123361)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(color: const Color(0xFF84B6ED), width: 1),
      ),
      padding: EdgeInsets.fromLTRB(
          compact ? 8 : 10, compact ? 6 : 8, compact ? 8 : 12, compact ? 6 : 8),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: EdgeInsets.all(compact ? 4 : 6),
              child: Icon(iconFor(step), color: Colors.white,
                  size: compact ? 32 : 42),
            ),
          ),
          SizedBox(width: compact ? 6 : 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (step.exitNumber != null || route != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        if (step.exitNumber != null)
                          _Badge(
                            text: 'EXIT ${step.exitNumber}',
                            color: const Color(0xFF1B7A3A),
                          ),
                        if (route != null)
                          _Badge(text: route, color: const Color(0xFFF5B400),
                              textColor: Colors.black),
                      ],
                    ),
                  ),
                Text(
                  signTitle(step),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 14 : 18,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                if (hasSignText)
                  Text(
                    instructionFor(step),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: compact ? 11 : 13,
                    ),
                  ),
                if (step.trafficSignal && distance < 350)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.traffic, size: 15, color: Color(0xFFFFD28A)),
                        SizedBox(width: 5),
                        Expanded(
                          child: Text('Lampu isyarat',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                Text(
                  formatDistance(distance),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 20 : 26,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final lanes = showLanes
        ? LaneStrip(
            lanes: step.lanes,
            modifier: step.modifier,
            iconSize: compact ? 24 : 34,
          )
        : null;

    Widget body;
    if (lanes != null && !compact) {
      body = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 6, child: sign),
            const SizedBox(width: 8),
            Expanded(flex: 5, child: lanes),
          ],
        ),
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sign,
          if (lanes != null) ...[const SizedBox(height: 6), lanes],
        ],
      );
    }

    final nextStep = next;
    return Material(
      elevation: 8,
      color: kNavPanel,
      borderRadius: BorderRadius.circular(compact ? 12 : 16),
      child: Padding(
        padding: EdgeInsets.all(compact ? 6 : 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            if (nextStep != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                child: Row(
                  children: [
                    const Text('Kemudian',
                        style: TextStyle(color: Colors.white60, fontSize: 13)),
                    const SizedBox(width: 6),
                    Icon(iconFor(nextStep), color: Colors.white, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        instructionFor(nextStep),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
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

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.color,
    this.textColor = Colors.white,
  });

  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Laju semasa + had laju (kotak gelap di kanan).
class SpeedBadge extends StatelessWidget {
  const SpeedBadge({super.key, required this.speedKmh, this.limitKmh});

  final double speedKmh;
  final double? limitKmh;

  @override
  Widget build(BuildContext context) {
    final limit = limitKmh;
    final over = limit != null && speedKmh > limit + 5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (limit != null)
          Container(
            width: 46,
            height: 46,
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
          elevation: 6,
          color: over ? const Color(0xFFD32F2F) : kNavPanel,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 68,
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  speedKmh.round().toString(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'km/j',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Nama jalan semasa (di bawah, tengah).
class RoadNamePill extends StatelessWidget {
  const RoadNamePill({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: kNavPanel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Bar bawah semasa navigasi: ETA (minit · waktu tiba · jarak) + butang.
class TripBar extends StatelessWidget {
  const TripBar({
    super.key,
    required this.remainingDuration,
    required this.remainingDistance,
    required this.voiceOn,
    required this.onToggleVoice,
    required this.onFuel,
    required this.onSettings,
    required this.onEnd,
    this.trafficDelay = 0,
    this.compact = false,
  });

  final double remainingDuration;
  final double remainingDistance;
  final double trafficDelay;
  final bool voiceOn;
  final VoidCallback onToggleVoice;
  final VoidCallback onFuel;
  final VoidCallback onSettings;
  final VoidCallback onEnd;

  /// Saiz kecil (landscape): butang suara & minyak dipindah ke tepi peta.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final eta =
        DateTime.now().add(Duration(seconds: remainingDuration.round()));
    final (minVal, minUnit) = durationParts(remainingDuration);
    final (clock, ampm) = formatClock12(eta);
    final (distVal, distUnit) = distanceParts(remainingDistance);
    final delayMin = (trafficDelay / 60).round();
    final timeColor = delayMin >= 10
        ? const Color(0xFFFF6B6B)
        : delayMin >= 3
            ? const Color(0xFFFFB74D)
            : const Color(0xFF69F0AE);
    final big = compact ? 22.0 : 30.0;

    Widget stat(String value, String unit, Color color) => Padding(
          padding: EdgeInsets.only(right: compact ? 12 : 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: big,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              Text(
                unit,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        );

    Widget btn(IconData icon, String tip, VoidCallback onTap,
            {Color? color}) =>
        IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, color: color ?? Colors.white),
        );

    return Material(
      elevation: 10,
      color: kNavPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 16 : 22),
        side: const BorderSide(color: Color(0xFF40546F)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 12 : 18, 10, 6, compact ? 8 : 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('ETA',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 12)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            stat(minVal, minUnit, timeColor),
                            stat(clock, ampm, Colors.white),
                            stat(distVal, distUnit, Colors.white),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 48, color: Colors.white12),
                const SizedBox(width: 4),
                if (!compact) ...[
                  btn(voiceOn ? Icons.volume_up : Icons.volume_off,
                      voiceOn ? 'Senyapkan suara' : 'Hidupkan suara',
                      onToggleVoice),
                  btn(Icons.local_gas_station, 'Stesen minyak di laluan',
                      onFuel),
                ],
                btn(Icons.settings, 'Tetapan', onSettings),
                btn(Icons.close, 'Tamat navigasi', onEnd,
                    color: const Color(0xFFFF6B6B)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
