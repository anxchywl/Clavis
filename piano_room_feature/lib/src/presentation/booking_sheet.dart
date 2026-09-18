import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../application/piano_room_controller.dart';
import '../domain/piano_room_models.dart';
import '../l10n/piano_room_strings.dart';
import 'piano_room_formatting.dart';
import 'piano_room_widgets.dart';

Future<void> showRoomSheet(
  BuildContext context,
  Widget child,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  // a soft rise and a quicker fall, still for anyone who asked for no motion
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : AnimationStyle(
          duration: const Duration(milliseconds: 340),
          reverseDuration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
  builder: (sheetContext) => PianoRoomStringsScope(
    child: SingleChildScrollView(
      // the theme's drag handle already stands above the title, and the
      // home indicator must not sit on the last button
      padding: AppSpacing.bottomSheetPadding.copyWith(
        top: AppSpacing.xs,
        bottom: AppSpacing.df + MediaQuery.paddingOf(sheetContext).bottom,
      ),
      child: child,
    ),
  ),
);

class BookingSheet extends StatefulWidget {
  const BookingSheet({
    super.key,
    required this.controller,
    required this.slot,
    this.releaseBooking,
  });
  final PianoRoomController controller;
  final PianoRoomSlot slot;
  final PianoRoomBooking? releaseBooking;
  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  bool _success = false;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    widget.controller.clearOutcome();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final booking = widget.releaseBooking;
    final success = booking == null
        ? await widget.controller.book(widget.slot)
        : await widget.controller.release(booking);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _success = success;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = PianoRoomLocalizations.of(context);
    final c = widget.controller;
    final releasing = widget.releaseBooking != null;
    final ink = roomInk(context);
    final slot = widget.slot;
    Text line(String text, TextStyle style, {Color? color}) => Text(
      text,
      textAlign: TextAlign.center,
      style: style.copyWith(color: color ?? ink),
    );
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final failure = c.mutationFailure;
        return PopScope(
          canPop: !_busy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                liveRegion: _success,
                child: line(
                  _success
                      ? (releasing ? s.releaseSuccess : s.success)
                      : releasing
                      ? s.releaseTitle
                      : s.confirmTitle,
                  AppTextStyles.titleMedium,
                ),
              ),
              AppSpacing.verticalXl,
              // the time is what the student came for, so it leads
              line(roomTime(s, slot.start, slot.end), AppTextStyles.amount),
              AppSpacing.verticalXs,
              line(roomLongDay(s, slot.start), AppTextStyles.bodyLarge),
              line(s.location, AppTextStyles.bodyMedium),
              if (!_success) ...[
                if (!releasing) ...[
                  AppSpacing.verticalXl,
                  if (c.week != null)
                    line(
                      s.quotaImpact(
                        c.projectedBooked(slot.id),
                        c.week!.quota.limit,
                      ),
                      AppTextStyles.bodySmall,
                    ),
                  AppSpacing.verticalXs,
                  line(s.reminder, AppTextStyles.bodySmall),
                ],
                if (failure != null) ...[
                  AppSpacing.verticalDf,
                  Semantics(
                    liveRegion: true,
                    child: line(
                      failureMessage(
                        s,
                        failure,
                        refreshed: c.phase == SchedulePhase.ready,
                      ),
                      AppTextStyles.bodyMedium,
                      color: roomDanger(context),
                    ),
                  ),
                ],
                if (_busy) Semantics(liveRegion: true, label: s.submitting),
                AppSpacing.verticalXl,
                _SheetActions(
                  primaryLabel: releasing ? s.release : s.confirm,
                  primaryColor: releasing ? roomDanger(context) : null,
                  busy: _busy,
                  onPrimary: !_busy && c.canRetryMutation ? _submit : null,
                  cancelLabel: s.cancel,
                  onCancel: _busy ? null : () => Navigator.of(context).pop(),
                ),
              ] else ...[
                if (c.hasStaleData) ...[
                  AppSpacing.verticalDf,
                  Semantics(
                    liveRegion: true,
                    child: line(
                      s.mutationAcceptedStale,
                      AppTextStyles.bodySmall,
                    ),
                  ),
                ],
                AppSpacing.verticalXl,
                AppPrimaryButton(
                  text: s.done,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// side by side, the way out narrower than the answer being asked for; very
// large text stacks them so neither label is cut
class _SheetActions extends StatelessWidget {
  const _SheetActions({
    required this.primaryLabel,
    required this.onPrimary,
    required this.cancelLabel,
    required this.onCancel,
    this.primaryColor,
    this.busy = false,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String cancelLabel;
  final VoidCallback? onCancel;
  final Color? primaryColor;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    // both at the kit's medium height with its own secondary styling, as
    // the confirm rows in the other apps are
    final primary = AppPrimaryButton(
      text: primaryLabel,
      size: AppButtonSize.medium,
      color: primaryColor,
      isLoading: busy,
      isEnabled: onPrimary != null,
      onPressed: onPrimary,
    );
    final cancel = AppSecondaryButton(
      text: cancelLabel,
      size: AppButtonSize.medium,
      isEnabled: onCancel != null,
      onPressed: onCancel,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final fits =
            constraints.maxWidth >=
            MediaQuery.textScalerOf(context).scale(AppSpacing.xxxxl * 4.5);
        if (!fits) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [primary, AppSpacing.verticalSm, cancel],
          );
        }
        return Row(
          children: [
            Expanded(flex: 2, child: cancel),
            AppSpacing.horizontalMd,
            Expanded(flex: 3, child: primary),
          ],
        );
      },
    );
  }
}
