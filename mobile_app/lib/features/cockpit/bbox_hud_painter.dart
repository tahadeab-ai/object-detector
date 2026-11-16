import 'package:flutter/material.dart';
import '../../core/l10n/coco_labels_repository.dart';
import '../../core/models/detection_item.dart';
import '../../core/ffi/native_structs.dart';

/// Decoupled CustomPainter rendering 60 FPS bounding boxes and spatial zones
class BBoxHudPainter extends CustomPainter {
  final List<DetectionItem> detections;
  final bool isArabic;
  final bool showZones;
  final CocoLabelsRepository labelsRepo;

  BBoxHudPainter({
    required this.detections,
    required this.isArabic,
    this.showZones = true,
    CocoLabelsRepository? repo,
  }) : labelsRepo = repo ?? CocoLabelsRepository();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Draw subtle vertical dividing lines for Spatial Zones (0.33 and 0.66)
    if (showZones) {
      final zonePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      final xLeft = size.width * 0.33;
      final xRight = size.width * 0.66;
      canvas.drawLine(Offset(xLeft, 0), Offset(xLeft, size.height), zonePaint);
      canvas.drawLine(Offset(xRight, 0), Offset(xRight, size.height), zonePaint);
    }

    // Paint bounding boxes
    for (final item in detections) {
      if (item.trackState == TrackState.deleted) continue;

      final rect = Rect.fromLTRB(
        item.x1 * size.width,
        item.y1 * size.height,
        item.x2 * size.width,
        item.y2 * size.height,
      );

      // Determine accent color from proximity tier
      final Color boxColor;
      switch (item.proximityTier) {
        case ProximityTier.near:
          boxColor = const Color(0xFFFF3B30); // Vibrant Near Red
          break;
        case ProximityTier.medium:
          boxColor = const Color(0xFFFF9500); // Amber/Orange Medium
          break;
        case ProximityTier.far:
          boxColor = const Color(0xFF34C759); // Green Far
          break;
      }

      // Box outline style based on tracking state
      final boxPaint = Paint()
        ..color = item.isConfirmed ? boxColor : boxColor.withValues(alpha: 0.4)
        ..strokeWidth = item.isConfirmed ? 2.5 : 1.5
        ..style = PaintingStyle.stroke;

      // Draw rounded rectangle for bounding box
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rrect, boxPaint);

      // Label background & text
      final labelText = labelsRepo.getLabel(item.classId, isArabic: isArabic);
      final confPercent = (item.confidence * 100).toStringAsFixed(0);
      final displayText = isArabic
          ? '#${item.trackId} $labelText $confPercent%'
          : '#${item.trackId} $labelText $confPercent%';

      final textSpan = TextSpan(
        text: displayText,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          fontFamily: isArabic ? 'Arial' : null,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 3),
          ],
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      )..layout(maxWidth: size.width);

      // Label badge position (above bounding box or inside if too close to top)
      final badgeHeight = textPainter.height + 6;
      final badgeWidth = textPainter.width + 10;
      final badgeY = (rect.top - badgeHeight < 0) ? rect.top : rect.top - badgeHeight;
      final badgeX = rect.left.clamp(0.0, size.width - badgeWidth);

      final badgeRect = Rect.fromLTWH(badgeX, badgeY, badgeWidth, badgeHeight);
      final bgPaint = Paint()
        ..color = boxColor.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
        bgPaint,
      );

      textPainter.paint(
        canvas,
        Offset(badgeX + 5, badgeY + 3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant BBoxHudPainter oldDelegate) {
    return true; // Decoupled 60 FPS repainting
  }
}
