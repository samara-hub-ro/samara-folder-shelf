# Changelog

All notable changes to this plugin are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The version in `manifest.json` is the source of truth and matches the git tag
for each release.

## [Unreleased]

## [1.0.0] — 2026-09-08

First release.

### Added

- A shelf of favourite folders that lives on the desktop, under your windows,
  and lifts above them from the bar icon or a keybinding.
- Move it anywhere and resize it by dragging; the position, the size and the
  monitor are remembered.
- A preview on hover: image thumbnails, the most recently changed entries,
  total size, entry counts, last change, a breakdown by file type, and the
  folder's owner and permissions.
- Double click opens a folder in whatever file manager the desktop is set to
  use; middle click drops a terminal into it; right click renames it, copies
  its path, or takes it off the shelf.
- Add folders with the built-in picker, by dropping them in from a file
  manager, or from the XDG folders the shelf offers on first run.
- Grid and list layouts, reordering by dragging, and a filter for shelves that
  have grown.
- **Show on every monitor**, off by default: one shelf per screen, sharing the
  same folders and position, with hover previews and menus local to the screen
  being pointed at. Workspaces never needed an option — a layer-shell surface
  belongs to an output rather than a workspace, so the shelf was always on all
  of them.

### Security

- The scanner reads `find` output as NUL-terminated records and strips control
  characters from every name before printing one. A file name may contain a
  newline, and with newline-delimited records that is an injection: a file
  called `$'x\nSTAT\tdrwxrwxrwx|root|root|0'` forged a record, and the preview
  showed somebody else's numbers — a wrong size, a wrong owner, a folder
  claimed to be world-writable when it was not. Nothing reached a shell, so
  this was never code execution; it was the card lying about the folder, on
  the say-so of whoever could drop a file into it.
- Labels read from the shelf file are stripped of control characters, so a
  hand-edited or pasted name cannot change the height of a tile.
