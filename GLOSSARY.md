# Glossary

**Terminal**
A program running in herdr-core, kept alive on its own and known by its address (`t2q`). What the plugin lists and attaches to.
_Avoid_: pane (for this thing)

**Program**
What a Terminal is running right now (`zsh`, `nvim`, `claude`), by its command name: the name an Agent reports for itself, else the program in the foreground, else the program the Terminal was started with. A Terminal's icon follows its Program.

**Agent**
A Terminal that reports an agent status, or whose Program is a known AI coding CLI (`claude`, `codex`, `opencode`, `agy`). Listed under Agents; every other Terminal, an unknown program included, is listed under Terminals.
_Avoid_: agent pane

**Space**
A named piece of work in the Herdr desktop app, holding Tabs. A Terminal belongs to at most one Space.

**Tab**
One view inside a Space, showing one or more Terminals.

**Split**
A Tern pane the plugin opens to show a Terminal, beside the focused one.
_Avoid_: pane (ambiguous between Tern, Herdr and herdr-core)
