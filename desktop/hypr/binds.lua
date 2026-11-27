-- ─────────────────────────────────────────────────────────────
-- Keybindings, shared by every machine that runs this desktop.
--
-- Every binding is declared once below, with a stable id, the group it is
-- shown under in Settings → Keybinds, and its default keys. hyprland.lua
-- calls this module with the few things that differ per machine (which
-- terminal, browser, file manager, mixer).
--
-- User changes never touch this file. Settings writes them to
--   ~/.local/state/hypr/keybinds.json      { "<id>": "<keys>", … }
-- and runs `hyprctl reload`; "" means unbound. On every load this module
-- writes what is actually bound to
--   ~/.local/state/hypr/keybinds-manifest.json
-- which is what the Settings page and the shortcut cheatsheet read, so
-- neither can drift from the real config. Both files live outside the repo,
-- so the desktop updater never overwrites a rebind.
--
-- Two kinds of entry:
--   keys   a full chord, "ALT + P", "SUPER + SHIFT + left", "XF86AudioMute"
--   prefix modifiers only, for families of binds that share them: the
--          workspace number keys, mouse drag/resize, scroll-to-switch.
-- ─────────────────────────────────────────────────────────────

return function(ctx)
    local HOME    = os.getenv("HOME")
    local STATE   = (os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/hypr"
    local scripts = HOME .. "/.config/hypr/scripts"
    local bin     = HOME .. "/.local/bin"
    local WS_PER_MONITOR = ctx.wsPerMonitor or 10

    local function exec(cmd) return hl.dsp.exec_cmd(cmd) end
    local function exists(path)
        local f = io.open(path, "r")
        if f then f:close() return true end
        return false
    end

    -- Workspaces — per-monitor. Monitors are ranked left to right by their
    -- position (top to bottom when stacked): the first owns workspaces
    -- 1..10, the second 11..20, and so on. Only the focused monitor switches; the others keep theirs.
    local function wsRange()
        local active = hl.get_active_monitor()
        local rank = 0
        if active then
            for _, m in ipairs(hl.get_monitors()) do
                if m.enabled ~= false and not m.is_mirror
                    and (m.x < active.x or (m.x == active.x and m.y < active.y)) then
                    rank = rank + 1
                end
            end
        end
        return rank * WS_PER_MONITOR + 1, (rank + 1) * WS_PER_MONITOR
    end

    local function goTo(target, carryWindow)
        if carryWindow then
            hl.dispatch(hl.dsp.window.move({ workspace = target }))
        else
            hl.dispatch(hl.dsp.focus({ workspace = target }))
        end
    end

    local function wsGo(n, carryWindow)
        return function()
            local lo = wsRange()
            goTo(lo - 1 + n, carryWindow)
        end
    end

    -- Windows-style next/prev, wrapping inside the focused monitor's range.
    -- Off-range (e.g. a special workspace): switching lands on the range's first
    -- for next / last for prev; carrying a window always lands on the first.
    local function wsStep(step, carryWindow)
        return function()
            local lo, hi = wsRange()
            local ws = hl.get_active_workspace()
            local cur = ws and ws.id or 0
            local target
            if cur < lo or cur > hi then
                target = (carryWindow or step > 0) and lo or hi
            else
                target = cur + step
                if target > hi then target = lo elseif target < lo then target = hi end
            end
            goTo(target, carryWindow)
        end
    end

    local launcher = "qs ipc call island toggle apps"

    -- { group, { id, keys | prefix, label, action(s), opts } … }
    -- `action` is a dispatcher or a list of them (one chord, several effects).
    local GROUPS = {
        { "Apps", {
            { id = "apps.terminal",    keys = "SUPER + Return",        label = "Terminal (" .. ctx.terminal .. ")",          action = exec(ctx.terminal) },
            { id = "apps.browser",     keys = "SUPER + B",             label = "Browser (" .. ctx.browser .. ")",            action = exec(ctx.browser) },
            { id = "apps.files",       keys = "SUPER + E",             label = "File manager (" .. ctx.fileManager .. ")",   action = exec(ctx.fileManager) },
            { id = "apps.launcher",    keys = "SUPER + space",         label = "App launcher",                                action = exec(launcher) },
            { id = "apps.launcher2",   keys = "SUPER + CTRL + Return", label = "App launcher (second key)",                   action = exec(launcher) },
            { id = "apps.rofi",        keys = "SUPER + SHIFT + space", label = "App launcher (rofi fallback)",                action = exec("pkill rofi || rofi -show drun -i") },
            { id = "apps.clipboard",   keys = "SUPER + V",             label = "Clipboard history (copies and pastes)",       action = exec(bin .. "/clipboard-paste-picker.sh") },
            { id = "apps.mixer",       keys = "SUPER + CTRL + V",      label = "Volume mixer (" .. ctx.volumeManager .. ")",  action = exec(ctx.volumeManager) },
        }},
        { "Shell", {
            { id = "shell.settings",   keys = "SUPER + S",             label = "Settings",                                   action = exec("qs ipc call settings toggle") },
            { id = "shell.cheatsheet", keys = "SUPER + slash",         label = "Shortcut cheatsheet",                        action = exec("qs ipc call island toggle keys") },
            { id = "shell.notifs",     keys = "SUPER + SHIFT + N",     label = "Notification panel",                         action = exec("qs ipc call notifications toggle") },
            { id = "shell.silent",     keys = "SUPER + Home",          label = "Silent mode (do not disturb) on/off",        action = exec("qs ipc call notifications dnd") },
            { id = "shell.bars",       keys = "SUPER + CTRL + B",      label = "Show / hide the bars",                       action = exec("qs ipc call bar toggle") },
            { id = "shell.restart",    keys = "SUPER + SHIFT + B",     label = "Restart the shell",                          action = exec(bin .. "/qs-restart") },
        }},
        { "Themes & wallpapers", {
            { id = "theme.switcher",   keys = "SUPER + W",             label = "Theme switcher",                             action = exec("qs ipc call island toggle themes") },
            { id = "theme.random",     keys = "SUPER + SHIFT + W",     label = "Random wallpaper in each monitor's theme",   action = exec("qs ipc call wallpaper random") },
            { id = "theme.browser",    keys = "SUPER + CTRL + W",      label = "Wallpaper browser by theme",                 action = exec("qs ipc call wallpaper toggle") },
            { id = "theme.we",         keys = "SUPER + ALT + W",       label = "Wallpaper Engine (animated) picker",         action = exec(scripts .. "/we-picker.sh"),
              when = exists(scripts .. "/we-picker.sh") },
        }},
        { "Windows", {
            { id = "win.close",        keys = "SUPER + Q",             label = "Close window",                    action = hl.dsp.window.close() },
            { id = "win.fullscreen",   keys = "SUPER + F",             label = "Fullscreen",                      action = hl.dsp.window.fullscreen({ mode = "fullscreen" }) },
            { id = "win.maximize",     keys = "SUPER + M",             label = "Maximize",                        action = hl.dsp.window.fullscreen({ mode = "maximized" }) },
            { id = "win.float",        keys = "SUPER + T",             label = "Toggle floating",                 action = hl.dsp.window.float() },
            { id = "win.split",        keys = "SUPER + J",             label = "Toggle split direction",          action = hl.dsp.layout("togglesplit") },
            { id = "win.pseudo",       keys = "SUPER + P",             label = "Pseudo-tile",                     action = hl.dsp.window.pseudo() },
            { id = "win.group",        keys = "SUPER + G",             label = "Toggle window group (tabbed)",    action = hl.dsp.group.toggle() },
            { id = "win.cycle",        keys = "ALT + Tab",             label = "Cycle windows",                   action = { hl.dsp.window.cycle_next(), hl.dsp.window.bring_to_top() }, opts = { repeating = true } },
            { id = "win.focus.left",   keys = "SUPER + left",          label = "Focus window left",               action = hl.dsp.focus({ direction = "l" }) },
            { id = "win.focus.right",  keys = "SUPER + right",         label = "Focus window right",              action = hl.dsp.focus({ direction = "r" }) },
            { id = "win.focus.up",     keys = "SUPER + up",            label = "Focus window up",                 action = hl.dsp.focus({ direction = "u" }) },
            { id = "win.focus.down",   keys = "SUPER + down",          label = "Focus window down",               action = hl.dsp.focus({ direction = "d" }) },
            { id = "win.swap.left",    keys = "SUPER + ALT + left",    label = "Swap window left",                action = hl.dsp.window.swap({ direction = "l" }) },
            { id = "win.swap.right",   keys = "SUPER + ALT + right",   label = "Swap window right",               action = hl.dsp.window.swap({ direction = "r" }) },
            { id = "win.swap.up",      keys = "SUPER + ALT + up",      label = "Swap window up",                  action = hl.dsp.window.swap({ direction = "u" }) },
            { id = "win.swap.down",    keys = "SUPER + ALT + down",    label = "Swap window down",                action = hl.dsp.window.swap({ direction = "d" }) },
            { id = "win.grow.x",       keys = "SUPER + SHIFT + right", label = "Resize window wider",             action = hl.dsp.window.resize({ x =  100, y =    0, relative = true }), opts = { repeating = true } },
            { id = "win.shrink.x",     keys = "SUPER + SHIFT + left",  label = "Resize window narrower",          action = hl.dsp.window.resize({ x = -100, y =    0, relative = true }), opts = { repeating = true } },
            { id = "win.grow.y",       keys = "SUPER + SHIFT + down",  label = "Resize window taller",            action = hl.dsp.window.resize({ x =    0, y =  100, relative = true }), opts = { repeating = true } },
            { id = "win.shrink.y",     keys = "SUPER + SHIFT + up",    label = "Resize window shorter",           action = hl.dsp.window.resize({ x =    0, y = -100, relative = true }), opts = { repeating = true } },
            { id = "win.drag",         prefix = "SUPER",               label = "Move window: hold and drag with the left button",    mouse = "mouse:272", action = hl.dsp.window.drag(),   opts = { mouse = true } },
            { id = "win.dragresize",   prefix = "SUPER",               label = "Resize window: hold and drag with the right button", mouse = "mouse:273", action = hl.dsp.window.resize(), opts = { mouse = true } },
        }},
        { "Workspaces", {
            { id = "ws.go",            prefix = "SUPER",               label = "Go to workspace 1–10 of this monitor: hold and press 1…0",  family = "number", carry = false },
            { id = "ws.move",          prefix = "SUPER + SHIFT",       label = "Move window to workspace 1–10: hold and press 1…0",         family = "number", carry = true },
            { id = "ws.next",          keys = "SUPER + CTRL + right",  label = "Next workspace on this monitor",          action = wsStep( 1, false) },
            { id = "ws.prev",          keys = "SUPER + CTRL + left",   label = "Previous workspace on this monitor",      action = wsStep(-1, false) },
            { id = "ws.empty",         keys = "SUPER + CTRL + down",   label = "First empty workspace on this monitor",   action = hl.dsp.focus({ workspace = "emptym" }) },
            { id = "ws.carry.next",    keys = "SUPER + CTRL + ALT + right", label = "Carry window to the next workspace",     action = wsStep( 1, true) },
            { id = "ws.carry.prev",    keys = "SUPER + CTRL + ALT + left",  label = "Carry window to the previous workspace", action = wsStep(-1, true) },
            { id = "ws.scroll",        prefix = "SUPER",               label = "Switch workspace: hold and scroll",       family = "scroll" },
        }},
        { "Session", {
            { id = "session.lock",     keys = "SUPER + L",             label = "Lock",                                   action = exec("qs ipc call lock lock") },
            { id = "session.lock2",    keys = "SUPER + SHIFT + L",     label = "Lock (hyprlock fallback)",               action = exec("pidof hyprlock || hyprlock") },
            { id = "session.sleep",    keys = "SUPER + Pause",         label = "Sleep",                                  action = exec("systemctl suspend"), opts = { locked = true } },
            { id = "session.logout",   keys = "SUPER + End",           label = "Log out",                                action = exec("uwsm stop") },
            { id = "session.reload",   keys = "SUPER + CTRL + R",      label = "Reload Hyprland config",                 action = exec("hyprctl reload") },
        }},
        { "Screenshots", {
            { id = "shot.area",        keys = "Print",                 label = "Copy an area",                           action = exec("grimblast --notify copy area") },
            { id = "shot.flameshot",   keys = "SUPER + Print",         label = "Flameshot on the focused monitor",       action = exec(bin .. "/flameshot-focused") },
            { id = "shot.output",      keys = "SUPER + SHIFT + Print", label = "Save the whole monitor",                 action = exec("grimblast --notify copysave output") },
        }},
        { "Media & brightness", {
            { id = "media.volup",      keys = "XF86AudioRaiseVolume",  label = "Volume up",       action = exec("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), opts = { locked = true, repeating = true } },
            { id = "media.voldown",    keys = "XF86AudioLowerVolume",  label = "Volume down",     action = exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      opts = { locked = true, repeating = true } },
            { id = "media.mute",       keys = "XF86AudioMute",         label = "Mute speakers",   action = exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     opts = { locked = true } },
            { id = "media.micmute",    keys = "XF86AudioMicMute",      label = "Mute microphone", action = exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   opts = { locked = true } },
            { id = "media.play",       keys = "XF86AudioPlay",         label = "Play / pause",    action = exec("playerctl play-pause"),                           opts = { locked = true } },
            { id = "media.next",       keys = "XF86AudioNext",         label = "Next track",      action = exec("playerctl next"),                                 opts = { locked = true } },
            { id = "media.prev",       keys = "XF86AudioPrev",         label = "Previous track",  action = exec("playerctl previous"),                             opts = { locked = true } },
            { id = "media.brightup",   keys = "XF86MonBrightnessUp",   label = "Brightness up",   action = exec("brightnessctl -q s +10%"),                        opts = { locked = true, repeating = true } },
            { id = "media.brightdown", keys = "XF86MonBrightnessDown", label = "Brightness down", action = exec("brightnessctl -q s 10%-"),                         opts = { locked = true, repeating = true } },
        }},
        -- Discord's own keybinds don't work under native Wayland, so these
        -- press its real Mute / Deafen / Go Live buttons through discord-cdp
        -- (debug port), then the RPC bridge, and only when Discord is
        -- unreachable fall back to PipeWire — which keeps the mute key a
        -- working mic key in every other app.
        { "Discord", {
            { id = "discord.mute",     keys = "ALT + apostrophe",      label = "Mute (microphone mute when Discord is closed)", action = exec(scripts .. "/discord-mic.sh") },
            { id = "discord.deafen",   keys = "ALT + I",               label = "Deafen",                                        action = exec(scripts .. "/discord-deafen.sh") },
            { id = "discord.stream",   keys = "ALT + P",               label = "Go Live: stream the running game (else the leftmost monitor)",          action = exec(bin .. "/discord-cdp stream") },
        }},
    }

    -- ── user overrides ────────────────────────────────────────
    -- A flat JSON object of strings, written only by Settings; ids and key
    -- names never contain quotes, so a pattern is a complete parser here.
    local overrides = {}
    local f = io.open(STATE .. "/keybinds.json", "r")
    if f then
        local text = f:read("a") or ""
        f:close()
        for k, v in text:gmatch('"([^"]*)"%s*:%s*"([^"]*)"') do overrides[k] = v end
    end

    local function chord(mods, key)
        if mods == nil or mods == "" then return key end
        return mods .. " + " .. key
    end

    local function bindAll(keys, action, opts)
        local list = type(action) == "table" and action[1] ~= nil and action or { action }
        for _, a in ipairs(list) do hl.bind(keys, a, opts) end
    end

    local manifest = {}
    for _, g in ipairs(GROUPS) do
        local items = {}
        for _, b in ipairs(g[2]) do
            if b.when ~= false then
                local default = b.keys or b.prefix
                local value = overrides[b.id]
                if value == nil then value = default end
                local opts = { description = b.label }
                for k, v in pairs(b.opts or {}) do opts[k] = v end

                if b.keys then
                    if value ~= "" then bindAll(value, b.action, opts) end
                elseif b.family == "number" then
                    for n = 1, WS_PER_MONITOR do
                        local key = tostring(n % 10)
                        bindAll(chord(value, key), wsGo(n, b.carry),
                            { description = (b.carry and "Move window to workspace " or "Workspace ") .. n .. " of the focused monitor" })
                    end
                elseif b.family == "scroll" then
                    bindAll(chord(value, "mouse_down"), hl.dsp.focus({ workspace = "m+1" }), { description = "Next workspace (scroll)" })
                    bindAll(chord(value, "mouse_up"),   hl.dsp.focus({ workspace = "m-1" }), { description = "Previous workspace (scroll)" })
                elseif b.mouse then
                    bindAll(chord(value, b.mouse), b.action, opts)
                end

                local suffix = ""
                if b.family == "number" then suffix = "1…0"
                elseif b.family == "scroll" then suffix = "Scroll"
                elseif b.mouse == "mouse:272" then suffix = "Left drag"
                elseif b.mouse == "mouse:273" then suffix = "Right drag" end
                items[#items + 1] = {
                    id = b.id, label = b.label, kind = b.keys and "keys" or "prefix",
                    keys = value, default = default, suffix = suffix,
                }
            end
        end
        manifest[#manifest + 1] = { name = g[1], items = items }
    end

    -- Key capture in Settings parks Hyprland here so no bind fires while a
    -- new chord is being pressed. Settings leaves it on its own; the chord
    -- below is the way out if the settings window ever dies mid-capture.
    hl.define_submap("keycapture", function()
        hl.bind("SUPER + CTRL + ALT + SHIFT + Escape", hl.dsp.submap("reset"), { description = "leave key capture" })
    end)

    -- ── manifest for Settings and the cheatsheet ──────────────
    local function q(s)
        return '"' .. tostring(s):gsub('[%c"\\]', function(c)
            if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
            return string.format("\\u%04x", c:byte())
        end) .. '"'
    end
    local out = {}
    for _, g in ipairs(manifest) do
        local items = {}
        for _, it in ipairs(g.items) do
            items[#items + 1] = string.format('{"id":%s,"label":%s,"kind":%s,"keys":%s,"default":%s,"suffix":%s}',
                q(it.id), q(it.label), q(it.kind), q(it.keys), q(it.default), q(it.suffix))
        end
        out[#out + 1] = string.format('{"name":%s,"items":[%s]}', q(g.name), table.concat(items, ","))
    end
    pcall(function()
        os.execute("mkdir -p '" .. STATE .. "'")
        local tmp = STATE .. "/keybinds-manifest.json.tmp"
        local mf = io.open(tmp, "w")
        if not mf then return end
        mf:write('{"groups":[' .. table.concat(out, ",") .. ']}\n')
        mf:close()
        os.rename(tmp, STATE .. "/keybinds-manifest.json")
    end)
end
