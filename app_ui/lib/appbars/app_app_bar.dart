import 'package:flutter/material.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_text_styles.dart';
import '../icons/app_icons.dart';
import '../icons/app_icon.dart';

class AppAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.toolbarHeight = AppSpacing.appBarHeight,
    this.leading,
    this.leadingWidth,
    this.actions,
    this.showBackButton = false,
    this.onBackPressed,
    this.centerTitle = true,
    this.backgroundColor,
    this.elevation = 0,
    this.bottom,
    this.showDivider = false,
  });

  final String? title;

  final Widget? titleWidget;

  final double toolbarHeight;

  final Widget? leading;

  final double? leadingWidth;

  final List<Widget>? actions;

  final bool showBackButton;

  final VoidCallback? onBackPressed;

  final bool centerTitle;

  final Color? backgroundColor;

  final double elevation;

  final PreferredSizeWidget? bottom;

  final bool showDivider;

  @override
  Size get preferredSize => Size.fromHeight(
    toolbarHeight + (bottom?.preferredSize.height ?? 0) + (showDivider ? 1 : 0),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final effectiveBackgroundColor =
        backgroundColor ??
        (isLight ? AppColors.background : const Color(0xFF171717));
    final textColor = isLight
        ? AppColors.textPrimary
        : AppColors.textPrimaryDark;

    Widget? leadingWidget = leading;
    if (leadingWidget == null && showBackButton) {
      leadingWidget = _buildBackButton(context, isLight);
    }

    Widget? titleWidgetFinal = titleWidget;
    if (titleWidgetFinal == null && title != null) {
      titleWidgetFinal = Text(
        title!,
        style: AppTextStyles.appBarTitle.copyWith(color: textColor),
        overflow: TextOverflow.ellipsis,
      );
    }

    PreferredSizeWidget? effectiveBottom = bottom;
    if (showDivider || bottom != null) {
      effectiveBottom = PreferredSize(
        preferredSize: Size.fromHeight(
          (bottom?.preferredSize.height ?? 0) + (showDivider ? 1 : 0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?bottom,
            if (showDivider)
              Divider(
                height: 1,
                thickness: 1,
                color: isLight ? AppColors.divider : AppColors.borderDark,
              ),
          ],
        ),
      );
    }

    return AppBar(
      leading: leadingWidget,
      leadingWidth: leadingWidth,
      automaticallyImplyLeading: false,
      title: titleWidgetFinal,
      centerTitle: centerTitle,
      actions: actions,
      backgroundColor: effectiveBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: elevation,
      scrolledUnderElevation: 0,
      bottom: effectiveBottom,
      toolbarHeight: toolbarHeight,
      iconTheme: IconThemeData(
        color: isLight ? AppColors.iconGrey : AppColors.white,
        size: AppSpacing.iconDf,
      ),
    );
  }

  Widget _buildBackButton(BuildContext context, bool isLight) {
    return IconButton(
      onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
      padding: EdgeInsets.zero,
      icon: AppIcon(
        AppIcons.back,
        size: AppSpacing.iconDf,
        color: isLight ? AppColors.iconGrey : AppColors.white,
      ),
    );
  }
}

class AppSliverAppBar extends StatelessWidget {
  const AppSliverAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.leadingWidth,
    this.actions,
    this.centerTitle = true,
    this.pinned = false,
    this.toolbarHeight,
  });

  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final double? leadingWidth;
  final List<Widget>? actions;
  final bool centerTitle;
  final bool pinned;

  final double? toolbarHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final bg = isLight ? AppColors.background : const Color(0xFF171717);
    final textColor = isLight
        ? AppColors.textPrimary
        : AppColors.textPrimaryDark;

    Widget? titleW = titleWidget;
    if (titleW == null && title != null) {
      titleW = Text(
        title!,
        style: AppTextStyles.appBarTitle.copyWith(color: textColor),
        overflow: TextOverflow.ellipsis,
      );
    }

    return SliverAppBar(
      leading: leading,
      leadingWidth: leadingWidth,
      automaticallyImplyLeading: false,
      title: titleW,
      centerTitle: centerTitle,
      actions: actions,
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: toolbarHeight ?? AppSpacing.appBarHeight,
      floating: true,
      snap: true,
      pinned: pinned,
      iconTheme: IconThemeData(
        color: isLight ? AppColors.iconGrey : AppColors.white,
        size: AppSpacing.iconDf,
      ),
    );
  }
}

class AppSimpleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppSimpleAppBar({super.key, required this.title, this.onBackPressed});

  final String title;
  final VoidCallback? onBackPressed;

  @override
  Size get preferredSize => const Size.fromHeight(AppSpacing.appBarHeight);

  @override
  Widget build(BuildContext context) {
    return AppAppBar(
      title: title,
      showBackButton: true,
      onBackPressed: onBackPressed,
    );
  }
}
