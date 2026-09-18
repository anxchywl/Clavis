import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../application/piano_room_controller.dart';
import '../application/piano_room_scope.dart';
import '../domain/piano_room_models.dart';
import '../l10n/piano_room_strings.dart';
import 'booking_sheet.dart';
import 'piano_room_formatting.dart';
import 'piano_room_widgets.dart';

// a phone column even on a tablet, so rows never stretch across the screen
const double _readingWidth = AppSpacing.xxxxl * 9;

// a flick faster than this turns the week, a slow drag is left alone
const double _swipeVelocity = AppSpacing.xxxxl * 5;

const Duration _motion = Duration(milliseconds: 260);

class PianoRoomScreen extends StatelessWidget {
  const PianoRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PianoRoomScope.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _readingWidth),
              child: ListView(
                padding: AppSpacing.screenPadding.copyWith(
                  bottom: AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  const _Header(),
                  AppSpacing.verticalDf,
                  _WeekSwitcher(controller: c),
                  _WeekPager(controller: c),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final s = PianoRoomLocalizations.of(context);
    final ink = roomInk(context);
    return Column(
      children: [
        Semantics(
          header: true,
          child: Text(
            s.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineSmall.copyWith(color: ink),
          ),
        ),
        Text(
          s.location,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(color: ink),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: AppTextStyles.sectionHeader.copyWith(color: roomInk(context)),
    ),
  );
}

class _WeekSwitcher extends StatelessWidget {
  const _WeekSwitcher({required this.controller});
  final PianoRoomController controller;

  @override
  Widget build(BuildContext context) {
    final s = PianoRoomLocalizations.of(context);
    final c = controller;
    final ink = roomInk(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppIconButton(
              icon: AppIcon(AppIcons.chevronLeft, color: ink),
              size: AppIconButtonSize.large,
              tooltip: s.previousWeek,
              onPressed: () => c.moveWeek(-1),
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : _motion,
                  child: Text(
                    roomWeek(
                      s,
                      c.selectedWeek,
                      c.policy.shiftDays(c.selectedWeek, 6),
                    ),
                    key: ValueKey(c.selectedWeek),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.titleMedium.copyWith(color: ink),
                  ),
                ),
              ),
            ),
            AppIconButton(
              icon: AppIcon(AppIcons.chevronRight, color: ink),
              size: AppIconButtonSize.large,
              tooltip: s.nextWeek,
              onPressed: () => c.moveWeek(1),
            ),
          ],
        ),
        // a refresh keeps its room so the schedule below never jumps
        SizedBox(
          height: AppSpacing.dividerThick,
          child: c.refreshing
              ? ExcludeSemantics(
                  child: LinearProgressIndicator(
                    minHeight: AppSpacing.dividerThick,
                    color: roomAccent(context),
                    backgroundColor: roomBorder(context),
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

// the week slides in from the side it was asked for, by arrow or by swipe
class _WeekPager extends StatefulWidget {
  const _WeekPager({required this.controller});
  final PianoRoomController controller;

  @override
  State<_WeekPager> createState() => _WeekPagerState();
}

class _WeekPagerState extends State<_WeekPager> {
  late DateTime _week = widget.controller.selectedWeek;
  var _direction = 1;

  @override
  void didUpdateWidget(_WeekPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    final week = widget.controller.selectedWeek;
    if (week != _week) {
      _direction = week.isAfter(_week) ? 1 : -1;
      _week = week;
    }
  }

  void _swiped(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < _swipeVelocity) return;
    widget.controller.moveWeek(velocity < 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    final key = ValueKey(_week);
    final still = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: _swiped,
      child: AnimatedSwitcher(
        duration: still ? Duration.zero : _motion,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, animation) {
          // the new week enters from the swipe side, the old one leaves
          // towards the other
          final entering = child.key == key;
          final from = Offset((entering ? _direction : -_direction) * 0.25, 0);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: from, end: Offset.zero).animate(animation),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: key,
          child: _WeekBody(controller: widget.controller),
        ),
      ),
    );
  }
}

class _WeekBody extends StatelessWidget {
  const _WeekBody({required this.controller});
  final PianoRoomController controller;

  @override
  Widget build(BuildContext context) {
    final s = PianoRoomLocalizations.of(context);
    final c = controller;
    final week = c.week;
    if (c.phase == SchedulePhase.loading && week == null) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.df),
        child: ScheduleSkeleton(loadingLabel: s.loading),
      );
    }
    if (c.phase == SchedulePhase.failed) {
      return RoomStateMessage(
        title: failureMessage(s, c.loadFailure!),
        actionLabel: s.retry,
        onAction: c.load,
      );
    }
    if (c.phase == SchedulePhase.empty || week == null) {
      return RoomStateMessage(
        title: s.empty,
        actionLabel: s.retry,
        onAction: c.load,
      );
    }
    final ink = roomInk(context);
    final day = week.days[c.selectedDay];
    final bookings = week.bookings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSpacing.verticalSm,
        _Status(controller: c, week: week),
        if (c.hasStaleData)
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    s.stale(failureMessage(s, c.loadFailure!)),
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: roomDanger(context),
                    ),
                  ),
                ),
              ),
              RoomTextAction(label: s.retry, onPressed: c.load),
            ],
          ),
        AppSpacing.verticalXl,
        _DayStrip(controller: c, week: week),
        AppSpacing.verticalXl,
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          children: [
            _SectionTitle(roomLongDay(s, day.date)),
            Text(
              s.availableCount(day.availableCount),
              style: AppTextStyles.bodySmall.copyWith(color: ink),
            ),
          ],
        ),
        AppSpacing.verticalSm,
        _Group(
          children: [
            for (final slot in day.slots) _SlotRow(slot: slot, controller: c),
          ],
        ),
        if (bookings.isNotEmpty) ...[
          AppSpacing.verticalXl,
          _SectionTitle(s.myBookings),
          AppSpacing.verticalSm,
          _Group(
            children: [
              for (final booking in bookings)
                _BookingRow(booking: booking, controller: c),
            ],
          ),
        ],
      ],
    );
  }
}

