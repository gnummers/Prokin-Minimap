# Prokin-Minimap

Prokin-Minimap is a World of Warcraft addon for **The Burning Crusade Anniversary** that turns the minimap into a square using the same mask approach ElvUI uses for TBC.

## Features

- Square minimap mask using `Interface\ChatFrame\ChatFrameBackground`
- Reports `GetMinimapShape()` as `SQUARE` for addon compatibility
- Reapplies the square mask on world entry, minimap show, and Blizzard hybrid minimap load
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

## Saved Variables

The addon stores its settings in:

- `ProkinMinimapDB`

## Repository

GitHub: <https://github.com/gnummers/Prokin-Minimap>
