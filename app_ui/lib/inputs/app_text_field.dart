import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_text_styles.dart';

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.helperText,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.validator,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.focusNode,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.trimSpaces = true,
    this.filled = true,
    this.fillColor,
    this.borderRadius,
    this.contentPadding,
  });

  final TextEditingController? controller;

  final String? label;

  final String? hint;

  final String? errorText;

  final String? helperText;

  final Widget? prefixIcon;

  final Widget? suffixIcon;

  final TextInputType? keyboardType;

  final TextInputAction? textInputAction;

  final ValueChanged<String>? onChanged;

  final ValueChanged<String>? onSubmitted;

  final VoidCallback? onTap;

  final FormFieldValidator<String>? validator;

  final bool enabled;

  final bool readOnly;

  final bool autofocus;

  final bool obscureText;

  final int? maxLines;

  final int? minLines;

  final int? maxLength;

  final FocusNode? focusNode;

  final List<TextInputFormatter>? inputFormatters;

  final bool trimSpaces;

  final TextCapitalization textCapitalization;

  final bool filled;

  final Color? fillColor;

  final BorderRadius? borderRadius;

  final EdgeInsets? contentPadding;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    final defaultFillColor = isLight
        ? AppColors.fieldBackground
        : AppColors.surfaceDark;
    final effectiveFillColor = widget.fillColor ?? defaultFillColor;
    final effectiveBorderRadius =
        widget.borderRadius ?? AppSpacing.borderRadiusMd;
    final effectiveContentPadding =
        widget.contentPadding ??
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.df,
          vertical: AppSpacing.md,
        );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: effectiveBorderRadius,
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: widget.errorText,
          helperText: widget.helperText,
          counterText: '',
          prefixIcon: widget.prefixIcon,
          suffixIcon: widget.suffixIcon,
          filled: widget.filled,
          fillColor: effectiveFillColor,
          contentPadding: effectiveContentPadding,
          hintStyle: AppTextStyles.hint.copyWith(color: AppColors.grey),
          labelStyle: AppTextStyles.labelLarge.copyWith(
            color: _focusNode.hasFocus
                ? AppColors.primary
                : (isLight ? AppColors.textPrimary : AppColors.textPrimaryDark),
          ),
          errorStyle: AppTextStyles.error.copyWith(color: AppColors.error),
          helperStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.grey),
          border: OutlineInputBorder(
            borderRadius: effectiveBorderRadius,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: effectiveBorderRadius,
            borderSide: isLight
                ? BorderSide.none
                : const BorderSide(color: AppColors.primary, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: effectiveBorderRadius,
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: effectiveBorderRadius,
            borderSide: const BorderSide(color: AppColors.error, width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: effectiveBorderRadius,
            borderSide: const BorderSide(color: AppColors.error, width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: effectiveBorderRadius,
            borderSide: BorderSide.none,
          ),
        ),
        style: AppTextStyles.bodyLarge.copyWith(
          color: isLight ? AppColors.textPrimary : AppColors.textPrimaryDark,
        ),
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        onChanged: widget.onChanged,
        onFieldSubmitted: widget.onSubmitted,
        onTap: widget.onTap,
        validator: widget.validator,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        autofocus: widget.autofocus,
        obscureText: widget.obscureText,
        maxLines: widget.obscureText ? 1 : widget.maxLines,
        minLines: widget.minLines,
        maxLength: widget.maxLength,
        inputFormatters: [
          ...?widget.inputFormatters,
          if (widget.trimSpaces) _SingleSpaceFormatter(),
        ],
        textCapitalization: widget.textCapitalization,
      ),
    );
  }
}

class _SingleSpaceFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String newText = newValue.text;

    if (newText.startsWith(' ')) {
      newText = newText.trimLeft();
    }

    newText = newText.replaceAll(RegExp(r' {2,}'), ' ');

    if (newText == newValue.text) {
      return newValue;
    }

    int selectionIndex =
        newValue.selection.end - (newValue.text.length - newText.length);
    if (selectionIndex < 0) selectionIndex = 0;
    if (selectionIndex > newText.length) selectionIndex = newText.length;

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selectionIndex),
    );
  }
}
