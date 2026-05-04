import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Generate Branding Assets', (tester) async {
    print('--- STARTING ASSET GENERATION ---');

    Future<void> saveIcon(String path, {bool isDark = true, bool isSplash = false}) async {
      print('Generating: $path...');
      final recorder = ui.PictureRecorder();
      final size = isSplash ? 512.0 : 1024.0;
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
      
      final bgPaint = Paint()..color = isDark ? const Color(0xFF120E15) : const Color(0xFFFAFAFA);
      if (isSplash) {
        canvas.drawRect(Rect.fromLTWH(0, 0, size, size), bgPaint);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size, size), Radius.circular(size * 0.2)), bgPaint);
      }

      final scale = size / 1024.0;
      final accentColor = const Color(0xFFD93846);
      
      // LOGO DESIGN: Modern Angular "HL"
      // Drawing style: Minimalist slanted vertical bars similar to modern HP logo
      final logoPaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.fill;

      void drawSlantedBar(double x, double y, double width, double height) {
        final path = Path()
          ..moveTo(x * scale, y * scale)
          ..lineTo((x + width) * scale, y * scale)
          ..lineTo((x + width - 40) * scale, (y + height) * scale)
          ..lineTo((x - 40) * scale, (y + height) * scale)
          ..close();
        canvas.drawPath(path, logoPaint);
      }

      // H - Left Bar
      drawSlantedBar(350, 300, 60, 424);
      // H - Right Bar
      drawSlantedBar(480, 300, 60, 424);
      // H - Crossbar (slightly slanted)
      final hCrossPath = Path()
        ..moveTo(395 * scale, 480 * scale)
        ..lineTo(525 * scale, 480 * scale)
        ..lineTo(515 * scale, 530 * scale)
        ..lineTo(385 * scale, 530 * scale)
        ..close();
      canvas.drawPath(hCrossPath, logoPaint);

      // L - Vertical Bar
      drawSlantedBar(610, 300, 60, 424);
      // L - Horizontal Bar
      final lBasePath = Path()
        ..moveTo(570 * scale, 674 * scale)
        ..lineTo(750 * scale, 674 * scale)
        ..lineTo(710 * scale, 724 * scale)
        ..lineTo(530 * scale, 724 * scale)
        ..close();
      canvas.drawPath(lBasePath, logoPaint);

      final picture = recorder.endRecording();
      
      print('  Step: picture.toImage...');
      final img = await picture.toImage(size.toInt(), size.toInt());
      
      print('  Step: img.toByteData...');
      final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
      
      print('  Step: File.write...');
      final file = File(path);
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      file.writeAsBytesSync(pngBytes!.buffer.asUint8List());
      print('Saved: $path (${file.lengthSync()} bytes)');
    }

    await tester.runAsync(() async {
      await saveIcon('assets/app_icon.png');
      await saveIcon('assets/splash_icon.png', isDark: false, isSplash: true);
      await saveIcon('assets/splash_icon_dark.png', isDark: true, isSplash: true);
    });

    print('--- ALL ASSETS GENERATED SUCCESSFULLY ---');
  });
}
