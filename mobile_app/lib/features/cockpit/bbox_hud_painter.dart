import 'package:flutter/material.dart';
import '../../core/l10n/coco_labels_repository.dart';
import '../../core/models/detection_item.dart';
import '../../core/ffi/native_structs.dart';

/// Decoupled CustomPainter rendering 60 FPS bounding boxes, motion trails, and spatial zones
class BBoxHudPainter extends CustomPainter {
  final List<DetectionItem> detections;
  final bool isArabic;
  final bool showZones;
  final bool showTrails;
  final CocoLabelsRepository labelsRepo;

  BBoxHudPainter({
    required this.detections,
    required this.isArabic,
    this.showZones = true,
    this.showTrails = true,
    CocoLabelsRepository? repo,
  }) : labelsRepo = repo ?? CocoLabelsRepository();

  // Distinct palette for COCO classes
  static const List<Color> _palette = [
    Color(0xFF00E5FF), // Cyan
    Color(0xFFFF9100), // Orange
    Color(0xFF76FF03), // Light Green
    Color(0xFFFF1744), // Red
    Color(0xFFD500F9), // Purple
    Color(0xFFFFEA00), // Yellow
    Color(0xFF1DE9B6), // Teal
    Color(0xFFFF4081), // Pink
  ];

  Color _getClassColor(int classId) => _palette[classId % _palette.length];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. Draw subtle vertical dividing lines and zone headers (0.33 and 0.66)
    if (showZones) {
      final zonePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      final xLeft = size.width * 0.33;
      final xRight = size.width * 0.66;
      canvas.drawLine(Offset(xLeft, 0), Offset(xLeft, size.height), zonePaint);
      canvas.drawLine(
          Offset(xRight, 0), Offset(xRight, size.height), zonePaint);

      // Subtle zone header watermark
      _drawZoneHeader(canvas, isArabic ? 'يسار' : 'LEFT', 0, xLeft / 2);
      _drawZoneHeader(
          canvas, isArabic ? 'وسط' : 'CENTER', 0, (xLeft + xRight) / 2);
      _drawZoneHeader(
          canvas, isArabic ? 'يمين' : 'RIGHT', 0, (xRight + size.width) / 2);
    }

    // 2. Paint motion trails
    if (showTrails) {
      for (final item in detections) {
        if (item.motionTrail.length < 2) continue;
        final baseColor = _getClassColor(item.classId);
        final trailPaint = Paint()
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

        for (int i = 0; i < item.motionTrail.length - 1; i++) {
          final p1 = Offset(item.motionTrail[i].dx * size.width,
              item.motionTrail[i].dy * size.height);
          final p2 = Offset(item.motionTrail[i + 1].dx * size.width,
              item.motionTrail[i + 1].dy * size.height);
          final opacity = ((i + 1) / item.motionTrail.length) * 0.5;
          trailPaint.color = baseColor.withValues(alpha: opacity);
          canvas.drawLine(p1, p2, trailPaint);
        }
      }
    }

    // 3. Paint bounding boxes and badges
    for (final item in detections) {
      if (item.trackState == TrackState.deleted) continue;

      final rect = Rect.fromLTRB(
        item.x1 * size.width,
        item.y1 * size.height,
        item.x2 * size.width,
        item.y2 * size.height,
      );

      final classColor = _getClassColor(item.classId);

      // Border style based on tracking confirmation
      final boxPaint = Paint()
        ..color =
            item.isConfirmed ? classColor : classColor.withValues(alpha: 0.4)
        ..strokeWidth = item.isConfirmed ? 2.5 : 1.5
        ..style = PaintingStyle.stroke;

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rrect, boxPaint);

      // Corner accent brackets for verified target look
      if (item.isConfirmed) {
        _drawCornerBrackets(canvas, rect, classColor);
      }

      // Label background & text: #ID Label Conf% [Zone | Age]
      final labelText = labelsRepo.getLabel(item.classId, isArabic: isArabic);
      final confPercent = (item.confidence * 100).toStringAsFixed(0);
      final ageStr = '${item.trackAgeSeconds.toStringAsFixed(1)}s';
      final zoneStr = _zoneBadgeText(item.spatialZone);

      final displayText = isArabic
          ? '#${item.trackId} $labelText $confPercent% ($zoneStr | $ageStr)'
          : '#${item.trackId} $labelText $confPercent% ($zoneStr | $ageStr)';

      final textSpan = TextSpan(
        text: displayText,
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          fontFamily: isArabic ? 'Arial' : null,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 4),
          ],
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      )..layout(maxWidth: size.width);

      // Label badge positioning
      final badgeHeight = textPainter.height + 6;
      final badgeWidth = textPainter.width + 12;
      final badgeY =
          (rect.top - badgeHeight < 0) ? rect.top : rect.top - badgeHeight;
      final badgeX = rect.left.clamp(0.0, size.width - badgeWidth);

      final badgeRect = Rect.fromLTWH(badgeX, badgeY, badgeWidth, badgeHeight);
      final bgPaint = Paint()
        ..color = classColor.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
        bgPaint,
      );

      textPainter.paint(
        canvas,
        Offset(badgeX + 6, badgeY + 3),
      );
    }
  }

  void _drawZoneHeader(Canvas canvas, String label, double y, double x) {
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.15),
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
    final tp = TextPainter(
      text: textSpan,
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y + 4));
  }

  void _drawCornerBrackets(Canvas canvas, Rect r, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    const len = 8.0;
    // Top-left
    canvas.drawLine(Offset(r.left, r.top), Offset(r.left + len, r.top), p);
    canvas.drawLine(Offset(r.left, r.top), Offset(r.left, r.top + len), p);
    // Top-right
    canvas.drawLine(Offset(r.right, r.top), Offset(r.right - len, r.top), p);
    canvas.drawLine(Offset(r.right, r.top), Offset(r.right, r.top + len), p);
    // Bottom-left
    canvas.drawLine(
        Offset(r.left, r.bottom), Offset(r.left + len, r.bottom), p);
    canvas.drawLine(
        Offset(r.left, r.bottom), Offset(r.left, r.bottom - len), p);
    // Bottom-right
    canvas.drawLine(
        Offset(r.right, r.bottom), Offset(r.right - len, r.bottom), p);
    canvas.drawLine(
        Offset(r.right, r.bottom), Offset(r.right, r.bottom - len), p);
  }

  String _zoneBadgeText(SpatialZone zone) {
    if (isArabic) {
      switch (zone) {
        case SpatialZone.left:
          return 'يسار';
        case SpatialZone.center:
          return 'وسط';
        case SpatialZone.right:
          return 'يمين';
      }
    } else {
      switch (zone) {
        case SpatialZone.left:
          return 'L';
        case SpatialZone.center:
          return 'C';
        case SpatialZone.right:
          return 'R';
      }
    }
  }

  @override
  bool shouldRepaint(covariant BBoxHudPainter oldDelegate) => true;
}
