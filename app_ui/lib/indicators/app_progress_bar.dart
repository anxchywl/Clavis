import 'package:flutter/material.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_text_styles.dart';

class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.progress,
    this.label,
    this.showPercentage = false,
    this.height = 8,
    this.backgroundColor,
    this.progressColor,
    this.borderRadius,
    this.animate = true,
  });

  final double progress;

  final String? label;

  final bool showPercentage;

  final double height;

  final Color? backgroundColor;

  final Color? progressColor;

  final BorderRadius? borderRadius;

  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    // a dark card is already surfaceDark, so the track needs a white wash
    final effectiveBackgroundColor =
        backgroundColor ??
        (isLight
            ? AppColors.fieldBackground
            : AppColors.white.withValues(alpha: 0.12));
    final effectiveProgressColor = progressColor ?? AppColors.primary;
    final effectiveBorderRadius = borderRadius ?? AppSpacing.borderRadiusRound;
    final clampedProgress = progress.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null || showPercentage)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (label != null)
                  // a label long enough to meet the figure wraps, not overflows
                  Flexible(
                    child: Text(
                      label!,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: isLight
                            ? AppColors.textPrimary
                            : AppColors.textPrimaryDark,
                      ),
                    ),
                  ),
                if (showPercentage)
                  Text(
                    '${(clampedProgress * 100).toInt()}%',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: effectiveProgressColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: effectiveBackgroundColor,
            borderRadius: effectiveBorderRadius,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth * clampedProgress;

              Widget progressIndicator = Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: effectiveProgressColor,
                  borderRadius: effectiveBorderRadius,
                ),
              );

              if (animate) {
                progressIndicator = AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    color: effectiveProgressColor,
                    borderRadius: effectiveBorderRadius,
                  ),
                );
              }

              return Align(
                alignment: Alignment.centerLeft,
                child: progressIndicator,
              );
            },
          ),
        ),
      ],
    );
  }
}

class AppStepProgress extends StatelessWidget {
  const AppStepProgress({
    super.key,
    required this.totalSteps,
    required this.currentStep,
    this.activeColor,
    this.inactiveColor,
    this.completedColor,
    this.height = 4,
    this.spacing = 4,
  });

  final int totalSteps;

  final int currentStep;

  final Color? activeColor;

  final Color? inactiveColor;

  final Color? completedColor;

  final double height;

  final double spacing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    final effectiveActiveColor = activeColor ?? AppColors.primary;
    // white wash for the same reason as AppProgressBar
    final effectiveInactiveColor =
        inactiveColor ??
        (isLight
            ? AppColors.fieldBackground
            : AppColors.white.withValues(alpha: 0.12));
    final effectiveCompletedColor = completedColor ?? AppColors.primary;

    return Row(
      children: List.generate(totalSteps, (index) {
        final stepNumber = index + 1;
        final isCompleted = stepNumber < currentStep;
        final isActive = stepNumber == currentStep;

        Color color;
        if (isCompleted) {
          color = effectiveCompletedColor;
        } else if (isActive) {
          color = effectiveActiveColor;
        } else {
          color = effectiveInactiveColor;
        }

        return Expanded(
          child: Container(
            height: height,
            margin: EdgeInsets.only(
              left: index == 0 ? 0 : spacing / 2,
              right: index == totalSteps - 1 ? 0 : spacing / 2,
            ),
            decoration: BoxDecoration(
              color: color,
              borderRadius: AppSpacing.borderRadiusRound,
            ),
          ),
        );
      }),
    );
  }
}
