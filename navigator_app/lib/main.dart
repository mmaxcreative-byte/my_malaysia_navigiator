import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';
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
    return ValueListenableBuilder<bool>(
      valueListenable: nightMode,
      builder: (context, night, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'My Malaysia Navigator',
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: night ? ThemeMode.dark : ThemeMode.light,
        home: const NavigationScreen(),
      ),
    );
  }
}
