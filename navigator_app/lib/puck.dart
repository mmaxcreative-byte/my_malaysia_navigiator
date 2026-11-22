import 'dart:typed_data';
import 'dart:ui' as ui;

/// Lukis ikon anak panah navigasi sebagai PNG,
/// untuk dijadikan ikon lokasi di peta.
Future<Uint8List?> buildArrowPuck({
  int size = 72,
  ui.Color fill = const ui.Color(0xFF087FE2),
}) async {
  try {
    final s = size.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Bentuk anak panah: hujung di atas, ekor berlekuk di bawah.
    final path = ui.Path()
      ..moveTo(s * 0.50, s * 0.08)
      ..lineTo(s * 0.86, s * 0.88)
      ..lineTo(s * 0.50, s * 0.70)
      ..lineTo(s * 0.14, s * 0.88)
      ..close();

    canvas.drawShadow(path, const ui.Color(0xFF000000), 4, false);
    canvas.drawPath(
      path,
      ui.Paint()
        ..color = fill
        ..style = ui.PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      ui.Paint()
        ..color = const ui.Color(0xFFFFFFFF)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = s * 0.06
        ..strokeJoin = ui.StrokeJoin.round,
    );

    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(size, size);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  } catch (_) {
    return null;
  }
}
