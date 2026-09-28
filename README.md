<div align="center">

<img src="docs/assets/banner-fade.png" alt="Colony" width="100%">


**Your team's projects, people and conversations, in your own iCloud.**

Plan projects and tasks, talk in channels, and keep track of the people you work with, in one native app.
It runs on iPhone, iPad, Mac and Apple Vision Pro.
There's no Colony server and no third-party service. Your data stays in your iCloud account, and your devices keep it in sync.

*For now a workspace belongs to one person and syncs across only that person's devices. Sharing a
workspace with teammates is the next milestone in the [roadmap](docs/ROADMAP.md).*

</div>

---

## What it is

Colony is a native SwiftUI app for Apple platforms. It has a home dashboard, projects with lists,
tasks as a list or a board, team channels, a sales pipeline, contacts and reports. All of these sit
behind a sidebar you can collapse and rearrange, and a ⌘K command center.

Every record is a SwiftData model mirrored to your private CloudKit database. Preferences sync
through iCloud's key-value store. Integrations use Apple's own frameworks: Contacts for importing
people, EventKit for Reminders, and Mail, Phone, FaceTime and the share sheet for reaching them.

You never create an account. You never run a server. Your iCloud account is your identity.

## Why it exists

The first Colony prototype followed the usual shape of a team tool: a self-hosted backend, its own
sign-in, and a server someone had to keep running. That's a lot of infrastructure for a workspace
most people use on their own devices.

Apple platforms already provide the rest: CloudKit for storage and sync, iCloud for identity,
Contacts and Reminders for the data people already have. Colony is the redesign built on those
services, with a Mac-first interface that also works on iPad, iPhone and Vision Pro.

## Status

**In development.** The native redesign is done:

- SwiftData + CloudKit storage, with iCloud key-value preferences.
- Home, Updates, Messages, My tasks and All tasks (list and board), Projects, Pipeline, Contacts,
  Reports, Apple services and Settings.
- One dialog system for every pop-up.
- A ⌘K command center.
- A sidebar you can drag to rearrange, which collapses to an icon column centred on the window
  controls.
- Swift Pieces components across the UI.
- Apple Contacts import and Reminders mirroring.

Builds without the iCloud entitlement fall back to an on-device store and say so in the sidebar.
The app builds for iOS, iPadOS, macOS and visionOS, and 11 unit tests cover the model and the
mutation path.

Still open:

- deploying the CloudKit schema to production;
- UI tests beyond Xcode's template;
- team workspaces through CloudKit sharing.

Start at [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). What's next is in
[`docs/ROADMAP.md`](docs/ROADMAP.md).

### Run the app locally

```sh
open Colony.xcodeproj                                    # Xcode 26+, scheme Colony, press Run
xcodebuild -scheme Colony -destination 'platform=macOS' \
  build CODE_SIGNING_ALLOWED=NO                          # unsigned: runs on an on-device store
xcodebuild -scheme Colony -destination 'platform=macOS' \
  -allowProvisioningUpdates build                        # signed: syncs through iCloud
xcodebuild test -scheme Colony -destination 'platform=macOS' \
  -only-testing:ColonyTests CODE_SIGNING_ALLOWED=NO      # 11 unit tests, in-memory store
```

An unsigned build is the quickest way to explore the UI. It saves on the device only, and the
sidebar footer shows *Saved on this device only*.

For iCloud sync, the project uses team `N6883L5366` and container `iCloud.yoavperetz.Colony`. To use
your own, pick your team and bundle ID in **Signing & Capabilities**, swap the iCloud container, and
update `CloudStore.containerIdentifier` to match. The first signed launch can take a minute while
CloudKit provisions the container. Starter content is created once per iCloud account. Pass
`-didSeedStarterContent NO` as a launch argument to create it again.

## Documentation

| | |
| --- | --- |
| [Architecture](docs/ARCHITECTURE.md) | Storage, CloudKit schema rules, Apple services, code layout |
| [Product](docs/PRODUCT.md) | What Colony is for, and the principles behind it |
| [Theming](docs/THEMING.md) | Design tokens and how personalization works |
| [Roadmap](docs/ROADMAP.md) | What's done, what's next, and what's not planned |

## Built with Swift Pieces

Many of Colony's components come from [Swift Pieces](https://swiftpieces.com): glass surfaces,
segmented controls, form fields, task rows, stats, sheets and toasts. They are vendored in
`Colony/SwiftPieces/`, and a small AppKit compatibility shim (`PlatformCompat.swift`) lets them run
on macOS.

## Licence

Not yet chosen. Until a `LICENSE` file is added, all rights are reserved.
