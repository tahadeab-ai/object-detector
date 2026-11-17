import 'package:flutter/material.dart';

/// Design tokens for the dark tactical cockpit design system.
///
/// Principles derived from:
/// - ui-ux-pro-max: Dark Mode (OLED) style, WCAG AA contrast (>=4.5:1),
///   min touch target >=48dp, 8px+ spacing scale, tabular figures for telemetry.
/// - frontend-design: Grounded in subject matter (precision optical cockpit),
///   restrained palette, visual hierarchy, no decorative clutter.
/// - ui-styling: Systematic token architecture (colors, typography, spacing,
///   radii, simulated glass, elevation via hairlines).
class AppTokens {
  AppTokens._();

  // ==========================================
  // 1. PALETTE (Dark Tactical Cockpit)
  // ==========================================
  static const Color bg = Color(0xFF0B0F14);
  static const Color surface = Color(0xFF121821);
  static const Color surfaceAlt = Color(0xFF1B2430);
  static const Color hairline = Color(0xFF2A3542);
  static const Color text = Color(0xFFE6EDF3);
  static const Color muted = Color(0xFF8B98A5);
  static const Color accent = Color(0xFF22D3EE); // Precision Cyan
  static const Color ok = Color(0xFF10B981); // Emerald Green
  static const Color warn = Color(0xFFF59E0B); // Amber Accent
  static const Color danger = Color(0xFFEF4444); // Crimson Red

  // 88%-opaque surface for simulated glass (Performance rule D2: NO BackdropFilter)
  static const Color surfaceGlass = Color(0xE0121821);
  static const Color surfaceAltGlass = Color(0xE01B2430);

  // Subtle linear gradient for simulated glass surfaces
  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xF01B2430),
      Color(0xD8121821),
    ],
  );

  static const LinearGradient glassGradientMuted = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xEA161E28),
      Color(0xD00F141B),
    ],
  );

  // ==========================================
  // 2. COLORBLIND-SAFE CATEGORY PALETTE (8 Classes)
  // ==========================================
  static const Color catPerson = Color(0xFF22D3EE); // Cyan
  static const Color catVehicle = Color(0xFF38BDF8); // Sky Blue
  static const Color catTraffic = Color(0xFFF59E0B); // Amber
  static const Color catAnimal = Color(0xFF10B981); // Emerald
  static const Color catIndoor = Color(0xFFA78BFA); // Purple / Violet
  static const Color catElectronics = Color(0xFFF472B6); // Magenta / Pink
  static const Color catFood = Color(0xFFFBBF24); // Warm Yellow
  static const Color catGeneral = Color(0xFF94A3B8); // Slate / Silver

  static Color getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'person':
        return catPerson;
      case 'vehicle':
        return catVehicle;
      case 'traffic':
      case 'outdoor':
        return catTraffic;
      case 'animal':
        return catAnimal;
      case 'indoor':
      case 'accessory':
      case 'sports':
      case 'furniture':
        return catIndoor;
      case 'electronics':
      case 'appliance':
        return catElectronics;
      case 'food':
      case 'kitchen':
        return catFood;
      case 'general':
      default:
        return catGeneral;
    }
  }

  // ==========================================
  // 3. SPACING SCALE (4, 8, 12, 16, 24, 32)
  // ==========================================
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;

  // Touch target minimum (WCAG 2.5.5 / Android Material)
  static const double minTouchTarget = 48.0;

  // ==========================================
  // 4. RADII (8, 12, 16)
  // ==========================================
  static const double r8 = 8.0;
  static const double r12 = 12.0;
  static const double r16 = 16.0;

  static const Radius radius8 = Radius.circular(r8);
  static const Radius radius12 = Radius.circular(r12);
  static const Radius radius16 = Radius.circular(r16);

  static const BorderRadius rounded8 = BorderRadius.all(radius8);
  static const BorderRadius rounded12 = BorderRadius.all(radius12);
  static const BorderRadius rounded16 = BorderRadius.all(radius16);

  // ==========================================
  // 5. ELEVATION VIA HAIRLINES (Not heavy shadows)
  // ==========================================
  static const Border hairlineBorder = Border.fromBorderSide(
    BorderSide(color: hairline, width: 1.0),
  );

  static const Border hairlineTop = Border(
    top: BorderSide(color: hairline, width: 1.0),
  );

  static const Border hairlineBottom = Border(
    bottom: BorderSide(color: hairline, width: 1.0),
  );

  static final BoxDecoration glassCardDecoration = BoxDecoration(
    color: surfaceGlass,
    gradient: glassGradient,
    borderRadius: rounded12,
    border: Border.all(color: hairline, width: 1.0),
  );

  static final BoxDecoration glassCardDecorationSmall = BoxDecoration(
    color: surfaceGlass,
    gradient: glassGradientMuted,
    borderRadius: rounded8,
    border: Border.all(color: hairline, width: 1.0),
  );

  // ==========================================
  // 6. TYPOGRAPHY (Cairo & Monospace Tabular)
  // Type scale: 12, 14, 16, 20, 24, 32
  // Arabic line-height: 1.6
  // ==========================================
  static const String fontCairo = 'Cairo';

  // Base text styles with Cairo (OFL)
  static const TextStyle type12 = TextStyle(
    fontFamily: fontCairo,
    fontSize: 12.0,
    fontWeight: FontWeight.w400,
    color: muted,
    height: 1.6,
  );

  static const TextStyle type14 = TextStyle(
    fontFamily: fontCairo,
    fontSize: 14.0,
    fontWeight: FontWeight.w400,
    color: text,
    height: 1.6,
  );

  static const TextStyle type16 = TextStyle(
    fontFamily: fontCairo,
    fontSize: 16.0,
    fontWeight: FontWeight.w600,
    color: text,
    height: 1.6,
  );

  static const TextStyle type20 = TextStyle(
    fontFamily: fontCairo,
    fontSize: 20.0,
    fontWeight: FontWeight.w700,
    color: text,
    height: 1.6,
  );

  static const TextStyle type24 = TextStyle(
    fontFamily: fontCairo,
    fontSize: 24.0,
    fontWeight: FontWeight.w700,
    color: text,
    height: 1.6,
  );

  static const TextStyle type32 = TextStyle(
    fontFamily: fontCairo,
    fontSize: 32.0,
    fontWeight: FontWeight.w700,
    color: text,
    height: 1.6,
  );

  // Monospace with tabular figures for telemetry (prevents jitter)
  static const TextStyle telemetry12 = TextStyle(
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 12.0,
    fontWeight: FontWeight.w600,
    color: text,
    height: 1.2,
  );

  static const TextStyle telemetry14 = TextStyle(
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 14.0,
    fontWeight: FontWeight.w700,
    color: text,
    height: 1.2,
  );

  static const TextStyle telemetry20 = TextStyle(
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 20.0,
    fontWeight: FontWeight.w700,
    color: text,
    height: 1.2,
  );

  // ==========================================
  // 7. MOTION & TRANSITIONS
  // ==========================================
  static const Duration fastMotion = Duration(milliseconds: 150);
  static const Duration standardMotion = Duration(milliseconds: 200);
  static const Curve standardCurve = Curves.easeOutCubic;
}
