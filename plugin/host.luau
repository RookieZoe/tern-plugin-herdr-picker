--!strict
-- Herdr Picker, host half: one block, `herdr-picker.herdr`, drawn with Tern's
-- picker sheet. It runs in the session daemon of the host its panes belong
-- to, so `hc` and the folders it browses are that host's (a remote host's
-- panes, a phone's view of the Mac).
--
-- Modes, chosen by the launch arg `mode=<…>` (none: home):
--   home   pick one of the three below
--   pick   herdr-core terminals, All / Agents / Terminals, opened in a split
--   space  a folder browser; starts a shell there as a new herdr space
--   tab    the herdr spaces with a live terminal; adds a tab to one
--
-- The block opens the chosen pane by splitting itself and then closing, so
-- the pane takes the block's place. `target=<pane>` splits that pane
-- instead (for a block shown in no split, such as a glimpse).
--
-- Splits open through the `tern` CLI (`tern split … -- hc attach <addr>`);
-- when that CLI can't be found or fails, through the window half's
-- `tern-herdr-picker:` link route.

local TIMEOUT_MS = 8000
local WINDOWS = tern.runtime.os == "windows"
local HOME = tern.getenv("HOME") or tern.getenv("USERPROFILE") or ""

-- Programs that mean "a plain terminal"; any other foreground program is an
-- agent CLI.
local SHELLS: { [string]: boolean } = {
	sh = true, bash = true, zsh = true, fish = true, dash = true, ksh = true,
	csh = true, tcsh = true, nu = true, xonsh = true, elvish = true,
	pwsh = true, powershell = true, cmd = true, login = true,
}

-- Tern's provider logos for well-known agents.
local PROVIDER: { [string]: string } = {
	["claude-code"] = "anthropic", claude = "anthropic",
	codex = "openai", gemini = "google", copilot = "github",
	cursor = "cursor", ["cursor-agent"] = "cursor",
}

local STATUS: { [string]: { text: string, tone: string } } = {
	working = { text = "working", tone = "info" },
	blocked = { text = "needs input", tone = "warning" },
	done = { text = "done", tone = "success" },
	idle = { text = "idle", tone = "muted" },
	error = { text = "error", tone = "error" },
}

-- `printf` marks the pane idle (OSC 7501) so closing the split doesn't ask
-- whether to end a running program; then `hc attach` takes the pane over.
local IDLE_ATTACH = [[printf '\033]7501;state=idle\007'; exec "$0" attach "$1"]]

type Pane = {
	address: string,
	space_id: string?, -- herdr.space label; nil outside any space
	space: string, -- the space's name, from `where`
	tab: string,
	where: string,
	program: string,
	agent: boolean,
	status: string?,
	cwd: string,
	index: number, -- position in hc's order
}

type Space = { id: string, name: string, cwd: string, tabs: number }

type State = {
	mode: string,
	entry: string, -- the mode the block opened in; Esc there closes it
	query: string,
	sel: number,
	view: string, -- pick: "all" | "agents" | "terminals"
	loading: boolean,
	err: string?,
	panes: { Pane },
	dir: string, -- space: the folder being browsed
	subdirs: { string },
	target: string,
	attached: { [string]: number }, -- address → the Tern block running `hc attach` on it
	collapsed: { [string]: boolean }, -- pick: space groups folded shut
	busy: boolean,
	cx: BlockCx,
}

-- A row of the sheet: what the picker node draws, plus what activating it does.
type Row = {
	id: string,
	item: { [string]: any },
}

---------------------------------------------------------------------------
-- Small helpers

local function log(...: any)
	tern.log.warn("herdr-picker:", ...)
end

local function first_line(s: string): string
	return string.match(s, "[^\r\n]+") or s
end

local function trim(s: string): string
	return string.match(s, "^%s*(.-)%s*$") or s
end

local function exists(path: string): boolean
	local ok, yes = pcall(tern.fs.exists, path)
	return ok and yes
end

local function first_existing(paths: { string }): string?
	for _, p in paths do
		if p ~= "" and exists(p) then
			return p
		end
	end
	return nil
end

-- The daemon's PATH is the system default (no ~/.local/bin, no Homebrew), and
-- a bare name that isn't found raises, so look in the usual places.
local function hc_bin(): string?
	local override = tern.getenv("HC_BIN")
	if override and override ~= "" then
		return override
	end
	local lad = tern.getenv("LOCALAPPDATA") or ""
	local found = first_existing({
		HOME .. "/.local/bin/hc",
		"/opt/homebrew/bin/hc",
		"/usr/local/bin/hc",
		if lad ~= "" then lad .. "/Programs/herdr-core/hc.exe" else "",
		if lad ~= "" then lad .. "/Programs/herdr-app/hc.exe" else "",
	})
	if found then
		return found
	end
	return if WINDOWS then "hc" else nil
