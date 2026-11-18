-- ─────────────────────────────────────────────────────────────
-- Keybindings, shared by every machine that runs this desktop.
--
-- hyprland.lua calls this module with the few things that differ per
-- machine (which terminal, browser, file manager, mixer). Everything else
-- — every key, every IPC call, the per-monitor workspace scheme — lives
-- only here, so a binding added once reaches all of them.
-- ─────────────────────────────────────────────────────────────

return function(ctx)
    local HOME    = os.getenv("HOME")
    local scripts = HOME .. "/.config/hypr/scripts"
    local bin     = HOME .. "/.local/bin"
    local mainMod = "SUPER"
    local WS_PER_MONITOR = ctx.wsPerMonitor or 10

    local function bind(keys, dispatcher, opts) hl.bind(keys, dispatcher, opts) end
    local function exec(cmd) return hl.dsp.exec_cmd(cmd) end
    local function exists(path)
        local f = io.open(path, "r")
        if f then f:close() return true end
        return false
    end

    -- Applications
    bind(mainMod .. " + Return",          exec(ctx.terminal),      { description = "terminal (" .. ctx.terminal .. ")" })
    bind(mainMod .. " + B",               exec(ctx.browser),       { description = "browser (" .. ctx.browser .. ")" })
    bind(mainMod .. " + E",               exec(ctx.fileManager),   { description = "file manager (" .. ctx.fileManager .. ")" })
    bind(mainMod .. " + space",           exec("qs ipc call island toggle apps"), { description = "app launcher (island)" })
    bind(mainMod .. " + SHIFT + space",   exec("pkill rofi || rofi -show drun -i"), { description = "app launcher (rofi fallback)" })
    bind(mainMod .. " + CTRL + Return",   exec("qs ipc call island toggle apps"), { description = "app launcher (island)" })
    bind(mainMod .. " + V",               exec(bin .. "/clipboard-paste-picker.sh"),            { description = "clipboard history (copies + auto-pastes into focused window)" })
    bind(mainMod .. " + CTRL + V",        exec(ctx.volumeManager),                              { description = "volume manager (per-app mixer)" })
    bind(mainMod .. " + W",               exec("qs ipc call island toggle themes"),             { description = "theme switcher (island carousel)" })
    bind(mainMod .. " + SHIFT + W",       exec("qs ipc call wallpaper random"),                 { description = "random wallpaper within each monitor's theme" })
    bind(mainMod .. " + S",               exec("qs ipc call settings toggle"),                  { description = "settings (quickshell)" })
    if exists(scripts .. "/we-picker.sh") then
        bind(mainMod .. " + ALT + W",     exec(scripts .. "/we-picker.sh"),                     { description = "Wallpaper Engine (animated) picker" })
    end
    bind(mainMod .. " + CTRL + W",        exec("qs ipc call wallpaper toggle"),                 { description = "wallpaper browser by theme" })
    bind(mainMod .. " + slash",           exec("qs ipc call island toggle keys"),               { description = "shortcut cheatsheet (quickshell)" })

    -- Window management
    bind(mainMod .. " + Q", hl.dsp.window.close(),                              { description = "close window" })
    bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }),  { description = "fullscreen" })
    bind(mainMod .. " + M", hl.dsp.window.fullscreen({ mode = "maximized" }),   { description = "maximize" })
    bind(mainMod .. " + T", hl.dsp.window.float(),                              { description = "toggle floating" })
    bind(mainMod .. " + J", hl.dsp.layout("togglesplit"),                       { description = "toggle split direction" })
    bind(mainMod .. " + P", hl.dsp.window.pseudo(),                             { description = "pseudo-tile" })
    bind(mainMod .. " + G", hl.dsp.group.toggle(),                              { description = "toggle window group (tabbed)" })
    -- Move focus
    bind(mainMod .. " + left",  hl.dsp.focus({ direction = "l" }), { description = "focus window left" })
    bind(mainMod .. " + right", hl.dsp.focus({ direction = "r" }), { description = "focus window right" })
    bind(mainMod .. " + up",    hl.dsp.focus({ direction = "u" }), { description = "focus window up" })
    bind(mainMod .. " + down",  hl.dsp.focus({ direction = "d" }), { description = "focus window down" })
    -- Swap windows
    bind(mainMod .. " + ALT + left",  hl.dsp.window.swap({ direction = "l" }), { description = "swap window left" })
    bind(mainMod .. " + ALT + right", hl.dsp.window.swap({ direction = "r" }), { description = "swap window right" })
    bind(mainMod .. " + ALT + up",    hl.dsp.window.swap({ direction = "u" }), { description = "swap window up" })
    bind(mainMod .. " + ALT + down",  hl.dsp.window.swap({ direction = "d" }), { description = "swap window down" })
    -- Resize active window
    bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x =  100, y =    0, relative = true }), { repeating = true, description = "resize window wider" })
    bind(mainMod .. " + SHIFT + left",  hl.dsp.window.resize({ x = -100, y =    0, relative = true }), { repeating = true, description = "resize window narrower" })
    bind(mainMod .. " + SHIFT + down",  hl.dsp.window.resize({ x =    0, y =  100, relative = true }), { repeating = true, description = "resize window taller" })
    bind(mainMod .. " + SHIFT + up",    hl.dsp.window.resize({ x =    0, y = -100, relative = true }), { repeating = true, description = "resize window shorter" })
    -- Move/resize with mouse
    bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "move window (drag, left button)" })
    bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "resize window (drag, right button)" })
    -- Cycle windows
    bind("ALT + Tab", hl.dsp.window.cycle_next(), { repeating = true, description = "cycle windows" })
    bind("ALT + Tab", hl.dsp.window.bring_to_top(), { description = "bring cycled window to front" })

    -- Session / system
    bind(mainMod .. " + L",         exec("qs ipc call lock lock"),           { description = "lock (quickshell)" })
    bind(mainMod .. " + SHIFT + L", exec("pidof hyprlock || hyprlock"),      { description = "lock (hyprlock fallback)" })
    bind(mainMod .. " + Pause",     exec("systemctl suspend"),               { locked = true, description = "sleep (same path as the power tool and the idle timeout)" })
    bind(mainMod .. " + CTRL + R",  exec("hyprctl reload"),                  { description = "reload config" })
    bind(mainMod .. " + End",       exec("uwsm stop"),                       { description = "log out (uwsm brings the session down in order)" })
    bind(mainMod .. " + CTRL + B",  exec("qs ipc call bar toggle"),          { description = "toggle bars" })
    bind(mainMod .. " + SHIFT + B", exec(bin .. "/qs-restart"),              { description = "restart shell" })
    bind(mainMod .. " + SHIFT + N", exec("qs ipc call notifications toggle"), { description = "notification panel (quickshell)" })
    bind(mainMod .. " + Home",      exec("qs ipc call notifications dnd"),   { description = "silent mode (do not disturb) on/off" })

    -- Screenshots
    bind("Print",                       exec("grimblast --notify copy area"),        { description = "quick area copy" })
    bind(mainMod .. " + Print",         exec(bin .. "/flameshot-focused"),           { description = "Flameshot capture focused monitor" })
    bind(mainMod .. " + SHIFT + Print", exec("grimblast --notify copysave output"),  { description = "full-output save" })

    -- Workspaces — per-monitor SUPER+N. Monitors are ranked left to right by
    -- their x position: the first owns workspaces 1..10, the second 11..20,
    -- and so on. Only the focused monitor switches; the others keep theirs.
    local function wsRange()
        local active = hl.get_active_monitor()
        local rank = 0
        if active then
            for _, m in ipairs(hl.get_monitors()) do
                if m.enabled ~= false and not m.is_mirror and m.x < active.x then
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

    -- SUPER+N / SUPER+SHIFT+N: nth workspace of the focused monitor (0 → 10th)
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

    for n = 1, WS_PER_MONITOR do
        local key = tostring(n % 10)   -- 10 maps to key 0
        bind(mainMod .. " + " .. key,            wsGo(n, false), { description = "workspace " .. n .. " of the focused monitor" })
        bind(mainMod .. " + SHIFT + " .. key,    wsGo(n, true),  { description = "move window to workspace " .. n .. " of the focused monitor" })
    end
    bind(mainMod .. " + CTRL + right",       wsStep( 1, false), { description = "next workspace (per-monitor cycle)" })
    bind(mainMod .. " + CTRL + left",        wsStep(-1, false), { description = "previous workspace (per-monitor cycle)" })
    bind(mainMod .. " + CTRL + down",        hl.dsp.focus({ workspace = "emptym" }), { description = "first empty workspace on this monitor" })
    bind(mainMod .. " + CTRL + ALT + right", wsStep( 1, true),  { description = "carry window to next workspace" })
    bind(mainMod .. " + CTRL + ALT + left",  wsStep(-1, true),  { description = "carry window to previous workspace" })
    -- Scroll through workspaces (m± = stay on the scrolled monitor)
    bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "m+1" }), { description = "next workspace (scroll)" })
    bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "m-1" }), { description = "previous workspace (scroll)" })

    -- Media / brightness keys
    bind("XF86AudioRaiseVolume",  exec("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),  { locked = true, repeating = true, description = "volume up" })
    bind("XF86AudioLowerVolume",  exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),       { locked = true, repeating = true, description = "volume down" })
    bind("XF86AudioMute",         exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),      { locked = true, description = "mute speakers" })
    bind("XF86AudioMicMute",      exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),    { locked = true, description = "mute microphone" })
    bind("XF86AudioPlay",         exec("playerctl play-pause"),                            { locked = true, description = "play / pause" })
    bind("XF86AudioNext",         exec("playerctl next"),                                  { locked = true, description = "next track" })
    bind("XF86AudioPrev",         exec("playerctl previous"),                              { locked = true, description = "previous track" })
    bind("XF86MonBrightnessUp",   exec("brightnessctl -q s +10%"),                         { locked = true, repeating = true, description = "brightness up" })
    bind("XF86MonBrightnessDown", exec("brightnessctl -q s 10%-"),                         { locked = true, repeating = true, description = "brightness down" })

    -- Discord's own keybinds don't work under native Wayland, so these toggle its
    -- real Mute / Deafen switches through discord-cdp (debug port), then the RPC
    -- bridge, and only when Discord is unreachable fall back to PipeWire — which
    -- keeps Alt+' a working mic key in every other app.
    --   Alt+'  -> Discord mute, else toggle microphone mute
    --   Alt+I  -> Discord deafen, else mute mic + Discord's audio together
    bind("ALT + I",          exec(scripts .. "/discord-deafen.sh"), { description = "Discord deafen (PipeWire fallback)" })
    bind("ALT + apostrophe", exec(scripts .. "/discord-mic.sh"),    { description = "Discord mute / microphone mute" })
    -- Alt+P -> toggle Go Live of the leftmost monitor: discord-cdp clicks
    -- Discord's own share buttons over its debug port (Discord is started with
    -- --remote-debugging-port=9285) and pre-answers the portal picker.
    bind("ALT + P",          exec(bin .. "/discord-cdp stream"),   { description = "Discord: toggle streaming the main monitor" })
end
