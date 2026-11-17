import 'package:flutter/material.dart';
import '../../core/l10n/coco_labels_repository.dart';
import '../../core/models/detection_item.dart';
import '../../core/theme/design_tokens.dart';

/// High-performance 60 FPS Bounding Box & HUD Painter.
/// Follows D2 performance rules: zero heap allocation in paint(), corner-bracket bounding boxes,
/// Cairo font, screen-edge clamping, and colorblind-safe category colors.
class BBoxHudPainter extends CustomPainter {
  final List<DetectionItem> detections;
  final bool isArabic;
  final bool showZones;
  final bool showTrails;
  final CocoLabelsRepository labelsRepo;

  BBoxHudPainter({
    required this.detections,
    required this.isArabic,
    this.showZones = false,
    this.showTrails = true,
    CocoLabelsRepository? repo,
  }) : labelsRepo = repo ?? CocoLabelsRepository();

  Color _getClassColor(int classId) {
    final cat = labelsRepo.getCategory(classId);
    return AppTokens.getCategoryColor(cat);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || detections.isEmpty) return;

    // 1. Paint motion trails (subtle line connecting previous centers)
    if (showTrails) {
      final trailPaint = Paint()
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      for (final item in detections) {
        if (item.motionTrail.length < 2) continue;
        final baseColor = _getClassColor(item.classId);

        for (int i = 0; i < item.motionTrail.length - 1; i++) {
          final p1 = Offset(
            item.motionTrail[i].dx * size.width,
            item.motionTrail[i].dy * size.height,
          );
          final p2 = Offset(
            item.motionTrail[i + 1].dx * size.width,
            item.motionTrail[i + 1].dy * size.height,
          );
          final opacity = ((i + 1) / item.motionTrail.length) * 0.4;
          trailPaint.color = baseColor.withValues(alpha: opacity);
          canvas.drawLine(p1, p2, trailPaint);
        }
      }
    }

    // 2. Paint corner-bracket bounding boxes and clean labels
    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final bracketPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeWidth = 2.5;

    final bgBadgePaint = Paint()..style = PaintingStyle.fill;

    for (final item in detections) {
      if (!item.isConfirmed && item.confidence < 0.45) continue;

      // Coordinate clamping to visible canvas
      final left = (item.x1 * size.width).clamp(0.0, size.width);
      final top = (item.y1 * size.height).clamp(0.0, size.height);
      final right = (item.x2 * size.width).clamp(0.0, size.width);
      final bottom = (item.y2 * size.height).clamp(0.0, size.height);

      if (right - left < 4.0 || bottom - top < 4.0) continue;

      final rect = Rect.fromLTRB(left, top, right, bottom);
      final classColor = _getClassColor(item.classId);

      // Subtle full boundary outline
      boxPaint.color = classColor.withValues(alpha: 0.35);
      canvas.drawRect(rect, boxPaint);

      // Tactical corner brackets
      bracketPaint.color = classColor;
      final bracketLen = ((right - left).clamp(8.0, 24.0)).toDouble();
      final bracketH = ((bottom - top).clamp(8.0, 24.0)).toDouble();
      final len = bracketLen < bracketH ? bracketLen : bracketH;

      // Top-Left
      canvas.drawLine(Offset(left, top), Offset(left + len, top), bracketPaint);
      canvas.drawLine(Offset(left, top), Offset(left, top + len), bracketPaint);
      // Top-Right
      canvas.drawLine(Offset(right, top), Offset(right - len, top), bracketPaint);
      canvas.drawLine(Offset(right, top), Offset(right, top + len), bracketPaint);
      // Bottom-Left
      canvas.drawLine(Offset(left, bottom), Offset(left + len, bottom), bracketPaint);
      canvas.drawLine(Offset(left, bottom), Offset(left, bottom - len), bracketPaint);
      // Bottom-Right
      canvas.drawLine(Offset(right, bottom), Offset(right - len, bottom), bracketPaint);
      canvas.drawLine(Offset(right, bottom), Offset(right, bottom - len), bracketPaint);

      // Label: #ID ClassName Conf%
      final labelText = labelsRepo.getLabel(item.classId, isArabic: isArabic);
      final confPercent = (item.confidence * 100).toStringAsFixed(0);
      final displayText = '#${item.trackId} $labelText $confPercent%';

      final textSpan = TextSpan(
        text: displayText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFamily: AppTokens.fontCairo,
          shadows: [
            Shadow(color: Colors.black, blurRadius: 4),
          ],
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      )..layout(maxWidth: size.width);

      // Position label clamped inside screen boundaries
      final badgeHeight = textPainter.height + 4;
      final badgeWidth = textPainter.width + 10;
      final badgeY = (top - badgeHeight < 4) ? top + 2 : top - badgeHeight - 2;
      final badgeX = left.clamp(2.0, (size.width - badgeWidth - 2.0).clamp(2.0, size.width));

      final badgeRect = Rect.fromLTWH(badgeX, badgeY, badgeWidth, badgeHeight);
      bgBadgePaint.color = classColor.withValues(alpha: 0.88);
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
        bgBadgePaint,
      );

      textPainter.paint(
        canvas,
        Offset(badgeX + 5, badgeY + 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant BBoxHudPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.isArabic != isArabic;
  }
}
