import 'package:flutter/material.dart';

sealed class AppIconData {
  const AppIconData();

  // escape hatch for packages that demand a raw IconData, null for svg icons
  IconData? get asIconData => null;

  static IconData? get chevronRight => null;

  static IconData? get visibility => null;

  static IconData? get visibilityOff => null;

  static IconData? get lock => null;

  static IconData? get phone => null;
}

final class SvgIcon extends AppIconData {
  const SvgIcon(this.assetPath, {this.package});

  final String assetPath;

  final String? package;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SvgIcon &&
          assetPath == other.assetPath &&
          package == other.package;

  @override
  int get hashCode => Object.hash(assetPath, package);

  @override
  String toString() => 'SvgIcon($assetPath)';
}

final class MaterialIcon extends AppIconData {
  const MaterialIcon(this.iconData);

  final IconData iconData;

  @override
  IconData? get asIconData => iconData;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MaterialIcon && iconData == other.iconData;

  @override
  int get hashCode => iconData.hashCode;

  @override
  String toString() => 'MaterialIcon(${iconData.codePoint})';
}
