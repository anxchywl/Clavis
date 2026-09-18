import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

// the kit styles carry no colour, these resolve one for the current brightness
bool _light(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light;

// secondary text keeps the primary ink, because the kit's grey fails contrast
Color roomInk(BuildContext context) =>
    _light(context) ? AppColors.textPrimary : AppColors.textPrimaryDark;

Color roomSurface(BuildContext context) =>
    _light(context) ? AppColors.surface : AppColors.surfaceDark;

Color roomBorder(BuildContext context) =>
    _light(context) ? AppColors.borderGrey : AppColors.borderDark;

Color roomAccent(BuildContext context) =>
    _light(context) ? AppColors.primary : AppColors.primaryAccentDark;

// white on the pale dark-mode accent would be unreadable
Color roomOnAccent(BuildContext context) =>
    _light(context) ? AppColors.white : AppColors.black;

Color roomDanger(BuildContext context) =>
    _light(context) ? AppColors.errorText : AppColors.errorTextDark;

// a quiet text action that still meets the minimum touch target
class RoomTextAction extends StatelessWidget {
  const RoomTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: color ?? roomAccent(context),
      minimumSize: const Size(
        AppSpacing.buttonHeightDf,
        AppSpacing.buttonHeightDf,
      ),
      padding: AppSpacing.buttonPaddingCompact,
      textStyle: AppTextStyles.buttonSmall,
      shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusMd),
    ),
    child: Text(label, textAlign: TextAlign.center),
  );
}

// a failed or empty schedule is a sentence and a way to try again
class RoomStateMessage extends StatelessWidget {
  const RoomStateMessage({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
    child: Column(
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyLarge.copyWith(color: roomInk(context)),
          ),
        ),
        AppSpacing.verticalSm,
        RoomTextAction(label: actionLabel, onPressed: onAction),
      ],
    ),
  );
}

class ScheduleSkeleton extends StatelessWidget {
  const ScheduleSkeleton({super.key, required this.loadingLabel});

  final String loadingLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('schedule-skeleton'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(liveRegion: true, label: loadingLabel),
        // empty room rather than a grey block, so a week sliding in while it
        // loads does not flash a placeholder
        const SizedBox(height: AppSpacing.buttonHeightLg * 6),
      ],
    );
  }
}
