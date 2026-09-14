import 'package:flutter/material.dart';

abstract class AppSpacing {
  static const double xs = 4.0;

  static const double sm = 8.0;

  static const double md = 12.0;

  static const double df = 16.0;

  static const double lg = 20.0;

  static const double xl = 24.0;

  static const double xxl = 32.0;

  static const double xxxl = 48.0;

  static const double xxxxl = 64.0;

  static const EdgeInsets screenPadding = EdgeInsets.all(df);

  static const EdgeInsets screenHorizontal = EdgeInsets.symmetric(
    horizontal: df,
  );

  static const EdgeInsets screenVertical = EdgeInsets.symmetric(vertical: df);

  static const EdgeInsets cardPadding = EdgeInsets.all(df);

  static const EdgeInsets cardPaddingSm = EdgeInsets.all(md);

  static const EdgeInsets cardPaddingLg = EdgeInsets.all(xl);

  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    horizontal: df,
    vertical: md,
  );

  static const EdgeInsets listItemPaddingCompact = EdgeInsets.symmetric(
    horizontal: df,
    vertical: sm,
  );

  static const EdgeInsets listItemPaddingSpacious = EdgeInsets.symmetric(
    horizontal: df,
    vertical: df,
  );

  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: xl,
    vertical: df,
  );

  static const EdgeInsets buttonPaddingCompact = EdgeInsets.symmetric(
    horizontal: df,
    vertical: md,
  );

  static const EdgeInsets iconButtonPadding = EdgeInsets.all(md);

  static const EdgeInsets dialogPadding = EdgeInsets.all(xl);

  static const EdgeInsets bottomSheetPadding = EdgeInsets.symmetric(
    horizontal: xl,
    vertical: df,
  );

  static const EdgeInsets chipPadding = EdgeInsets.symmetric(
    horizontal: md,
    vertical: 6,
  );

  static const EdgeInsets tagPadding = EdgeInsets.symmetric(
    horizontal: sm,
    vertical: xs,
  );

  static const EdgeInsets zero = EdgeInsets.zero;

  static const SizedBox verticalXs = SizedBox(height: xs);

  static const SizedBox verticalSm = SizedBox(height: sm);

  static const SizedBox verticalMd = SizedBox(height: md);

  static const SizedBox verticalDf = SizedBox(height: df);

  static const SizedBox verticalLg = SizedBox(height: lg);

  static const SizedBox verticalXl = SizedBox(height: xl);

  static const SizedBox verticalXxl = SizedBox(height: xxl);

  static const SizedBox verticalXxxl = SizedBox(height: xxxl);

  static const SizedBox horizontalXs = SizedBox(width: xs);

  static const SizedBox horizontalSm = SizedBox(width: sm);

  static const SizedBox horizontalMd = SizedBox(width: md);

  static const SizedBox horizontalDf = SizedBox(width: df);

  static const SizedBox horizontalLg = SizedBox(width: lg);

  static const SizedBox horizontalXl = SizedBox(width: xl);

  static const SizedBox horizontalXxl = SizedBox(width: xxl);

  static const double radiusXs = 4.0;

  static const double radiusSm = 8.0;

  static const double radiusMd = 12.0;

  static const double radiusDf = 16.0;

  static const double radiusLg = 20.0;

  static const double radiusXl = 24.0;

  static const double radiusRound = 100.0;

  static BorderRadius get borderRadiusXs => BorderRadius.circular(radiusXs);

  static BorderRadius get borderRadiusSm => BorderRadius.circular(radiusSm);

  static BorderRadius get borderRadiusMd => BorderRadius.circular(radiusMd);

  static BorderRadius get borderRadiusDf => BorderRadius.circular(radiusDf);

  static BorderRadius get borderRadiusLg => BorderRadius.circular(radiusLg);

  static BorderRadius get borderRadiusXl => BorderRadius.circular(radiusXl);

  static BorderRadius get borderRadiusRound =>
      BorderRadius.circular(radiusRound);

  static BorderRadius get borderRadiusTopSheet =>
      const BorderRadius.vertical(top: Radius.circular(24));

  static BorderRadius get borderRadiusBottomSheet =>
      const BorderRadius.vertical(bottom: Radius.circular(24));

  static const double iconSm = 16.0;

  static const double iconMd = 20.0;

  static const double iconDf = 24.0;

  static const double iconLg = 32.0;

  static const double iconXl = 48.0;

  static const double avatarSm = 32.0;

  static const double avatarMd = 40.0;

  static const double avatarDf = 48.0;

  static const double avatarLg = 64.0;

  static const double avatarXl = 80.0;

  static const double avatarXxl = 100.0;

  static const double avatarXxxl = 120.0;

  static const double buttonHeightSm = 40.0;

  static const double buttonHeightDf = 48.0;

  static const double buttonHeightLg = 56.0;

  static const double appBarHeight = 56.0;

  static const double dividerThin = 0.5;

  static const double dividerDf = 1.0;

  static const double dividerThick = 2.0;
}