end

local function tern_bin(): string?
	local override = tern.getenv("TERN_EXE")
	if override and override ~= "" then
		return override
	end
	local lad = tern.getenv("LOCALAPPDATA") or ""
	return first_existing({
		"/Applications/Tern.app/Contents/MacOS/tern",
		HOME .. "/Applications/Tern.app/Contents/MacOS/tern",
		HOME .. "/.local/bin/tern",
		"/usr/local/bin/tern",
		"/usr/bin/tern",
		if lad ~= "" then lad .. "/Programs/Tern/tern.exe" else "",
	})
end

-- "/Users/me/x" → "~/x".
local function short_path(p: string): string
	if HOME == "" then
		return p
	end
	local head = string.sub(p, 1, #HOME)
	local same = if WINDOWS then string.lower(head) == string.lower(HOME) else head == HOME
	if same then
		local rest = string.sub(p, #HOME + 1)
		if rest == "" or string.match(rest, "^[/\\]") then
			return "~" .. rest
		end
	end
	return p
end

local function expand_home(p: string): string
	if string.sub(p, 1, 1) ~= "~" then
		return p
	end
	local rest = string.sub(p, 2)
	if rest ~= "" and not string.match(rest, "^[/\\]") then
		return p
	end
	return if HOME ~= "" then HOME .. rest else p
end

local function is_dir(path: string): boolean
	return (pcall(tern.fs.list, path))
end

local function join(dir: string, name: string): string
	if string.match(dir, "[/\\]$") then
		return dir .. name
	end
	return dir .. "/" .. name
end

-- "/a/b" → "/a", "/a" → "/", "C:\a" → "C:\"; nil at a root.
local function parent(dir: string): string?
	local trimmed = string.gsub(dir, "[/\\]+$", "")
	local head = string.match(trimmed, "^(.*[/\\])[^/\\]+$")
	if not head then
		return nil
	end
	if head == "/" or string.match(head, "^%a:[/\\]$") then
		return head
	end
	return (string.gsub(head, "[/\\]+$", ""))
end

local function program_name(raw: string): string
	local base = string.match(raw, "([^/\\]+)$") or raw
	base = string.gsub(base, "%.[eE][xX][eE]$", "")
	return string.lower(base)
end

-- UTF-16 offset of byte position `i` in `s`, as the picker's hits count.
local function u16(s: string, i: number): number
	local n = 0
	local ok = pcall(function()
		for _, c in utf8.codes(string.sub(s, 1, i - 1)) do
			n += if c > 0xFFFF then 2 else 1
		end
	end)
	return if ok then n else i - 1
end

local function matches(query: string, ...: string): boolean
	if query == "" then
		return true
	end
	local q = string.lower(query)
	for i = 1, select("#", ...) do
		local s = select(i, ...)
		if string.find(string.lower(s), q, 1, true) then
			return true
		end
	end
	return false
end

-- Marks `query` in `label` for the picker (bold hits).
local function hits(label: string, query: string): { { number } }?
	if query == "" then
		return nil
	end
	local a, b = string.find(string.lower(label), string.lower(query), 1, true)
	if not a then
		return nil
	end
	return { { u16(label, a), u16(label, (b :: number) + 1) } }
end

local function urlencode(s: string): string
	return (string.gsub(s, "[^%w%-%._~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

---------------------------------------------------------------------------
-- Processes

-- Runs argv; `cb(ok, stdout, err)` gets the first line of stderr (or stdout)
-- as `err` on a failure, a spawn failure included.
-- `pane`, when given, is passed as TERN_PANE so the `tern` CLI works on the
-- window showing that pane.
local function run(argv: { string }, stdin: string?, cb: (ok: boolean, out: string, err: string) -> (), pane: string?)
	local env: { [string]: string } = { NO_COLOR = "1" }
	if pane then
		env.TERN_PANE = pane
	end
	local ok, spawn_err = pcall(tern.process.run, argv,
		{ timeout_ms = TIMEOUT_MS, env = env, stdin = stdin },
		function(r: ProcessResult)
			if r.timed_out then
				cb(false, "", "timed out")
			elseif r.status ~= 0 then
				local msg = if r.stderr ~= "" then r.stderr else r.stdout
				cb(false, r.stdout, first_line(trim(msg)))
			else
				cb(true, r.stdout, "")
			end
		end)
	if not ok then
		cb(false, "", first_line(tostring(spawn_err)))
	end
end

-- 64 random hex digits (two ids' worth) from the OS, for herdr space and tab
-- ids. Luau's `math.random` can't be used: in Tern's VM it starts from the
-- same seed on every load, so two plugin loads made the same ids, and a new
-- space landed in an older one.
local function random_hex(cb: (hex: string?) -> ())
	local argv = if WINDOWS
		then { "powershell", "-NoProfile", "-Command", "[guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')" }
		else { "/bin/sh", "-c", "od -An -N32 -tx1 /dev/urandom" }
	run(argv, nil, function(ok, out, err)
		local hex = string.lower((string.gsub(out, "[^%x]", "")))
		if not ok or #hex < 64 then
			log("no random bytes", err)
			cb(nil)
		else
			cb(string.sub(hex, 1, 64))
		end
	end)
end

local function parse_ls(stdout: string): { Pane }?
	local ok, doc = pcall(tern.json.decode, stdout)
	if not ok or type(doc) ~= "table" or type(doc.terminals) ~= "table" then
		return nil
	end
	local out: { Pane } = {}
	for _, r in doc.terminals do
		if type(r) == "table" and type(r.address) == "string" and r.state ~= "finished" then
			local program = program_name(if type(r.agent) == "string" then r.agent else "")
			local status = r.status
			if type(status) == "table" then
				status = status.state
			end
			local where = if type(r.where) == "string" and r.where ~= "" then r.where else r.address
			local space, tab = string.match(where, "^(.*) / (.-)$")
			table.insert(out, {
				address = r.address,
				space = space or where,
				tab = tab or where,
				where = where,
				program = program,
				-- hc reports a status only for agent CLIs; the program name
				-- covers agents that haven't reported yet.
				agent = type(status) == "string" or (program ~= "" and not SHELLS[program]),
				status = if type(status) == "string" then status else nil,
				cwd = if type(r.cwd) == "string" then r.cwd else "",
				index = #out + 1,
			})
		end
	end
	return out
end

-- address → herdr.space, from a terminal.list reply.
local function parse_spaces(stdout: string): { [string]: string }
	local out: { [string]: string } = {}
	local ok, doc = pcall(tern.json.decode, first_line(stdout))
	if not ok or type(doc) ~= "table" or type(doc.result) ~= "table" or type(doc.result.terminals) ~= "table" then
		return out
	end
	for _, r in doc.result.terminals do
		if type(r) == "table" and type(r.address) == "string" and type(r.labels) == "table" then
			local space = r.labels["herdr.space"]
			if type(space) == "string" and space ~= "" then
				out[r.address] = space
			end
		end
	end
	return out
end

-- The herdr-core address a Tern block attaches to, from its command line:
-- `… hc attach <addr>` (typed, or opened by the link route), or this
-- plugin's `/bin/sh -c '<IDLE_ATTACH>' hc <addr>`. Tern may report that one
-- as a single shell-quoted line (`… attach "$1"' /path/hc t44`) or as
-- separate arguments.
local function attached_address(b: { [string]: any }): string?
	local args: { string } = {}
	if type(b.args) == "table" then
		for _, a in b.args do
			if type(a) == "string" then
				table.insert(args, a)
			end
		end
	end
	for _, line in { if type(b.command) == "string" then b.command else "", table.concat(args, " ") } do
		local addr = string.match(line, "hc%S*%s+attach%s+['\"]?([%w_%-]+)")
			or string.match(line, "attach \"%$1\"'?%s+%S*hc%S*['\"]?%s+['\"]?([%w_%-]+)")
		if addr then
			return addr
		end
	end
	if #args >= 2 and table.find(args, IDLE_ATTACH) then
		local addr = args[#args]
		if string.match(addr, "^[%w_%-]+$") then
			return addr
		end
	end
	return nil
end

-- address → live block, from `tern ls --json`.
local function parse_attached(stdout: string): { [string]: number }
	local out: { [string]: number } = {}
	local ok, doc = pcall(tern.json.decode, stdout)
	if not ok or type(doc) ~= "table" or type(doc.sessions) ~= "table" then
		return out
	end
	for _, session in doc.sessions do
		for _, tab in (if type(session) == "table" and type(session.tabs) == "table" then session.tabs else {}) do
			for _, b in (if type(tab) == "table" and type(tab.blocks) == "table" then tab.blocks else {}) do
				if type(b) == "table" and type(b.id) == "number" and b.live and b.exited == nil then
					local addr = attached_address(b)
					if addr and not out[addr] then
						out[addr] = b.id
					end
				end
			end
		end
	end
	return out
end

-- Calls `cb` with the blocks already attached to herdr-core terminals
-- (empty when the `tern` CLI can't tell).
local function load_attached(s: State, cb: (attached: { [string]: number }) -> ())
	local tern_exe = tern_bin()
	if not tern_exe then
		cb({})
		return
	end
	run({ tern_exe, "ls", "--json" }, nil, function(ok, out, err)
		if not ok then
			log("tern ls failed", err)
		end
		cb(if ok then parse_attached(out) else {})
	end, s.target)
end

---------------------------------------------------------------------------
-- State changes

local function set_mode(s: State, mode: string)
	s.mode = mode
	s.query = ""
	s.sel = 1
	s.err = nil
end

-- Loads the terminals (`hc ls` joined with terminal.list's labels) into
-- `s.panes`, then renders.
local function load_panes(s: State)
	local hc = hc_bin()
	if not hc then
		s.loading = false
		s.err = "Can't find hc. Set HC_BIN to its full path."
		return
	end
	s.loading = true
	s.err = nil
	local ls_out: string? = nil
	local spaces_out: string? = nil
	local attached: { [string]: number }? = nil
	local failed: string? = nil
	local function done()
		if failed then
			s.loading = false
			s.err = failed
			s.cx:render()
			return
		end
		if not ls_out or not spaces_out or not attached then
			return
		end
		s.attached = attached
		local panes = parse_ls(ls_out)
		s.loading = false
		if not panes then
			s.err = "Could not read hc ls output."
		else
			local spaces = parse_spaces(spaces_out)
			for _, p in panes do
				p.space_id = spaces[p.address]
			end
			s.panes = panes
		end
		s.cx:render()
	end
	run({ hc, "ls", "--json" }, nil, function(ok, out, err)
		if ok then
			ls_out = out
		else
			failed = failed or ("hc ls failed: " .. err)
		end
		done()
	end)
	-- terminal.list carries the labels hc ls leaves out; without it every
	-- terminal is outside a space, which only empties "New tab".
	run({ hc, "connect", "--json" }, '{"jsonrpc":"2.0","id":1,"method":"terminal.list","params":{}}\n',
		function(ok, out, _err)
			spaces_out = if ok then out else ""
			done()
		end)
	load_attached(s, function(a)
		attached = a
		done()
	end)
end

local function load_dir(s: State, dir: string)
	local ok, names = pcall(tern.fs.list, dir)
	if not ok then
		s.cx:toast("error", "Herdr: can't list " .. short_path(dir), first_line(tostring(names)))
		return
	end
	local subdirs: { string } = {}
	for _, name in names :: { string } do
		if string.sub(name, 1, 1) ~= "." and is_dir(join(dir, name)) then
			table.insert(subdirs, name)
		end
	end
	table.sort(subdirs, function(a, b)
		return string.lower(a) < string.lower(b)
	end)
	s.dir = dir
	s.subdirs = subdirs
	s.query = ""
	s.sel = 1
end

local function enter_mode(s: State, mode: string)
	set_mode(s, mode)
	if mode == "pick" or mode == "tab" then
		load_panes(s)
	elseif mode == "space" then
		load_dir(s, s.dir)
	end
end

---------------------------------------------------------------------------
-- Opening a terminal in a split

-- Fallback: the window half's link route splits the pane and runs hc attach.
local function open_by_link(s: State, address: string, cwd: string)
	local url = "tern-herdr-picker:attach?addr=" .. urlencode(address)
		.. "&target=" .. urlencode(s.target) .. "&cwd=" .. urlencode(cwd)
	log("open by link", url)
	s.cx:open(url)
	s.cx:exit(0)
end

-- Opens `hc attach <address>` in a split of the target pane, then closes
-- this block, so the new pane takes its place, and focuses the new pane.
local function split_attach(s: State, tern_exe: string, hc: string, address: string, cwd: string)
	local argv = { tern_exe, "split", s.target, "right", "--json" }
	if cwd ~= "" then
		table.insert(argv, "--cwd")
		table.insert(argv, cwd)
	end
	table.insert(argv, "--")
	if WINDOWS then
		for _, a in { hc, "attach", address } do
			table.insert(argv, a)
		end
	else
		for _, a in { "/bin/sh", "-c", IDLE_ATTACH, hc, address } do
			table.insert(argv, a)
		end
	end
	log("open", address, "beside", s.target)
	run(argv, nil, function(ok, out, err)
		if not ok then
			log("tern split failed, using the link route", err)
			s.busy = false
			open_by_link(s, address, cwd)
			return
		end
		local okj, doc = pcall(tern.json.decode, out)
		local block = if okj and type(doc) == "table" and type(doc.block) == "number" then tostring(doc.block) else nil
		-- Close this block first, so its closing doesn't move the focus.
		s.cx:exit(0)
		if block then
			run({ tern_exe, "focus", block }, nil, function(fok, _o, ferr)
				if not fok then
					log("focus failed", ferr)
				end
			end, block)
		end
	end, s.target)
end

local function open_pane(s: State, address: string, cwd: string)
	if s.busy then
		return
	end
	local tern_exe = tern_bin()
	local hc = hc_bin()
	if not tern_exe or not hc then
		open_by_link(s, address, cwd)
		return
	end
	s.busy = true
	-- Ask Tern afresh: the pane may have been attached or closed since the
	-- list was drawn.
	load_attached(s, function(attached)
		local existing = attached[address]
		if existing then
			-- Close this block first, so its closing doesn't take the focus
			-- back; the process outlives the block.
			log("already open", address, "in", existing)
			s.cx:exit(0)
			run({ tern_exe, "focus", tostring(existing) }, nil, function(ok, _out, err)
				if not ok then
					log("focus failed", err)
				end
			end, tostring(existing))
			return
		end
		split_attach(s, tern_exe :: string, hc :: string, address, cwd)
	end)
end

-- Starts a shell in `dir` under `space` and a tab the Herdr app doesn't know
-- yet, then opens it. Without `space`, a fresh id makes a new space
-- (docs/adr/0001). Ids are "sp"/"tb" .. 32 hex digits, the shape of the
-- Herdr app's own.
local function start_shell(s: State, dir: string, space: string?)
	local hc = hc_bin()
	if not hc then
		s.cx:toast("error", "Herdr: can't find hc", "Set HC_BIN to its full path.")
		return
	end
	if s.busy then
		return
	end
	s.busy = true
	random_hex(function(hex)
		if not hex then
			s.busy = false
			s.cx:toast("error", "Herdr: couldn't make an id for the new tab")
			s.cx:render()
			return
		end
		local space_id = space or ("sp" .. string.sub(hex, 1, 32))
		local tab_id = "tb" .. string.sub(hex, 33, 64)
		log("start shell", dir, space_id, tab_id)
		run({
			hc, "run", "--bg", "--keep", "--no-parent", "--json",
			"--cwd", dir,
			"--label", "herdr.space=" .. space_id,
			"--label", "herdr.tab=" .. tab_id,
		}, nil, function(ok, out, err)
			s.busy = false
			if not ok then
				s.cx:toast("error", "Herdr: hc run failed", err)
				s.cx:render()
				return
			end
			local okj, doc = pcall(tern.json.decode, out)
			if not okj or type(doc) ~= "table" or type(doc.address) ~= "string" then
				s.cx:toast("error", "Herdr: could not read hc run output")
				s.cx:render()
				return
			end
			open_pane(s, doc.address, dir)
		end)
	end)
end

---------------------------------------------------------------------------
-- Rows of each mode

local HOME_ROWS = {
	{ id = "pick", label = "Open a pane", detail = "attach to a running herdr-core terminal", icon = "terminal" },
	{ id = "space", label = "New space", detail = "start a herdr space in a folder", icon = "folder" },
	{ id = "tab", label = "New tab", detail = "add a tab to a herdr space", icon = "list" },
}

local function home_rows(s: State): { Row }
	local out: { Row } = {}
	for _, r in HOME_ROWS do
		if matches(s.query, r.label, r.detail) then
			table.insert(out, {
				id = r.id,
				item = { id = r.id, label = r.label, detail = r.detail, icon = r.icon, hits = hits(r.label, s.query) },
			})
		end
	end
	return out
end

local function in_view(s: State, p: Pane): boolean
	return s.view == "all" or (s.view == "agents") == p.agent
end

local function pane_item(s: State, p: Pane, label: string, show_cwd: boolean): { [string]: any }
	local bits = { if p.program ~= "" then p.program else "terminal" }
	if show_cwd and p.cwd ~= "" then
		table.insert(bits, short_path(p.cwd))
	end
	local st = p.status and STATUS[p.status]
	local item: { [string]: any } = {
		id = p.address,
		label = label,
		detail = table.concat(bits, "  ·  "),
		badges = if st then { { text = st.text, tone = st.tone } } else nil,
		hits = hits(label, s.query),
	}
	local provider = PROVIDER[p.program]
	if p.agent and provider then
		item.mark = { text = p.program, icon = "provider:" .. provider }
	else
		item.icon = if p.agent then "sparkle" else "terminal"
	end
	return item
end

local function tab_order(a: Pane, b: Pane): boolean
	local na, nb = tonumber(a.tab), tonumber(b.tab)
	if na and nb and na ~= nb then
		return na < nb
	end
	if a.tab ~= b.tab then
		return a.tab < b.tab
	end
	return a.index < b.index
end

-- The panes in view, as a tree: a space with more than one pane is a row
-- of its own with its panes under it; a space with one pane is a single row.
-- Spaces keep the order their first pane has in `hc ls`.
local function pane_rows(s: State): { Row }
	local groups: { { key: string, name: string, panes: { Pane } } } = {}
	local by_key: { [string]: { key: string, name: string, panes: { Pane } } } = {}
	for _, p in s.panes do
		if in_view(s, p) and matches(s.query, p.where, p.program, p.cwd) then
			local key = p.space_id or ("name:" .. p.space)
			local g = by_key[key]
			if not g then
				g = { key = key, name = p.space, panes = {} }
				by_key[key] = g
				table.insert(groups, g)
			end
			table.insert(g.panes, p)
		end
	end
	local out: { Row } = {}
	for _, g in groups do
		if #g.panes == 1 then
			local p = g.panes[1]
			local item = pane_item(s, p, p.where, true)
			item.depth = 0
			table.insert(out, { id = p.address, item = item })
		else
			table.sort(g.panes, tab_order)
			local id = "g:" .. g.key
			-- A search keeps every matching group open.
			local open = s.query ~= "" or not s.collapsed[g.key]
			local cwd = g.panes[1].cwd
			local same_cwd = true
			for _, p in g.panes do
				if p.cwd ~= cwd then
					same_cwd = false
				end
			end
			local bits = { #g.panes .. " panes" }
			if same_cwd and cwd ~= "" then
				table.insert(bits, short_path(cwd))
			end
			table.insert(out, {
				id = id,
				item = {
					id = id,
					label = g.name,
					detail = table.concat(bits, "  ·  "),
					icon = "folder",
					depth = 0,
					open = open,
					hits = hits(g.name, s.query),
				},
			})
			if open then
				for _, p in g.panes do
					local item = pane_item(s, p, "Tab " .. p.tab, not same_cwd)
					item.depth = 1
					table.insert(out, { id = p.address, item = item })
				end
			end
		end
	end
	return out
end

-- Folds or unfolds a space group row; false for any other row.
local function toggle_group(s: State, id: string, open: boolean?): boolean
	if s.mode ~= "pick" or string.sub(id, 1, 2) ~= "g:" then
		return false
	end
	local key = string.sub(id, 3)
	if open == nil then
		s.collapsed[key] = not s.collapsed[key] or nil
	else
		s.collapsed[key] = (not open) or nil
	end
	return true
end

local function looks_like_path(q: string): boolean
	return string.match(q, "^[/~]") ~= nil or string.match(q, "^%a:[/\\]") ~= nil
end

local function space_rows(s: State): { Row }
	local out: { Row } = {}
	local q = trim(s.query)
	if looks_like_path(q) then
		local path = expand_home(q)
		local ok = is_dir(path)
		table.insert(out, {
			id = "@go",
			item = {
				id = "@go",
				label = "Go to " .. q,
				detail = if ok then "" else "not a folder",
				icon = "folder",
				disabled = if ok then nil else "Not a folder",
			},
		})
		return out
	end
	if q == "" then
		table.insert(out, {
			id = "@use",
			item = { id = "@use", label = "Use " .. short_path(s.dir), detail = "start the new space here", icon = "terminal" },
		})
		local up = parent(s.dir)
		if up then
			table.insert(out, { id = "@up", item = { id = "@up", label = "..", detail = short_path(up), icon = "folder" } })
		end
	end
	for _, name in s.subdirs do
		if matches(q, name) then
			table.insert(out, {
				id = "d:" .. name,
				item = { id = "d:" .. name, label = name .. "/", icon = "folder", hits = hits(name, q) },
			})
		end
	end
	return out
end

-- Spaces in the order their first terminal appears in `hc ls`.
local function spaces_of(panes: { Pane }): { Space }
	local ordered = table.clone(panes)
	table.sort(ordered, function(a, b)
		return a.index < b.index
	end)
	local out: { Space } = {}
	local by_id: { [string]: Space } = {}
	local seen: { [string]: { [string]: boolean } } = {}
	for _, p in ordered do
		local id = p.space_id
		if id then
			local sp = by_id[id]
			if not sp then
				sp = { id = id, name = p.space, cwd = p.cwd, tabs = 0 }
				by_id[id] = sp
				seen[id] = {}
				table.insert(out, sp)
			end
			if sp.cwd == "" then
				sp.cwd = p.cwd
			end
			if not seen[id][p.tab] then
				seen[id][p.tab] = true
				sp.tabs += 1
			end
		end
	end
	return out
end

local function tab_rows(s: State): { Row }
	local out: { Row } = {}
	for _, sp in spaces_of(s.panes) do
		if matches(s.query, sp.name, sp.cwd) then
			local bits = { if sp.tabs == 1 then "1 tab" else sp.tabs .. " tabs" }
			if sp.cwd ~= "" then
				table.insert(bits, short_path(sp.cwd))
			end
			table.insert(out, {
				id = sp.id,
				item = {
					id = sp.id,
					label = sp.name,
					detail = table.concat(bits, "  ·  "),
					icon = "folder",
					hits = hits(sp.name, s.query),
				},
			})
		end
	end
	return out
end

local function rows_of(s: State): { Row }
	if s.mode == "pick" then
		return pane_rows(s)
	elseif s.mode == "space" then
		return space_rows(s)
	elseif s.mode == "tab" then
		return tab_rows(s)
	end
	return home_rows(s)
end

---------------------------------------------------------------------------
-- Actions

local VIEWS = { "all", "agents", "terminals" }

local function cycle_view(s: State, step: number)
	local i = table.find(VIEWS, s.view) or 1
	s.view = VIEWS[(i - 1 + step) % #VIEWS + 1]
	s.sel = 1
end

-- Esc and the sheet's Close/Back: back to home when the block opened there.
local function back(s: State)
	if s.mode ~= "home" and s.entry == "home" then
		set_mode(s, "home")
	else
		s.cx:exit(0)
	end
end

local function find_pane(s: State, address: string): Pane?
	for _, p in s.panes do
		if p.address == address then
			return p
		end
	end
	return nil
end

local function activate(s: State, id: string?)
	if not id or s.busy then
		return
	end
	if s.mode == "home" then
		enter_mode(s, id)
	elseif s.mode == "pick" then
		if toggle_group(s, id) then
			return
		end
		local p = find_pane(s, id)
		if p then
			open_pane(s, p.address, p.cwd)
		end
	elseif s.mode == "space" then
		if id == "@use" then
			start_shell(s, s.dir, nil)
		elseif id == "@up" then
			local up = parent(s.dir)
			if up then
				load_dir(s, up)
			end
		elseif id == "@go" then
			local path = expand_home(trim(s.query))
			if is_dir(path) then
				load_dir(s, path)
			end
		elseif string.sub(id, 1, 2) == "d:" then
			load_dir(s, join(s.dir, string.sub(id, 3)))
		end
	elseif s.mode == "tab" then
		for _, sp in spaces_of(s.panes) do
			if sp.id == id then
				start_shell(s, if sp.cwd ~= "" then sp.cwd else s.dir, sp.id)
			end
		end
	end
end

local function selected_id(s: State): string?
	local rows = rows_of(s)
	local r = rows[s.sel]
	return if r then r.id else nil
end

---------------------------------------------------------------------------
-- View

local SHEET: { [string]: { placeholder: string, noun: string, icon: string, title: string?, primary: string } } = {
	home = { placeholder = "Herdr…", noun = "actions", icon = "terminal", primary = "Choose" },
	pick = { placeholder = "Find a herdr-core pane…", noun = "panes", icon = "terminal", primary = "Open" },
	space = { placeholder = "Filter folders, or type a path…", noun = "folders", icon = "folder", title = "New space", primary = "Choose" },
	tab = { placeholder = "Add a tab to a herdr space…", noun = "spaces", icon = "folder", primary = "Add tab" },
}

local function count_panes(s: State, agents: boolean?): number
	local n = 0
	for _, p in s.panes do
		if agents == nil or p.agent == agents then
			n += 1
		end
	end
	return n
end

-- Below this many rows the palette-sized sheet ("md": 72px down from the
-- top, chrome around a short list) leaves room for a row or two, so the
-- sheet fills the block instead ("screen").
local SMALL_ROWS = 28

local function sheet(s: State): Node
	local spec = SHEET[s.mode] or SHEET.home
	local rows = rows_of(s)
	if s.sel > #rows then
		s.sel = math.max(1, #rows)
	end
	local items: { any } = {}
	local order: { any } = {}
	for _, r in rows do
		table.insert(items, r.item)
		table.insert(order, r.id)
	end

	local current: { string } = {}
	if s.mode == "pick" then
		for _, p in s.panes do
			if s.attached[p.address] then
				table.insert(current, p.address)
			end
		end
	end

	local sel = rows[s.sel]
	local primary = spec.primary
	if sel and sel.item.open ~= nil then
		primary = if sel.item.open then "Fold" else "Unfold"
	end
	local props: { [string]: any } = {
		key = "sheet-" .. s.mode,
		size = if s.cx.rows < SMALL_ROWS then "screen" else "md",
		-- "screen" defaults to a preview pane; there is nothing to preview.
		preview = "none",
		icon = spec.icon,
		placeholder = spec.placeholder,
		noun = spec.noun,
		query = s.query,
		state = if s.err then "error" elseif s.loading then "loading" else "ready",
		message = s.err,
		items = items,
		order = order,
		selected = if sel then sel.id else nil,
		current = current,
		actions = {
			{ id = "close", label = if s.mode ~= "home" and s.entry == "home" then "Back" else "Close", keys = { "esc" } },
			{ id = "activate", label = primary, keys = { "enter" }, primary = true, disabled = (sel == nil) or nil },
		},
	}
	if s.err then
		table.insert(props.actions, 2, { id = "retry", label = "Retry" })
	end
	if spec.title then
		props.title = spec.title
		props.subtitle = short_path(s.dir)
	end
	if s.mode == "space" then
		props.actions = {
			{ id = "close", label = if s.entry == "home" then "Back" else "Close", keys = { "esc" } },
			{ id = "create", label = "Create here", keys = { "cmd", "enter" } },
			{ id = "activate", label = spec.primary, keys = { "enter" }, primary = true, disabled = (sel == nil) or nil },
		}
	elseif s.mode == "pick" then
		props.tabs = {
			{ id = "all", label = "All", count = count_panes(s, nil) },
			{ id = "agents", label = "Agents", count = count_panes(s, true) },
			{ id = "terminals", label = "Terminals", count = count_panes(s, false) },
		}
		props.tab = s.view
		props.layout = "tree"
	end
	if s.mode == "tab" and not s.loading and not s.err and #s.panes > 0 and #rows == 0 and s.query == "" then
		props.empty = "No herdr spaces with a live terminal"
	end
	if s.mode == "pick" and not s.loading and not s.err and #s.panes == 0 then
		props.empty = "No running herdr-core panes"
	end
	return tern.ui.node("picker", props)
end

---------------------------------------------------------------------------
-- The block

tern.block.define("herdr", {
	font = "sans",

	init = function(cx: BlockCx, args: { string }, _saved: any): State
		local s: State = {
			mode = "home",
			entry = "home",
			query = "",
			sel = 1,
			view = "all",
			loading = false,
			err = nil,
			panes = {},
			dir = cx.cwd or HOME,
			subdirs = {},
			target = tostring(cx.pane),
			attached = {},
			collapsed = {},
			busy = false,
			cx = cx,
		}
		local mode = "home"
		for _, a in args do
			local k, v = string.match(a, "^(%w+)=(.*)$")
			if k == "mode" and v and SHEET[v] then
				mode = v
			elseif k == "target" and v and string.match(v, "^%d+$") then
				s.target = v
			end
		end
		if s.dir == "" or not is_dir(s.dir) then
			s.dir = if HOME ~= "" then HOME else "/"
		end
		s.entry = mode
		enter_mode(s, mode)
		return s
	end,

	title = function(_s: State): string?
		return "Herdr"
	end,

	view = function(s: State, _cx: BlockCx): BlockView
		return {
			main = tern.ui.col({}),
			layer = tern.ui.col({ sheet(s) }),
		}
	end,

	key = function(s: State, key: Key, _cx: BlockCx): boolean?
		local name = key.name
		if name == "escape" then
			back(s)
		elseif name == "up" or name == "down" then
			-- Wraps around at either end.
			local n = #rows_of(s)
			if n > 0 then
				s.sel = (s.sel - 1 + (if name == "up" then -1 else 1)) % n + 1
			end
		elseif name == "pageup" or name == "home" then
			s.sel = 1
		elseif name == "pagedown" or name == "end" then
			s.sel = math.max(#rows_of(s), 1)
		elseif (name == "right" or name == "left" or name == "tab") and s.mode == "pick" then
			cycle_view(s, if name == "left" or (name == "tab" and key.shift) then -1 else 1)
		elseif name == "backspace" then
			if s.query == "" then
				if s.mode == "space" then
					local up = parent(s.dir)
					if up then
						load_dir(s, up)
					end
				else
					return false
				end
			else
				s.query = string.sub(s.query, 1, (utf8.offset(s.query, -1) or 1) - 1)
				s.sel = 1
			end
		elseif name == "enter" then
			if s.mode == "space" and (key.meta or key.ctrl) then
				start_shell(s, s.dir, nil)
			else
				activate(s, selected_id(s))
			end
		elseif key.text and key.text ~= "" and not key.ctrl and not key.meta then
			s.query ..= key.text
			s.sel = 1
		else
			return false
		end
		return true
	end,

	event = function(s: State, ev: UiEvent, _cx: BlockCx)
		if ev.ev == "select" and type(ev.item) == "string" then
			for i, r in rows_of(s) do
				if r.id == ev.item then
					s.sel = i
				end
			end
		elseif ev.ev == "activate" and type(ev.item) == "string" then
			activate(s, ev.item)
		elseif ev.ev == "action" then
			local act = ev.act
			if act == "close" then
				back(s)
			elseif act == "activate" then
				activate(s, selected_id(s))
			elseif act == "create" and s.mode == "space" then
				start_shell(s, s.dir, nil)
			elseif act == "tab" and type(ev.value) == "string" then
				s.view = ev.value
				s.sel = 1
			elseif act == "clear" then
				s.query = ""
				s.sel = 1
			elseif act == "retry" then
				enter_mode(s, s.mode)
			end
		end
		s.cx:render()
	end,
})
