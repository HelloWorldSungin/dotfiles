# Vim from zero (for VS Code refugees)

You know vim *keys* from the VS Code plugin; this is about living in the
real editor. Two things are new: **nothing else exists** (no menus, no
mouse-first UI), and **the editor has modes**.

Best first step: run `:Tutor` inside nvim. It's a built-in 20-minute
interactive lesson and worth more than any cheat sheet. This file is the
reference for afterwards.

## Modes - the core idea

The same keys mean different things depending on mode. You are always in
exactly one:

| Mode | You get there by | What keys do |
|------|------------------|--------------|
| **Normal** | `Esc` (from anywhere) | keys are commands (navigate, delete, copy) |
| **Insert** | `i` `a` `o` | keys type text, like a normal editor |
| **Visual** | `v` (chars) `V` (lines) | keys extend a selection |
| **Command** | `:` | type a command at the bottom, Enter runs it |

Golden rule: **when confused, press `Esc`** - you're back in Normal mode,
the home state. (In this config Esc also saves the file. Spam it freely.)

## Survival: open, edit, save, quit

```
nvim file.txt     open a file
i                 start typing (insert before cursor)
Esc               stop typing, back to Normal (and save, in this config)
:w                save   |  :q  quit  |  :wq  save+quit  |  :q!  quit, discard
```

If you're ever trapped in a weird state: `Esc` `Esc` `:q!` `Enter`.

## Moving (Normal mode)

| Keys | Moves |
|------|-------|
| `h j k l` | left / down / up / right (arrows also work; wean off later) |
| `w` / `b` | next / previous word |
| `0` / `$` | start / end of line |
| `gg` / `G` | top / bottom of file |
| `42G` or `:42` | line 42 |
| `5j` `12k` | 5 down, 12 up - read the count off the relative line numbers |
| `Ctrl-d` / `Ctrl-u` | half-page down / up |
| `/text` then `Enter` | search; `n` next match, `N` previous |

## Editing (Normal mode - this is where vim pays off)

Commands are **verb + object**: `d`elete, `c`hange (delete then insert),
`y`ank (copy) - combined with what to act on:

| Keys | Does |
|------|------|
| `x` | delete character |
| `dd` / `yy` | delete / copy whole line |
| `dw` / `cw` | delete / change to end of word |
| `diw` / `ciw` | delete / change the word under cursor (any position) |
| `ci"` / `ci(` | change inside the quotes / parens - magic for strings & args |
| `p` / `P` | paste after / before cursor |
| `u` / `Ctrl-r` | undo / redo (persistent across restarts in this config) |
| `.` | repeat the last change - massively useful |
| `>>` / `<<` | indent / outdent line |

Insert-mode entries: `i` before cursor, `a` after, `A` end of line,
`o` new line below, `O` new line above.

## Visual mode (when you want to see the selection)

`v` then move to select, then hit a verb: `d` delete, `y` copy, `>` indent.
`V` selects whole lines. In this config, pasting over a selection with `p`
does NOT clobber your clipboard (normally it does - it's patched in
`keys.lua`).

## Splits and buffers

| Keys | Does |
|------|------|
| `:vsp` / `:sp` | vertical / horizontal split |
| `Ctrl-w` then `h/j/k/l` | jump between splits |
| `Ctrl-w q` | close this split |
| `space b` | picker: jump between open files ("buffers") |

Typical layout while reviewing an agent's work: `space g` (neogit) in one
split, the code in another.

## The learning path

1. `:Tutor` once or twice (seriously).
2. Use only: modes, `hjkl`, `w b`, `i a o`, `dd yy p`, `u`, `/search`,
   `:wq`. That's a complete, working editor.
3. Add `ciw`, `ci"`, `.`, counts (`5j`), `f`+char as they feel needed.
4. The plugin layer (`space f`, `space s`, `space g`, `space e`) is in
   [nvim.md](nvim.md) - it removes most reasons to touch the file tree.

Expect ~3 slow days, then parity with VS Code, then it keeps getting
faster for years. Everyone goes through the same curve.