// two lines under the week: whether it can be booked, and how much is left
class _Status extends StatelessWidget {
  const _Status({required this.controller, required this.week});
  final PianoRoomController controller;
  final PianoRoomWeek week;

  @override
  Widget build(BuildContext context) {
    final s = PianoRoomLocalizations.of(context);
    final c = controller;
    final ink = roomInk(context);
    final quota = week.quota;
    final window = c.window;
    return Semantics(
      liveRegion: true,
      container: true,
      // short lines of steady size, centred under the week they describe
      child: Column(
        children: [
          Text(
            switch (window) {
              BookingWindowStatus.upcoming => s.upcoming,
              BookingWindowStatus.open => s.open,
              BookingWindowStatus.closed => s.closed,
              BookingWindowStatus.unavailable => s.unavailable,
            },
            textAlign: TextAlign.center,
            style: AppTextStyles.titleSmall.copyWith(
              color: window == BookingWindowStatus.open
                  ? roomAccent(context)
                  : ink,
            ),
          ),
          // when it opens only matters while the week cannot be booked yet
          if (window == BookingWindowStatus.upcoming)
            Text(
              s.opensAt(roomLongDay(s, c.policy.opensAt(c.selectedWeek))),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: ink),
            ),
          Text(
            s.quota(quota.booked, quota.limit),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: ink),
          ),
          if (quota.isPenalized)
            Text(
              s.penalty,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: roomDanger(context),
              ),
            ),
        ],
      ),
    );
  }
}

