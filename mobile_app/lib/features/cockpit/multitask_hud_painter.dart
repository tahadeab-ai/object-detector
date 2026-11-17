import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/ffi/native_structs.dart';
import '../../core/l10n/coco_labels_repository.dart';
import '../../core/l10n/multitask_labels_repository.dart';
import '../../core/models/detection_item.dart';
import '../../core/models/multitask_results.dart';
import '../../core/theme/design_tokens.dart';

/// 60 FPS Multi-Task HUD CustomPainter
/// Renders Detection, Segmentation, Pose, Classification, and OBB overlays.
class MultiTaskHudPainter extends CustomPainter {
  final VisionTask task;
  final bool isArabic;
  final bool showTrails;

  final List<DetectionItem> detections;
  final List<SegmentationItem> segmentations;
  final List<PoseItem> poses;
  final List<ClassificationItem> classifications;
  final List<ObbItem> obbs;

  final MultiTaskLabelsRepository labelsRepo;
  final CocoLabelsRepository cocoRepo;

  // Reusable paint instances to reduce GC churn
  final Paint _boxPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  final Paint _bracketPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.square
    ..strokeWidth = 2.5;

  final Paint _badgePaint = Paint()..style = PaintingStyle.fill;

  final Paint _trailPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  final Paint _maskFillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _maskStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  final Paint _bonePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 2.2;

  final Paint _jointFillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _jointBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = Colors.white;

  final Paint _obbFillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _obbStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  final Paint _headingPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 2.0;

  MultiTaskHudPainter({
    required this.task,
    required this.isArabic,
    this.showTrails = true,
    this.detections = const [],
    this.segmentations = const [],
    this.poses = const [],
    this.classifications = const [],
    this.obbs = const [],
    MultiTaskLabelsRepository? multiTaskRepo,
    CocoLabelsRepository? cocoLabelsRepo,
  })  : labelsRepo = multiTaskRepo ?? MultiTaskLabelsRepository(),
        cocoRepo = cocoLabelsRepo ?? CocoLabelsRepository();

  Color _getColorForClass(int classId) {
    const palette = [
      AppTokens.accent,
      AppTokens.ok,
      AppTokens.warn,
      AppTokens.catFood,
      AppTokens.catPerson,
      AppTokens.catAnimal,
      AppTokens.catIndoor,
      AppTokens.catVehicle,
      AppTokens.catElectronics,
      AppTokens.catTraffic,
      AppTokens.catGeneral,
    ];
    return palette[classId.abs() % palette.length];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    switch (task) {
      case VisionTask.detection:
        _paintDetections(canvas, size);
        break;
      case VisionTask.segmentation:
        _paintSegmentations(canvas, size);
        break;
      case VisionTask.pose:
        _paintPoses(canvas, size);
        break;
      case VisionTask.classification:
        _paintClassifications(canvas, size);
        break;
      case VisionTask.obb:
        _paintObbs(canvas, size);
        break;
    }
  }

  // ==========================================
  // TASK A: OBJECT DETECTION
  // ==========================================
  void _paintDetections(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    // 1. Trails
    if (showTrails) {
      for (final item in detections) {
        if (item.motionTrail.length < 2) continue;
        final baseColor = _getColorForClass(item.classId);

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
          _trailPaint.color = baseColor.withValues(alpha: opacity);
          canvas.drawLine(p1, p2, _trailPaint);
        }
      }
    }

