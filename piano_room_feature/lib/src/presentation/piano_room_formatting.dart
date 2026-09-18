import 'package:intl/intl.dart';
import '../domain/piano_room_failure.dart';
import '../domain/piano_room_models.dart';
import '../l10n/piano_room_strings.dart';

String roomDate(PianoRoomLocalizations s, DateTime date) =>
    DateFormat.yMMMd(s.localeName).format(date);
String roomLongDay(PianoRoomLocalizations s, DateTime date) =>
    DateFormat.MMMMEEEEd(s.localeName).format(date);
// the year is said once, on the end of the range
String roomWeek(PianoRoomLocalizations s, DateTime monday, DateTime sunday) =>
    s.weekLabel(
      DateFormat.MMMd(s.localeName).format(monday),
      roomDate(s, sunday),
    );
String roomTime(PianoRoomLocalizations s, DateTime start, DateTime end) =>
    s.timeRange(
      DateFormat.Hm(s.localeName).format(start),
      DateFormat.Hm(s.localeName).format(end),
    );
String bookingStatus(PianoRoomLocalizations s, BookingStatus status) =>
    switch (status) {
      BookingStatus.confirmed => s.confirmed,
      BookingStatus.released => s.released,
      BookingStatus.completed => s.completed,
      BookingStatus.dropped => s.dropped,
      BookingStatus.noShow => s.noShow,
    };
String failureMessage(
  PianoRoomLocalizations s,
  PianoRoomFailureCode code, {
  bool refreshed = true,
}) => switch (code) {
  PianoRoomFailureCode.offline => s.offline,
  PianoRoomFailureCode.conflict =>
    refreshed ? s.conflict : s.conflictUnverified,
  PianoRoomFailureCode.quota => s.quotaError,
  PianoRoomFailureCode.windowClosed => s.windowError,
  PianoRoomFailureCode.past => s.pastError,
  PianoRoomFailureCode.releaseDeadline => s.deadlineError,
  _ => s.genericError,
};
