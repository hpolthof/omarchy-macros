# Changelog

## 1.0.0

First release.

- Records every key on every window between an explicit start and stop, and
  replays it, through a root-owned recorder that takes no arguments and a
  sudoers rule that names exactly that binary.
- Playback through a system `ydotoold` that hands the user one socket, rather
  than putting the user in a group where every process they run can read the
  keyboard.
- Takes are named and kept, or thrown away; a saved macro can be renamed,
  given a shortcut, played, or deleted.
- Two replay timings: a fixed 12ms per key, or the pauses that were actually
  recorded with anything over two seconds shortened.
- Playback follows an absolute schedule rather than sleeping between keys, so
  a long macro does not drift by the cost of every `ydotool` it spawns.
- Every modifier is released before a playback starts, so a macro fired from a
  keybinding is not typed with SUPER still held.
- Recording drops autorepeat and ignores the virtual keyboard `ydotool`
  creates, so a playback cannot record itself.
- Macro shortcuts become Hyprland bindings in a generated
  `~/.config/hypr/macros.lua`, loaded by one `pcall(require, ...)` line. Every
  binding in it is guarded on the plugin still existing, so removing the
  plugin removes its keys — Omarchy has no uninstall hook.
- The key that starts and stops a recording is proposed, not bound: a switch
  in the panel binds it, and the chip next to the switch changes it. Stopping
  with that key trims the chord off the tail of the recording, unless the
  macro genuinely ends in those keys.
- Keyboard-first panel: `↑↓` move, `⏎` plays, `r` renames, `k` sets a
  shortcut, `s` switches timing, `⌦` deletes, and the save form takes Tab
  between its two fields.
- A recording stops on its own after ten minutes, and the bar shows a pulsing
  red dot for every second of it.
- `bin/macros-setup` installs the privileged pieces and takes them back out
  again; `bin/macros doctor` reports what is missing and the command that
  fixes it, in the terminal and in the panel.
- IPC on `io.github.hpolthof.macros`, so `open`, `toggleRecording` and
  `play <id>` can be reached from a Hyprland binding or a script.
