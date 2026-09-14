import 'package:flutter/material.dart';

abstract class AppColors {
  static const Color primary = Color(0xFF7100FF);

  static const Color primaryAccentDark = Color(0xFFA78BFA);

  static const Color primaryDark = Color(0xFF4A00E0);

  static const Color primaryLight = Color(0xFFEEE5FF);

  static const Color primaryLightDark = Color(0x26A78BFA);

  static const Color secondary = Color(0xFFE5D4FF);

  static const Color background = Color(0xFFF9F9FF);

  static const Color surface = Color(0xFFFFFFFF);

  // one step above the #171717 dark background so a card reads as raised
  static const Color surfaceDark = Color(0xFF242424);

  static const Color fieldBackground = Color(0xFFEAEAFF);

  static const Color textPrimary = Color(0xFF5D5186);

  static const Color textPrimaryDark = Color(0xFFF5F5F5);

  static const Color textSecondary = Color(0xFF91919F);

  static const Color textDisabled = Color(0xFFBDBDBD);

  static const Color iconPrimary = Color(0xFF5D5186);

  static const Color iconSecondary = Color(0xFF91919F);

  static const Color iconDisabled = Color(0xFFBDBDBD);

  static const Color success = Color(0xFF00A86B);

  static const Color error = Color(0xFFFD3C4A);

  // error is a fill colour: as 14pt text on white it reaches only 3.6:1
  static const Color errorText = Color(0xFFD32F2F);

  // error reaches only 4.4:1 on the dark surface
  static const Color errorTextDark = Color(0xFFFF6B75);

  static const Color warning = Color(0xFFE8820C);

  static const Color info = Color(0xFF0077FF);

  static const Color successLight = Color(0xFFD4F7E5);

  static const Color errorLight = Color(0xFFFFEBEE);

  static const Color infoLight = Color(0xFFD4E5FF);

  static const Color warningLight = Color(0xFFFFF3E0);

  static const Color white = Color(0xFFFFFFFF);

  static const Color black = Color(0xFF0D0E0F);

  static const Color grey = Color(0xFF91919F);

  static const Color lightGrey = Color(0xFFE3E5E5);

  static const Color borderGrey = Color(0xFFEEEEEE);

  // light enough to stay visible on the #242424 surface
  static const Color borderDark = Color(0xFF333333);

  static const Color divider = Color(0xFFE0E0E0);

  static const Color iconGrey = Color(0xFF9487C1);

  static const Color overlay = Color(0x0D000000);

  static const Color transparent = Color(0x00000000);

  static const Color blue = Color(0xFF0077FF);

  static const Color blueLight = Color(0xFFE1F5FE);

  static const Color green = Color(0xFF00A86B);

  static const Color red = Color(0xFFFD3C4A);

  static const Color yellow = Color(0xFFFFE34F);

  static const Color orange = Color(0xFFFF9800);

  static const Color orangeLight = Color(0xFFFFF3E0);

  static const Color purple = Color(0xFF9C27B0);

  static const Color purpleLight = Color(0xFFF3E5F5);

  static const Color deepPurple = Color(0xFF673AB7);

  static const Color deepPurpleLight = Color(0xFFEDE7F6);

  static const Color cyan = Color(0xFF00BCD4);

  static const Color promotedBlue = Color(0xFF4FA0FF);

  static const Color socialWhatsapp = Color(0xFF25D366);

  static const Color socialTwitter = Color(0xFF1DA1F2);

  static const Color socialFacebook = Color(0xFF0A66C2);

  static const Color socialInstagram = Color(0xFFE4405F);

  static const Color avatar1 = Color(0xFFFF6B35);

  static const Color avatar2 = Color(0xFF52B788);

  static const Color avatar3 = Color(0xFF7367F0);

  static const Color avatar4 = Color(0xFFFF6B9D);

  static const Color avatar5 = Color(0xFFC98BDB);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