// one plain surface with hairlines between rows, like a settings list
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: roomSurface(context),
      borderRadius: AppSpacing.borderRadiusDf,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0)
            Divider(
              height: AppSpacing.dividerDf,
              thickness: AppSpacing.dividerDf,
              indent: AppSpacing.df,
              color: roomBorder(context),
            ),
          children[index],
        ],
      ],
    ),
  );
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({required this.booking, required this.controller});
  final PianoRoomBooking booking;
  final PianoRoomController controller;

  @override
  Widget build(BuildContext context) {
    final s = PianoRoomLocalizations.of(context);
    final c = controller;
    final ink = roomInk(context);
    final releasable = c.canRelease(booking);
    final confirmed = booking.status == BookingStatus.confirmed;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.df,
        end: AppSpacing.xs,
        top: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  roomTime(s, booking.start, booking.end),
                  style: AppTextStyles.bodyLarge.copyWith(color: ink),
                ),
                Text(
                  roomLongDay(s, booking.start),
                  style: AppTextStyles.bodySmall.copyWith(color: ink),
                ),
                // a confirmed booking needs no label, anything else does
                if (!confirmed)
                  Text(
                    bookingStatus(s, booking.status),
                    style: AppTextStyles.bodySmall.copyWith(color: ink),
                  )
                else if (!releasable)
                  Text(
                    s.releaseBlocked,
                    style: AppTextStyles.bodySmall.copyWith(color: ink),
                  ),
              ],
            ),
          ),
          if (releasable)
            AppIconButton(
              icon: AppIcon(
                AppIcons.close,
                size: AppSpacing.iconMd,
                color: roomDanger(context),
              ),
              size: AppIconButtonSize.large,
              tooltip: s.release,
              onPressed: () => showRoomSheet(
                context,
                BookingSheet(
                  controller: c,
                  slot: c.week!.days
                      .expand((day) => day.slots)
                      .firstWhere((slot) => slot.id == booking.slotId),
                  releaseBooking: booking,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// all seven days fit at once, so no day hides behind a sideways scroll
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.controller, required this.week});
  final PianoRoomController controller;
  final PianoRoomWeek week;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < week.days.length; index++)
        Expanded(
          child: _DayCell(
            day: week.days[index],
            selected: controller.selectedDay == index,
            onPressed: () => controller.selectDay(index),
          ),
        ),
    ],
  );
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.onPressed,
  });
  final PianoRoomDay day;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = PianoRoomLocalizations.of(context);
    final ink = roomInk(context);
    final accent = roomAccent(context);
    final booked = day.slots.any((slot) => slot.belongsToCurrentStudent);
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _motion;
    return Semantics(
      selected: selected,
      onTap: onPressed,
      button: true,
      label:
          '${roomDate(s, day.date)}, ${s.availableCount(day.availableCount)}',
      value: booked ? s.ownSlot : null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppSpacing.borderRadiusMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          // large text shrinks inside the cell rather than breaking the row
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              children: [
                Text(
                  DateFormat.E(s.localeName).format(day.date),
                  style: AppTextStyles.labelSmall.copyWith(color: ink),
                ),
                AppSpacing.verticalXs,
                AnimatedContainer(
                  duration: motion,
                  curve: Curves.easeOutCubic,
                  width: AppSpacing.xxxl - AppSpacing.md,
                  height: AppSpacing.xxxl - AppSpacing.md,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: selected ? 1 : 0),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    DateFormat.d(s.localeName).format(day.date),
                    style: AppTextStyles.titleMedium.copyWith(
                      color: selected ? roomOnAccent(context) : ink,
                    ),
                  ),
                ),
                AppSpacing.verticalXs,
                // a small mark under a day that holds one of your bookings
                AnimatedContainer(
                  duration: motion,
                  width: AppSpacing.xs * 1.5,
                  height: AppSpacing.xs * 1.5,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: booked ? 1 : 0),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot, required this.controller});
  final PianoRoomSlot slot;
  final PianoRoomController controller;

  @override
  Widget build(BuildContext context) {
    final s = PianoRoomLocalizations.of(context);
    final enabled = controller.eligible(slot);
    void book() => showRoomSheet(
      context,
      BookingSheet(controller: controller, slot: slot),
    );
    final ink = roomInk(context);
    final status = switch (slot.availability) {
      SlotAvailability.own => s.ownSlot,
      SlotAvailability.unavailable => s.otherBooking,
      SlotAvailability.available => enabled ? s.available : s.notEligible,
    };
    // only the exceptions are spelled out; a bookable slot gets the usual
    // chevron and one nobody can book shows just its time
    final visibleStatus = slot.availability == SlotAvailability.available
        ? null
        : status;
    return Semantics(
      label: s.slotLabel(
        roomDate(s, slot.start),
        roomTime(s, slot.start, slot.end),
        status,
      ),
      button: true,
      enabled: enabled,
      onTap: enabled ? book : null,
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? book : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.buttonHeightLg - AppSpacing.xs,
          ),
          child: Padding(
            padding: AppSpacing.listItemPadding,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.df,
              children: [
                Text(
                  roomTime(s, slot.start, slot.end),
                  style: AppTextStyles.bodyLarge.copyWith(color: ink),
                ),
                if (visibleStatus != null)
                  Text(
                    visibleStatus,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: slot.belongsToCurrentStudent
                          ? roomAccent(context)
                          : ink,
                    ),
                  )
                else if (enabled)
                  AppIcon(
                    AppIcons.chevronRight,
                    size: AppSpacing.iconMd,
                    color: roomAccent(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
