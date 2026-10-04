import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Generate app icon assets', (tester) async {
    Future<void> saveIcon(String path, int size) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final scale = size / 1024;
      canvas.scale(scale);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 1024, 1024),
          const Radius.circular(200),
        ),
        Paint()..color = const Color(0xFF120E15),
      );

      final red = Paint()..color = const Color(0xFFD93846);
      Path polygon(List<Offset> points) => Path()..addPolygon(points, true);
      canvas
        ..drawPath(polygon(const [
          Offset(350, 280), Offset(415, 280), Offset(355, 730), Offset(290, 730),
        ]), red)
        ..drawPath(polygon(const [
          Offset(530, 280), Offset(595, 280), Offset(535, 730), Offset(470, 730),
        ]), red)
        ..drawPath(polygon(const [
          Offset(710, 280), Offset(775, 280), Offset(715, 730), Offset(650, 730),
        ]), red)
        ..drawPath(polygon(const [
          Offset(656, 680), Offset(780, 680), Offset(773, 730), Offset(650, 730),
        ]), red)
        ..drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(270, 462, 11, 118), const Radius.circular(2)), Paint()..color = const Color(0xFFE5636C))
        ..drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(283, 462, 11, 118), const Radius.circular(2)), Paint()..color = const Color(0xFFE5636C))
        ..drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(296, 462, 11, 118), const Radius.circular(2)), Paint()..color = const Color(0xFFE5636C))
        ..drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(570, 462, 11, 118), const Radius.circular(2)), Paint()..color = const Color(0xFFE5636C))
        ..drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(583, 462, 11, 118), const Radius.circular(2)), Paint()..color = const Color(0xFFE5636C))
        ..drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(596, 462, 11, 118), const Radius.circular(2)), Paint()..color = const Color(0xFFE5636C))
        ..drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(250, 502, 380, 38), const Radius.circular(19),
          ),
          Paint()..color = const Color(0xFFF4EDE8),
        );

      final image = await recorder.endRecording().toImage(size, size);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(png!.buffer.asUint8List());
    }

    await tester.runAsync(() async {
      await saveIcon('assets/app_icon.png', 1024);
      await saveIcon('web/icons/Icon-512.png', 512);
      await saveIcon('web/icons/Icon-192.png', 192);
      await saveIcon('web/icons/Icon-maskable-512.png', 512);
      await saveIcon('web/icons/Icon-maskable-192.png', 192);
      await saveIcon('web/favicon.png', 32);
      await saveIcon('android/app/src/main/res/mipmap-mdpi/ic_launcher.png', 48);
      await saveIcon('android/app/src/main/res/mipmap-hdpi/ic_launcher.png', 72);
      await saveIcon('android/app/src/main/res/mipmap-xhdpi/ic_launcher.png', 96);
      await saveIcon('android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', 144);
      await saveIcon('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', 192);
    });
  });
}
