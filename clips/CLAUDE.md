# Clips for DropClip

A **clip** is an action on selected text: the user selects text in any app,
DropClip's pill appears beside it, and your action is one of its buttons (or a
row in its searchable palette). See `../CLAUDE.md` for how clips relate to
droplets.

**DropClip** is a droplet (id `dropclip`, 2.2.x) that runs inside Droppy. It is
an MIT-licensed fork of **OpenClip** by Ganesh M, taken before OpenClip moved to
the AGPL, and it loads OpenClip's extension format unchanged: a folder named
`<Name>.openclipext` holding an `openclip.json` manifest plus optional scripts,
icons and a `README.md`. No compilation, no framework.

## Where the truth is

- `docs/manifest-spec.md`: **the** spec. Every manifest key, the action kinds
  (`url`, `javascript`, `applescript`, `shell`, `textsnippet`, `keypress`,
  `shortcut`, `service`, `group`), options and secrets, `requirements` and
  visibility, result delivery (`output`, `toast`, `secondary`, `loading`),
  placeholders and env vars, the `openclip.*` JavaScript bridge, localization,
  JSON effect shapes, worked examples, failure modes, the trust model and a
  "Do NOT" list. Same text as getopenclip.app/docs/manifest-spec. Read it before
  writing a manifest; the decoder ignores keys it does not document.
- `docs/openclip/developer-guide/`: `overview.md`, `package-format.md`,
  `extensions-modules.md` (multi-file `require()`, npm + esbuild bundles,
  TypeScript), `snippets.md`, `integration-api.md`.
- `docs/openclip/runtimes/`: `javascript.md`, `applescript.md`, `zsh-python.md`,
  `url-templates.md`.
- `docs/openclip/architecture/`: how the host loads and runs actions
  (`extensions.md` covers the trust tiers).
- `docs/clip-store-README.md`: the Clip Store's design principles (single
  purpose, under 50 ms for transforms, `async` + `loading` for anything slow,
  privacy by default).
- `examples/`: all ~120 extensions from the Clip Store. Copy the closest one
  rather than starting blank: `WordCount`/`Uppercase` (inline JS),
  `QuickTranslate`/`GoogleTranslate` (network, options), `Droppy` (AppleScript
  + shell, options, localized strings), `Bitly` (secret option + API).
- `../docs/droppy-handbook.md`, section "DropClip": what users see.

## DropClip vs. upstream OpenClip

The spec is written for the standalone OpenClip app. In DropClip:

- Extensions live in **`~/.dropclip/extensions/`**, not `~/.openclip/extensions/`.
  DropClip watches the folder and reloads on change; no relaunch needed.
- Users install from a file: a folder, a `.zip` or a single script. The
  "Import from OpenClip" button copies `~/.openclip` into `~/.dropclip` once.
- Settings and the extension list are DropClip's page in Droppy's Settings;
  shortcuts are on Droppy's Shortcuts page.
- The JS runtime is sandboxed. Some Node modules are refused outright; npm
  libraries must be bundled with esbuild (see `extensions-modules.md`).
- DropClip is a frozen fork of OpenClip at commit `7919d76` (2026-09-23), taken
  before OpenClip relicensed to the AGPL (`b9d19bc`, 2026-09-25); see
  `PROVENANCE.md` in its source. `docs/openclip/` is OpenClip's docs at that same
  commit, so it describes the code DropClip runs. Never copy OpenClip code from
  after `b9d19bc` into anything that ships in Droppy.
- Version gating: DropClip reads `minDropClipVersion`, falling back to
  `minOpenClipVersion`, and compares it with DropClip's own version (2.2.x). A
  clip that needs a DropClip feature declares `minDropClipVersion`; the spec's
  `minOpenClipVersion` values (1.3.0, 1.7.0) are always met in DropClip, and
  `openclip.pasteboard` and native file output are both in DropClip's JS host.
- DropClip's source is public and MIT, in the Droplet Store repository
  (gitlab.com/droppyformac1/droplets, cloned at `../reference/droplet-store/droplets/dropclip/`). The truth for what
  it loads: `Sources/DropClipCore/Extensions/Manifest/ExtensionManifest.swift`,
  `Sources/DropClipCore/Extensions/ExtensionManager.swift` and
  `Sources/DropClip/Platform/Runtimes/DropClipJSHost.swift`.
- Droppy itself needs Accessibility access to read the selection; your clip
  never asks for permissions of its own.

## The loop

```bash
cd clips
./scripts/create.sh MyAction --type js        # js | url | shell | applescript; writes ./MyAction.openclipext
# edit MyAction.openclipext/openclip.json, scripts, README.md
./scripts/validate.sh MyAction.openclipext     # needs jq (brew install jq); no argument validates every clip here
./scripts/install.sh MyAction.openclipext      # validates, then copies into ~/.dropclip/extensions
```

**A new clip is off until you enable it.** A folder copied into
`~/.dropclip/extensions` loads as `seen`: registered, but not in the pill.
DropClip posts a "New Extension" notification; enabling it there (or on the
clip in DropClip's settings) is the user's consent for its scripts to run, so an
agent never clicks it for them. After that, edits to a developer clip hot-reload
without asking again (spec §11).

Then test in Droppy: select text in any app, open the pill (or the palette
shortcut), confirm the action shows up only when it should (spec §5), run it,
and check the result and whether the pill closes. Did it load? Ask the log
(`log` is a zsh builtin, so call `/usr/bin/log`):

```bash
/usr/bin/log show --last 5m --style compact --predicate 'process == "Droppy" AND subsystem == "com.dropclip"'
```

"Loaded extension manifest <identifier>" means it decoded; a rejected manifest
or a dropped action is logged in the same place.

**Unit tests** live outside the package in `tests/` (they would ship
otherwise) and run with `node --test tests/`, with a stand-in for the
`openclip` bridge. Node is V8 and DropClip is JavaScriptCore: run a changed
script once through JavaScriptCore too
(`/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc`).

For an npm/TypeScript clip: `npm install` once, `npm run build` after every
edit (the manifest points at `dist/main.js`), then `install.sh`.

## Rules

- `identifier` is reverse-DNS and unique (`com.<you>.<name>`); bump `version`
  (semver) on every change you ship.
- Declare `output` explicitly on every action that produces a result.
- Declare `requirements` honestly: `input: "optional"` only for actions that
  work with no selection.
- Anything slow or networked: `"async": true` plus `loading` with a message.
- Network from JS goes through `openclip.fetch`; private, loopback and
  link-local addresses are blocked.
- API keys are `secret` options (Keychain), never in the manifest or scripts.
- Every clip ships an end-user `README.md`: what it does, options,
  requirements, examples. No developer setup instructions in it.
- Icons: SF Symbol names or a local SVG/PNG in the package.
- Keep clips in this folder as `<Name>.openclipext/`. `examples/` is a
  read-only snapshot of upstream; do not develop in it.

## Publishing

- **OpenClip Clip Store** (also reaches DropClip users who install from the
  store): open a pull request adding the folder under `raw/` in
  github.com/ganeshmshetty/openclip-extensions. Merging publishes it; their CI
  validates and packages it.
- **Directly**: zip the `.openclipext` folder and share it; users install it
  from a file in DropClip's settings.
