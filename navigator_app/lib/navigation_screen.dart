import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:material_ui/material_ui.dart';

import 'config.dart';
import 'geo_utils.dart';
import 'instructions_ms.dart';
import 'mapbox_api.dart';
import 'models.dart';

// Warna garisan laluan (format ARGB untuk Mapbox).
const int _routeColor = 0xFF00E5FF;
const int _routeCasingColor = 0xFF004D66;
const int _destColor = 0xFFFF5252;

// Had untuk logik navigasi (meter / saat).
const double _maneuverReachedMeters = 25;
const double _arrivedMeters = 30;
const double _offRouteMeters = 50;
const int _offRouteHits = 3;
const Duration _rerouteCooldown = Duration(seconds: 15);

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final MapboxApi _api = MapboxApi(kMapboxToken);

  // Peta
  mb.MapboxMap? _map;
  mb.PolylineAnnotationManager? _lineManager;
  mb.CircleAnnotationManager? _circleManager;

  // Carian
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;
  List<PlaceResult> _results = [];
  bool _searching = false;
  String? _searchMessage;

  // Lokasi
  LatLng? _myPos;
  double? _heading;
  double _speed = 0;
  bool _locationReady = false;
  StreamSubscription<geo.Position>? _posSub;

  // Laluan & navigasi
  PlaceResult? _destination;
  NavRoute? _route;
  bool _loadingRoute = false;
  bool _navigating = false;
  bool _arrived = false;
  bool _followUser = true;
  int _stepIndex = 0;
  double _distToManeuver = 0;
  double _remainingDistance = 0;
  double _remainingDuration = 0;
  int _offRouteCount = 0;
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _posSub?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Lokasi
  // ---------------------------------------------------------------------

  Future<void> _initLocation() async {
    try {
      final serviceOn = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        _toast('Sila hidupkan GPS / Lokasi di telefon anda.');
        return;
      }
      var perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied) {
        perm = await geo.Geolocator.requestPermission();
      }
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        _toast('Kebenaran lokasi diperlukan untuk navigasi.');
        return;
      }

      if (!mounted) return;
      setState(() => _locationReady = true);
      await _enablePuck();

      try {
        final p = await geo.Geolocator.getCurrentPosition(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
        _onPosition(p);
        await _flyTo(_myPos!, zoom: 15);
      } catch (_) {
        // Abaikan — strim di bawah akan beri lokasi nanti.
      }

      _posSub = geo.Geolocator.getPositionStream(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        ),
      ).listen(_onPosition, onError: (Object _) {});
    } catch (_) {
      _toast('Gagal mendapatkan lokasi.');
    }
  }

  Future<void> _enablePuck() async {
    final map = _map;
    if (map == null || !_locationReady) return;
    try {
      await map.location.updateSettings(mb.LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        puckBearingEnabled: true,
      ));
    } catch (_) {}
  }

  void _onPosition(geo.Position p) {
    final hadPos = _myPos != null;
    _myPos = LatLng(p.latitude, p.longitude);
    _speed = p.speed;
    if (p.heading >= 0 && p.speed > 1.5) _heading = p.heading;

    if (_navigating && _route != null) {
      _updateProgress();
      if (_followUser) _followCamera();
    }

    // Jika destinasi dipilih sebelum GPS sedia, kira laluan sekarang.
    if (!hadPos && _destination != null && _route == null && !_loadingRoute) {
      _loadRoute();
    }

    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------
  // Peta & kamera
  // ---------------------------------------------------------------------

  Future<void> _onMapCreated(mb.MapboxMap map) async {
    _map = map;
    try {
      _lineManager = await map.annotations.createPolylineAnnotationManager();
      _circleManager = await map.annotations.createCircleAnnotationManager();
    } catch (_) {}
    await _enablePuck();
    final pos = _myPos;
    if (pos != null) await _flyTo(pos, zoom: 15);
  }

  mb.Point _pt(LatLng p) => mb.Point(coordinates: mb.Position(p.lng, p.lat));

  Future<void> _flyTo(LatLng p, {double zoom = 15}) async {
    final map = _map;
    if (map == null) return;
    try {
      await map.flyTo(
        mb.CameraOptions(center: _pt(p), zoom: zoom, pitch: 0, bearing: 0),
        mb.MapAnimationOptions(duration: 1000),
      );
    } catch (_) {}
  }

  Future<void> _followCamera() async {
    final map = _map;
    final pos = _myPos;
    if (map == null || pos == null) return;
    try {
      await map.easeTo(
        mb.CameraOptions(
          center: _pt(pos),
          zoom: _speed > 22 ? 15.5 : 17,
          pitch: 55,
          bearing: _heading,
          // Tolak titik pengguna ke bawah supaya nampak jalan di hadapan.
          padding:
              mb.MbxEdgeInsets(top: 280, left: 0, bottom: 0, right: 0),
        ),
        mb.MapAnimationOptions(duration: 900),
      );
    } catch (_) {}
  }

  Future<void> _fitRoute(NavRoute route) async {
    final map = _map;
    if (map == null || route.coordinates.isEmpty) return;
    try {
      final points = sample(route.coordinates, 120).map(_pt).toList();
      final camera = await map.cameraForCoordinatesPadding(
        points,
        mb.CameraOptions(pitch: 0, bearing: 0),
        mb.MbxEdgeInsets(top: 170, left: 50, bottom: 280, right: 50),
        16,
        null,
      );
      await map.flyTo(camera, mb.MapAnimationOptions(duration: 1200));
    } catch (_) {
      final dest = _destination;
      if (dest != null) await _flyTo(dest.location, zoom: 13);
    }
  }

  Future<void> _drawRoute(NavRoute route) async {
    final manager = _lineManager;
    if (manager == null) return;
    try {
      await manager.deleteAll();
      final line = mb.LineString(
        coordinates:
            route.coordinates.map((c) => mb.Position(c.lng, c.lat)).toList(),
      );
      await manager.create(mb.PolylineAnnotationOptions(
        geometry: line,
        lineColor: _routeCasingColor,
        lineWidth: 11,
      ));
      await manager.create(mb.PolylineAnnotationOptions(
        geometry: line,
        lineColor: _routeColor,
        lineWidth: 6,
      ));
    } catch (_) {}
  }

  Future<void> _drawDestination(LatLng p) async {
    final manager = _circleManager;
    if (manager == null) return;
    try {
      await manager.deleteAll();
      await manager.create(mb.CircleAnnotationOptions(
        geometry: _pt(p),
        circleColor: _destColor,
        circleRadius: 9,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 3,
      ));
    } catch (_) {}
  }

  Future<void> _clearMap() async {
    try {
      await _lineManager?.deleteAll();
      await _circleManager?.deleteAll();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Carian
  // ---------------------------------------------------------------------

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 3) {
      setState(() {
        _results = [];
        _searchMessage = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    setState(() {
      _searching = true;
      _searchMessage = null;
    });
    try {
      final results = await _api.search(q, near: _myPos);
      if (!mounted || _searchCtrl.text.trim() != q) return;
      setState(() {
        _results = results;
        _searchMessage = results.isEmpty ? 'Tiada hasil untuk "$q".' : null;
      });
    } on MapboxApiException catch (e) {
      if (mounted) setState(() => _searchMessage = e.message);
    } catch (_) {
      if (mounted) setState(() => _searchMessage = 'Carian gagal.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectPlace(PlaceResult place) async {
    _searchFocus.unfocus();
    setState(() {
      _searchCtrl.text = place.name;
      _results = [];
      _searchMessage = null;
      _destination = place;
      _route = null;
      _arrived = false;
    });
    await _drawDestination(place.location);
    if (_myPos == null) {
      _toast('Menunggu lokasi GPS anda...');
      await _flyTo(place.location, zoom: 14);
      return;
    }
    await _loadRoute();
  }

  // ---------------------------------------------------------------------
  // Laluan & navigasi
  // ---------------------------------------------------------------------

  Future<void> _loadRoute({bool fit = true}) async {
    final from = _myPos;
    final dest = _destination;
    if (from == null || dest == null) return;

    setState(() => _loadingRoute = true);
    try {
      final route = await _api.route(from, dest.location);
      if (!mounted || _destination != dest) return;
      setState(() {
        _route = route;
        _stepIndex = route.steps.length > 1 ? 1 : 0;
        _remainingDistance = route.distance;
        _remainingDuration = route.duration;
        _distToManeuver = route.steps.isNotEmpty ? route.steps.first.distance : 0;
        _offRouteCount = 0;
        _arrived = false;
      });
      await _drawRoute(route);
      if (fit) await _fitRoute(route);
      if (_navigating) _updateProgress();
    } on MapboxApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Gagal mendapatkan laluan.');
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  void _startNavigation() {
    if (_route == null || _myPos == null) return;
    setState(() {
      _navigating = true;
      _followUser = true;
      _arrived = false;
    });
    _updateProgress();
    _followCamera();
  }

  Future<void> _stopNavigation() async {
    setState(() {
      _navigating = false;
      _followUser = true;
    });
    final route = _route;
    if (route != null) await _fitRoute(route);
  }

  Future<void> _cancelRoute() async {
    setState(() {
      _navigating = false;
      _arrived = false;
      _route = null;
      _destination = null;
      _searchCtrl.clear();
      _results = [];
    });
    await _clearMap();
    final pos = _myPos;
    if (pos != null) await _flyTo(pos);
  }

  /// Kemas kini langkah semasa, jarak & masa berbaki.
  void _updateProgress() {
    final route = _route;
    final pos = _myPos;
    final dest = _destination;
    if (route == null || pos == null || dest == null) return;
    final steps = route.steps;
    if (steps.isEmpty) return;

    // Sudah tiba?
    if (distanceBetween(pos, dest.location) < _arrivedMeters) {
      _arrived = true;
      _navigating = false;
      _remainingDistance = 0;
      _remainingDuration = 0;
      return;
    }

    // Maju ke langkah seterusnya bila sudah melepasi gerakan.
    _distToManeuver = distanceBetween(pos, steps[_stepIndex].location);
    while (_stepIndex < steps.length - 1 &&
        _distToManeuver < _maneuverReachedMeters) {
      _stepIndex++;
      _distToManeuver = distanceBetween(pos, steps[_stepIndex].location);
    }

    // Jarak & masa berbaki.
    var dist = _distToManeuver;
    var time = 0.0;
    final current = _stepIndex > 0 ? steps[_stepIndex - 1] : null;
    if (current != null && current.distance > 0) {
      time += current.duration *
          (_distToManeuver / current.distance).clamp(0.0, 1.0).toDouble();
    }
    for (var i = _stepIndex; i < steps.length; i++) {
      dist += steps[i].distance;
      time += steps[i].duration;
    }
    _remainingDistance = dist;
    _remainingDuration = time;

    // Terkeluar laluan? Kira semula.
    final off = distanceToPolyline(pos, route.coordinates);
    _offRouteCount = off > _offRouteMeters ? _offRouteCount + 1 : 0;
    if (_offRouteCount >= _offRouteHits &&
        !_loadingRoute &&
        DateTime.now().difference(_lastReroute) > _rerouteCooldown) {
      _lastReroute = DateTime.now();
      _offRouteCount = 0;
      _toast('Mengira semula laluan...');
      _loadRoute(fit: false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerMove: (_) {
              if (_navigating && _followUser) {
                setState(() => _followUser = false);
              }
            },
            child: mb.MapWidget(
              styleUri: kMapStyle,
              viewport: mb.CameraViewportState(
                center: _pt(const LatLng(kDefaultLat, kDefaultLng)),
                zoom: 12,
              ),
              onMapCreated: _onMapCreated,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _navigating ? _buildInstructionBanner() : _buildSearch(),
            ),
          ),
          Positioned(
            right: 16,
            bottom: _bottomPanelVisible ? 230 : 40,
            child: _buildLocateButton(),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 20,
            child: SafeArea(top: false, child: _buildBottomPanel()),
          ),
        ],
      ),
    );
  }

  bool get _bottomPanelVisible =>
      _loadingRoute || _route != null || _arrived;

  Widget _buildSearch() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          elevation: 6,
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(14),
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (q) {
              if (q.trim().length >= 2) _runSearch(q.trim());
            },
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Cari destinasi (cth: KLCC, Mid Valley)',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.search, color: Colors.cyanAccent),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: _cancelRoute,
                        )
                      : null),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        if (_results.isNotEmpty || _searchMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              elevation: 6,
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: _searchMessage != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _searchMessage!,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _results.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Colors.white12),
                        itemBuilder: (context, i) {
                          final r = _results[i];
                          final pos = _myPos;
                          return ListTile(
                            leading: const Icon(Icons.place,
                                color: Colors.cyanAccent),
                            title: Text(
                              r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              r.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60),
                            ),
                            trailing: pos == null
                                ? null
                                : Text(
                                    formatDistance(
                                        distanceBetween(pos, r.location)),
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 12),
                                  ),
                            onTap: () => _selectPlace(r),
                          );
                        },
                      ),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _buildInstructionBanner() {
    final route = _route;
    if (route == null || route.steps.isEmpty) return const SizedBox.shrink();
    final step = route.steps[_stepIndex];
    final next =
        _stepIndex + 1 < route.steps.length ? route.steps[_stepIndex + 1] : null;

    return Material(
      elevation: 8,
      color: const Color(0xFF0B6E4F),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(iconFor(step), color: Colors.white, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatDistance(_distToManeuver),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        instructionFor(step),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (next != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Kemudian ',
                      style: TextStyle(color: Colors.white70)),
                  Icon(iconFor(next), color: Colors.white70, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      instructionFor(next),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocateButton() {
    final recenter = _navigating && !_followUser;
    return FloatingActionButton(
      heroTag: 'locate',
      backgroundColor: const Color(0xFF1E1E1E),
      foregroundColor: Colors.cyanAccent,
      tooltip: recenter ? 'Pusat semula' : 'Lokasi saya',
      onPressed: () {
        final pos = _myPos;
        if (pos == null) {
          if (!_locationReady) {
            _initLocation();
          } else {
            _toast('Menunggu lokasi GPS...');
          }
          return;
        }
        if (_navigating) {
          setState(() => _followUser = true);
          _followCamera();
        } else {
          _flyTo(pos, zoom: 16);
        }
      },
      child: Icon(recenter ? Icons.navigation : Icons.my_location),
    );
  }

  Widget _buildBottomPanel() {
    Widget card(Widget child) => Material(
          elevation: 8,
          color: Colors.black87,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.cyanAccent, width: 1.5),
            ),
            child: child,
          ),
        );

    if (_arrived) {
      return card(Row(
        children: [
          const Icon(Icons.flag, color: Colors.cyanAccent, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Anda telah tiba di ${_destination?.name ?? 'destinasi'}',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
          FilledButton(onPressed: _cancelRoute, child: const Text('Selesai')),
        ],
      ));
    }

    if (_loadingRoute && _route == null) {
      return card(const Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 14),
          Text('Mengira laluan...',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ));
    }

    final route = _route;
    if (route == null) return const SizedBox.shrink();

    final eta = DateTime.now()
        .add(Duration(seconds: _remainingDuration.round()));
    final summary = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          formatDuration(_remainingDuration),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            '${formatDistance(_remainingDistance)} • Tiba ${formatClock(eta)}',
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ),
      ],
    );

    if (_navigating) {
      return card(Row(
        children: [
          Expanded(child: summary),
          FilledButton.tonal(
            onPressed: _stopNavigation,
            child: const Text('Tamat'),
          ),
        ],
      ));
    }

    return card(Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _destination?.name ?? 'Destinasi',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.grey, fontSize: 14),
        ),
        const SizedBox(height: 4),
        summary,
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _myPos == null ? null : _startNavigation,
                icon: const Icon(Icons.navigation),
                label: const Text('Mula'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _cancelRoute,
              child: const Text('Batal'),
            ),
          ],
        ),
      ],
    ));
  }
}