    // 2. Boxes & Badges
    for (final item in detections) {
      if (!item.isConfirmed && item.confidence < 0.40) continue;

      final left = (item.x1 * size.width).clamp(0.0, size.width);
      final top = (item.y1 * size.height).clamp(0.0, size.height);
      final right = (item.x2 * size.width).clamp(0.0, size.width);
      final bottom = (item.y2 * size.height).clamp(0.0, size.height);

      if (right - left < 4.0 || bottom - top < 4.0) continue;

      final rect = Rect.fromLTRB(left, top, right, bottom);
      final classColor = _getColorForClass(item.classId);

      _boxPaint.color = classColor.withValues(alpha: 0.35);
      canvas.drawRect(rect, _boxPaint);

      _drawCornerBrackets(canvas, left, top, right, bottom, classColor);

      final labelText = labelsRepo.getLabelForTask(
        task: VisionTask.detection,
        classId: item.classId,
        isArabic: isArabic,
      );
      final confPercent = (item.confidence * 100).toStringAsFixed(0);
      final displayText = '#${item.trackId} $labelText $confPercent%';

      _drawBadge(canvas, size, left, top, displayText, classColor);
    }
  }

  // ==========================================
  // TASK B: INSTANCE SEGMENTATION
  // ==========================================
  void _paintSegmentations(Canvas canvas, Size size) {
    if (segmentations.isEmpty) return;

    for (final item in segmentations) {
      if (item.confidence < 0.40) continue;

      final classColor = _getColorForClass(item.classId);

      // Draw Polygon Contour Path
      if (item.contourPoints.length >= 3) {
        final path = Path();
        final firstPt = Offset(
          item.contourPoints[0].dx * size.width,
          item.contourPoints[0].dy * size.height,
        );
        path.moveTo(firstPt.dx, firstPt.dy);

        for (int i = 1; i < item.contourPoints.length; i++) {
          path.lineTo(
            item.contourPoints[i].dx * size.width,
            item.contourPoints[i].dy * size.height,
          );
        }
        path.close();

        // Alpha mask fill
        _maskFillPaint.color = classColor.withValues(alpha: 0.28);
        canvas.drawPath(path, _maskFillPaint);

        // Solid boundary outline
        _maskStrokePaint.color = classColor.withValues(alpha: 0.85);
        canvas.drawPath(path, _maskStrokePaint);
      }

      // Draw Bounding Box & Badge
      final left = (item.x1 * size.width).clamp(0.0, size.width);
      final top = (item.y1 * size.height).clamp(0.0, size.height);
      final right = (item.x2 * size.width).clamp(0.0, size.width);
      final bottom = (item.y2 * size.height).clamp(0.0, size.height);

      if (right - left >= 4.0 && bottom - top >= 4.0) {
        _boxPaint.color = classColor.withValues(alpha: 0.25);
        canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), _boxPaint);

        final labelText = labelsRepo.getLabelForTask(
          task: VisionTask.segmentation,
          classId: item.classId,
          isArabic: isArabic,
        );
        final confPercent = (item.confidence * 100).toStringAsFixed(0);
        final displayText = '$labelText $confPercent%';
        _drawBadge(canvas, size, left, top, displayText, classColor);
      }
    }
  }

  // ==========================================
  // TASK C: POSE ESTIMATION
  // ==========================================
  void _paintPoses(Canvas canvas, Size size) {
    if (poses.isEmpty) return;

    for (final pose in poses) {
      if (pose.confidence < 0.40) continue;

      const classColor = AppTokens.accent;

      // Draw subtle bounding box
      final left = (pose.x1 * size.width).clamp(0.0, size.width);
      final top = (pose.y1 * size.height).clamp(0.0, size.height);
      final right = (pose.x2 * size.width).clamp(0.0, size.width);
      final bottom = (pose.y2 * size.height).clamp(0.0, size.height);

      if (right - left >= 4.0 && bottom - top >= 4.0) {
        _boxPaint.color = classColor.withValues(alpha: 0.20);
        canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), _boxPaint);

        final confPercent = (pose.confidence * 100).toStringAsFixed(0);
        final labelText = isArabic ? 'شخص $confPercent%' : 'person $confPercent%';
        _drawBadge(canvas, size, left, top, labelText, classColor);
      }

      // Draw Skeleton Bones
      for (final bone in labelsRepo.skeleton) {
        if (bone.startJoint >= pose.keypoints.length ||
            bone.endJoint >= pose.keypoints.length) {
          continue;
        }

        final kp1 = pose.keypoints[bone.startJoint];
        final kp2 = pose.keypoints[bone.endJoint];

        if (kp1.confidence < 0.35 || kp2.confidence < 0.35) continue;

        final p1 = Offset(kp1.x * size.width, kp1.y * size.height);
        final p2 = Offset(kp2.x * size.width, kp2.y * size.height);

        // Color bone based on side (Left=Cyan, Right=Orange, Torso/Head=Lime)
        Color boneColor;
        if (bone.startJoint % 2 == 1 && bone.endJoint % 2 == 1) {
          boneColor = const Color(0xFF00E5FF); // Left side
        } else if (bone.startJoint % 2 == 0 && bone.endJoint % 2 == 0 && bone.startJoint > 0) {
          boneColor = const Color(0xFFFF9100); // Right side
        } else {
          boneColor = const Color(0xFF00E676); // Center / Torso
        }

        _bonePaint.color = boneColor.withValues(alpha: 0.90);
        canvas.drawLine(p1, p2, _bonePaint);
      }

      // Draw Keypoint Joint Circles
      for (int i = 0; i < pose.keypoints.length; i++) {
        final kp = pose.keypoints[i];
        if (kp.confidence < 0.35) continue;

        final center = Offset(kp.x * size.width, kp.y * size.height);
        Color jointColor;
        if (i == 0) {
          jointColor = const Color(0xFFFFD600); // Nose
        } else if (i % 2 == 1) {
          jointColor = const Color(0xFF00E5FF); // Left joint
        } else {
          jointColor = const Color(0xFFFF9100); // Right joint
        }

        _jointFillPaint.color = jointColor;
        canvas.drawCircle(center, 3.5, _jointFillPaint);
        canvas.drawCircle(center, 3.5, _jointBorderPaint);
      }
    }
  }

  // ==========================================
  // TASK D: IMAGE CLASSIFICATION
  // ==========================================
  void _paintClassifications(Canvas canvas, Size size) {
    if (classifications.isEmpty) return;

    // Render Top-5 Leaderboard Card at Top-Right (or Top-Left in Arabic)
    const cardWidth = 220.0;
    final cardHeight = (classifications.length * 28.0) + 36.0;

    final cardX = isArabic ? 16.0 : (size.width - cardWidth - 16.0);
    const cardY = 72.0;

    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cardX, cardY, cardWidth, cardHeight),
      const Radius.circular(12),
    );

    // Glass background
    final bgPaint = Paint()
      ..color = const Color(0xCC121620)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(cardRect, bgPaint);

    final borderPaint = Paint()
      ..color = AppTokens.hairline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(cardRect, borderPaint);

    // Title Header
    final titleSpan = TextSpan(
      text: isArabic ? 'تصنيف الصورة (Top-5)' : 'Classification (Top-5)',
      style: const TextStyle(
        color: AppTokens.accent,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        fontFamily: AppTokens.fontCairo,
      ),
    );
    final titlePainter = TextPainter(
      text: titleSpan,
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
    )..layout(maxWidth: cardWidth - 20);
    titlePainter.paint(canvas, Offset(cardX + 10, cardY + 8));

    // Progress rows
    for (int i = 0; i < classifications.length; i++) {
      final item = classifications[i];
      final rowY = cardY + 30.0 + (i * 26.0);

      final labelText = labelsRepo.getLabelForTask(
        task: VisionTask.classification,
        classId: item.classId,
        isArabic: isArabic,
      );
      final confPct = (item.confidence * 100).toStringAsFixed(1);
      final rowText = '#${i + 1} $labelText';

      // Bar background
      final barRect = Rect.fromLTWH(cardX + 10, rowY + 14, cardWidth - 20, 4);
      final barBgPaint = Paint()..color = Colors.white12;
      canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, const Radius.circular(2)),
        barBgPaint,
      );

      // Bar filled
      final fillWidth = (cardWidth - 20) * item.confidence.clamp(0.0, 1.0);
      final fillRect = Rect.fromLTWH(cardX + 10, rowY + 14, fillWidth, 4);
      final fillPaint = Paint()
        ..color = i == 0 ? AppTokens.accent : AppTokens.ok;
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, const Radius.circular(2)),
        fillPaint,
      );

      // Text row: name on left, % on right
      final itemSpan = TextSpan(
        text: rowText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          fontFamily: AppTokens.fontCairo,
        ),
      );
      final itemPainter = TextPainter(
        text: itemSpan,
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      )..layout(maxWidth: cardWidth - 70);
      itemPainter.paint(canvas, Offset(cardX + 10, rowY));

      final pctSpan = TextSpan(
        text: '$confPct%',
        style: TextStyle(
          color: i == 0 ? AppTokens.accent : Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: AppTokens.fontCairo,
        ),
      );
      final pctPainter = TextPainter(
        text: pctSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      pctPainter.paint(
        canvas,
        Offset(cardX + cardWidth - 10 - pctPainter.width, rowY),
      );
    }
  }

  // ==========================================
  // TASK E: ORIENTED BOUNDING BOX (OBB)
  // ==========================================
  void _paintObbs(Canvas canvas, Size size) {
    if (obbs.isEmpty) return;

    for (final obb in obbs) {
      if (obb.confidence < 0.35 || obb.corners.length < 4) continue;

      final classColor = _getColorForClass(obb.classId);

      final c0 = Offset(obb.corners[0].dx * size.width, obb.corners[0].dy * size.height);
      final c1 = Offset(obb.corners[1].dx * size.width, obb.corners[1].dy * size.height);
      final c2 = Offset(obb.corners[2].dx * size.width, obb.corners[2].dy * size.height);
      final c3 = Offset(obb.corners[3].dx * size.width, obb.corners[3].dy * size.height);

      final path = Path()
        ..moveTo(c0.dx, c0.dy)
        ..lineTo(c1.dx, c1.dy)
        ..lineTo(c2.dx, c2.dy)
        ..lineTo(c3.dx, c3.dy)
        ..close();

      // Semi-transparent fill
      _obbFillPaint.color = classColor.withValues(alpha: 0.22);
      canvas.drawPath(path, _obbFillPaint);

      // Rotated boundary
      _obbStrokePaint.color = classColor.withValues(alpha: 0.90);
      canvas.drawPath(path, _obbStrokePaint);

      // Heading Vector Line from Center
      final center = Offset(obb.cx * size.width, obb.cy * size.height);
      final headingLen = (obb.width * size.width * 0.45).clamp(12.0, 36.0);
      final headingEnd = Offset(
        center.dx + math.cos(obb.angleRad) * headingLen,
        center.dy + math.sin(obb.angleRad) * headingLen,
      );

      _headingPaint.color = Colors.white;
      canvas.drawLine(center, headingEnd, _headingPaint);
      canvas.drawCircle(headingEnd, 2.5, _jointFillPaint..color = Colors.white);

      // Badge at top-most corner
      final topCornerY = math.min(math.min(c0.dy, c1.dy), math.min(c2.dy, c3.dy));
      final topCornerX = [c0, c1, c2, c3].firstWhere((c) => (c.dy - topCornerY).abs() < 1.0).dx;

      final labelText = labelsRepo.getLabelForTask(
        task: VisionTask.obb,
        classId: obb.classId,
        isArabic: isArabic,
      );
      final confPercent = (obb.confidence * 100).toStringAsFixed(0);
      final degText = '${obb.angleDeg.toStringAsFixed(0)}°';
      final displayText = '$labelText $confPercent% ($degText)';

      _drawBadge(canvas, size, topCornerX, topCornerY, displayText, classColor);
    }
  }

  // ==========================================
  // HELPER METHODS
  // ==========================================
  void _drawCornerBrackets(
    Canvas canvas,
    double left,
    double top,
    double right,
    double bottom,
    Color color,
  ) {
    _bracketPaint.color = color;
    final bracketLen = ((right - left).clamp(8.0, 24.0)).toDouble();
    final bracketH = ((bottom - top).clamp(8.0, 24.0)).toDouble();
    final len = bracketLen < bracketH ? bracketLen : bracketH;

    // Top-Left
    canvas.drawLine(Offset(left, top), Offset(left + len, top), _bracketPaint);
    canvas.drawLine(Offset(left, top), Offset(left, top + len), _bracketPaint);
    // Top-Right
    canvas.drawLine(Offset(right, top), Offset(right - len, top), _bracketPaint);
    canvas.drawLine(Offset(right, top), Offset(right, top + len), _bracketPaint);
    // Bottom-Left
    canvas.drawLine(Offset(left, bottom), Offset(left + len, bottom), _bracketPaint);
    canvas.drawLine(Offset(left, bottom), Offset(left, bottom - len), _bracketPaint);
    // Bottom-Right
    canvas.drawLine(Offset(right, bottom), Offset(right - len, bottom), _bracketPaint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - len), _bracketPaint);
  }

  void _drawBadge(
    Canvas canvas,
    Size size,
    double x,
    double y,
    String text,
    Color color,
  ) {
    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        fontFamily: AppTokens.fontCairo,
        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
    )..layout(maxWidth: size.width);

    final badgeHeight = textPainter.height + 4;
    final badgeWidth = textPainter.width + 10;
    final badgeY = (y - badgeHeight < 4) ? y + 2 : y - badgeHeight - 2;
    final badgeX = x.clamp(2.0, (size.width - badgeWidth - 2.0).clamp(2.0, size.width));

    final badgeRect = Rect.fromLTWH(badgeX, badgeY, badgeWidth, badgeHeight);
    _badgePaint.color = color.withValues(alpha: 0.88);
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
      _badgePaint,
    );

    textPainter.paint(canvas, Offset(badgeX + 5, badgeY + 2));
  }

  @override
  bool shouldRepaint(covariant MultiTaskHudPainter oldDelegate) => true;
}
