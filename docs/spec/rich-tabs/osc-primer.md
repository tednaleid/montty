# OSC Escape Sequences Primer

## What are OSC sequences?

OSC (Operating System Command) escape sequences are a mechanism for programs running inside a terminal to communicate metadata back to the terminal emulator. They're part of the ANSI escape code standard, using the format:

```
ESC ] <code> ; <data> ST
```

Where `ESC ]` starts the sequence, `<code>` identifies the command, `<data>` is the payload, and `ST` (String Terminator, `ESC \` or `BEL`) ends it. The shell or application writes these bytes to stdout, and the terminal emulator intercepts and processes them instead of displaying them.

## Common OSC codes

| Code | Name | Purpose | Example |
|------|------|---------|---------|
| 0 | Set title | Set window/tab title | `\e]0;my title\a` |
| 1 | Set icon name | Set icon title (legacy) | `\e]1;icon\a` |
| 2 | Set window title | Same as 0 in most terminals | `\e]2;title\a` |
| 7 | Set working directory | Report current directory as URI | `\e]7;file:///Users/ted/project\a` |
| 9 | Desktop notification | Trigger a system notification | `\e]9;Build done\a` |
| 133 | Semantic prompts | Mark prompt/command/output regions | `\e]133;A\a` (prompt start) |
| 1337 | iTerm2 custom | Arbitrary user variables, images | `\e]1337;SetUserVar=key=base64value\a` |

## How Ghostty uses OSC

Ghostty's shell integration scripts (installed automatically for zsh/bash/fish) emit OSC sequences at key points:

- **On every prompt** (`precmd`): OSC 7 reports the current working directory
- **On every command** (`preexec`): OSC 0 sets the title to the running command (when `title` feature is enabled)
- **Prompt boundaries**: OSC 133 marks where prompts and command output begin/end

These flow through GhosttyKit and surface as Swift actions:
- `GHOSTTY_ACTION_SET_TITLE` -> `surfaceView.title`
- `GHOSTTY_ACTION_PWD` -> `surfaceView.pwd`

## What montty can use today

| Data | Source | Shell config needed? |
|------|--------|---------------------|
| Working directory | OSC 7 via `surfaceView.pwd` | No (Ghostty shell integration) |
| Terminal title | OSC 0 via `surfaceView.title` | No |
| Command finished | OSC 133 via `GHOSTTY_ACTION_COMMAND_FINISHED` | No |

## What requires extra work

| Data | Approach | Notes |
|------|----------|-------|
| Git branch/repo | Walk up from pwd to find `.git`, read HEAD | No shell config, filesystem read |
| Custom user vars | Would need OSC 1337 SetUserVar | Ghostty doesn't support this |
| Foreground process | Would need PTY fd access | GhosttyKit doesn't expose this |
| Process environment | Cannot read directly | Shell must report via OSC |

## Shell integration example

A user wanting to report custom metadata to montty could add to their `.zshrc`:

```zsh
# Report a custom variable via OSC 0 title (workaround until OSC 1337 is supported)
precmd() {
    # Set title to include git branch for montty to parse
    local branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [[ -n $branch ]]; then
        printf '\e]0;%s [%s]\a' "${PWD##*/}" "$branch"
    fi
}
```

However, montty's approach is to auto-derive git info from the working directory, requiring zero shell configuration.

## References

- [ECMA-48 (ANSI escape codes)](https://www.ecma-international.org/publications-and-standards/standards/ecma-48/)
- [Ghostty VT Reference](https://ghostty.org/docs/vt/reference)
- [iTerm2 Proprietary Escape Codes](https://iterm2.com/documentation-escape-codes.html)
- [WezTerm Shell Integration](https://wezterm.org/shell-integration.html)
- [Kitty Shell Integration](https://sw.kovidgoyal.net/kitty/shell-integration/)
- [FinalTerm Semantic Prompts (OSC 133)](https://gitlab.freedesktop.org/Per_Bothner/specifications/blob/master/proposals/semantic-prompts.md)
- [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)
