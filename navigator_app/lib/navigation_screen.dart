import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_theme.dart';
import 'config.dart';
import 'geo_utils.dart';
import 'instructions_ms.dart';
import 'mapbox_api.dart';
import 'models.dart';
import 'puck.dart';
import 'toll_api.dart';
import 'voice.dart';
import 'widgets.dart';

// Had untuk logik navigasi (meter / saat).
const double _arrivedMeters = 30;
const double _offRouteMeters = 50;
const int _offRouteHits = 3;
const Duration _rerouteCooldown = Duration(seconds: 15);

/// Pilihan tema: ikut waktu, sentiasa siang, sentiasa malam.
enum ThemePref { auto, day, night }

enum NavigationView {
  standard('Paparan 1 · Standard', 0),
  closer('Paparan 2 · Lebih dekat', 0.6);

  const NavigationView(this.label, this.zoomOffset);

  final String label;
  final double zoomOffset;
}

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final MapboxApi _api = MapboxApi(kMapboxToken);
  final VoiceGuide _voice = VoiceGuide();
  final TollRates _tollRates = TollRates();

  // Peta
  mb.MapboxMap? _map;
  mb.PolylineAnnotationManager? _lineManager;
  mb.CircleAnnotationManager? _markerManager;
  mb.CircleAnnotationManager? _fuelManager;
  mb.PointAnnotationManager? _signalManager;
  Future<Uint8List?>? _signalIcon;
  Future<void> _routeDrawing = Future<void>.value();

  // Tema
  ThemePref _themePref = ThemePref.auto;
  late bool _night;
  bool _show3d = true;
  NavigationView _navigationView = NavigationView.standard;
  Uint8List? _arrowPuck;
  Timer? _themeTimer;

  // Susun atur (dikemas kini dalam build)
  bool _landscape = false;
  double _panelWidth = 0;
  Size _screen = Size.zero;

  // Carian
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;
  int _searchRevision = 0;
  List<PlaceResult> _results = [];
  bool _searching = false;
  String? _searchMessage;

  // Lokasi
  LatLng? _myPos;
  double? _heading;
  double _speedKmh = 0;
  double _accuracy = 10;
  bool _locationReady = false;
  StreamSubscription<geo.Position>? _posSub;

  // Laluan & navigasi
  PlaceResult? _destination;
  PlaceResult? _stop;
  NavRoute? _route;
  List<NavRoute> _routeOptions = [];
  Map<NavRoute, Future<double?>> _tollQuotes = {};
  int _routeRevision = 0;
  List<PlaceResult> _fuelResults = [];
  bool _loadingRoute = false;
  bool _showOptionsOnRoute = false;
  bool _navigating = false;
  bool _arrived = false;
  bool _followUser = true;
  int _stepIndex = 0;
  int _snapSegment = 0;
  double _distToManeuver = 0;
  double _remainingDistance = 0;
  double _remainingDuration = 0;
  double? _limitKmh;
  RouteIncident? _incidentAhead;
  double _incidentDist = 0;
  int _offRouteCount = 0;
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);

  // Suara
  bool _voiceOn = true;
  int _announcedStep = -1;
  bool _saidFar = false;
  bool _saidNear = false;
  final Set<int> _announcedIncidents = {};
  String? _speechPrefix;

  @override
  void initState() {
    super.initState();
    _night = _computeNight(); // sama dengan nilai awal nightMode
    _themeTimer =
        Timer.periodic(const Duration(minutes: 1), (_) => _applyTheme());
    _initVoice();
    _keepScreenOn();
    _initLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _themeTimer?.cancel();
    _posSub?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _voice.stop();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Skrin, suara & tema
  // ---------------------------------------------------------------------

  /// Skrin kekal menyala selagi aplikasi dibuka (seperti Waze).
  Future<void> _keepScreenOn() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }

  Future<void> _initVoice() async {
    await _voice.init();
    if (!mounted) return;
    if (_voice.language == null) {
      _toast('Suara tidak tersedia. Semak tetapan "Text-to-speech" telefon.');
    } else if (!_voice.usingMalay) {
      _toast('Suara Bahasa Melayu tiada di telefon — guna suara Indonesia.');
    }
  }

  void _say(String text) {
    final prefix = _speechPrefix;
    _speechPrefix = null;
    _voice.speak(prefix == null ? text : '$prefix $text');
  }

  bool _computeNight() {
    switch (_themePref) {
      case ThemePref.day:
        return false;
      case ThemePref.night:
        return true;
      case ThemePref.auto:
        return isNightHour();
    }
  }

  Future<void> _applyTheme() async {
    final night = _computeNight();
    if (night != _night && mounted) setState(() => _night = night);
    nightMode.value = night;
    await _applyMapLook();
    // Warna laluan berbeza ikut tema.
    await _refreshRouteDrawing();
  }

  /// Peta Standard: pencahayaan siang/malam dan bangunan 3D.
  Future<void> _applyMapLook() async {
    final style = _map?.style;
    if (style == null) return;
    try {
      await style.setStyleImportConfigProperty(
          'basemap', 'lightPreset', _night ? 'night' : 'day');
      await style.setStyleImportConfigProperty(
          'basemap', 'show3dObjects', _show3d);
    } catch (_) {}
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
    // Anak panah berputar mengikut arah pergerakan kenderaan.
    _arrowPuck ??= await buildArrowPuck();
    final arrow = _arrowPuck;
    try {
      await map.location.updateSettings(mb.LocationComponentSettings(
        enabled: true,
        pulsingEnabled: false,
        showAccuracyRing: false,
        puckBearingEnabled: true,
        puckBearing: mb.PuckBearing.COURSE,
        locationPuck: arrow == null
            ? null
            : mb.LocationPuck(
                locationPuck2D: mb.LocationPuck2D(bearingImage: arrow),
              ),
      ));
    } catch (_) {
      // Sandaran: ikon lalai Mapbox.
      try {
        await map.location.updateSettings(mb.LocationComponentSettings(
          enabled: true,
          puckBearingEnabled: true,
        ));
      } catch (_) {}
    }
  }

  void _onPosition(geo.Position p) {
    final hadPos = _myPos != null;
    _myPos = LatLng(p.latitude, p.longitude);
    _speedKmh = math.max(0.0, p.speed * 3.6);
    _accuracy = p.accuracy;
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
      _fuelManager = await map.annotations.createCircleAnnotationManager();
      _markerManager = await map.annotations.createCircleAnnotationManager();
      _signalManager = await map.annotations.createPointAnnotationManager();
    } catch (_) {}
    try {
      // Buang pembaris jarak di atas kiri (tidak berguna semasa memandu).
      await map.scaleBar.updateSettings(mb.ScaleBarSettings(enabled: false));
    } catch (_) {}
    await _enablePuck();
    await _refreshRouteDrawing();
    final pos = _myPos;
    if (pos != null) await _flyTo(pos, zoom: 15);
  }

  /// Dipanggil setiap kali gaya peta siap dimuatkan (termasuk tukar tema).
  Future<void> _onStyleLoaded() async {
    await _applyMapLook();
    await _enablePuck();
    await _refreshRouteDrawing();
    await _drawMarkers();
    await _drawFuelMarkers();
  }

  mb.Point _pt(LatLng p) => mb.Point(coordinates: mb.Position(p.lng, p.lat));

  Future<void> _flyTo(LatLng p, {double zoom = 15}) async {
    final map = _map;
    if (map == null) return;
    try {
      await map.flyTo(
        mb.CameraOptions(
          center: _pt(p),
          zoom: zoom,
          pitch: 0,
          bearing: 0,
          padding: _sidePadding(),
        ),
        mb.MapAnimationOptions(duration: 1000),
      );
    } catch (_) {}
  }

  /// Ruang yang dilindungi panel (landscape: panel di kiri).
  mb.MbxEdgeInsets _sidePadding() => _landscape
      ? mb.MbxEdgeInsets(top: 0, left: _panelWidth, bottom: 0, right: 0)
      : mb.MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0);

  Future<void> _followCamera() async {
    final map = _map;
    final pos = _myPos;
    if (map == null || pos == null) return;
    // Letak titik pengguna di bahagian bawah supaya nampak jalan di hadapan.
    final padding = _landscape
        ? mb.MbxEdgeInsets(
            top: _screen.height * 0.35,
            left: _panelWidth,
            bottom: 0,
            right: 0)
        : mb.MbxEdgeInsets(
            top: _screen.height * 0.40, left: 0, bottom: 0, right: 0);
    final baseZoom = _speedKmh > 80 ? 15.5 : (_speedKmh > 50 ? 16.3 : 17.0);
    try {
      await map.easeTo(
        mb.CameraOptions(
          center: _pt(pos),
          zoom: baseZoom + _navigationView.zoomOffset,
          pitch: 55,
          bearing: _heading,
          padding: padding,
        ),
        mb.MapAnimationOptions(duration: 900),
      );
    } catch (_) {}
  }

  Future<void> _fitRoute(NavRoute route) async {
    final map = _map;
    if (map == null || route.coordinates.isEmpty) return;
    final padding = _landscape
        ? mb.MbxEdgeInsets(
            top: 40, left: _panelWidth + 40, bottom: 40, right: 80)
        : mb.MbxEdgeInsets(top: 150, left: 50, bottom: 340, right: 50);
    try {
      final points = sample(route.coordinates, 120).map(_pt).toList();
      final camera = await map.cameraForCoordinatesPadding(
        points,
        mb.CameraOptions(pitch: 0, bearing: 0),
        padding,
        16,
        null,
      );
      await map.flyTo(camera, mb.MapAnimationOptions(duration: 1200));
    } catch (_) {
      final dest = _destination;
      if (dest != null) await _flyTo(dest.location, zoom: 13);
    }
  }

  static String _bucket(String c) {
    switch (c) {
      case 'moderate':
      case 'heavy':
      case 'severe':
        return c;
      default:
        return 'low';
    }
  }

  int _congestionColor(String level) {
    switch (level) {
      case 'moderate':
        return _night ? 0xFFFFBD52 : 0xFFFFA000;
      case 'heavy':
        return _night ? 0xFFFF7262 : 0xFFE53935;
      case 'severe':
        return _night ? 0xFFFF4E9B : 0xFF8B0000;
      default:
        return _night ? 0xFF63EDFF : 0xFF00A5D6;
    }
  }

  Future<void> _refreshRouteDrawing() {
    _routeDrawing = _routeDrawing.then((_) async {
      if (!mounted) return;
      final route = _route;
      if (route == null) {
        try {
          await _lineManager?.deleteAll();
        } catch (_) {}
      } else {
        await _drawRoute(route);
      }
      await _drawSignals(route);
    });
    return _routeDrawing;
  }

  Future<void> _drawSignals(NavRoute? route) async {
    final manager = _signalManager;
    if (manager == null) return;
    try {
      await manager.deleteAll();
      if (route == null || route.trafficSignals.isEmpty) return;
      final png = await (_signalIcon ??= _makeSignalIcon());
      if (png == null || !mounted || _route != route) return;
      await manager.createMulti([
        for (final signal in route.trafficSignals)
          mb.PointAnnotationOptions(geometry: _pt(signal), image: png),
      ]);
    } catch (_) {}
  }

  Future<Uint8List?> _makeSignalIcon() async {
    const size = 28;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(const Offset(14, 14), 13, paint);
    paint.color = const Color(0xFF162538);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(8, 3, 12, 22),
          const Radius.circular(4)),
      paint,
    );
    const colors = [Color(0xFFFF6363), Color(0xFFFFCA57), Color(0xFF53E6A1)];
    for (var i = 0; i < colors.length; i++) {
      paint.color = colors[i];
      canvas.drawCircle(Offset(14, 8 + i * 6.0), 2, paint);
    }
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(size, size);
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.png))
            ?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// Lukis laluan dengan warna ikut kesesakan trafik.
  Future<void> _drawRoute(NavRoute route) async {
    final manager = _lineManager;
    if (manager == null) return;
    final coords = route.coordinates;
    try {
      await manager.deleteAll();
      if (coords.length < 2) return;

      mb.LineString line(List<LatLng> pts) => mb.LineString(
            coordinates: pts.map((c) => mb.Position(c.lng, c.lat)).toList(),
          );

      final all = line(coords);
      final options = <mb.PolylineAnnotationOptions>[
        if (!_navigating)
          for (final alternative in _routeOptions)
            if (alternative != route)
              mb.PolylineAnnotationOptions(
                geometry: line(alternative.coordinates),
                lineColor: _night ? 0xFFACBFD4 : 0xFF6D839F,
                lineSortKey: 0,
                lineWidth: 5,
                lineOpacity: 0.8,
              ),
        // Cahaya lembut di sekeliling laluan.
        mb.PolylineAnnotationOptions(
          geometry: all,
          lineColor: 0xFF00E5FF,
          lineWidth: 22,
          lineOpacity: _night ? 0.4 : 0.18,
          lineSortKey: 1,
          lineBlur: 6,
        ),
        // Garis tepi memisahkan laluan daripada peta.
        mb.PolylineAnnotationOptions(
          geometry: all,
          lineColor: _night ? 0xFFDAF8FF : 0xFF005A73,
          lineSortKey: 2,
          lineWidth: 13,
        ),
      ];

      final segCount = coords.length - 1;
      String level(int i) =>
          i < route.congestion.length ? _bucket(route.congestion[i]) : 'low';

      var start = 0;
      for (var i = 1; i <= segCount; i++) {
        if (i == segCount || level(i) != level(start)) {
          options.add(mb.PolylineAnnotationOptions(
            geometry: line(coords.sublist(start, i + 1)),
            lineColor: _congestionColor(level(start)),
            lineSortKey: 3,
            lineWidth: 8,
          ));
          start = i;
        }
      }
      await manager.createMulti(options);
    } catch (_) {}
  }

  Future<void> _drawMarkers() async {
    final manager = _markerManager;
    if (manager == null) return;
    try {
      await manager.deleteAll();
      final dest = _destination;
      if (dest != null) {
        await manager.create(mb.CircleAnnotationOptions(
          geometry: _pt(dest.location),
          circleColor: 0xFFE53935,
          circleRadius: 10,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 3,
        ));
      }
      final stop = _stop;
      if (stop != null) {
        await manager.create(mb.CircleAnnotationOptions(
          geometry: _pt(stop.location),
          circleColor: 0xFFF57C00,
          circleRadius: 9,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 3,
        ));
      }
    } catch (_) {}
  }

  Future<void> _drawFuelMarkers() async {
    final manager = _fuelManager;
    if (manager == null) return;
    try {
      await manager.deleteAll();
      if (_fuelResults.isEmpty) return;
      await manager.createMulti([
        for (final f in _fuelResults)
          mb.CircleAnnotationOptions(
            geometry: _pt(f.location),
            circleColor: 0xFFFFA000,
            circleRadius: 7,
            circleStrokeColor: 0xFFFFFFFF,
            circleStrokeWidth: 2,
          ),
      ]);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Carian
  // ---------------------------------------------------------------------

  void _onSearchChanged(String text) {
    setState(_invalidateSearch);
    final q = text.trim();
    if (q.length >= 3) {
      _debounce = Timer(const Duration(milliseconds: 450), () => _runSearch(q));
    }
  }

  void _invalidateSearch() {
    _debounce?.cancel();
    _searchRevision++;
    _results = [];
    _searchMessage = null;
    _searching = false;
  }

  Future<void> _runSearch(String q) async {
    setState(() {
      _invalidateSearch();
      _searching = true;
    });
    final revision = _searchRevision;
    List<PlaceResult> results = [];
    String? message;
    try {
      results = await _api.search(q, near: _myPos);
      if (results.isEmpty) message = 'Tiada hasil untuk "$q".';
    } on MapboxApiException catch (e) {
      message = e.message;
    } catch (_) {
      message = 'Carian gagal.';
    }
    if (!mounted || revision != _searchRevision) return;
    setState(() {
      _results = results;
      _searchMessage = message;
      _searching = false;
    });
  }

  Future<void> _selectPlace(PlaceResult place) async {
    _searchFocus.unfocus();
    setState(() {
      _searchCtrl.text = place.name;
      _invalidateSearch();
      _destination = place;
      _showOptionsOnRoute = true;
      _stop = null;
      _route = null;
      _routeOptions = [];
      _tollQuotes = {};
      _loadingRoute = false;
      _routeRevision++;
      _arrived = false;
    });
    await _refreshRouteDrawing();
    await _drawMarkers();
    if (!mounted || _destination != place) return;
    if (_myPos == null) {
      _toast('Menunggu lokasi GPS anda...');
      await _flyTo(place.location, zoom: 14);
      return;
    }
    await _loadRoute();
  }

  // ---------------------------------------------------------------------
  // Stesen minyak
  // ---------------------------------------------------------------------

  Future<void> _findFuel() async {
    final pos = _myPos;
    final route = _route;
    List<LatLng>? ahead;
    if (route != null && route.coordinates.length > 1) {
      final from = (_navigating ? _snapSegment : 0)
          .clamp(0, route.coordinates.length - 2)
          .toInt();
      ahead = route.coordinates.sublist(from);
    }
    if (pos == null && ahead == null) {
      _toast('Menunggu lokasi GPS anda...');
      return;
    }

    _toast(ahead != null
        ? 'Mencari stesen minyak di sepanjang laluan...'
        : 'Mencari stesen minyak berdekatan...');
    try {
      final list = await _api.fuelStations(near: pos, routeAhead: ahead);
      if (!mounted) return;
      if (list.isEmpty) {
        _toast('Tiada stesen minyak dijumpai.');
        return;
      }
      if (pos != null) {
        list.sort((a, b) => distanceBetween(pos, a.location)
            .compareTo(distanceBetween(pos, b.location)));
      }
      setState(() => _fuelResults = list);
      await _drawFuelMarkers();
      await _showFuelSheet(list);
    } on MapboxApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Carian stesen minyak gagal.');
    }
  }

  /// Penanda oren stesen minyak di sepanjang laluan (tanpa senarai).
  Future<void> _loadFuelAlongRoute(NavRoute route) async {
    try {
      final list = await _api.fuelStations(
        near: _myPos,
        routeAhead: route.coordinates,
      );
      if (!mounted || _route != route) return;
      setState(() => _fuelResults = list);
      await _drawFuelMarkers();
    } catch (_) {
      // Tidak kritikal — abaikan.
    }
  }

  Future<void> _showFuelSheet(List<PlaceResult> list) async {
    final hasRoute = _route != null && _destination != null;
    final chosen = await showModalBottomSheet<PlaceResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final pos = _myPos;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    hasRoute
                        ? 'Stesen minyak — pilih untuk singgah'
                        : 'Stesen minyak berdekatan',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final f = list[i];
                      final subtitle = [
                        if (f.brand != null) f.brand!,
                        if (f.address.isNotEmpty) f.address,
                      ].join(' • ');
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFFFE0B2),
                          child: Icon(Icons.local_gas_station,
                              color: Color(0xFFE65100)),
                        ),
                        title: Text(f.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(subtitle,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: pos == null
                            ? null
                            : Text(formatDistance(
                                distanceBetween(pos, f.location))),
                        onTap: () => Navigator.of(ctx).pop(f),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || chosen == null) return;

    if (hasRoute) {
      setState(() => _stop = chosen);
      await _drawMarkers();
      _speechPrefix = 'Singgah di ${chosen.name}.';
      await _loadRoute(fit: !_navigating);
    } else {
      await _selectPlace(chosen);
    }
  }

  Future<void> _removeStop() async {
    setState(() => _stop = null);
    await _drawMarkers();
    await _loadRoute();
  }

  // ---------------------------------------------------------------------
  // Laluan & navigasi
  // ---------------------------------------------------------------------

  Future<void> _loadRoute({bool fit = true}) async {
    final from = _myPos;
    final dest = _destination;
    if (!mounted || from == null || dest == null) return;
    final stop = _stop;
    final revision = ++_routeRevision;
    final avoidTolls = _route?.avoidTolls ?? false;
    final preview = !_navigating;
    final points = [from, if (stop != null) stop.location, dest.location];

    setState(() => _loadingRoute = true);
    try {
      final options = preview
          ? await _api.routeOptions(points)
          : [await _api.route(points, avoidTolls: avoidTolls)];
      if (!mounted ||
          revision != _routeRevision ||
          _destination != dest ||
          _stop != stop) {
        return;
      }
      final route = avoidTolls
          ? options.firstWhere((route) => route.avoidTolls,
              orElse: () => options.first)
          : options.first;
      setState(() {
        _routeOptions = options;
        _tollQuotes = {
          if (preview)
            for (final option in options)
              if (option.hasToll && option.tollPlazas.isNotEmpty)
                option: _tollRates.estimate(option),
        };
        _setRoute(route);
      });
      await _showRoute(route, fit: fit);
    } on MapboxApiException catch (e) {
      if (mounted && revision == _routeRevision) _toast(e.message);
    } catch (_) {
      if (mounted && revision == _routeRevision) {
        _toast('Gagal mendapatkan laluan.');
      }
    } finally {
      if (mounted && revision == _routeRevision) {
        setState(() => _loadingRoute = false);
      }
    }
    if (mounted &&
        revision == _routeRevision &&
        _showOptionsOnRoute &&
        _routeOptions.isNotEmpty) {
      _showOptionsOnRoute = false;
      await _chooseRoute();
    }
  }

  void _setRoute(NavRoute route) {
    _route = route;
    _stepIndex = route.steps.length > 1 ? 1 : 0;
    _remainingDistance = route.distance;
    _remainingDuration = route.duration;
    _distToManeuver = route.steps.isNotEmpty ? route.steps.first.distance : 0;
    _offRouteCount = 0;
    _arrived = false;
    _announcedStep = -1;
    _incidentAhead = null;
    _announcedIncidents.clear();
    _fuelResults = [];
  }

  Future<void> _showRoute(NavRoute route, {required bool fit}) async {
    await _refreshRouteDrawing();
    if (!mounted || _route != route) return;
    if (fit) await _fitRoute(route);
    if (!mounted || _route != route) return;
    if (_navigating) _updateProgress();
    await _drawFuelMarkers();
    if (fit && mounted && _route == route) _loadFuelAlongRoute(route);
  }

  Future<void> _chooseRoute() async {
    final options = _routeOptions;
    final chosen = await showModalBottomSheet<NavRoute>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => RouteOptionsSheet(
        options: options,
        selected: _route,
        quotes: _tollQuotes,
      ),
    );
    if (!mounted || _routeOptions != options || _loadingRoute || _navigating) {
      return;
    }
    if (chosen == null) {
      await _cancelRoute();
      return;
    }
    if (_route == chosen) return;
    setState(() => _setRoute(chosen));
    await _showRoute(chosen, fit: true);
  }

  void _startNavigation() {
    if (_route == null || _myPos == null || _loadingRoute) return;
    setState(() {
      _navigating = true;
      _followUser = true;
      _arrived = false;
      _announcedStep = -1;
    });
    unawaited(_refreshRouteDrawing());
    _speechPrefix = 'Memulakan navigasi.';
    _updateProgress();
    if (_speechPrefix != null) _say('');
    _followCamera();
  }

  Future<void> _stopNavigation() async {
    _voice.stop();
    setState(() {
      _navigating = false;
      _followUser = true;
      _incidentAhead = null;
    });
    final route = _route;
    await _refreshRouteDrawing();
    if (mounted && route != null && _route == route) await _fitRoute(route);
  }

  Future<void> _cancelRoute() async {
    _searchFocus.unfocus();
    _voice.stop();
    setState(() {
      _navigating = false;
      _arrived = false;
      _route = null;
      _routeOptions = [];
      _tollQuotes = {};
      _loadingRoute = false;
      _routeRevision++;
      _destination = null;
      _showOptionsOnRoute = false;
      _stop = null;
      _incidentAhead = null;
      _fuelResults = [];
      _searchCtrl.clear();
      _invalidateSearch();
    });
    await _refreshRouteDrawing();
    await _drawMarkers();
    await _drawFuelMarkers();
    final pos = _myPos;
    if (pos != null) await _flyTo(pos);
  }

  void _arrive() {
    _arrived = true;
    _navigating = false;
    _remainingDistance = 0;
    _remainingDuration = 0;
    _incidentAhead = null;
    _say('Anda telah tiba di destinasi.');
  }

  /// Kemas kini kedudukan dalam laluan, arahan, suara & amaran.
  void _updateProgress() {
    final route = _route;
    final pos = _myPos;
    final dest = _destination;
    if (route == null || pos == null || dest == null) return;
    final steps = route.steps;
    if (steps.isEmpty || route.coordinates.length < 2) return;

    final snap = snapToLine(pos, route.coordinates, route.cumulative);
    _snapSegment = snap.segment;
    final along = snap.along;
    final total = route.geometryLength;
    final scale = total > 0 ? route.distance / total : 1.0;

    // Tiba di destinasi akhir?
    if (distanceBetween(pos, dest.location) < _arrivedMeters ||
        (total - along < 15 && snap.offRoute < 40)) {
      _arrive();
      return;
    }

    // Melepasi hentian (stesen minyak)?
    final stop = _stop;
    if (stop != null && distanceBetween(pos, stop.location) < 40) {
      _stop = null;
      _drawMarkers();
      _say('Anda telah tiba di hentian. Teruskan ke destinasi.');
    }

    // Gerakan seterusnya = langkah pertama yang belum dilepasi.
    var idx = steps.length - 1;
    for (var i = 1; i < steps.length; i++) {
      if (route.stepAlong[i] > along + 3) {
        idx = i;
        break;
      }
    }
    _stepIndex = idx;
    _distToManeuver = math.max(0.0, (route.stepAlong[idx] - along) * scale);
    _remainingDistance = math.max(0.0, (total - along) * scale);

    var time = 0.0;
    for (var k = 0; k < steps.length; k++) {
      final s = route.stepAlong[k];
      final e = k + 1 < steps.length ? route.stepAlong[k + 1] : total;
      if (e <= along) continue;
      final len = e - s;
      final frac = len <= 0
          ? 0.0
          : ((e - math.max(s, along)) / len).clamp(0.0, 1.0).toDouble();
      time += steps[k].duration * frac;
    }
    _remainingDuration = time;

    // Had laju di segmen semasa.
    _limitKmh = snap.segment < route.maxSpeedKmh.length
        ? route.maxSpeedKmh[snap.segment]
        : null;

    // Arahan suara untuk belokan.
    final spoke = _announceManeuver(route, idx);

    // Insiden di hadapan.
    RouteIncident? nearest;
    var nearestDist = double.infinity;
    for (final inc in route.incidents) {
      final d = (route.cumulative[inc.geometryIndex] - along) * scale;
      if (d > -30 && d < 3000 && d < nearestDist) {
        nearest = inc;
        nearestDist = d;
      }
    }
    _incidentAhead = nearest;
    _incidentDist = nearest == null ? 0.0 : math.max(0.0, nearestDist);
    if (!spoke &&
        nearest != null &&
        nearestDist < 1200 &&
        _announcedIncidents.add(nearest.geometryIndex)) {
      final label = incidentLabel(nearest.type).replaceAll(' / ', ' atau ');
      _say('Awas, ${lowerFirst(label)} di hadapan, '
          '${spokenDistance(math.max(50.0, nearestDist))}.');
    }

    // Terkeluar laluan? Kira semula.
    final limit = math.max(_offRouteMeters, _accuracy * 1.5);
    _offRouteCount = snap.offRoute > limit ? _offRouteCount + 1 : 0;
    if (_offRouteCount >= _offRouteHits &&
        !_loadingRoute &&
        DateTime.now().difference(_lastReroute) > _rerouteCooldown) {
      _lastReroute = DateTime.now();
      _offRouteCount = 0;
      _say('Mengira semula laluan.');
      _loadRoute(fit: false);
    }
  }

  /// Sebut arahan belokan pada jarak yang sesuai. Pulang true jika bercakap.
  bool _announceManeuver(NavRoute route, int idx) {
    final steps = route.steps;
    final step = steps[idx];
    final highway = _speedKmh > 60;
    final far = highway ? 1000.0 : 400.0;
    final near = highway ? 300.0 : 90.0;
    final d = _distToManeuver;

    if (idx != _announcedStep) {
      _announcedStep = idx;
      _saidFar = false;
      _saidNear = false;
      if (d > far + 600 && step.type != 'arrive') {
        _say('Ikut jalan ini sejauh ${spokenDistance(d)}.');
        return true;
      }
    }

    if (!_saidNear && d <= near) {
      _saidNear = true;
      _saidFar = true;
      var text = d < 25
          ? instructionFor(step)
          : spokenAhead(step, math.max(10.0, d));
      if (idx + 1 < steps.length &&
          route.stepAlong[idx + 1] - route.stepAlong[idx] < 150) {
        text += ', kemudian ${lowerFirst(instructionFor(steps[idx + 1]))}';
      }
      _say('$text.');
      return true;
    }

    if (!_saidFar && d <= far && d > near * 1.5) {
      _saidFar = true;
      _say('${spokenAhead(step, d)}.');
      return true;
    }
    return false;
  }

  void _toggleVoice() {
    setState(() => _voiceOn = !_voiceOn);
    _voice.enabled = _voiceOn;
    if (!_voiceOn) _voice.stop();
    _toast(_voiceOn ? 'Suara dihidupkan' : 'Suara disenyapkan');
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
    final size = MediaQuery.sizeOf(context);
    _screen = size;
    _landscape = size.width > size.height;
    _panelWidth = _landscape ? math.min(320.0, size.width * 0.34) : 0.0;

    final canReturnToSearch = _destination != null ||
        _searchCtrl.text.isNotEmpty ||
        _fuelResults.isNotEmpty;
    return PopScope<void>(
      canPop: !canReturnToSearch,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && canReturnToSearch) unawaited(_cancelRoute());
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(child: _mapView),
            if (_landscape) ..._buildLandscape() else ..._buildPortrait(),
          ],
        ),
      ),
    );
  }

  /// Peta dibina sekali sahaja supaya kamera tidak ditetapkan semula
  /// setiap kali skrin dikemas kini.
  late final Widget _mapView = Listener(
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
        onStyleLoadedListener: (_) => _onStyleLoaded(),
      ),
    );

  /// Telefon menegak: arahan di atas, ringkasan di bawah.
  List<Widget> _buildPortrait() {
    return [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _buildTopContent(),
          ),
        ),
      ),
      Positioned(
        left: 12,
        right: 12,
        bottom: 12,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMapControls(),
              const SizedBox(height: 10),
              _buildBottomContent(),
            ],
          ),
        ),
      ),
    ];
  }

  /// Telefon melintang: semua maklumat dalam satu panel di kiri,
  /// peta kekal jelas di kanan.
  List<Widget> _buildLandscape() {
    return [
      // Arahan / carian: kecil di atas kiri.
      Positioned(
        top: 0,
        left: 0,
        width: _panelWidth,
        child: SafeArea(
          right: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 0, 0),
            child: _buildTopContent(),
          ),
        ),
      ),
      // Ringkasan perjalanan: kecil di bawah kiri.
      Positioned(
        bottom: 0,
        left: 0,
        width: _panelWidth,
        child: SafeArea(
          right: false,
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 0, 6),
            child: _buildBottomContent(),
          ),
        ),
      ),
      Positioned(
        right: 12,
        bottom: 12,
        left: _panelWidth + 12,
        child: SafeArea(left: false, top: false, child: _buildMapControls()),
      ),
    ];
  }

  Widget _buildTopContent() {
    final route = _route;
    if (_navigating && route != null && route.steps.isNotEmpty) {
      final step = route.steps[_stepIndex];
      NavStep? next;
      if (_stepIndex + 1 < route.steps.length &&
          route.stepAlong[_stepIndex + 1] - route.stepAlong[_stepIndex] <
              300) {
        next = route.steps[_stepIndex + 1];
      }
      final incident = _incidentAhead;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ManeuverBanner(
            step: step,
            distance: _distToManeuver,
            next: next,
            compact: _landscape,
          ),
          if (incident != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: IncidentPill(
                incident: incident,
                distanceAhead: _incidentDist,
              ),
            ),
          ],
        ],
      );
    }
    return _buildSearch();
  }

  Widget _buildBottomContent() {
    if (_arrived) {
      return PanelCard(
        child: Row(
          children: [
            const Icon(Icons.flag, color: kNavGreen, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Anda telah tiba di ${_destination?.name ?? 'destinasi'}',
                style: const TextStyle(fontSize: 17),
              ),
            ),
            FilledButton(
                onPressed: _cancelRoute, child: const Text('Selesai')),
          ],
        ),
      );
    }

    final route = _route;
    if (route == null) {
      if (!_loadingRoute) return const SizedBox.shrink();
      return const PanelCard(
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 14),
            Text('Mengira laluan...', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    if (_navigating) {
      return TripBar(
        remainingDuration: _remainingDuration,
        remainingDistance: _remainingDistance,
        trafficDelay: route.trafficDelay,
        voiceOn: _voiceOn,
        onToggleVoice: _toggleVoice,
        onFuel: _findFuel,
        onSettings: _openSettings,
        onEnd: _stopNavigation,
        compact: _landscape,
      );
    }

    return RoutePreviewCard(
      route: route,
      tollQuote: _tollQuotes[route],
      onChooseRoute: _routeOptions.isNotEmpty && !_loadingRoute
          ? _chooseRoute
          : null,
      destinationName: _destination?.name ?? 'Destinasi',
      stopName: _stop?.name,
      onRemoveStop: _stop == null ? null : _removeStop,
      remainingDuration: _remainingDuration,
      remainingDistance: _remainingDistance,
      loading: _loadingRoute,
      onStart: _myPos == null ? null : _startNavigation,
      onCancel: _cancelRoute,
      onFuel: _findFuel,
    );
  }

  /// Nama jalan semasa (jalan yang sedang dilalui).
  String get _currentRoadName {
    final route = _route;
    if (!_navigating || route == null || _stepIndex <= 0) return '';
    return route.steps[_stepIndex - 1].name.trim();
  }

  /// Nama jalan (tengah) dan butang/laju peta (kanan).
  Widget _buildMapControls() {
    final recenter = _navigating && !_followUser;
    final road = _currentRoadName;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: road.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(left: 76, right: 8),
                  child: Center(child: RoadNamePill(name: road)),
                ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_navigating && _landscape) ...[
              MapRoundButton(
                tooltip: _voiceOn ? 'Senyapkan suara' : 'Hidupkan suara',
                icon: _voiceOn ? Icons.volume_up : Icons.volume_off,
                onPressed: _toggleVoice,
              ),
              const SizedBox(height: 10),
              MapRoundButton(
                tooltip: 'Stesen minyak di laluan',
                icon: Icons.local_gas_station,
                onPressed: _findFuel,
              ),
              const SizedBox(height: 10),
            ],
            if (!_navigating) ...[
              MapRoundButton(
                tooltip: 'Tetapan peta',
                icon: switch (_themePref) {
                  ThemePref.auto => Icons.brightness_auto,
                  ThemePref.day => Icons.light_mode,
                  ThemePref.night => Icons.dark_mode,
                },
                onPressed: _openSettings,
              ),
              const SizedBox(height: 10),
            ],
            if (recenter || !_navigating) ...[
              MapRoundButton(
                tooltip: recenter ? 'Pusat semula' : 'Lokasi saya',
                icon: recenter ? Icons.navigation : Icons.my_location,
                active: recenter,
                onPressed: _onLocatePressed,
              ),
              if (_navigating) const SizedBox(height: 10),
            ],
            if (_navigating) ...[
              Material(
                elevation: 4,
                shape: const CircleBorder(),
                color: Theme.of(context).colorScheme.surface,
                child: PopupMenuButton<NavigationView>(
                  tooltip: 'Tukar paparan navigasi',
                  initialValue: _navigationView,
                  onSelected: _setNavigationView,
                  icon: Icon(_navigationView == NavigationView.closer
                      ? Icons.zoom_in
                      : Icons.layers_outlined),
                  itemBuilder: (_) => [
                    for (final view in NavigationView.values)
                      CheckedPopupMenuItem(
                        value: view,
                        checked: _navigationView == view,
                        child: Text(view.label),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (_navigating)
              SpeedBadge(speedKmh: _speedKmh, limitKmh: _limitKmh),
          ],
        ),
      ],
    );
  }

  void _setNavigationView(NavigationView view) {
    setState(() {
      _navigationView = view;
      if (_navigating) _followUser = true;
    });
    if (_navigating) unawaited(_followCamera());
  }

  /// Tetapan peta dan pandangan semasa navigasi.
  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tetapan', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 12),
                const Text('Tema peta'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in ThemePref.values)
                      ChoiceChip(
                        label: Text(switch (t) {
                          ThemePref.auto => 'Auto',
                          ThemePref.day => 'Siang',
                          ThemePref.night => 'Malam',
                        }),
                        selected: _themePref == t,
                        onSelected: (_) {
                          setState(() => _themePref = t);
                          setSheet(() {});
                          _applyTheme();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Paparan navigasi'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final view in NavigationView.values)
                      ChoiceChip(
                        label: Text(view.label),
                        selected: _navigationView == view,
                        onSelected: (_) {
                          _setNavigationView(view);
                          setSheet(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Suara arahan'),
                  value: _voiceOn,
                  onChanged: (_) {
                    _toggleVoice();
                    setSheet(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bangunan 3D'),
                  value: _show3d,
                  onChanged: (v) {
                    setState(() => _show3d = v);
                    setSheet(() {});
                    _applyMapLook();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onLocatePressed() {
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
  }

  Widget _buildSearch() {
    final scheme = Theme.of(context).colorScheme;
    final showFuelChip = _searchCtrl.text.isEmpty && _route == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelCard(
          padding: EdgeInsets.zero,
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (q) {
              if (q.trim().length >= 2) _runSearch(q.trim());
            },
            style: TextStyle(color: scheme.onSurface, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Cari destinasi',
              hintStyle: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.square(
                    dimension: 36,
                    child: Icon(Icons.search, color: scheme.onPrimaryContainer),
                  ),
                ),
              ),
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
                          icon: const Icon(Icons.close),
                          tooltip: 'Kosongkan carian',
                          onPressed: _cancelRoute,
                        )
                      : null),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        if (showFuelChip)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                elevation: 2,
                backgroundColor: scheme.surface,
                side: BorderSide(color: scheme.outlineVariant),
                avatar: Icon(Icons.local_gas_station, color: scheme.primary),
                label: const Text('Stesen minyak berdekatan'),
                onPressed: _findFuel,
              ),
            ),
          ),
        if (_results.isNotEmpty || _searchMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: PanelCard(
              padding: EdgeInsets.zero,
              child: _searchMessage != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_searchMessage!),
                    )
                  : ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: _landscape ? 220 : 320,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _results.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = _results[i];
                          final pos = _myPos;
                          return ListTile(
                            leading: Icon(Icons.place, color: scheme.primary),
                            title: Text(
                              r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              r.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: pos == null
                                ? null
                                : Text(
                                    formatDistance(
                                        distanceBetween(pos, r.location)),
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
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
}
