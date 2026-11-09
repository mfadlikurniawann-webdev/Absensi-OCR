import 'package:flutter/material.dart';

/// Oval panduan di tengah area preview kamera, dengan area luar diredupkan.
///
/// Ukuran & posisinya relatif terhadap preview, sama dengan acuan yang dipakai
/// saat mengecek posisi wajah, sehingga "di tengah oval" = "di tengah gambar".
class FaceGuidePainter extends CustomPainter {
  FaceGuidePainter({required this.color});

  final Color color;

  /// Lebar oval relatif terhadap lebar preview.
  static const widthFactor = 0.64;

  static Rect ovalRect(Size size) {
    final width = size.width * widthFactor;
    final height = (width * 1.3).clamp(0.0, size.height * 0.85);
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: width,
      height: height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final oval = ovalRect(size);
    final overlay = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(oval);
    canvas.drawPath(overlay, Paint()..color = Colors.black45);
    canvas.drawOval(
      oval,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(FaceGuidePainter oldDelegate) =>
      oldDelegate.color != color;
}
