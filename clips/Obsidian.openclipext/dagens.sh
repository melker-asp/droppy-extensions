#!/bin/zsh
# Till dagens anteckning: the selection arrives on stdin, lib/obsidian.js does the work and prints the toast JSON.
# DropClip gives script actions no option values, so the vault is the one open in Obsidian.
dir=${0:A:h}
text=$(cat)
export OBSIDIAN_CLIP_TEXT=$text
exec /usr/bin/osascript -l JavaScript "$dir/lib/obsidian.js" dagens
