# Repository rules

Piano Room follows `piano_room_app -> piano_room_feature -> app_ui`.
Domain is pure Dart; application depends on domain interfaces; presentation never imports data. Data factories assemble dependencies. The host owns identity, theme and locale. Never store tokens or describe mocks as production enforcement.

Use existing AppColors, AppTextStyles and AppSpacing tokens. Every visible string belongs in EN/RU/KK ARB files. No emoji. Comments explain non-obvious intent, lowercase without trailing punctuation. Keep changes scoped. Use flutter_test and hand-written fakes only.

Run ./scripts/verify.sh and a standalone host build before reporting completion. Keep feature coverage at least 85 percent; test meaningful outcomes. Do not alter app_ui except for generic improvements. Its source is the Gradus fork at 2bcc62067d2c89b0b0fcd1cd5d40ac515f526cc4.
