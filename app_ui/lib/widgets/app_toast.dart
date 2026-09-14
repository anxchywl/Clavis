import 'package:flutter/material.dart';
import 'toast_manager.dart';

class AppToast {
  AppToast._();

  static void showSuccess(BuildContext context, String message) {
    ToastManager.showSuccess(context, message);
  }

  static void showError(BuildContext context, String message) {
    ToastManager.showError(context, message);
  }

  static void showWarning(BuildContext context, String message) {
    ToastManager.showWarning(context, message);
  }

  static void showInfo(BuildContext context, String message) {
    ToastManager.showInfo(context, message);
  }
}
