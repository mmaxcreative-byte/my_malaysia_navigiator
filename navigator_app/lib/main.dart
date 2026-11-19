import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:material_ui/material_ui.dart';

import 'config.dart';
import 'navigation_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  mb.MapboxOptions.setAccessToken(kMapboxToken);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Malaysia Navigator',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
      ),
      home: const NavigationScreen(),
    );
  }
}
