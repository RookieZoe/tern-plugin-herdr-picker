--!strict
-- "Herdr: pick a pane" lists herdr-core terminals in Tern's native picker
-- (the same overlay the command palette uses), grouped into agent CLIs and
-- plain terminals, each with its directory, and opens the chosen one in a
-- Tern split running `hc attach`.
--
-- "Herdr: new space" asks for a folder, starts a shell there with fresh
-- herdr.space / herdr.tab labels (the Herdr app adopts unknown ids as a new
-- space and tab; see the repo's docs/adr/0001), and opens it the same way.
--
-- "Herdr: new tab" lists the herdr spaces that have a live terminal, starts a
-- shell under the chosen space's herdr.space label and a fresh herdr.tab, and
-- opens it the same way.
--
-- The terminal list joins `hc ls --json` (program, status, where) with
-- herdr-core's terminal.list method (labels, hence the space) by address.

local TIMEOUT_MS = 8000

-- Programs that mean "a plain terminal"; anything else hc reports as the
-- foreground program is treated as an agent CLI.
local SHELLS: { [string]: boolean } = {
	sh = true, bash = true, zsh = true, fish = true, dash = true, ksh = true,
	csh = true, tcsh = true, nu = true, xonsh = true, elvish = true,
	pwsh = true, powershell = true, cmd = true, login = true,
}

-- Brand icons for well-known agents; others get the generic agent icon.
local AGENT_ICON: { [string]: string } = {
	["claude-code"] = "provider-anthropic",
	claude = "provider-anthropic",
	codex = "provider-openai",
	gemini = "provider-google",
	cursor = "provider-cursor",
	["cursor-agent"] = "provider-cursor",
	copilot = "provider-github",
}

local STATUS_LABEL: { [string]: string } = {
	working = "working",
	blocked = "needs input",
	done = "done",
	idle = "idle",
	error = "error",
}

type HcPane = {
	address: string,
	where: string,
	program: string,
	agent: boolean,
	status: string?,
	cwd: string,
	-- herdr.space label; nil for a terminal no Herdr space holds.
	space: string?,
	-- Position in hc's own order, before agents are sorted first.
	index: number,
}

local function which(name: string, env: string): string
	local override = tern.getenv(env)
	if override and override ~= "" then
		return override
	end
	local home = tern.getenv("HOME") or ""
	if home ~= "" and tern.fs.exists(home .. "/.local/bin/" .. name) then
		return home .. "/.local/bin/" .. name
	end
	local localappdata = tern.getenv("LOCALAPPDATA")
	if localappdata then
		for _, dir in { "herdr-core", "herdr-app" } do
			local path = localappdata .. "/Programs/" .. dir .. "/" .. name .. ".exe"
			if tern.fs.exists(path) then
				return path
			end
		end
	end
	for _, path in { "/opt/homebrew/bin/" .. name, "/usr/local/bin/" .. name } do
		if tern.fs.exists(path) then
			return path
		end
	end
	-- On Windows, usually hc.exe on PATH. GUI-launched Tern may not inherit
	-- the user's PATH additions; set HC_BIN when needed.
	return name
end

local function quote(s: string): string
	return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

local function hc_bin(): string
	return which("hc", "HC_BIN")
end

local function attach_command(address: string): string
	local bin = hc_bin()
	-- A quoted program name is not callable in PowerShell without `&`.
	if string.find(bin, "%s") then
		bin = if tern.runtime.os == "windows" then "& " .. quote(bin) else quote(bin)
	end
	return bin .. " attach " .. address
end

local function first_line(s: string): string
	return string.match(s, "[^\r\n]+") or s
end

-- Runs `hc <args>` and hands its stdout to `on_ok`; every failure becomes a
-- toast that names the subcommand.
local function run_hc(cx: WindowCx, args: { string }, on_ok: (stdout: string, cx: WindowCx) -> (), stdin: string?)
	local argv = { hc_bin() }
	for _, a in args do
		table.insert(argv, a)
	end
	local what = "hc " .. args[1]
	local ok, spawn_err = pcall(tern.process.run, argv,
		{ timeout_ms = TIMEOUT_MS, env = { NO_COLOR = "1" }, stdin = stdin },
		function(r: ProcessResult, cx2: WindowCx?)
			local wcx = cx2 or cx
			if r.timed_out then
				wcx:toast("error", "Herdr: " .. what .. " timed out")
				return
			end
			if r.status ~= 0 then
				local msg = if r.stderr ~= "" then r.stderr else r.stdout
				wcx:toast("error", "Herdr: " .. what .. " failed", first_line(string.gsub(msg, "%s+$", "")))
				return
			end
			on_ok(r.stdout, wcx)
		end)
	if not ok then
		cx:toast("error", "Herdr: could not run hc",
			first_line(tostring(spawn_err)) .. " (set HC_BIN to its full path)")
	end
end

-- cx:pick with icons; an icon name this Tern build doesn't know raises, so
-- retry without them.
local function pick(cx: WindowCx, opts: PickOptions, items: (with_icons: boolean) -> { PickItem }): Awaitable<PickItem?>
	opts.items = items(true)
	local ok, pending = pcall(cx.pick, cx, opts)
	if ok then
		return pending
	end
	tern.log.warn("herdr-picker: pick with icons failed", tostring(pending))
	opts.items = items(false)
	return cx:pick(opts)
end

-- "C:\Users\me\x" or "/Users/me/x" → "~\x" / "~/x".
local function short_path(p: string): string
	for _, var in { "HOME", "USERPROFILE" } do
		local home = tern.getenv(var)
		if home and home ~= "" then
			local n = #home
			local head = string.sub(p, 1, n)
			local same = if tern.runtime.os == "windows"
				then string.lower(head) == string.lower(home)
				else head == home
			if same then
				local rest = string.sub(p, n + 1)
				if rest == "" or string.match(rest, "^[/\\]") then
					return "~" .. rest
				end
			end
		end
	end
	return p
end

local function program_name(raw: string): string
	-- "C:\...\pwsh.exe" → "pwsh"
	local base = string.match(raw, "([^/\\]+)$") or raw
	base = string.gsub(base, "%.[eE][xX][eE]$", "")
	return string.lower(base)
end

local function parse(stdout: string): ({ HcPane }?, string?)
	local ok, doc = pcall(tern.json.decode, stdout)
	if not ok or type(doc) ~= "table" or type(doc.terminals) ~= "table" then
		return nil, "could not read hc output"
	end
	local out: { HcPane } = {}
	for _, r in doc.terminals do
		if type(r) == "table" and type(r.address) == "string" and r.state ~= "finished" then
			local raw = if type(r.agent) == "string" then r.agent else ""
			local program = program_name(raw)
			local status = r.status
			if type(status) == "table" then
				status = status.state
			end
			table.insert(out, {
				address = r.address,
				where = if type(r.where) == "string" and r.where ~= "" then r.where else r.address,
				program = program,
				-- hc only reports an agent status for agent CLIs; the program
				-- name covers agents that haven't reported yet.
				agent = type(status) == "string" or (program ~= "" and not SHELLS[program]),
				status = if type(status) == "string" then status else nil,
				cwd = if type(r.cwd) == "string" then r.cwd else "",
				index = #out + 1,
			})
		end
	end
	-- Agents first, then terminals; within a group keep hc's order.
	table.sort(out, function(a, b)
		if a.agent ~= b.agent then
			return a.agent
		end
		return a.index < b.index
	end)
	return out, nil
end

-- address → herdr.space, from a terminal.list reply.
local function parse_spaces(stdout: string): ({ [string]: string }?, string?)
	local ok, doc = pcall(tern.json.decode, first_line(stdout))
	if not ok or type(doc) ~= "table" then
		return nil, "could not read hc connect output"
	end
	if type(doc.error) == "table" then
		return nil, "terminal.list: " .. tostring(doc.error.message)
	end
	local result = doc.result
	if type(result) ~= "table" or type(result.terminals) ~= "table" then
		return nil, "could not read hc connect output"
	end
	local out: { [string]: string } = {}
	for _, r in result.terminals do
		if type(r) == "table" and type(r.address) == "string" and type(r.labels) == "table" then
			local space = r.labels["herdr.space"]
			if type(space) == "string" and space ~= "" then
				out[r.address] = space
			end
		end
	end
	return out, nil
end

-- Runs `hc ls --json` and terminal.list side by side and hands `on_ok` the
-- live terminals, each with its space. hc ls leads: a terminal that
-- terminal.list doesn't report (started between the two calls) has no space.
local function list_terminals(cx: WindowCx, on_ok: (panes: { HcPane }, cx: WindowCx) -> ())
	local ls_out: string? = nil
	local spaces_out: string? = nil
	local function done(wcx: WindowCx)
		if not ls_out or not spaces_out then
			return
		end
		local panes, err = parse(ls_out)
		if not panes then
			wcx:toast("error", "Herdr Picker", err)
			return
		end
		local spaces, err2 = parse_spaces(spaces_out)
		if not spaces then
			wcx:toast("error", "Herdr Picker", err2)
			return
		end
		for _, p in panes do
			p.space = spaces[p.address]
		end
		on_ok(panes, wcx)
	end
	run_hc(cx, { "ls", "--json" }, function(stdout, wcx)
		ls_out = stdout
		done(wcx)
	end)
	run_hc(cx, { "connect", "--json" }, function(stdout, wcx)
		spaces_out = stdout
		done(wcx)
	end, '{"jsonrpc":"2.0","id":1,"method":"terminal.list","params":{}}\n')
end

-- Focuses the split already showing `address` in this window, or opens one.
local function open_pane(cx: WindowCx, address: string, cwd: string)
	local key = "pane:" .. cx:window_key() .. ":" .. address
	local existing = tern.kv.get(key)
	if type(existing) == "number" then
		for _, p in cx.session:panes() do
			if p.pane == existing then
				cx.layout:focus(existing)
				return
			end
		end
		tern.kv.set(key, nil)
	end

	local target = cx.session:focused()
	if not target then
		cx:toast("error", "Herdr: no pane to split")
		return
	end
	local command = attach_command(address)
	tern.log.info("herdr-picker: open", address, command)
	local pane = cx.layout:split(target, "right", {
		command = command,
		cwd = if cwd ~= "" then cwd else nil,
	})
	if pane then
		tern.kv.set(key, pane)
	else
		cx:toast("error", "Herdr: could not open " .. address)
	end
end

-- Addresses this window already shows in a split (checked in the picker).
local function attached_addresses(cx: WindowCx, panes: { HcPane }): { [string]: boolean }
	local live: { [number]: boolean } = {}
	for _, p in cx.session:panes() do
		live[p.pane] = true
	end
	local prefix = "pane:" .. cx:window_key() .. ":"
	local out: { [string]: boolean } = {}
	for _, p in panes do
		local pane = tern.kv.get(prefix .. p.address)
		if type(pane) == "number" and live[pane] then
			out[p.address] = true
		end
	end
	return out
end

local function show_picker(cx: WindowCx, panes: { HcPane })
	local open_now = attached_addresses(cx, panes)
	local function items(with_icons: boolean): { PickItem }
		local out: { PickItem } = {}
		for _, p in panes do
			local bits: { string } = {}
			if p.agent then
				table.insert(bits, if p.program ~= "" then p.program else "agent")
				if p.status then
					table.insert(bits, STATUS_LABEL[p.status] or p.status)
				end
			else
				table.insert(bits, if p.program ~= "" then "terminal · " .. p.program else "terminal")
			end
			if p.cwd ~= "" then
				table.insert(bits, short_path(p.cwd))
			end
			local item: PickItem = {
				label = p.where,
				detail = table.concat(bits, "  ·  "),
				group = if p.agent then "Agent CLIs" else "Terminals",
				current = open_now[p.address] or nil,
				address = p.address,
				cwd = p.cwd,
			}
			if with_icons then
				item.icon = if p.agent then (AGENT_ICON[p.program] or "sparkle") else "terminal"
			end
			table.insert(out, item)
		end
		return out
	end

	local opts: PickOptions = {
		items = {},
		placeholder = "Find a herdr-core pane…",
		icon = "terminal",
		action = "attach",
	}
	pick(cx, opts, items):next(function(item, err, cx2)
		local wcx = cx2 or cx
		if err then
			wcx:toast("error", "Herdr Picker", err)
			return
		end
		if item and type(item.address) == "string" then
			open_pane(wcx, item.address, if type(item.cwd) == "string" then item.cwd else "")
		end
	end)
end

tern.command({
	id = "pick",
	title = "Herdr: pick a pane",
	icon = "terminal",
	run = function(cx)
		list_terminals(cx, function(panes, wcx)
			if #panes == 0 then
				wcx:toast("info", "No running herdr-core panes")
				return
			end
			show_picker(wcx, panes)
		end)
	end,
})

-- New space ---------------------------------------------------------------

local seeded = false

-- "sp" .. 32 hex digits, the shape of the Herdr app's own ids.
local function new_id(prefix: string): string
	if not seeded then
		-- Luau's generator starts from a fixed seed; mix the clock with a
		-- table address, which differs between VMs.
		local addr = tonumber(string.match(tostring({}), "0x(%x+)") or "0", 16) or 0
		local clock = 0
		pcall(function()
			clock = os.time() + math.floor(os.clock() * 1e6)
		end)
		math.randomseed(clock + addr % 1e9)
		seeded = true
	end
	local digits = table.create(32)
	for i = 1, 32 do
		digits[i] = string.format("%x", math.random(0, 15))
	end
	return prefix .. table.concat(digits)
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

local function expand_home(p: string): string
	if string.sub(p, 1, 1) ~= "~" then
		return p
	end
	local rest = string.sub(p, 2)
	if rest ~= "" and not string.match(rest, "^[/\\]") then
		return p
	end
	local home = tern.getenv("HOME") or tern.getenv("USERPROFILE")
	return if home and home ~= "" then home .. rest else p
end

local function focused_cwd(cx: WindowCx): string
	local focused = cx.session:focused()
	if focused then
		for _, p in cx.session:panes() do
			if p.pane == focused and p.cwd and p.cwd ~= "" then
				return p.cwd
			end
		end
	end
	return tern.getenv("HOME") or tern.getenv("USERPROFILE") or "/"
end

-- Starts a shell in `dir` under `space` and a Tab the Herdr app doesn't know
-- yet, then opens it in a split. A fresh `space` id makes a new Space.
local function start_shell(cx: WindowCx, dir: string, space: string)
	local args = {
		"run", "--bg", "--keep", "--no-parent", "--json",
		"--cwd", dir,
		"--label", "herdr.space=" .. space,
		"--label", "herdr.tab=" .. new_id("tb"),
	}
	run_hc(cx, args, function(stdout, wcx)
		local ok, doc = pcall(tern.json.decode, stdout)
		if not ok or type(doc) ~= "table" or type(doc.address) ~= "string" then
			wcx:toast("error", "Herdr: could not read hc run output")
			return
		end
		open_pane(wcx, doc.address, dir)
	end)
end

local function create_space(cx: WindowCx, dir: string)
	tern.log.info("herdr-picker: new space", dir)
	start_shell(cx, dir, new_id("sp"))
end

local function type_path(cx: WindowCx, dir: string)
	cx:prompt({
		value = short_path(dir),
		placeholder = "Folder for the new space",
		icon = "folder",
		action = "create",
	}):next(function(text, err, cx2)
		local wcx = cx2 or cx
		if err then
			wcx:toast("error", "Herdr: new space", err)
			return
		end
		if not text then
			return
		end
		local path = expand_home(string.match(text, "^%s*(.-)%s*$") or "")
		if path == "" or not is_dir(path) then
			wcx:toast("error", "Herdr: not a folder", text)
			return
		end
		create_space(wcx, path)
	end)
end

-- One level of the folder browser: use this folder, go up, go into a
-- subfolder, or type a path.
local function browse(cx: WindowCx, dir: string)
	local ok, names = pcall(tern.fs.list, dir)
	if not ok then
		cx:toast("error", "Herdr: can't list " .. short_path(dir), first_line(tostring(names)))
		return
	end
	local subdirs: { string } = {}
	for _, name in names :: { string } do
		if string.sub(name, 1, 1) ~= "." and is_dir(join(dir, name)) then
			table.insert(subdirs, name)
		end
	end
	local up = parent(dir)

	local function items(with_icons: boolean): { PickItem }
		local out: { PickItem } = {}
		local function add(item: PickItem, icon: string)
			if with_icons then
				item.icon = icon
			end
			table.insert(out, item)
		end
		add({ label = "Use " .. short_path(dir), detail = "new space here", kind = "use" }, "terminal")
		if up then
			add({ label = "..", detail = short_path(up), kind = "go", path = up }, "folder")
		end
		for _, name in subdirs do
			add({ label = name .. "/", kind = "go", path = join(dir, name) }, "folder")
		end
		add({ label = "Type a path…", kind = "type" }, "list")
		return out
	end

	local opts: PickOptions = {
		items = {},
		placeholder = "New herdr space in " .. short_path(dir),
		icon = "folder",
		action = "choose",
	}
	pick(cx, opts, items):next(function(item, err, cx2)
		local wcx = cx2 or cx
		if err then
			wcx:toast("error", "Herdr: new space", err)
			return
		end
		if not item then
			return
		end
		if item.kind == "use" then
			create_space(wcx, dir)
		elseif item.kind == "go" and type(item.path) == "string" then
			browse(wcx, item.path)
		elseif item.kind == "type" then
			type_path(wcx, dir)
		end
	end)
end

tern.command({
	id = "new-space",
	title = "Herdr: new space",
	icon = "folder",
	run = function(cx)
		browse(cx, focused_cwd(cx))
	end,
})

-- New tab -------------------------------------------------------------------

type Space = {
	id: string,
	name: string,
	-- The first terminal's directory (in hc's order), where a new tab starts.
	cwd: string,
	tabs: number,
}

