import 'package:flutter/material.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_text_styles.dart';

class AppPrimaryButton extends StatefulWidget {
  const AppPrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isEnabled = true,
    this.icon,
    this.width,
    this.height,
    this.size = AppButtonSize.large,
    this.color,
  });

  final String text;

  final VoidCallback? onPressed;

  final bool isLoading;

  final bool isEnabled;

  final Widget? icon;

  final double? width;

  final double? height;

  final AppButtonSize size;

  // a destructive action passes its own colour; everything else is the brand
  final Color? color;

  double get _height => height ?? size.height;

  @override
  State<AppPrimaryButton> createState() => _AppPrimaryButtonState();
}

class _AppPrimaryButtonState extends State<AppPrimaryButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = widget.isEnabled && !widget.isLoading
        ? widget.onPressed
        : null;
    final background = widget.color ?? AppColors.primary;

    return Listener(
      onPointerDown: (_) {
        if (effectiveOnPressed != null) setState(() => _isPressed = true);
      },
      onPointerUp: (_) => setState(() => _isPressed = false),
      onPointerCancel: (_) => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOutCubic,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppSpacing.borderRadiusMd,
            // a soft glow in the button's own colour lifts it off the surface,
            // and goes with the colour when the button cannot be pressed
            boxShadow: effectiveOnPressed == null
                ? const []
                : [
                    BoxShadow(
                      color: background.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: SizedBox(
            width: widget.width ?? double.infinity,
            height: widget._height,
            child: ElevatedButton(
              onPressed: effectiveOnPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: background,
                foregroundColor: AppColors.white,
                disabledBackgroundColor: background.withValues(alpha: 0.5),
                disabledForegroundColor: AppColors.white.withValues(alpha: 0.7),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: AppSpacing.borderRadiusMd,
                ),
                padding: widget.size.padding,
              ),
              child: _buildChild(),
            ),
          ),
        ),
      ),
    );
  }

  // a spinner on its own says that something is happening and never what, and
  // it leaves the control with no accessible name for as long as it spins
  Widget _buildChild() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isLoading) ...[
          const SizedBox(
            width: AppSpacing.iconSm,
            height: AppSpacing.iconSm,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
            ),
          ),
          AppSpacing.horizontalSm,
        ] else if (widget.icon != null) ...[
          widget.icon!,
          AppSpacing.horizontalSm,
        ],
        Flexible(
          child: Text(
            widget.text,
            style: widget.size == AppButtonSize.small
                ? AppTextStyles.buttonSmall
                : AppTextStyles.button,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

enum AppButtonSize {
  small(AppSpacing.buttonHeightSm, AppSpacing.buttonPaddingCompact),
  medium(AppSpacing.buttonHeightDf, AppSpacing.buttonPaddingCompact),
  large(AppSpacing.buttonHeightLg, AppSpacing.buttonPadding);

  const AppButtonSize(this.height, this.padding);

  final double height;
  final EdgeInsets padding;
}
