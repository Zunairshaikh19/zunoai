import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Cached decoded watermark mark so repeated downloads/shares don't
/// re-decode the PNG from the asset bundle every time.
ui.Image? _cachedMark;

Future<ui.Image> _loadMark() async {
  if (_cachedMark != null) return _cachedMark!;
  final data = await rootBundle.load('assets/watermark/watermark_mark.png');
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  _cachedMark = frame.image;
  return _cachedMark!;
}

/// Stamps the small "Zuno AI" brand mark (spark + wordmark, on a translucent
/// pill) into the bottom-right corner of image bytes. Used so a free-tier
/// result stays branded in the actual downloaded/shared file, not just in
/// the on-screen preview.
Future<Uint8List> applyWatermark(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final mark = await _loadMark();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(image, Offset.zero, Paint());

  // Mark width ~26% of the shorter side, capped so it never looks oversized
  // on very wide/tall generations; keeps the mark's own aspect ratio.
  final shortSide = image.width < image.height ? image.width : image.height;
  final markWidth = (shortSide * 0.26).clamp(80.0, 340.0);
  final markHeight = markWidth * (mark.height / mark.width);
  final inset = shortSide * 0.035;

  final dstRect = Rect.fromLTWH(
    image.width - markWidth - inset,
    image.height - markHeight - inset,
    markWidth,
    markHeight,
  );
  final srcRect = Rect.fromLTWH(0, 0, mark.width.toDouble(), mark.height.toDouble());

  canvas.drawImageRect(mark, srcRect, dstRect, Paint()..filterQuality = FilterQuality.high);

  final picture = recorder.endRecording();
  final outputImage = await picture.toImage(image.width, image.height);
  final byteData = await outputImage.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
