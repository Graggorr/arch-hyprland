-- ─────────────────────────────────────────────────────────────
--  Hyprland — minimal profile (Lua config; hyprlang `.conf` is
--  deprecated since 0.55).
--  Docs:  https://wiki.hypr.land/Configuring/
--  API:   /usr/share/hypr/stubs/hl.meta.lua  (lua-ls completion)
--  Check: Hyprland --verify-config -c ~/.config/hypr/hyprland.lua
--
--  Nothing here is tied to one machine or one user: monitors are
--  auto-detected, every path is built from $HOME, and each autostart
--  entry is guarded by whether its program is actually installed.
-- ─────────────────────────────────────────────────────────────

local HOME = os.getenv("HOME")

-- ── Monitors ──────────────────────────────────────────────────
-- Any monitor gets a working default. displays.lua, written for this
-- machine's monitors by scripts/monitors.py at first login and on every
-- hotplug, refines them: native resolution at the highest refresh rate, a
-- scale for HiDPI panels, left-to-right positions. Each monitor then owns
-- ten workspaces in that order (1-10, 11-20, ...), which is what SUPER+N in
-- binds.lua and the workspace strip expect.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.0 })

require("monitors-apply")(10)

-- ── Programs ──────────────────────────────────────────────────
local terminal      = "ghostty"
local browser       = "brave"
local fileManager   = "nautilus"
local volumeManager = "pavucontrol"
local scripts       = HOME .. "/.config/hypr/scripts"

hl.on("hyprland.start", function()
    local autostart = {
        "gnome-keyring-daemon --start --components=secrets",
        "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1",
        "nm-applet --indicator",
        "blueman-applet",
        scripts .. "/wallpaper-restore.sh",
        "qs -p " .. HOME .. "/.config/quickshell/shell.qml",
        "hypridle",
        "wl-paste --watch " .. HOME .. "/.config/quickshell/scripts/cliphist-store.sh",
        "playerctld daemon",
        scripts .. "/apply-theme.sh",
        scripts .. "/workspace-apps.sh",
    }
    for _, cmd in ipairs(autostart) do
        hl.exec_cmd(cmd)
    end
end)

hl.env("XCURSOR_THEME", "phinger-cursors-dark")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "phinger-cursors-dark")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

hl.config({
    input = {
        -- Add or reorder layouts here; the toggle is both Ctrl+Shift keys.
        kb_layout          = "us,ua",
        kb_options         = "grp:lctrl_lshift_toggle",
        numlock_by_default = true,
        follow_mouse       = 1,
        mouse_refocus      = false,
        sensitivity        = 0,
        touchpad = {
            natural_scroll       = true,
            disable_while_typing = true,
        },
    },
})

local okColors, colors = pcall(require, "colors")
if not okColors or type(colors) ~= "table" then colors = {} end
local borderActive1  = colors.border_active1  or "rgba(ffb599ee)"
local borderActive2  = colors.border_active2  or "rgba(d4c78eee)"
local borderInactive = colors.border_inactive or "rgba(3d322faa)"

hl.config({
    general = {
        -- No gaps at all: windows run flush to each other, the screen edges
        -- and the bar, and the screen's own rounded corners
        -- (ScreenCorners.qml) frame the whole thing instead of a margin.
        -- The shell applies Settings → Gaps over these at start.
        gaps_in     = 0,
        gaps_out    = 0,
        -- No frame: windows meet the bar and each other directly.
        border_size = 0,
        col = {
            active_border   = { colors = { borderActive1, borderActive2 }, angle = 45 },
            inactive_border = borderInactive,
        },
        layout           = "dwindle",
        resize_on_border = true,
        allow_tearing    = false,
    },

    decoration = {
        rounding           = 10,
        active_opacity     = 1.0,
        inactive_opacity   = 0.95,
        fullscreen_opacity = 1.0,
        blur = {
            enabled           = true,
            size              = 6,
            passes            = 3,
            new_optimizations = true,
        },
        shadow = {
            enabled      = true,
            range        = 12,
            render_power = 3,
            color        = "rgba(00000044)",
        },
    },

    animations = { enabled = true },

    dwindle = { preserve_split = true },

    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
        focus_on_activate        = true,
    },
})

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.animation({ leaf = "windows",    enabled = true, speed = 4, bezier = "easeOutQuint", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4, bezier = "easeOutQuint", style = "slide" })
hl.animation({ leaf = "border",     enabled = true, speed = 6, bezier = "default" })
hl.animation({ leaf = "fade",       enabled = true, speed = 4, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "easeOutQuint", style = "slide" })

