# Droplets

Native extensions for Droppy, written in SwiftUI against **DroppyKit** and
loaded into Droppy's own process. See `../CLAUDE.md` for how droplets relate to
clips.

## What is here

- `droppykit/`: the SDK checkout (git, gitlab.com/droppyformac1/droppykit).
  Its `AGENTS.md` explains what is where in the SDK. **Do not edit it**; fixes
  go upstream.
- `pong/`, `sums/`, `desk-dj/`, `todoist/`, `speedtest/`: droplets, one SwiftPM package each. Every
  package has its own `AGENTS.md` (the brief: the loop, the rules, the surfaces
  table, "done means") and a `CLAUDE.md` that imports it. Work inside the
  package you are changing, and follow its `AGENTS.md`.

## Where the truth is

- Guides: `droppykit/Sources/DroppyKit/Documentation.docc/` (`CreateYourFirstDroplet.md`,
  `DropletSetup.md`, `DesignGuidelines.md`, `ShelfWidgets.md`, `LiveActivities.md`,
  `ExpandedSurfaces.md`, `SettingsPanes.md`, `Icons.md`, `Harness.md`, `HostSupport.md`,
  `Playground.md`, `Submitting.md`, `BuildWithCodingAgents.md`, `AddSPM.md`). The same
  text as getdroppy.app/docs/droppykit.
- Surface protocols: `droppykit/Sources/DroppyKit/Capabilities/`.
- Host services: `droppykit/Sources/DroppyKit/Services/DropletServices.swift`,
  `droppykit/Sources/DroppyKit/Core/DropletHost.swift`.
- Manifest fields: `droppykit/Sources/DroppyKit/Bundle/DropletManifest.swift`.
- Design tokens and settings components: `droppykit/Sources/DroppyKit/DesignSystem/`.
- Example using every surface: `droppykit/Examples/WorldClock/`.
- ABI/API promise and version ledger: `droppykit/COMPATIBILITY.md`.
- Real droplets Droppy ships, as source: `../reference/droplet-store/droplets/`
  (`teleprompter` and `thaw`, about 3,000 lines each: shelf widget + settings pane;
  `sales`, 5,700 lines: also a live activity and a HUD; `dropclip`, 60,000 lines:
  a settings pane around its own engine). The Store's rules for a
  droplet folder (changelog, README, version bump, dependencies, review) are in
  `../reference/droplet-store/CONTRIBUTING.md`: follow them even before publishing.
- Apple's guidance for native feel: the
  [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
  (HIG) and the [developer documentation](https://developer.apple.com/documentation/)
  for SwiftUI and AppKit. `DesignGuidelines.md` decides Droppy's look; the HIG
  decides behaviour, accessibility and system conventions.
- How the finished droplet looks to users: `../docs/droppy-handbook.md`.

## New droplet

```bash
export PATH="$PWD/droppykit/Scripts:$PATH"
droppykit new <id> --name "<Name>"     # run from this folder; creates ./<id>/
cd <id> && droppykit agent             # writes AGENTS.md, CLAUDE.md, .mcp.json for this Mac
```

## The loop (short form; the package's AGENTS.md is the full one)

1. Edit `Sources/<Name>/` and `droplet.json`.
2. `droppykit build` (never a bare `swift build` for the bundle).
3. `droppykit validate`.
4. `droppykit run -- --shots ./shots --report ./shots/report.json`; look at every shot,
   `problems` must be empty.
5. Install into Droppy Playground and confirm it loaded.

With the DroppyKit MCP server from the package's `.mcp.json` these are
`droppykit_build`, `droppykit_validate`, `droppykit_shots`, `droppykit_install`.

## Thunderstorm (Droppy's launcher)

A droplet shows up in Thunderstorm without any code of its own. This is how Todoist,
Calendar and Speedtest get there. There is no Thunderstorm API or surface to declare.
Droppy turns what the droplet already provides into launcher rows (the item kinds are in
`droppykit/Sources/DroppyKit/Services/DropletLauncherService.swift`):

- **The droplet itself** (`kind: .droplet`): its Store page.
- **Every shelf widget** (`kind: .surface`): one row per `ShelfWidgetDescriptor`,
  titled `title` with `systemImage` as its icon. It is found by the title and
  `searchKeywords`, so fill those with the words a user would type, in English.
  Picking the row mounts the same `makeWidgetView` inside the launcher's window, at
  the launcher's width. The launcher presents it as a detail view with a way back,
  and the view takes the keyboard there.
- **The settings pane** (`kind: .setting`): it opens right in the launcher panel,
  and `settingsSearchEntries` make it findable.

So build for the launcher by building a good widget:

- The launcher mounts the widget wider than any solo shelf card (440pt is the
  widest here). Branch on `context.availableSize.width` and give the wide
  composition room for what the shelf hides: the full result, actions with
  labels. Speedtest switches at 500pt (`SpeedtestWidget.launcherWidth`).
- `focusPolicy: .keyboardFocusable` only for a widget whose main control is a text
  field, as on the shelf. A widget without one stays `.none`.
- Mounting must have no side effects: no test starting, no permission prompt. The
  user picks the row and then presses the widget's own button.
- For a start-it-now action without opening the widget, adopt `DropletURLHandling`.
  The user can then put `droppy://droplet/<id>/<path>` behind a Thunderstorm
  quicklink or a hotkey.
- The `launcher` capability and `host.launcher` are not how a droplet gets into
  Thunderstorm. They are for a droplet that draws **its own** launcher and wants
  Droppy's items in it (`Launchers.md`).
- A Raycast-style extension in `../thunderstorm/` is only worth it for a launcher
  command with lists, forms or arguments that a widget cannot be. It runs in
  Thunderstorm's Node runtime and shares no code with the droplet.

Measured on this Mac (Droppy 16.0.2-nightly, 2026-10-27, Speedtest opened from
Thunderstorm): the launcher mounts the widget three times in a row, at 0×0, then
710×209, then 710×217, with `isCompact` false. So the launcher gives about 710pt of
width, well past Speedtest's 500pt switch, and a height of its own that ignores the
descriptor's `contentHeight` (Speedtest declares `.fixed(175)`). Lay the wide
composition out for that height, and ignore a 0×0 pass. With the widget open, the
launcher's search field keeps the keyboard focus. Whether Return reaches the widget's
buttons is still unverified. To read a droplet's `host.log.debug` lines, stream them
while you mount it (`/usr/bin/log stream --level debug --predicate 'process == "Droppy"'`),
because `log show` does not keep debug lines. In zsh, call `/usr/bin/log`: a bare
`log` is a shell builtin and prints nothing.

## Keeping the wiring current

- The SDK checkout is DroppyKit 1.20.1 and every droplet here pins it. `droppykit update`
  (in `droppykit/`, then in each package) moves both to the newest release; `--raise` also
  raises `minAPI` and `Package.swift`'s floor, which only a droplet that uses the new API
  should do.
- After moving this folder or the SDK, run `droppykit agent` in each package: it rewrites
  `.mcp.json`, `.cursor/` and the absolute paths. `--force` also rewrites `AGENTS.md` from the
  template and drops anything added below it, so copy a package's own notes section
  (for example "## Sums notes") out first and append it again.
- Sums is the exception to the build loop: it links SoulverCore and builds with
  `./Scripts/build-droplet.sh`, not `droppykit build` (see its `AGENTS.md`).
