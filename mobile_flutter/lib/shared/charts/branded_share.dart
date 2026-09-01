import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
// Only DateFormat: intl also exports a TextDirection that shadows dart:ui's.
import 'package:intl/intl.dart' show DateFormat;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_tokens.dart';

/// Exports a chart as a branded PNG — the chart composited under a RepRoot
/// header (logo mark + wordmark + chart title) and a footer strip — and
/// hands it to the Android share sheet.
///
/// Flutter equivalent of mobile/src/app/shared/branded-share.service.ts. That
/// version rasterises a Chart.js <canvas> and composites with the Canvas 2D
/// API; here the chart is a widget subtree, so it is captured through a
/// RepaintBoundary and composited with dart:ui. Same output, same brand, and
/// the layout is equivalent rather than pixel-identical — the same stance the
/// chart renderer takes.
///
/// Two deliberate improvements over the Ionic version:
///
///  * Colors come from AppColors, not the hardcoded palette in the TS service.
///    That service uses #0b7de3 as primary where the app's actual brand blue is
///    #2563EB, so every graph an Ionic user shares carries a logo in the wrong
///    blue. Nothing here should reintroduce that — these are the same tokens
///    the app itself paints with.
///
///  * A ring chart exports with its center label. In Ionic the percentage is an
///    HTML overlay outside the <canvas>, so shared rings come out as a bare
///    donut with no number on it. Capturing the widget subtree includes it.
class BrandedShare {
  const BrandedShare._();

  /// Exported at 3x so the PNG still looks sharp after a messaging app
  /// recompresses it.
  static const double _exportScale = 3;

  static const double _pad = 16;
  static const double _headerHeight = 112;
  static const double _footerHeight = 34;
  static const double _markSize = 40;

  /// Keeps the header from looking stranded above a narrow chart.
  static const double _minContentWidth = 320;

  /// Captures the subtree behind [boundaryKey] and opens the share sheet.
  ///
  /// Returns false if the boundary isn't mounted or hasn't painted yet, which
  /// is the one failure the caller can act on; anything else throws.
  static Future<bool> shareChart({
    required GlobalKey boundaryKey,
    required String title,
    required String subtitle,
    required Brightness brightness,
  }) async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return false;

    final ui.Image chart = await boundary.toImage(pixelRatio: _exportScale);
    final ui.Image branded;
    try {
      branded = await _compose(chart, title, subtitle, brightness);
    } finally {
      chart.dispose();
    }

    final ByteData? png;
    try {
      png = await branded.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      branded.dispose();
    }
    if (png == null) return false;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_fileName(title)}');
    await file.writeAsBytes(png.buffer.asUint8List(), flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        title: '$title — RepRoot',
        text: subtitle.isEmpty ? title : '$title · $subtitle',
      ),
    );
    return true;
  }

  /// `Body weight (lb)` -> `reproot-body-weight-lb.png`
  static String _fileName(String title) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return 'reproot-${slug.isEmpty ? 'chart' : slug}.png';
  }

  static Future<ui.Image> _compose(
    ui.Image chart,
    String title,
    String subtitle,
    Brightness brightness,
  ) async {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightSurface;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final text = isDark ? AppColors.darkText : AppColors.lightText;
    final muted = isDark ? AppColors.darkMuted : AppColors.lightMuted;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final primary = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    // The capture is in device pixels; lay out in logical ones and scale the
    // whole canvas up at the end so every number below reads as a real size.
    final chartWidth = chart.width / _exportScale;
    final chartHeight = chart.height / _exportScale;
    final contentWidth = chartWidth < _minContentWidth
        ? _minContentWidth
        : chartWidth;
    final width = contentWidth + _pad * 2;
    final height = _headerHeight + chartHeight + _footerHeight;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_exportScale);

    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = bg);

    _drawMark(canvas, const Offset(_pad, _pad), primary);

    const brandX = _pad + _markSize + 12;
    _drawText(
      canvas,
      'RepRoot',
      const Offset(brandX, _pad + 2),
      TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w800),
    );
    _drawText(
      canvas,
      'Professional & Client Management Platform',
      const Offset(brandX, _pad + 22),
      TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w600),
    );

    _drawText(
      canvas,
      title,
      const Offset(_pad, 70),
      TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w800),
      maxWidth: width - _pad * 2,
    );
    if (subtitle.isNotEmpty) {
      _drawText(
        canvas,
        subtitle,
        const Offset(_pad, 89),
        TextStyle(color: muted, fontSize: 10.5, fontWeight: FontWeight.w600),
        maxWidth: width - _pad * 2,
      );
    }

    canvas.drawLine(
      const Offset(_pad, _headerHeight - 6),
      Offset(width - _pad, _headerHeight - 6),
      Paint()
        ..color = border
        ..strokeWidth = 1,
    );

    // Card-colored plate behind the chart: the capture is transparent wherever
    // the card showed through, and a bare chart on the page background reads
    // washed out.
    canvas.drawRect(
      Rect.fromLTWH(_pad, _headerHeight, contentWidth, chartHeight),
      Paint()..color = surface,
    );
    canvas.drawImageRect(
      chart,
      Rect.fromLTWH(0, 0, chart.width.toDouble(), chart.height.toDouble()),
      Rect.fromLTWH(
        _pad + (contentWidth - chartWidth) / 2,
        _headerHeight,
        chartWidth,
        chartHeight,
      ),
      Paint()..filterQuality = FilterQuality.high,
    );

    _drawText(
      canvas,
      'Generated ${DateFormat.yMd().format(DateTime.now())} · rep-root.com',
      Offset(_pad, height - 22),
      TextStyle(color: muted, fontSize: 9, fontWeight: FontWeight.w600),
    );

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(
        (width * _exportScale).round(),
        (height * _exportScale).round(),
      );
    } finally {
      picture.dispose();
    }
  }

  /// The RepRoot brand mark: rounded square with a dumbbell knocked out of
  /// it. Stroke coordinates are the 24-unit grid from the web/Ionic brand glyph
  /// so all three apps share one logo.
  static void _drawMark(Canvas canvas, Offset origin, Color primary) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(origin.dx, origin.dy, _markSize, _markSize),
        const Radius.circular(11),
      ),
      Paint()..color = primary,
    );

    const unit = _markSize / 24;
    Offset at(double x, double y) =>
        Offset(origin.dx + x * unit, origin.dy + y * unit);

    final stroke = Paint()
      ..color = AppColors.onPrimary
      ..strokeWidth = _markSize * 2.4 / 44
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(at(6, 8), at(6, 16), stroke);
    canvas.drawLine(at(18, 8), at(18, 16), stroke);
    canvas.drawLine(at(6, 12), at(18, 12), stroke);
    canvas.drawLine(at(3.5, 9.5), at(3.5, 14.5), stroke);
    canvas.drawLine(at(20.5, 9.5), at(20.5, 14.5), stroke);
  }

  static void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    double? maxWidth,
  }) {
    TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(fontFamily: 'Roboto'),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )
      ..layout(maxWidth: maxWidth ?? double.infinity)
      ..paint(canvas, offset);
  }
}