-- ── Window rules ──────────────────────────────────────────────
-- Evaluated top to bottom; later rules win.
hl.window_rule({
    name   = "pavucontrol",
    match  = { class = "(.*org.pulseaudio.pavucontrol.*)" },
    float  = true,
    center = true,
    pin    = true,
    size   = { 700, 600 },
})
hl.window_rule({
    name   = "waypaper",
    match  = { class = "(.*waypaper.*)" },
    float  = true,
    center = true,
    pin    = true,
    size   = { 900, 700 },
})
hl.window_rule({
    name   = "blueman",
    match  = { class = "(.*blueman-manager.*)" },
    float  = true,
    center = true,
    size   = { 700, 600 },
})

-- ── Workspaces ────────────────────────────────────────────────
--   1 Web · 2 Chat · 3 Music · 4 Files · 5 Games · 6-9 spare
-- Games are exempt from the compositor's blur and window opacity so a
-- fullscreen game renders at native cost.
hl.window_rule({ name = "no-blur-games",       match = { content = "game" },                             no_blur = true })
hl.window_rule({ name = "no-blur-steam-games", match = { class = "^(steam_app_\\d+|gamescope|.*\\.exe)$" }, no_blur = true })

hl.window_rule({
    name           = "ws2-telegram",
    match          = { class = "^(org.telegram.desktop|TelegramDesktop)$" },
    workspace      = "2 silent",
    suppress_event = "activate",
})
hl.window_rule({ name = "ws3-spotify", match = { class = "^(Spotify)$" }, workspace = "3 silent" })
hl.window_rule({ name = "ws5-steam",   match = { class = "^(steam)$" },   workspace = "5 silent" })

-- ── Shell layers ──────────────────────────────────────────────
-- Everything Quickshell draws (bar, launcher, OSD, notifications, power
-- menu, tray menus, tooltips, lock screen) shares the `quickshell`
-- namespace, so one rule frosts all of it. ignore_alpha is what makes a
-- full-width panel safe: pixels below the threshold are skipped, and the
-- bar is transparent, so the gaps between pills don't paint a blurred
-- rectangle across the screen. 0.25 must stay below every alpha in
-- Theme.qml that is meant to frost — scrimOpacity 0.35 is the lowest.
hl.layer_rule({ name = "quickshell-blur", match = { namespace = "quickshell" }, blur = true, ignore_alpha = 0.25 })
hl.layer_rule({ name = "rofi-blur",       match = { namespace = "rofi" },       blur = true, ignore_alpha = 0.25 })

-- Discord keeps rendering while it is off-screen, so Alt+P can stream from
-- another workspace (Hyprland otherwise stops its frame callbacks).
hl.window_rule({ name = "discord-render-unfocused", match = { class = "^(discord)$" }, render_unfocused = true })

-- ── Keybindings ───────────────────────────────────────────────
-- Every binding lives in binds.lua, the same file the original desktop
-- uses; only the apps it launches are chosen here. Workspaces are per
-- monitor: the leftmost monitor owns 1..10, the next 11..20.
require("binds")({
    terminal      = terminal,
    browser       = browser,
    fileManager   = fileManager,
    volumeManager = volumeManager,
})
