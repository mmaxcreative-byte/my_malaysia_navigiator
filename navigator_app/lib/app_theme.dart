import 'package:material_ui/material_ui.dart';

/// true = tema malam. Ditukar oleh skrin navigasi (auto/siang/malam).
final ValueNotifier<bool> nightMode = ValueNotifier<bool>(isNightHour());

/// Waktu malam: 7 petang hingga 7 pagi.
bool isNightHour([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  return h < 7 || h >= 19;
}

ThemeData _navigationTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF1765C1),
        brightness: brightness,
      ).copyWith(
        surface: isDark ? const Color(0xFF152338) : const Color(0xFFF9FBFF),
        surfaceContainerHigh: isDark
            ? const Color(0xFF202F47)
            : const Color(0xFFEFF4FC),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
  );
}

final ThemeData lightTheme = _navigationTheme(Brightness.light);
final ThemeData darkTheme = _navigationTheme(Brightness.dark);
