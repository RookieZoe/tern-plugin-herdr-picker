--!strict
-- Herdr Picker, window half: commands that open the host half's block
-- (`herdr-picker.herdr`, see host.luau) in a split of the focused pane, and
-- the `tern-herdr-picker:` link route the block falls back to when the `tern`
-- CLI can't open its pane.
--
--   Herdr: open below     (⌘⇧H)
--   Herdr: open right     (⌘⌥H)
--
-- The block offers open a pane / new space / new tab; the pane it ends with
-- takes the block's place. Users rebind these in settings.json `keybinds`
-- (plugin.herdr-picker.<id>).

local KIND = "herdr-picker.herdr"
local MAC = tern.runtime.os == "macos" or tern.runtime.os == "ios"

-- ⌘ on a Mac; elsewhere `cmd` would be the Windows/Super key, so use Ctrl.
local function chord(rest: string): { string }
	return { (if MAC then "cmd+" else "ctrl+") .. rest }
end

local function open_block(cx: WindowCx, dir: Dir)
	local pane = cx:new_block(KIND, { "mode=home" }, "beside", { dir = dir, focus = true })
	if not pane then
		cx:toast("error", "Herdr Picker isn't installed on this host",
			"Install the plugin where the session runs (tern plugin install)")
	end
end

tern.command({
	id = "open",
	title = "Herdr: open below",
	icon = "terminal",
	keys = chord("shift+h"),
	run = function(cx)
		open_block(cx, "down")
	end,
})

tern.command({
	id = "open-right",
	title = "Herdr: open right",
	icon = "terminal",
	keys = chord("alt+h"),
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

local function attach_command(address: string): string
	local bin = hc_bin()
	-- A quoted program name is not callable in PowerShell without `&`.
	if string.find(bin, "%s") then
		bin = if tern.runtime.os == "windows" then "& " .. quote(bin) else quote(bin)
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
	local target = tonumber(params.target or "")
	if target and not cx.session:pane(target) then
		target = nil
	end
	target = target or cx.session:focused() or link.pane
	local pane = cx.layout:split(target :: number, "right", {
		command = attach_command(address),
		cwd = if params.cwd and params.cwd ~= "" then params.cwd else nil,
	})
	if not pane then
		cx:toast("error", "Herdr: could not open " .. address)
	end
	return { handled = true }
end)
