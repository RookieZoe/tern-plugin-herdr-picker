--!strict
-- "Herdr: pick a pane" lists herdr-core terminals in Tern's native picker
-- (the same overlay the command palette uses), grouped into agent CLIs and
-- plain terminals, each with its directory, and opens the chosen one in a
-- Tern split running `hc attach`.

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

local function attach_command(address: string): string
	local bin = which("hc", "HC_BIN")
	-- A quoted program name is not callable in PowerShell without `&`.
	if string.find(bin, "%s") then
		bin = if tern.runtime.os == "windows" then "& " .. quote(bin) else quote(bin)
	end
	return bin .. " attach " .. address
end

local function first_line(s: string): string
	return string.match(s, "[^\r\n]+") or s
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
			})
		end
	end
	-- Agents first, then terminals; within a group keep hc's order.
	local order: { [HcPane]: number } = {}
	for i, p in out do
		order[p] = i
	end
	table.sort(out, function(a, b)
		if a.agent ~= b.agent then
			return a.agent
		end
		return order[a] < order[b]
	end)
	return out, nil
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
		items = items(true),
		placeholder = "Find a herdr-core pane…",
		icon = "terminal",
		action = "attach",
	}
	-- An icon name this Tern build doesn't know raises; retry without them.
	local ok, pending = pcall(cx.pick, cx, opts)
	if not ok then
		tern.log.warn("herdr-picker: pick with icons failed", tostring(pending))
		opts.items = items(false)
		pending = cx:pick(opts)
	end
	pending:next(function(item, err, cx2)
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
		local argv = { which("hc", "HC_BIN"), "ls", "--json" }
		local ok, spawn_err = pcall(tern.process.run, argv,
			{ timeout_ms = TIMEOUT_MS, env = { NO_COLOR = "1" } },
			function(r: ProcessResult, cx2: WindowCx?)
				local wcx = cx2 or cx
				if r.timed_out then
					wcx:toast("error", "Herdr Picker: hc ls timed out")
					return
				end
				if r.status ~= 0 then
					local msg = if r.stderr ~= "" then r.stderr else r.stdout
					wcx:toast("error", "Herdr Picker: hc ls failed", first_line(string.gsub(msg, "%s+$", "")))
					return
				end
				local panes, err = parse(r.stdout)
				if not panes then
					wcx:toast("error", "Herdr Picker", err)
					return
				end
				if #panes == 0 then
					wcx:toast("info", "No running herdr-core panes")
					return
				end
				show_picker(wcx, panes)
			end)
		if not ok then
			cx:toast("error", "Herdr Picker: could not run hc",
				first_line(tostring(spawn_err)) .. " (set HC_BIN to its full path)")
		end
	end,
})
