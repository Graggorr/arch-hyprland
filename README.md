# arch-hyprland

A complete Hyprland desktop for Arch Linux: a Quickshell bar with a dynamic
island, a control center, a dock, a lock screen, notifications, a wallpaper-
driven colour scheme, and the scripts behind them. One command installs it.
After that a timer keeps the desktop config in step with this repo and merges
in any edits you made yourself.

The repo holds configuration only. It contains no accounts, no keys and no
calendars. Everything that needs a login (Discord, Google, iCloud, Spotify)
is set up on your own machine with your own credentials and stays there.

---

## Install

On a fresh Arch install, logged in as your normal user (not root):

```bash
sudo pacman -S --needed git
git clone https://github.com/Graggorr/arch-hyprland.git ~/arch-hyprland
cd ~/arch-hyprland
./install.sh
```

The repo is public, so cloning over HTTPS needs no GitHub account, SSH key or
token. The hourly updater fetches the same way.

Options:

```bash
./install.sh --no-gaming          # skip Steam, gamescope, gamemode, multilib
./install.sh --no-office          # skip LibreOffice, PDF viewer, printing
./install.sh desktop dotfiles     # re-run individual steps
```

The steps run in order: `packages`, `desktop`, `dotfiles`, `system`, `sync`.
Each is a standalone script and safe to re-run. Before overwriting, they save
your existing config to `~/.config/.desktop-backups/<timestamp>/`.

When it finishes, log out and pick **Hyprland (uwsm-managed)** at the login
screen.

---

## What you get

| | |
|---|---|
| Desktop | Hyprland, Quickshell bar + dynamic island + control center + dock, rofi as a fallback launcher |
| Theming | Wallpaper-driven: the bar, GTK, Qt, rofi, the terminal and the lock screen are recoloured from the wallpaper (`Super+W`) |
| Apps | Brave, Telegram, Discord, Spotify, Claude Desktop, VLC, Nautilus, Loupe, File Roller, pavucontrol, Seahorse, Flameshot, GPU Screen Recorder |
| Calendar | Google / iCloud calendars and Google Tasks in the island (your own accounts, see below) |
| Discord | Mute, deafen and Go Live from global hotkeys, even while Discord is unfocused |
| Gaming | Steam, gamescope, gamemode, MangoHud, multilib |
| Office | LibreOffice, Papers (PDF), CUPS printing |
| Shell | fish with oh-my-posh, ghostty, btop, fastfetch, eza |

---

## Keys

`Super + /` opens the shortcut cheatsheet with every binding. The most used:

| Key | Action |
|---|---|
| `Super + Enter` | terminal |
| `Super + Space` | app launcher |
| `Super + S` | settings |
| `Super + W` | theme switcher · `Super+Shift+W` random wallpaper · `Super+Ctrl+W` wallpaper browser |
| `Super + V` | clipboard history |
| `Super + B` / `Super + E` | browser / file manager |
| `Super + Q` / `F` / `M` / `T` | close / fullscreen / maximize / float |
| `Super + 1…0` | workspace 1–10 of the focused monitor (a second monitor owns 11–20) |
| `Super + Shift + 1…0` | move the window there |
| `Super + L` | lock · `Super + End` log out · `Super + Pause` sleep |
| `Print` / `Super + Print` | area to clipboard / Flameshot on this monitor |
| `Alt + '` / `Alt + I` / `Alt + P` | Discord mute / deafen / Go Live |
| `Alt + Z` | GPU Screen Recorder overlay (record, replay, screenshot; its own hotkey) |

All bindings live in `~/.config/hypr/binds.lua`. Which terminal, browser, file
manager and mixer they launch is set at the top of
`~/.config/hypr/hyprland.lua`.

---

## Discord

The `Discord` launcher this repo installs starts Discord with a local debug
port (`--remote-debugging-port=9285`). `~/.local/bin/discord-cdp` uses that
port to press Discord's own Mute, Deafen and Go Live buttons, which works on
Wayland, where Discord's built-in global keybinds do not. Start Discord from
the launcher (or the dock) rather than another way, or the port is not open.

