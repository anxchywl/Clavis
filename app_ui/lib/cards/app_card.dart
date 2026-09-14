import 'package:flutter/material.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.borderRadius,
    this.elevation = 0,
    this.border,
    this.onTap,
    this.width,
    this.height,
    this.clipBehavior = Clip.none,
  });

  final Widget child;

  final EdgeInsets? padding;

  final EdgeInsets? margin;

  final Color? backgroundColor;

  final BorderRadius? borderRadius;

  final double elevation;

  final BoxBorder? border;

  final VoidCallback? onTap;

  final double? width;

  final double? height;

  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    final effectiveBorderRadius = borderRadius ?? AppSpacing.borderRadiusDf;
    final effectiveBackgroundColor =
        backgroundColor ?? (isLight ? AppColors.white : AppColors.surfaceDark);

    final cardDecoration = BoxDecoration(
      color: effectiveBackgroundColor,
      borderRadius: effectiveBorderRadius,
      border: border,
    );

    Widget cardContent = Container(
      width: width,
      height: height,
      padding: padding ?? AppSpacing.cardPadding,
      margin: margin,
      decoration: cardDecoration,
      clipBehavior: clipBehavior,
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: AppColors.transparent,
        borderRadius: effectiveBorderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: effectiveBorderRadius,
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }
}

class AppCardWithHeader extends StatelessWidget {
  const AppCardWithHeader({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding,
    this.backgroundColor,
    this.borderRadius,
    this.elevation = 0,
    this.onTap,
    this.onHeaderTap,
  });

  final String title;

  final String? subtitle;

  final Widget child;

  final Widget? trailing;

  final EdgeInsets? padding;

  final Color? backgroundColor;

  final BorderRadius? borderRadius;

  final double elevation;

  final VoidCallback? onTap;

  final VoidCallback? onHeaderTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final textColor = isLight
        ? AppColors.textPrimary
        : AppColors.textPrimaryDark;

    return AppCard(
      backgroundColor: backgroundColor,
      borderRadius: borderRadius,
      elevation: elevation,
      onTap: onTap,
      padding: AppSpacing.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onHeaderTap,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(AppSpacing.radiusDf),
              topRight: Radius.circular(AppSpacing.radiusDf),
            ),
            child: Padding(
              padding: padding ?? AppSpacing.cardPadding,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null) ...[
                          AppSpacing.verticalXs,
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
          Padding(
            padding: (padding ?? AppSpacing.cardPadding).copyWith(top: 0),
            child: child,
          ),
        ],
      ),
    );
  }
}