-- "my-app / 2" → "my-app", "2"; the last " / " splits, as tab names are short.
local function split_where(where: string): (string, string?)
	local space, tab = string.match(where, "^(.*) / (.-)$")
	if space then
		return space, tab
	end
	return where, nil
end

-- Spaces in the order their first terminal appears in `hc ls`.
local function group_spaces(panes: { HcPane }): { Space }
	local ls_order = table.clone(panes)
	table.sort(ls_order, function(a, b)
		return a.index < b.index
	end)
	local out: { Space } = {}
	local by_id: { [string]: Space } = {}
	local tab_seen: { [string]: { [string]: boolean } } = {}
	for _, p in ls_order do
		local id = p.space
		if id then
			local space_name, tab = split_where(p.where)
			local s = by_id[id]
			if not s then
				s = { id = id, name = space_name, cwd = p.cwd, tabs = 0 }
				by_id[id] = s
				tab_seen[id] = {}
				table.insert(out, s)
			end
			if s.cwd == "" then
				s.cwd = p.cwd
			end
			local key = tab or p.address
			if not tab_seen[id][key] then
				tab_seen[id][key] = true
				s.tabs += 1
			end
		end
	end
	return out
end

local function show_spaces(cx: WindowCx, spaces: { Space })
	local function items(with_icons: boolean): { PickItem }
		local out: { PickItem } = {}
		for _, s in spaces do
			local bits = { if s.tabs == 1 then "1 tab" else s.tabs .. " tabs" }
			if s.cwd ~= "" then
				table.insert(bits, short_path(s.cwd))
			end
			local item: PickItem = {
				label = s.name,
				detail = table.concat(bits, "  ·  "),
				space = s.id,
				cwd = s.cwd,
			}
			if with_icons then
				item.icon = "folder"
			end
			table.insert(out, item)
		end
		return out
	end

	local opts: PickOptions = {
		items = {},
		placeholder = "Add a tab to a herdr space…",
		icon = "folder",
		action = "add tab",
	}
	pick(cx, opts, items):next(function(item, err, cx2)
		local wcx = cx2 or cx
		if err then
			wcx:toast("error", "Herdr: new tab", err)
			return
		end
		if not item or type(item.space) ~= "string" then
			return
		end
		local dir = if type(item.cwd) == "string" and item.cwd ~= "" then item.cwd else focused_cwd(wcx)
		tern.log.info("herdr-picker: new tab", item.space, dir)
		start_shell(wcx, dir, item.space)
	end)
end

tern.command({
	id = "new-tab",
	title = "Herdr: new tab",
	icon = "folder",
	run = function(cx)
		list_terminals(cx, function(panes, wcx)
			local spaces = group_spaces(panes)
			if #spaces == 0 then
				wcx:toast("info", "No herdr spaces with a live terminal")
				return
			end
			show_spaces(wcx, spaces)
		end)
	end,
})
