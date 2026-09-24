#!/usr/bin/env bash
# runs the debug app against production as one student. there is no sign-in
# yet, so the server issues a token that expires in 12 hours; it goes straight
# into the build defines and is never printed or saved
set -euo pipefail
cd "$(dirname "$0")/.."

host=${CLAVIS_SSH:-deploy@clavis.anxchywl.dev}
student=${PIANO_STUDENT_ID:-student-a}

# checked here as well, because it travels inside a remote shell command
[[ "$student" =~ ^[A-Za-z0-9._@-]{1,64}$ ]] || {
  echo "PIANO_STUDENT_ID must be letters, digits, dot, dash, underscore or @" >&2
  exit 1
}

token=$(ssh -o BatchMode=yes "$host" \
  docker exec clavis-api .venv/bin/python -m app.commands.issue_token \
  --subject "$student" --hours 12)

cd piano_room_app
exec flutter run \
  --dart-define=PIANO_BACKEND=remote \
  --dart-define=PIANO_ACCESS_TOKEN="$token" \
  --dart-define=PIANO_STUDENT_ID="$student" \
  "$@"