- `Alt + '`: Discord mute, or plain microphone mute when Discord is not running
- `Alt + I`: Discord deafen
- `Alt + P`: start or stop streaming your leftmost monitor (pick another one
  with `DISCORD_STREAM_OUTPUT=<output>`; `hyprctl monitors` lists the names)

**Optional: call status in the island.** The island can show your Discord mute
and deafen state through Discord's RPC socket. That needs a Discord
application of your own (it takes a minute and it's free):

1. <https://discord.com/developers/applications> → New Application.
   Under OAuth2, add the redirect `http://localhost`.
2. Write its Application ID into the config, and store its Client Secret in
   your keyring:
   ```bash
   echo '{"client_id":"<your application id>"}' > ~/.config/quickshell/discord-rpc.json
   secret-tool store --label='Discord RPC' service discord-rpc key client_secret
   python3 ~/.config/quickshell/scripts/discord-rpc.py auth
   ```
3. Approve the popup in Discord. The token is stored in
   `~/.local/state/quickshell/` and refreshed automatically.

---

## Calendar

The island's calendar reads your own calendars from local copies that
`vdirsyncer` keeps in sync: Google Calendar, iCloud Calendar and Google Tasks.
Nothing is connected until you run the guided setup:

```bash
calendar-setup
```

It walks you through creating your own Google OAuth app (the console steps
are spelled out in the terminal) and an iCloud app-specific password. Every
credential goes into your login keyring, never into a file in this repo.
Then turn on background sync:

```bash
systemctl --user enable --now vdirsyncer.timer
```

`calendar-subscribe` adds read-only feeds (sports schedules, public holidays)
by URL.

---

## Things to change by hand

- **Keyboard layouts**: `kb_layout` in `~/.config/hypr/hyprland.lua` (default
  `"us,ua"`, both Ctrl+Shift keys switch).
- **Monitors**: auto-detected. To arrange several, use `nwg-displays` or edit
  the `hl.monitor` line.
- **Weather city**: `wxCity` in `~/.config/quickshell/IslandState.qml` (the
  sinoptik.ua city slug, default `kyiv`).
- **Autostarted apps**: `~/.config/hypr/scripts/workspace-apps.sh`.

Edits like these survive updates (see below).

---

## Keeping it updated

Apps are installed once and update with the system (`yay -Syu`). The desktop
config (`~/.config/{hypr,quickshell,rofi,wlogout,waypaper,matugen}`) keeps
following this repo:

```
repo push ──> desktop-sync.timer ──> update.sh ──> install-desktop.sh --update
              (3 min after login,    git pull      build, then patch ~/.config
               then hourly)          --ff-only
```

Each update is first built into a scratch directory and checked with
`Hyprland --verify-config`, and only then patched in. A commit that fails the
check changes nothing on your machine and raises a "Desktop update failed"
notification.

The patch is a three-way merge against the version applied last time
(`~/.local/state/desktop-sync/base`):

| The repo changed the file | You changed the file | Result |
|---|---|---|
| no | — | left exactly as it is |
| yes | no | replaced with the repo version |
| yes | yes | merged; your edit and the repo's both survive |
| yes | yes, same lines | repo version wins; yours is saved in `~/.config/.desktop-backups/<timestamp>-update/` |
| deleted | no | deleted |

Files the desktop writes for itself (palettes, the chosen wallpaper and theme)
are never touched. Afterwards Hyprland is reloaded, and the shell restarts if
its files changed. While the screen is locked the restart waits until the next
run.

```bash
~/arch-hyprland/update.sh            # pull and patch now
~/arch-hyprland/update.sh --force    # rebuild and patch even with no new commit
journalctl --user -u desktop-sync    # what the timer did
```

`~/.local/bin` scripts and other dotfiles are installed once. To pick up newer
versions, run `./install.sh dotfiles` (it backs up anything it replaces).

---

## What is deliberately not installed

- **No git identity, SSH keys or `~/.gitconfig`**: those are yours to set.
- **No autologin**: logging in at SDDM lets PAM unlock your keyring, so stored
  passwords work without a prompt.
- **No fstab, bootloader, initramfs or Secure Boot changes**:
  `install-system.sh` only touches portable things (locale, udev rules for
  CPU power readings, systemd-oomd, gamemode) and enables NetworkManager,
  Bluetooth and SDDM.
