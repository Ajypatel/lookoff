# LookOff

Native macOS menu-bar app that reminds you to look off the screen.

Short and long breaks, smart pause during meetings or video, posture and blink nudges, daily stats, and a Tahoe liquid-glass status panel. Runs as a menu extra — no Dock icon unless Settings is open.

Requires **macOS 14+**. Built with Swift 6.

## Features

- Screen breaks with a full-screen overlay, heads-up warning, and optional lock
- Smart pause for idle, video playback, meetings, office hours, and Focus filters
- Wellness reminders (posture / blink) as liquid-glass orbs
- Today stats: screen time, breaks taken or skipped, app usage, Screen Score
- Menu-bar panel: Now / Stats, start or postpone a break, current focus time
- Sounds, global shortcuts, planned breaks, break-start/end automations
- AppleScript dictionary (`LookOff.sdef`)
- Optional Accessibility, Calendar, and Focus Status — core schedule works with none of them

## Build

Xcode 16+ (macOS 26 SDK is fine). Ad-hoc signed for local use.

```bash
make install
```

That builds Release, copies `LookOff.app` to `/Applications`, and launches it. Or:

```bash
make build
open build/Build/Products/Release/LookOff.app
```

`make open` opens the Xcode project.

## Permissions

LookOff does not ask for TCC at launch.

| Permission | Used for |
| --- | --- |
| Accessibility | Global hotkeys; postpone while typing or dragging |
| Calendar | Pause during events you enable |
| Focus Status | Pause when a Focus filter is on |

Idle pause uses HID idle time and does not need Accessibility.

## License

[MIT](LICENSE)

Not affiliated with LookAway or other commercial break timers.
