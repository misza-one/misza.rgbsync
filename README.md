RGB Sync — sync PC lighting to the Omarchy theme.

## What it does

- Watches the Omarchy theme accent (`qs.Commons Color.accent`) and
  `~/.local/state/omarchy/current/theme.name`, then sets every selected
  OpenRGB device to that colour (hue from accent, saturation from per-theme
  intensity, value from global brightness). Same semantics as Theme Sync in
  `misza.hass`, but the sink is local hardware instead of Home Assistant.
- Renders a theme-matched splash (wallpaper backdrop, theme name, live
  liquid/pump readings) onto the NZXT Kraken LCD and refreshes it
  periodically.
- A refresh timer re-applies both paths, healing missed triggers and
  firmware that drifts back to stock effects.

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
- Hardware access: user in `input` + `i2c` groups (or active logind session
  via uaccess). Re-login after adding groups.

```sh
# Arch/Omarchy
sudo pacman -S openrgb i2c-tools python-pillow
pipx install liquidctl   # or: pip install --user liquidctl

# NZXT Kraken / RGB Controller access without re-login (udev/ in this repo)
sudo cp udev/71-nzxt-uaccess.rules /etc/udev/rules.d/
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
  "liquidctlBinary": "liquidctl"
}
```

- `devices`: substrings matched against OpenRGB names, empty = all.
- `deviceModes`: name substring → OpenRGB mode (default `Direct`).
- `deviceZones`: name substring → zone index. The RTX 4090 Suprim X only
  holds the colour with its zone addressed explicitly (default baked in).
- `intensity`: per-theme saturation 0–100. `brightness`: global value 0–100.
- `refreshInterval`: seconds between refresh ticks (0–30, 0 disables).
  Ticks re-apply RGB when it drifted and refresh LCD readings.
- `lcdDim`: wallpaper brightness 0.1–1. `lcdThemeName`: title on/off.
- `lcdTitle`/`lcdTop`/`lcdBottom`: custom LCD texts (single line, 40 chars).
  Empty title falls back to the theme name; empty lines fall back to
  `LIQUID …` / `PUMP …`. Placeholders: `{theme}` `{liquid}` `{pump}` `{fan}`.
  Edit in the popup (Apply texts) or directly in config.json.
- `lcdZoom` (1–3) + `lcdPanX`/`lcdPanY`: wallpaper framing. The popup shows
  a round live preview — drag to position, zoom with the slider, release
  applies to the pump. `Reset wallpaper view` restores full-bleed.

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
