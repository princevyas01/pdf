import 'package:flutter/material.dart';

/// Design 01: Quiet Editorial Document Studio design tokens.
/// Strictly implements the visual specification from Stitch Design 01
/// (Project 6842743049063587818, Screen ce1b7cb24c07466bbcd8ff127720056d, 9c4e7bc9ce72493ebc3c52fed97cf445).
class EditorialTokens {
  EditorialTokens._();

  static const serifFamily = 'SourceSerif4';
  static const sansFamily = 'Inter';
  static const monoFamily = 'JetBrainsMono';

  // --- Foundational Palette (Stitch Design 01 Specification) ---
  static const Color canvas = Color(0xFFF4EFEB); // Neutral #F4EFEB
  static const Color surface = Color(0xFFFFFFFF); // Card surface
  static const Color surfaceSubtle = Color(0xFFF4EFEB); // Subtle secondary strip
  static const Color surfaceMuted = Color(0xFFEBE6DC); // Tertiary neutral
  static const Color surfaceStrong = Color(0xFFFFFFFF);

  // Accents
  static const Color primary = Color(0xFF7D4E2D); // #7D4E2D warm terracotta / burnt umber
  static const Color secondary = Color(0xFF3E2718); // #3E2718 dark roast chocolate brown
  static const Color tertiary = Color(0xFF266169); // #266169 slate / ocean teal
  static const Color accentSecondary = Color(0xFF8C5333);
  static const Color neutral = Color(0xFFF4EFEB); // #F4EFEB

  // Ink / Text
  static const Color ink = Color(0xFF1C1A18); // #1C1A18 main text
  static const Color inkSecondary = Color(0xFF68615A); // #68615A secondary text
  static const Color inkMuted = Color(0xFF928A82); // #928A82 muted metadata

  // Hairlines & Borders
  static const Color border = Color(0xFFD9D1C8); // #D9D1C8 framing border
  static const Color borderSoft = Color(0xFFE7E0D8); // #E7E0D8 subtle hairline

  // Document & Canvas
  static const Color viewerBed = Color(0xFFE8E4DA); // #E8E4DA viewer bed
  static const Color paper = Color(0xFFFBF8F4); // #FBF8F4 physical paper page

  // Semantic
  static const Color success = Color(0xFF2D6E3F);
  static const Color successLight = Color(0xFFEBF5EE);
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorLight = Color(0xFFFDE8E8);

  // Dark Mode Quiet Equivalents
  static const Color darkCanvas = Color(0xFF141210);
  static const Color darkSurface = Color(0xFF1C1A18);
  static const Color darkSurfaceStrong = Color(0xFF24211E);
  static const Color darkSurfaceMuted = Color(0xFF2C2825);
  static const Color darkBorder = Color(0xFF3A3530);
  static const Color darkBorderSoft = Color(0xFF2E2A26);
  static const Color darkInk = Color(0xFFF4EFEB);
  static const Color darkInkSecondary = Color(0xFFB5ADA4);
  static const Color darkInkMuted = Color(0xFF847C74);

  static const double hairline = 0.5;

  static const double r2 = 2.0;
  static const double r4 = 4.0;
  static const double r6 = 6.0;
  static const double r8 = 8.0;

  static const BorderRadius br2 = BorderRadius.all(Radius.circular(r2));
  static const BorderRadius br4 = BorderRadius.all(Radius.circular(r4));
  static const BorderRadius br6 = BorderRadius.all(Radius.circular(r6));
  static const BorderRadius br8 = BorderRadius.all(Radius.circular(r8));

  // --- Typography Factory (Bundled Fonts, Restrained Hierarchy) ---
  static TextStyle eyebrow({Color color = inkSecondary}) {
    return TextStyle(
      fontFamily: sansFamily,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      height: 1.2,
      color: color,
    );
  }

  static TextStyle displayLarge({Color color = ink}) {
    return TextStyle(
      fontFamily: serifFamily,
      fontSize: 26,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.25,
      height: 1.15,
      color: color,
    );
  }

  static TextStyle displayMedium({Color color = ink}) {
    return TextStyle(
      fontFamily: serifFamily,
      fontSize: 21,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.15,
      height: 1.2,
      color: color,
    );
  }

  static TextStyle headlineSmall({Color color = ink}) {
    return TextStyle(
      fontFamily: serifFamily,
      fontSize: 18,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.2,
      color: color,
    );
  }

  static TextStyle title({Color color = ink}) {
    return TextStyle(
      fontFamily: serifFamily,
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 1.2,
      color: color,
    );
  }

  static TextStyle titleLarge({Color color = ink}) => displayMedium(color: color);
  static TextStyle titleMedium({Color color = ink}) => title(color: color);
  static TextStyle titleSmall({Color color = ink}) {
    return TextStyle(
      fontFamily: serifFamily,
      fontSize: 14.5,
      fontWeight: FontWeight.w500,
      height: 1.2,
      color: color,
    );
  }

  static TextStyle body({Color color = ink}) {
    return TextStyle(
      fontFamily: sansFamily,
      fontSize: 13.5,
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: color,
    );
  }

  static TextStyle bodyMedium({Color color = ink}) => body(color: color);

  static TextStyle bodySmall({Color color = inkSecondary}) {
    return TextStyle(
      fontFamily: sansFamily,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.35,
      color: color,
    );
  }

  static TextStyle label({Color color = inkSecondary}) {
    return TextStyle(
      fontFamily: sansFamily,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      height: 1.2,
      color: color,
    );
  }

  static TextStyle metadata({Color color = inkSecondary}) {
    return TextStyle(
      fontFamily: monoFamily,
      fontSize: 10,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
      height: 1.25,
      color: color,
    );
  }

  static TextStyle metadataStrong({Color color = ink}) {
    return TextStyle(
      fontFamily: monoFamily,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      height: 1.25,
      color: color,
    );
  }
}
