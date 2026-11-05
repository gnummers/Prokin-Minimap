# Prokin-Minimap

Prokin-Minimap is a World of Warcraft addon for **The Burning Crusade Anniversary** and **World of Warcraft: Forever** that turns the minimap into a square using the same mask approach ElvUI uses for TBC.

## Features

- Square minimap mask using `Interface\ChatFrame\ChatFrameBackground`
- Reports `GetMinimapShape()` as `SQUARE` for addon compatibility
- Reapplies the square mask on world entry, minimap show, and Blizzard hybrid minimap load
- Minimap zoom in and out with the mouse wheel
- Uses a pfUI-style custom zone label with a server-time suffix in `[HH:MM AM/PM]` format, plus runtime-safe suppression of Blizzard minimap header widgets so the floating bar, red X, and duplicate zone text do not appear
- Adds a draggable Prokin minimap button bordering the minimap with left-click role check, right-click options, and a hover tooltip that lists the current party or raid roles
- Shows the current session Gold Per Hour (GPH) in the Prokin minimap button tooltip
- Uses TradeSkillMaster-style item pricing when available, with vendor fallback if TradeSkillMaster is not installed
- Tracks gold income and expenses including repairs, postage, and crafting material costs
- Calculates inventory worth and maintains per-character ledgers
- Automatically tracks disenchanting transactions (item loss vs. dust/shard gain)
- Thanks to the TradeSkillMaster authors for the pricing model inspiration
- Adds always-visible Blizzard-style tracking and LFG proxy buttons just outside the square minimap border without letting MinimapButtonButton collect them into its tray
- Keeps the Blizzard mail icon visible only while unread mail is waiting
- Keeps the Blizzard PvP or battleground button outside the square minimap border only when battlefield state is active, while preserving Blizzard's native secure queue interactions
- Lets you left-drag the visible Blizzard minimap widgets around the outside edge of the square minimap border
- Includes MinimapButtonButton compatibility so those Blizzard widgets are not pulled into its collected button tray
- Repositions the AutoMarkAssist minimap button to the square minimap edge without modifying AutoMarkAssist
- Gives the Prokin button, LibDBIcon addon buttons, Blizzard tracking button, and Forever day/night icon one size and lines them up along the left border, with an option to turn this off and a slider for the spacing between them
- Resizable zone text, from the options window or `/pkm zonetext`
- With icon alignment off, lets you left-drag the Forever day/night icon anywhere on the minimap
- Saved minimap size with a default of **400x400**

## Compatibility

- **Game versions:** The Burning Crusade Anniversary, World of Warcraft: Forever
- **Interface:** `20506`, `16001`

On Forever, Blizzard's native queue eye replaces the LFG proxy button, so it appears only while queued and cannot be dragged. Blizzard's calendar button stays hidden, as it does on Anniversary.

## Installation

1. Download or clone this repository.
2. Copy the `Prokin-Minimap` folder into:
   `C:\World of Warcraft\_anniversary_\Interface\AddOns\` or `C:\World of Warcraft\_forever_\Interface\AddOns\`
3. Start the game and enable **Prokin-Minimap** in the addon list.

## Usage

- `/pkm` - show the current size and command help
- `/pkm size 400` - set the minimap to an exact square size
- `/pkm larger` - increase size by 25
- `/pkm larger 50` - increase size by a custom step
- `/pkm smaller` - decrease size by 25
- `/pkm smaller 50` - decrease size by a custom step
- `/pkm reset` - restore the default `400x400` size
- `/pkm zonetext 14` - set the zone text size, from 8 to 32
- `/pkm zonetext reset` - restore the default zone text size
- `/pkm resetmoon` - restore the default position of the Forever day/night icon when icon alignment is off
- `/pkm options` - open the Prokin Minimap options window

### Gold Tracking Commands

The Gold Tracker provides detailed income and expense tracking:

- `/pkm ledger` - display your current character's ledger (income, expenses, breakdown)
- `/pkm ledger <character-name>` - display a specific character's ledger
- `/pkm expenses [limit]` - show recent expense history (default 10 entries)
- `/pkm allcharacters` - display ledger summary for all characters on your account

The tooltip on the Prokin minimap button displays:
- **GPH**: Gold Per Hour (net income)
- **Session Income**: Total gold earned
- **Session Expense**: Total gold spent (repairs, postage, materials)
- **Session Net**: Net income after expenses
- **Daily Total**: Daily income
- **Daily Expense**: Daily expenses
- **Daily Net**: Daily net income
- **Inventory Worth**: Total value of items in your bags

The custom zone label uses the server clock and appends the current time in the format `[HH:MM AM/PM]`.

Left-drag the visible Blizzard minimap widgets to reorganize them around the square border. Their positions are saved in `ProkinMinimapDB`, the tracking proxy still opens Blizzard's tracking menu when clicked, and the battleground queue button now uses Blizzard's native button directly so queue actions stay protected.

The Prokin minimap button starts a role check on left-click, opens the options window on right-click, and can be repositioned with Alt + Left Drag. Its tooltip shows each party or raid member's assigned role.

## Gold Tracking System

The Gold Tracker provides comprehensive expense tracking alongside income tracking:

### Tracked Expense Categories

1. **Repairs** - Costs from repairing armor and weapons
2. **Postage** - Mail postage fees
3. **Crafting Materials** - Value of items consumed when crafting
4. **Disenchanting** - Loss from disenchanting items (gain from dust/shards is tracked as income)
5. **Item Loss** - Other item losses not categorized
6. **Other Expenses** - Miscellaneous gold spending

### How Tracking Works

- **Income** is tracked from:
  - Looting gold and items
  - Quest rewards
  - Vendor sales
  - Mail items and gold
  - Disenchant dust/shards

- **Expenses** are tracked from:
  - NPC repairs automatically detected via `GetRepairAllCost()`
  - Mail postage via `GetSendMailPrice()`
  - Crafting materials based on inventory changes
  - Item transactions automatically tracked through inventory snapshots

- **Inventory Worth** is calculated by:
  - Scanning all bags
  - Using TSM pricing (dbmarket) when available
  - Falling back to vendor prices if TSM is not installed

## Saved Variables

The addon stores its settings in:

- `ProkinMinimapDB`

## Repository

GitHub: <https://github.com/gnummers/Prokin-Minimap>

## License

Licensed under the GNU Affero General Public License version 3 (AGPLv3). See [LICENSE](LICENSE).
