import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Stamps a translucent diagonal "ZUNO AI" watermark onto image bytes.
/// Used so a free-tier result stays watermarked in the actual downloaded/
/// shared file, not just in the on-screen preview — otherwise "unlock to
/// remove" would be trivially bypassable by just saving the raw network image.
Future<Uint8List> applyWatermark(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(image, Offset.zero, Paint());

  final fontSize = image.width * 0.08;
  final paragraphBuilder = ui.ParagraphBuilder(
    ui.ParagraphStyle(textAlign: TextAlign.center, fontWeight: FontWeight.w900),
  )
    ..pushStyle(ui.TextStyle(color: const Color(0x80FFFFFF), fontSize: fontSize))
    ..addText('ZUNO AI');
  final paragraph = paragraphBuilder.build()
    ..layout(ui.ParagraphConstraints(width: image.width * 1.5));

  canvas.save();
  canvas.translate(image.width / 2, image.height / 2);
  canvas.rotate(-0.4);
  canvas.translate(-paragraph.width / 2, -paragraph.height / 2);
  canvas.drawParagraph(paragraph, Offset.zero);
  canvas.restore();

  final picture = recorder.endRecording();
  final outputImage = await picture.toImage(image.width, image.height);
  final byteData = await outputImage.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
