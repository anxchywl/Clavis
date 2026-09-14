import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../icons/app_icons.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_text_styles.dart';

// narrower than this reads as a fragment, wider stops being a list of labels
const double _minMenuWidth = 220;
const double _maxMenuWidth = 320;

class AppMenuItem<T> {
  const AppMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.description,
    this.enabled = true,
    this.isDestructive = false,
  });

  final T value;
  final String label;
  final AppIconData? icon;

  // a disabled item reason belongs here rather than always on the screen
  final String? description;

  final bool enabled;

  // grouped last behind a divider so a mis-tap cannot land on one
  final bool isDestructive;
}

// a bare PopupMenuButton takes material defaults that match nothing in the kit
class AppMenu<T> extends StatelessWidget {
  const AppMenu({
    super.key,
    required this.items,
    required this.onSelected,
    required this.tooltip,
    this.icon = AppIcons.moreVert,
    this.iconColor,
  });

  final List<AppMenuItem<T>> items;
  final ValueChanged<T> onSelected;

  // also the accessible name of the button, it has no label of its own
  final String tooltip;

  final AppIconData icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final safe = items.where((item) => !item.isDestructive);
    final destructive = items.where((item) => item.isDestructive);

    return PopupMenuButton<T>(
      tooltip: tooltip,
      icon: AppIcon(
        icon,
        color:
            iconColor ??
            (isLight ? AppColors.iconPrimary : AppColors.textPrimaryDark),
      ),
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      offset: const Offset(0, AppSpacing.xs),
      color: isLight ? AppColors.white : AppColors.surfaceDark,
      surfaceTintColor: AppColors.transparent,
      shadowColor: AppColors.black,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderRadiusDf,
        side: BorderSide(
          color: isLight ? AppColors.borderGrey : AppColors.borderDark,
        ),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      constraints: const BoxConstraints(
        minWidth: _minMenuWidth,
        maxWidth: _maxMenuWidth,
      ),
      itemBuilder: (context) => [
        for (final item in safe) _entry(item),
        if (safe.isNotEmpty && destructive.isNotEmpty)
          PopupMenuDivider(
            height: AppSpacing.md,
            color: isLight ? AppColors.divider : AppColors.borderDark,
          ),
        for (final item in destructive) _entry(item),
      ],
    );
  }

  PopupMenuItem<T> _entry(AppMenuItem<T> item) => PopupMenuItem<T>(
    value: item.value,
    enabled: item.enabled,
    height: AppSpacing.buttonHeightSm,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.df,
      vertical: AppSpacing.sm,
    ),
    child: _MenuItemContent(item: item),
  );
}

class _MenuItemContent extends StatelessWidget {
  const _MenuItemContent({required this.item});

  final AppMenuItem<dynamic> item;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final destructive = isLight ? AppColors.errorText : AppColors.errorTextDark;
    final label = !item.enabled
        ? AppColors.textDisabled
        : item.isDestructive
        ? destructive
        : (isLight ? AppColors.textPrimary : AppColors.textPrimaryDark);
    final icon = !item.enabled
        ? AppColors.iconDisabled
        : item.isDestructive
        ? destructive
        : AppColors.textSecondary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.icon != null) ...[
          Padding(
            // keeps the icon on the first line when the label wraps to two
            padding: const EdgeInsets.only(top: 2),
            child: AppIcon(item.icon!, size: AppSpacing.iconMd, color: icon),
          ),
          AppSpacing.horizontalMd,
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.label,
                style: AppTextStyles.bodyMedium.copyWith(color: label),
              ),
              if (item.description != null) ...[
                const SizedBox(height: 2),
                Text(
                  item.description!,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
