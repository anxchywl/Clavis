enum PianoRoomFailureCode {
  offline,
  conflict,
  quota,
  windowClosed,
  past,
  releaseDeadline,
  notOwner,
  invalidRequest,
  unavailable,
}

class PianoRoomFailure implements Exception {
  const PianoRoomFailure(this.code);
  final PianoRoomFailureCode code;
}
