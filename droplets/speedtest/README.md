# Speedtest

A Droplet for [Droppy](https://getdroppy.app), built with
[DroppyKit](https://getdroppy.app/docs/droppykit).

## Using it

- Install Ookla's Speedtest CLI with Homebrew:
  `brew tap teamookla/speedtest && brew install speedtest`.
  Speedtest's settings have the command to copy.
- The first time you run a test, accept Ookla's license and privacy policy, from the
  widget or in Speedtest's settings. Speedtest passes your answer on to the CLI.
- Press play on the Speedtest widget. Download and upload speed show beside the notch
  while the test runs; the widget keeps the full result.
- Without the CLI, Speedtest measures with Apple's network test (`networkQuality`,
  built into macOS) and labels the result as Apple's. You can turn that off in its settings.
- To start a test from Thunderstorm, add a quicklink to `droppy://droplet/speedtest/run`.
  `droppy://droplet/speedtest/stop` stops it.

## Developing

```bash
droppykit run        # open it in Droppy's Settings panel
droppykit build      # produce Speedtest.droplet
droppykit validate   # the checks the Store repository runs
droppykit submit     # open the merge request that puts it in the Store
```

## With a coding agent

Open this folder in Claude Code, Codex or Cursor. `AGENTS.md` is the brief
they read first, and `.mcp.json` / `.cursor/mcp.json` connect the DroppyKit
MCP server, which gives them the build, the checks, pictures of every surface
and an install into Droppy Playground as tools. Codex registers the server
once per Mac: `codex mcp add droppykit -- path/to/droppykit/Scripts/droppykit mcp`.
Run `droppykit agent` again after moving this folder or the SDK checkout.

## Before submitting

- Leave `Speedtest.icon` as it is. It is a placeholder for the harness:
  Jordy designs every Store droplet's icon, and `droppykit submit` leaves it
  out. Have an idea for yours? Put it in the merge request's Icon concept
  section.
- Replace `Assets/Creator.png` with your own square, unrounded mark.
- Fill in `summary`, `description` and `creator` in `droplet.json`, and
  write `CHANGELOG.md`.
- `droppykit submit`: the Store is a repository, one folder per droplet, and
  this opens the merge request that adds yours. See
  [Submitting](https://getdroppy.app/docs/droppykit/submitting).
