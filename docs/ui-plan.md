# UI Plan

The first GUI should be a native SwiftUI app that wraps `CP2077ArchiveCore`. The goal is a double-clickable app distributed from GitHub Releases as a signed and eventually notarized `.dmg`.

## Principles

- Native macOS controls and file pickers.
- No hardcoded user paths.
- Detect common Steam/GOG installs automatically.
- Make the patch strategy visible before applying.
- Prefer hybrid patching by default.
- Treat aggressive patching as a warning-level operation.
- Always offer backup and restore from the same screen.

## Main Window

### Header

Shows detected game install:

```text
Cyberpunk 2077
/Users/.../Steam/steamapps/common/Cyberpunk 2077
```

Controls:

- `Auto-detect`
- `Choose Game Folder...`
- status pill: `Verified`, `Needs attention`, or `Not found`

### Mod Drop Zone

Large drag-and-drop area:

```text
Drop PC .archive mods here
```

Accepted:

- `.archive`

Rejected with banner:

- `.reds`
- `.dll`
- `.asi`
- `.yaml`
- `.xl`
- REDmod layouts
- CET/redscript/ArchiveXL/TweakXL indicators

### Mod List

Table columns:

- Enabled checkbox
- Mod name
- Records
- Existing overrides
- New resources
- Strategy
- Status

Strategy labels:

- `Plugin method`: all records are new/missing and can be installed as a loose `basegame_99_*.archive`
- `Hybrid method`: some records patch official archives, some install loose
- `Aggressive method`: requires patching a whole mod into a selected official archive

### Warning Banner

Displayed for hybrid/aggressive:

```text
This mod changes records that already exist in the native Mac game archives.
The patcher will back up the affected archives before writing.
```

For aggressive:

```text
Aggressive mode rewrites more of an official game archive and is a fallback option.
Use it only when hybrid mode does not work.
```

Controls:

- `Create Backup` checkbox, on and locked for official archive patching
- `Open Backup Folder`

### Patch Button

Bottom-right primary button:

```text
Patch Enabled Mods
```

Disabled until:

- game path is valid
- at least one supported archive-only mod is enabled
- backup location is writable

### Progress

Progress phases:

1. Scanning mods
2. Finding matching Mac archives
3. Creating backups
4. Installing loose plugin archives
5. Patching official archives
6. Verifying CRC and alignment
7. Writing manifest

Use a determinate progress bar when operation counts are known. Show current archive filename under the bar.

### Completion Dialog

Success:

```text
Patch complete.
Official archives changed: 3
Loose plugin archives installed: 2
Backups created: 3
```

Buttons:

- `Launch Game`
- `Open Backup Folder`
- `Done`

Failure:

- show failed phase
- show archive name
- offer `Restore backups created during this run`

## Restore Screen

List backup sets:

- date
- affected archives
- source mods
- strategy

Actions:

- `Restore Selected`
- `Restore Latest`
- `Reveal in Finder`

## Distribution

Short term:

- GitHub Release zip containing `CP2077 Mac Archive Patcher.app`
- ad-hoc signed for local testing

Release quality:

- Developer ID signing
- notarized `.dmg`
- hardened runtime

The app should never require users to install Swift, Xcode, Homebrew, Node, or command-line tools.

