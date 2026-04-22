# Gear Track Colorizer

A World of Warcraft addon (Midnight) that colors your equipped gear slots and bag item slots based on their upgrade track, so you can see at a glance what tier each piece is at.

## Features

- **Character frame borders** — colored borders on each equipped slot matching the item's upgrade track
- **Bag item borders** — colored borders on gear in your bags (Blizzard bags and third-party addons like ArkInventory, Bagnon, etc.)
- **Tooltip badge** — a colored "Track: X" line added to item tooltips
- **Crafted gear support** — crafted gear (quality stars, no track name) is colored by item level
- **Maxed detection** — Myth gear at max upgrade (6/6) shows a distinct color so you know nothing is left to upgrade
- **Legendary support** — Legendary quality items show their own color
- **Customizable** — change any track color, reset to defaults, and adjust border thickness

## Track Colors (defaults)

| Track | Color |
|-------|-------|
| Explorer | Gray |
| Adventurer | Green |
| Veteran | Blue |
| Champion | Purple |
| Hero | Yellow |
| Myth | Red |
| Maxed (Myth 6/6) | White |
| Legendary | Orange |

## Settings

Open via **Esc → Interface → AddOns → Gear Track Colorizer**.

- **Enable addon** — toggle all coloring on/off
- **Color borders in bags** — toggle bag item borders independently
- **Border Thickness** — slider from 1 to 6 px (default 4)
- **Track Colors** — color swatch per track with individual and bulk reset buttons

## Slash Commands

| Command | Action |
|---------|--------|
| `/gtc on` | Enable the addon |
| `/gtc off` | Disable the addon |
| `/gtc reload` | Force-refresh all borders |

## Notes

- Compatible with Blizzard's default bag UI and third-party bag addons
- For third-party bag addons, borders appear after hovering one item the first time the bag is opened in a session (bootstraps frame discovery)
- Borders on the character frame appear when you open the character sheet

## Installation

1. Download the latest release zip
2. Extract to `World of Warcraft/_retail_/Interface/AddOns/GearTrackColorizer`
3. Reload or restart WoW
