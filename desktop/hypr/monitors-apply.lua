-- ─────────────────────────────────────────────────────────────
-- Applies ~/.config/hypr/displays.lua, shared by every machine.
--
-- displays.lua belongs to the machine, not to the repo: it is written by
-- scripts/monitors.py (first login, hotplug) and by Settings → Displays,
-- and hand edits are welcome. It returns
--   { signature = "…", monitors = { { output, mode, position, scale,
--     transform, vrr, disabled }, … } }
-- Each entry goes to hl.monitor as is. Workspaces follow the left-to-right
-- (then top-to-bottom) order of the enabled monitors' positions: the first owns 1-10, the next
-- 11-20, and so on — the ranges SUPER+N (binds.lua) and the workspace strip
-- use.
--
-- loadfile, not require: a typo in the file must only skip it, not raise a
-- config error (require reports one even inside pcall), and must never make
-- the desktop updater reject hyprland.lua.
--
-- Returns the number of monitors it placed; 0 means the caller's own
-- defaults are in charge.
-- ─────────────────────────────────────────────────────────────

return function(wsPerMonitor)
    local HOME = os.getenv("HOME")
    local per = wsPerMonitor or 10

    -- Keep the file in step with what is plugged in: at login and on every
    -- hotplug monitors.py files the current layout under its combination
    -- and restores (or generates) the one for the new combination.
    local function sync() hl.exec_cmd(HOME .. "/.config/hypr/scripts/monitors.py --auto") end
    hl.on("hyprland.start", sync)
    hl.on("monitor.added", sync)
    hl.on("monitor.removed", sync)

    local chunk = loadfile(HOME .. "/.config/hypr/displays.lua")
    if not chunk then return 0 end
    local ok, spec = pcall(chunk)
    if not ok or type(spec) ~= "table" or type(spec.monitors) ~= "table" then return 0 end

    local placed = {}
    for _, m in ipairs(spec.monitors) do
        if type(m) == "table" and type(m.output) == "string" and m.output ~= "" then
            if pcall(hl.monitor, m) and not m.disabled then placed[#placed + 1] = m end
        end
    end

    local function at(m)
        local x, y = tostring(m.position or ""):match("^(-?%d+)x(-?%d+)")
        return tonumber(x) or 0, tonumber(y) or 0
    end
    table.sort(placed, function(a, b)
        local ax, ay = at(a)
        local bx, by = at(b)
        if ax ~= bx then return ax < bx end
        return ay < by
    end)
    for rank, m in ipairs(placed) do
        for i = 1, per do
            hl.workspace_rule({ workspace = tostring((rank - 1) * per + i), monitor = m.output, default = (i == 1) or nil })
        end
    end
    return #placed
end
