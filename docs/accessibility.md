---
title: Accessibility
permalink: /accessibility/
---

# Accessibility Statement

[עברית](he/)

**Last reviewed 29 September 2026 · Colony 1.0**

I want Colony to be usable by everyone, including people who use assistive technology. Colony is
built with Apple's native frameworks so that the accessibility features built into iPhone, iPad, Mac
and Apple Vision Pro work with it.

## Standard

Colony aims to meet the **Web Content Accessibility Guidelines (WCAG) 2.1, Level AA**, as applied to
native apps. That is the level used by the Israeli standard **SI 5568** and the European standard
**EN 301 549**.

## Supported features

| Feature | Status | Notes |
|---|---|---|
| **VoiceOver** | Supported | Every button, field and menu on every screen has a spoken name. Tested on all screens, dialogs and the command palette. |
| **Voice Control** | Supported | Controls can be activated by their visible or spoken names. |
| **Larger Text** (Dynamic Type) | Supported on iPhone, iPad and Apple Vision Pro | Text follows the system text size, including the largest accessibility sizes. Rows grow instead of clipping, and the sidebar widens. Sidebar and toolbar labels stop growing at a size that keeps them usable. Your own content keeps growing. |
| **Dark Mode** | Supported | Light, dark, or follow the system. |
| **Increase Contrast** | Supported | Secondary text, hints and borders become darker (or lighter in dark mode). |
| **Sufficient contrast** | Supported | Primary and secondary text meet the 4.5:1 AA ratio in light and dark mode. With Increase Contrast, all text does, and control borders meet 3:1. These ratios are checked by automated tests. |
| **Reduce Motion** | Supported | Sliding, springing and resizing animations are replaced by instant changes or a short fade. |
| **Keyboard** (Mac) | Supported | Command palette (⌘K), new task (⌘N), new project (⇧⌘N), toggle sidebar (⌃⌘S), arrow keys and Return in lists and pickers, Esc to close any dialog. |
| **Colour independence** | Supported | Priority, status and deal stage are shown with text, not colour alone. |

## Known limitations

I'm working on these:

- **Minor text below AA contrast.** Timestamps, keyboard-shortcut hints and placeholder text are
  lighter than 4.5:1 in the standard appearance (about 2.5:1 to 3:1). Turn on **Increase Contrast** to
  raise them to AA:
  - **iPhone or iPad:** Settings › Accessibility › Display & Text Size.
  - **Mac:** System Settings › Accessibility › Display.
- **Drag and drop.** Reordering the sidebar and moving deals between pipeline stages is done by
  dragging. Keyboard and VoiceOver alternatives are available: the **Move to…** menu for sidebar
  items and the **Stage** picker on each contact. Reordering projects with the keyboard alone is not
  yet available.
- **Mac text size.** macOS has no system-wide Dynamic Type, so Colony on Mac uses fixed sizes.
  The custom fonts you pick in Settings › Appearance don't change size.

## Feedback and contact

If you run into an accessibility barrier in Colony, please tell me. I'll reply within
**5 business days** and aim to fix barriers in the next release.

- **Accessibility coordinator:** Yoav Peretz
- **Email:** [realyoavperetz@gmail.com](mailto:realyoavperetz@gmail.com)
- **GitHub:** [open an issue](https://github.com/MasterYoav/colony/issues)

Please describe what you were trying to do, the device, and any assistive technology you use.

## How this was tested

- Automated checks: contrast-ratio tests for every text colour on every surface, in light, dark and
  Increase Contrast.
- Manual testing:
  - VoiceOver names checked on macOS across all screens, dialogs and the command palette.
  - Larger Text checked on the iPad simulator from the default size to the largest accessibility size.
  - Reduce Motion checked on macOS.
