# Prokin-Minimap

Prokin-Minimap is a World of Warcraft addon for **The Burning Crusade Anniversary** that turns the minimap into a square using the same mask approach ElvUI uses for TBC.

## Features

- Square minimap mask using `Interface\ChatFrame\ChatFrameBackground`
- Reports `GetMinimapShape()` as `SQUARE` for addon compatibility
- Reapplies the square mask on world entry, minimap show, and Blizzard hybrid minimap load
- Minimap zoom in and out with the mouse wheel
- Uses a pfUI-style custom zone label with a server-time suffix in `[HH:MM AM/PM]` format, plus runtime-safe suppression of Blizzard minimap header widgets so the floating bar, red X, and duplicate zone text do not appear
- Keeps the Blizzard tracking button, LFG icon, clock, mail icon, and PvP or battleground indicator visible just outside the square minimap border
- Includes MinimapButtonButton compatibility so those Blizzard widgets are not pulled into its collected button tray
- Repositions the AutoMarkAssist minimap button to the square minimap edge without modifying AutoMarkAssist
- Saved minimap size with a default of **400x400**

## Compatibility

- **Game version:** The Burning Crusade Anniversary
- **Interface:** `20505`

## Installation

1. Download or clone this repository.
2. Copy the `Prokin-Minimap` folder into:
   `C:\World of Warcraft\_anniversary_\Interface\AddOns\`
3. Start the game and enable **Prokin-Minimap** in the addon list.

## Usage

- `/pkm` - show the current size and command help
- `/pkm size 400` - set the minimap to an exact square size
- `/pkm larger` - increase size by 25
- `/pkm larger 50` - increase size by a custom step
- `/pkm smaller` - decrease size by 25
- `/pkm smaller 50` - decrease size by a custom step
- `/pkm reset` - restore the default `400x400` size

The custom zone label uses the server clock and appends the current time in the format `[HH:MM AM/PM]`.

## Saved Variables

The addon stores its settings in:

- `ProkinMinimapDB`

## Repository

GitHub: <https://github.com/gnummers/Prokin-Minimap>
