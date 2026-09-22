# Piano Room

Piano Room is a development-only Flutter demo for the NU Piano Room booking flow.

The package direction is:

`piano_room_app -> piano_room_feature -> app_ui`

The demo uses a synthetic student, sample data, and a fixed Almaty clock. It has no real authentication or backend. Bookings reset when the app restarts.

```sh
cd piano_room_feature
flutter pub get
flutter gen-l10n
cd ../piano_room_app
flutter pub get
flutter run -d chrome
```

Use `--dart-define=PIANO_LOCALE=ru` or `kk` to change the language. Use `--dart-define=PIANO_SCENARIO=conflict` to test a booking conflict.

More details:

- [Product rules](docs/PRODUCT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Repository and security contract](docs/API.md)
- [Development and verification](docs/INFRASTRUCTURE.md)
