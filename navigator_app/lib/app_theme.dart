import 'package:material_ui/material_ui.dart';

/// true = tema malam. Ditukar oleh skrin navigasi (auto/siang/malam).
final ValueNotifier<bool> nightMode = ValueNotifier<bool>(isNightHour());

/// Waktu malam: 7 petang hingga 7 pagi.
bool isNightHour([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  return h < 7 || h >= 19;
}

final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF1A73E8),
    brightness: Brightness.light,
  ),
);

final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4FC3F7),
    brightness: Brightness.dark,
  ),
);
