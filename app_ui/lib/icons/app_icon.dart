import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_icon_data.dart';
import '../tokens/app_colors.dart';

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.colorFilter,
    this.semanticLabel,
  });

  final AppIconData icon;

  final double? size;

  final Color? color;

  final ColorFilter? colorFilter;

  final String? semanticLabel;

  static const double defaultSize = 24.0;

  @override
  Widget build(BuildContext context) {
    final effectiveSize = size ?? defaultSize;

    return switch (icon) {
      SvgIcon(:final assetPath, :final package) => SvgPicture.asset(
        assetPath,
        package: package,
        width: effectiveSize,
        height: effectiveSize,
        colorFilter:
            colorFilter ??
            (color != null ? ColorFilter.mode(color!, BlendMode.srcIn) : null),
        semanticsLabel: semanticLabel,
      ),
      MaterialIcon(:final iconData) => Icon(
        iconData,
        size: effectiveSize,
        color: color ?? AppColors.iconPrimary,
        semanticLabel: semanticLabel,
      ),
    };
  }
}

extension AppIconPresets on AppIcon {
  static AppIcon small(AppIconData icon, {Color? color}) =>
      AppIcon(icon, size: 16, color: color);

  static AppIcon medium(AppIconData icon, {Color? color}) =>
      AppIcon(icon, size: 24, color: color);

  static AppIcon large(AppIconData icon, {Color? color}) =>
      AppIcon(icon, size: 32, color: color);

  static AppIcon xl(AppIconData icon, {Color? color}) =>
      AppIcon(icon, size: 48, color: color);
}
