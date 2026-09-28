# Colony

Colony is a private workspace for Apple devices: projects and tasks, team channels, and a lightweight CRM in one app.

Everything is stored in your iCloud account through CloudKit and syncs across iPhone, iPad, Mac and Apple Vision Pro. Colony has no server of its own and uses no third-party services. Integrations use Apple's built-in apps: Contacts, Reminders, Mail, Phone, FaceTime and the share sheet.

## Documentation

- [Architecture](docs/ARCHITECTURE.md): storage, CloudKit schema rules, Apple services, code layout
- [Product](docs/PRODUCT.md)
- [Theming](docs/THEMING.md)
- [Roadmap](docs/ROADMAP.md)

## Running

1. Open `Colony.xcodeproj` in Xcode 26 or later.
2. Signing & Capabilities uses team `N6883L5366` with iCloud (CloudKit) container `iCloud.yoavperetz.Colony`, iCloud key-value storage, and push notifications for silent sync.
3. Sign in to iCloud on the device or simulator, then run.

Tests: `xcodebuild test -scheme Colony -destination 'platform=macOS' -only-testing:ColonyTests`
