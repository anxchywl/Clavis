import 'piano_room_models.dart';

abstract interface class PianoRoomRepository {
  Future<PianoRoomWeek> loadWeek(DateTime monday);
  Future<PianoRoomBooking> book({
    required String slotId,
    required String requestId,
  });
  Future<void> release(String bookingId);
}
