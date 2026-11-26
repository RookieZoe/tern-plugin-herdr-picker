--!strict
-- Herdr Picker, window half: commands that open the host half's block
-- (`herdr-picker.herdr`, see host.luau) in a split of the focused pane, and
-- the `tern-herdr-picker:` link route the block falls back to when the `tern`
-- CLI can't open its pane.
--
--   Herdr: open below     (⌘⇧H; Ctrl+Alt+H on Linux and Windows)
--   Herdr: open right     (⌘⌥H; Ctrl+Alt+Shift+H on Linux and Windows)
--
-- The block offers open a pane / new space / new tab; the pane it ends with
-- takes the block's place. Users rebind these in settings.json `keybinds`
-- (plugin.herdr-picker.<id>).

local KIND = "herdr-picker.herdr"
local MAC = tern.runtime.os == "macos" or tern.runtime.os == "ios"

-- Default keys per platform. On a Mac, ⌘⇧H and ⌘⌥H. Elsewhere `cmd` would be
-- the Windows/Super key, and Tern's Linux/Windows preset already binds
-- Ctrl+Shift+H (a plugin key the preset binds is dropped), so Ctrl+Alt+H and
-- Ctrl+Alt+Shift+H, both free there.
local KEYS = if MAC
	then { below = "cmd+shift+h", right = "cmd+alt+h" }
	else { below = "ctrl+alt+h", right = "ctrl+alt+shift+h" }

-- Beside the focused pane; with no pane to open beside (an empty session,
-- e.g. a remote host's with no blocks yet), as a tab of its own, where
-- `beside` would raise "no focused pane to open beside".
local function open_block(cx: WindowCx, dir: Dir)
	local function try(how: How, opts: BlockOpts): (boolean, any)
		return pcall(function()
			return cx:new_block(KIND, { "mode=home" }, how, opts)
		end)
	end
	local ok, pane = false, nil
	if cx.session:focused() then
		ok, pane = try("beside", { dir = dir, focus = true })
	end
	if not ok then
		ok, pane = try("tab", { focus = true })
	end
	if not ok then
		cx:toast("error", "Herdr: can't open the block", tostring(pane))
	elseif not pane then
		cx:toast("error", "Herdr Picker isn't installed on this host",
			"Install the plugin where the session runs (tern plugin install)")
	end
end

tern.command({
	id = "open",
	title = "Herdr: open below",
	icon = "terminal",
	keys = { KEYS.below },
	run = function(cx)
		open_block(cx, "down")
	end,
})

tern.command({
	id = "open-right",
	title = "Herdr: open right",
	icon = "terminal",
	keys = { KEYS.right },
	run = function(cx)
		open_block(cx, "right")
	end,
})

-- Link route fallback ------------------------------------------------------

local function quote(s: string): string
	return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

local function hc_bin(): string
	local override = tern.getenv("HC_BIN")
	if override and override ~= "" then
		return override
	end
	local home = tern.getenv("HOME") or ""
	local lad = tern.getenv("LOCALAPPDATA") or ""
	for _, path in {
		if home ~= "" then home .. "/.local/bin/hc" else "",
		if lad ~= "" then lad .. "/Programs/herdr-core/hc.exe" else "",
		if lad ~= "" then lad .. "/Programs/herdr-app/hc.exe" else "",
		"/opt/homebrew/bin/hc",
		"/usr/local/bin/hc",
	} do
		if path ~= "" and tern.fs.exists(path) then
			return path
		end
	end
	return "hc"
end

-- The host's `hc` path from the link, if it looks like one: absolute, named
-- hc, hc.exe or herdr-core, and free of quotes and shell metacharacters. The
-- link can be any text a program printed, so nothing else is run.
local function host_hc(path: string?): string?
	if not path or path == "" or string.find(path, "[%c'\"`$;&|<>%%!^]") then
		return nil
	end
	if not (string.match(path, "^/") or string.match(path, "^%a:[\\/]")) then
		return nil
	end
	local name = string.lower(string.match(path, "([^\\/]+)$") or "")
	if name == "hc" or name == "hc.exe" or name == "herdr-core" or name == "herdr-core.exe" then
		return path
	end
	return nil
end

-- `hc attach <address>` as the host's shell runs it. The command runs on the
-- session's host, which in a remote session isn't this machine, so the host's
-- own `hc` path (from the link) wins over the one found here.
local function attach_command(address: string, from_host: string?): string
	local bin = from_host or hc_bin()
	local windows_path = string.match(bin, "^%a:[\\/]") ~= nil
		or (from_host == nil and tern.runtime.os == "windows")
	if from_host or string.find(bin, "%s") then
		-- A quoted program name is not callable in PowerShell without `&`.
		bin = if windows_path then "& " .. quote(bin) else quote(bin)
	end
	return bin .. " attach " .. address
end

local function urldecode(s: string): string
	return (string.gsub(s, "%%(%x%x)", function(h)
		return string.char(tonumber(h, 16) :: number)
	end))
end

local function query_params(url: string): { [string]: string }
	local out: { [string]: string } = {}
	local q = string.match(url, "%?(.*)$") or ""
	for k, v in string.gmatch(q, "([^&=]+)=([^&]*)") do
		out[k] = urldecode(v)
	end
	return out
end

-- The Herdr block that sent the link, found by its kind, not by a pane id:
-- the host half only knows the host's ids, and a window numbers a remote
-- host's panes its own way, so a host id could name an unrelated local pane.
-- The link's own pane first, then a focused Herdr block, then one in the
-- focused tab, then any.
local function herdr_block(cx: WindowCx, link_pane: number): number?
	local info = cx.session:pane(link_pane)
	if info and info.block == KIND then
		return link_pane
	end
	local focused = cx.session:focused()
	local focused_tab = if focused then cx.session:tab_of(focused) else nil
	local in_tab, any
	for _, p in cx.session:panes() do
		if p.block == KIND and not p.parked then
			if p.focused then
				return p.pane
			end
			if focused_tab and p.tab == focused_tab then
				in_tab = in_tab or p.pane
			end
			any = any or p.pane
		end
	end
	return in_tab or any
end

tern.route.link(function(link: LinkRequest, cx: WindowCx): RouteDecision?
	if not string.match(link.url, "^tern%-herdr%-picker:attach%?") then
		return nil
	end
	local params = query_params(link.url)
	local address = params.addr
	if not address or not string.match(address, "^[%w%-_]+$") then
		cx:toast("error", "Herdr: bad link", link.url)
		return { handled = true }
	end
	local target = herdr_block(cx, link.pane) or cx.session:focused() or link.pane
	local pane = cx.layout:split(target :: number, "right", {
		command = attach_command(address, host_hc(params.hc)),
		cwd = if params.cwd and params.cwd ~= "" then params.cwd else nil,
	})
	if not pane then
		cx:toast("error", "Herdr: could not open " .. address)
	end
	return { handled = true }
end)
