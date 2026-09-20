RGB Sync — sync PC lighting to the Omarchy theme.

## What it does

- Watches the Omarchy theme accent (`qs.Commons Color.accent`) and
  `~/.local/state/omarchy/current/theme.name`, then sets every selected
  OpenRGB device to that colour (hue from accent, saturation from per-theme
  intensity, value from global brightness). Same semantics as Theme Sync in
  `misza.hass`, but the sink is local hardware instead of Home Assistant.
- Syncs a wired Keychron Q3 Pro through its stock QMK/VIA Raw HID interface;
  no unofficial keyboard firmware is required.
- Renders a theme-matched splash (wallpaper backdrop, theme name, live
  liquid/pump readings) onto the NZXT Kraken LCD and refreshes it
  periodically.
- Optional **animated pet overlay**: walks an OpenPets spritesheet on top
  of that wallpaper via NZXT CAM's live LCD stream (`0x09` BGR888), not
  `liquidctl` GIF. The popup includes an animated preview, file picker,
  favorites, and one-click switching.
- Keeps one OpenRGB SDK server alive, avoiding a full 18–40 second hardware
  scan on every theme change. Reconciles once after startup so USB monitors
  whose firmware finishes booting late cannot overwrite the synchronized
  colour.

Click the bar button for the popup: sync toggle, intensity, brightness,
per-device selection, Kraken LCD section, refresh interval.

## Install

```sh
omarchy plugin add https://github.com/misza-one/misza.rgbsync.git --enable
```

## Requirements

- `openrgb` package (provides `/usr/bin/openrgb` and udev rules).
- `liquidctl` on `PATH` for the Kraken LCD (override path in config).
- `python-pillow` for LCD image rendering.
- LCD pet overlay and Keychron Q3 Pro sync need Python `hid`; the LCD stream
  additionally needs `pyusb` and `zenity`. Installing catalog pets by ID needs
  Node.js/npm (`npx`).
- Hardware access: user in `input` + `i2c` groups (or active logind session
  via uaccess). Re-login after adding groups.

```sh
# Arch/Omarchy
sudo pacman -S openrgb i2c-tools python-pillow
pipx install liquidctl   # or: pip install --user liquidctl

# NZXT and Keychron access without re-login (udev/ in this repo)
sudo cp udev/71-nzxt-uaccess.rules /etc/udev/rules.d/
sudo cp udev/72-keychron-q3-pro-uaccess.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=hidraw --subsystem-match=usb

# Verify (no sudo):
openrgb --list-devices
liquidctl list
```

On a fresh machine the service probes all of this at startup and reports
exactly what is missing (`omarchy-shell misza.rgbsync status`, `deps=`).
Unknown hardware picks the first usable OpenRGB mode automatically
(Direct → Static → anything but Off); per-device overrides live in config.

The Keychron Q3 Pro must be connected in wired mode. Bluetooth does not expose
the VIA Raw HID interface used for synchronization.
IPC: `omarchy-shell misza.rgbsync status` / `... refresh`.

## Config

`~/.config/omarchy/misza.rgbsync/config.json`:

```json
{
  "enabled": true,
  "devices": [],
  "deviceModes": {},
  "deviceZones": { "RTX 4090": 0 },
  "intensity": { "vault": { "intensity": 63 } },
  "brightness": 100,
  "refreshInterval": 30,
  "lcdEnabled": true,
  "lcdBrightness": 60,
  "lcdWallpaper": true,
  "lcdDim": 0.5,
  "lcdThemeName": true,
  "lcdTitle": "",
  "lcdTop": "",
  "lcdBottom": "",
  "lcdZoom": 1,
  "lcdPanX": 0,
  "lcdPanY": 0,
  "lcdPet": false,
  "lcdPetPath": "",
  "lcdPetFavorites": [],
  "lcdPetScale": 1,
  "lcdPetX": 0,
  "lcdPetY": 510,
  "liquidctlBinary": "liquidctl"
}
```

- `devices`: substrings matched against OpenRGB names, empty = all.
- `deviceModes`: name substring → OpenRGB mode (default `Direct`).
- `deviceZones`: name substring → zone index. The RTX 4090 Suprim X only
  holds the colour with its zone addressed explicitly (default baked in).
- `intensity`: per-theme saturation 0–100. `brightness`: global value 0–100.
- `refreshInterval`: seconds between refresh ticks (0–30, 0 disables).
  Ticks apply changed RGB colours and refresh LCD readings.
- `lcdDim`: wallpaper brightness 0.1–1. `lcdThemeName`: title on/off.
- `lcdTitle`/`lcdTop`/`lcdBottom`: custom LCD texts (single line, 40 chars).
  Empty title falls back to the theme name; empty lines fall back to
  `LIQUID …` / `PUMP …`. Placeholders: `{theme}` `{liquid}` `{pump}` `{fan}`.
  Edit in the popup (Apply texts) or directly in config.json.
- `lcdZoom` (1–3) + `lcdPanX`/`lcdPanY`: wallpaper framing. The popup shows
  a round live preview — drag to position, zoom with the slider, release
  applies to the pump. `Reset wallpaper view` restores full-bleed.
- `lcdPet`: stream an OpenPets walk on top of the wallpaper (CAM `0x09`).
  Open **Pet library** in the popup. Pets previously installed from a terminal
  with `npx -y install-pet <id>` are discovered automatically under
  **Installed OpenPets** and can be selected with **Use**. You can also paste a
  catalog ID such as `gpt-niang` and click **Install**; this runs the official
  installer, selects the downloaded spritesheet, and adds it to favorites.
  Local PNG/WebP/JPEG sheets work through **Choose file…**. Star favorites,
  switch them with **Use**, or restore the bundled pet. Both full 8×9 OpenPets
  sheets and cropped 8×3 sheets work.
- `lcdPetPath`: selected spritesheet; empty uses the bundled companion.
  `lcdPetFavorites` stores up to 32 absolute paths. `lcdPetScale`,
  `lcdPetX`, and `lcdPetY` control size and walking position.

## Notes

- The RTX 4090 reports mode `[Off]` in `--list-devices` even while lit;
  readback is not trusted, the last applied colour is.
- NZXT Kraken Elite, Keychron Q3 Pro and the Logitech PRO X keyboard are not
  covered by OpenRGB on this machine (Kraken LCD: `liquidctl`, Keychron:
  VIA/QMK).
- A full LCD image push moves ~1 MB over USB bulk and takes tens of seconds;
  the popup status shows the current phase (query/render/push) while busy.
- Disabling leaves the current LED/LCD state untouched.

## Remove

```sh
omarchy plugin remove misza.rgbsync
```
