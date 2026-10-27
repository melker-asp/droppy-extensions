# Droppy extensions workspace

This folder is where extensions for **Droppy** (the Dynamic Island, shelf and
launcher for Mac, getdroppy.app) are built. Droppy has two extension systems here,
one per folder. Each folder has its own `AGENTS.md` with the full loop and
rules; this file is the map and the rules they share.

| Folder | What you build | Runs in | Language | Format |
| --- | --- | --- | --- | --- |
| `droplets/` | **Droplets**: native features on the notch, shelf, lock screen, HUD, menu bar and in Settings | Droppy's own process, via DroppyKit | Swift / SwiftUI | `<Name>.droplet` bundle built from a SwiftPM package + `droplet.json` |
| `clips/` | **Clips**: actions on selected text, shown in DropClip's pill | DropClip (a droplet; MIT fork of OpenClip) | JSON manifest + JS / shell / AppleScript / URL templates | `<Name>.openclipext` folder with `openclip.json` |

DropClip is itself a droplet. Droppy reuses an existing ecosystem for it
instead of inventing a new format, so the upstream OpenClip docs apply, with the
Droppy-specific differences listed in the folder's `AGENTS.md`.

## Which one to build

- Something that **lives on a Droppy surface** (a shelf widget, a live
  activity, a HUD, the lock screen, a full notch takeover, a menu bar item, or
  a settings page): a **droplet**.
- Something that **acts on the text the user has selected** (transform, look
  up, send somewhere): a **clip**. Smallest of the two: often one JSON file.
- Something that should **also be reachable from Thunderstorm**: still a droplet.
  Its shelf widgets and settings show up in the launcher on their own (see
  `droplets/CLAUDE.md`, Thunderstorm). Build a `thunderstorm/` extension only for
  a launcher command with its own lists, forms or arguments.

## Layout

```
AGENTS.md                        this file
docs/droppy-handbook.md          Droppy's user handbook (getdroppy.app/docs/handbook), what users see
droplets/
  AGENTS.md                      droplet loop, where the SDK docs are
  droppykit/                     the DroppyKit SDK checkout (git, gitlab.com/droppyformac1/droppykit); do not edit
  <droplet>/                     one SwiftPM package per droplet, each with its own AGENTS.md/CLAUDE.md
clips/
  AGENTS.md                      DropClip loop and differences from OpenClip
  docs/manifest-spec.md          the openclip.json spec, every key and runtime contract
  docs/openclip/                 OpenClip's developer guide, runtimes, architecture, user guide
  scripts/                       create.sh, validate.sh, install.sh (adapted for DropClip)
  examples/                      every extension in the OpenClip Clip Store, as reference
  <Name>.openclipext/            your clips, one folder each
reference/
  droplet-store/                 git clone of gitlab.com/droppyformac1/droplets: Droppy's own droplets
                                 (dropclip, sales, teleprompter, thaw) and the Store's CONTRIBUTING.md; read only
```

## Where Droppy keeps things on this Mac

- Installed droplets: `~/Library/Application Support/Droppy/Droplets/<id>/<Name>.droplet`
  (Droppy Playground: `~/Library/Application Support/Droppy Playground/Droplets/`).
- DropClip extensions: `~/.dropclip/extensions/<Name>.openclipext` (watched, hot reload).
- Droppy itself: `/Applications/Droppy.app` (16.0.2-nightly at the time of writing).
- Node.js: Homebrew's (`/opt/homebrew/bin/node`, Node 26, npm 11) for npm-based clips.

## Shared rules

- **Read the docs on disk before guessing an API.** Each folder lists where its
  truth is. Droppy-specific behaviour beats the upstream docs when they disagree,
  and what the installed Droppy actually does beats both: verify by running.
- **Vendored docs are snapshots; do not edit them.** `reference/`, `docs/`, `clips/docs/`
  and `clips/examples/` are copies of upstream (see Sources below). Notes of our own go in the `AGENTS.md` files, not in the copies.
- **Look like Droppy.** Dark surfaces, sentence case, no ALL-CAPS labels, no
  borders or gradients of your own, short summaries. Text written for users
  (summaries, toasts, README) follows the handbook's voice: plain, concrete,
  second person.
- **Feel native.** Droppy is a Mac app, so what you build should feel like
  one. Before designing a surface, check Apple's guidance and follow it unless
  Droppy's own `DesignGuidelines.md` says otherwise (Droppy wins on look, Apple
  wins on behaviour):
  - [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
    (HIG): layout, typography, color, motion, SF Symbols, accessibility, and
    the macOS pages for menus, keyboard, windows and pointer.
  - [Apple developer documentation](https://developer.apple.com/documentation/)
    for the frameworks you use: SwiftUI, AppKit, and anything system-level.
  - In practice: system fonts and text styles, semantic colors (they adapt to
    light/dark and Increase Contrast), SF Symbols, standard controls before
    custom ones, keyboard and VoiceOver support, Reduce Motion respected, and
    system animations and timings.
- **Ask for the least.** Declare only the capabilities, permissions,
  `requirements` or preferences the code uses. Users see the list. Never send
  the user's selection, clipboard or files anywhere the action does not need.
- **Done means tested in Droppy.** A build or a valid manifest is not the end:
  install it into Droppy (or Droppy Playground for droplets) and confirm it
  loads and works.
- **No secrets in the repo.** API keys go in a clip's `secret` option, never in source.

## Sources and refreshing the docs

Snapshots taken 2026-10-08:

| Copy | Upstream | Commit |
| --- | --- | --- |
| `clips/docs/manifest-spec.md`, `clip-store-README.md`, `clips/scripts/`, `clips/examples/` | github.com/ganeshmshetty/openclip-extensions (`AGENTS.md`, `README.md`, `scripts/`, `raw/`); also www.getopenclip.app/docs/manifest-spec | `8b7b534` |
| `clips/docs/openclip/` | github.com/ganeshmshetty/openclip (`docs/`) at DropClip's fork point, the last MIT commit; do not refresh past it | `7919d76` |
| `docs/droppy-handbook.md` | getdroppy.app/docs/handbook, converted from HTML | — |
| DroppyKit guides | `droplets/droppykit/Sources/DroppyKit/Documentation.docc/` (git checkout, `droppykit update`), published as getdroppy.app/docs/droppykit | tag `v1.20.1` |

`reference/droplet-store` is a git clone: `git -C reference/droplet-store pull`.
To refresh the rest: clone the upstream again and replace the copy wholesale. The three
scripts in `clips/scripts/` were adapted (paths), so diff before replacing them.
