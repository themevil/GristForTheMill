# Grist for the Mill

A profession companion for World of Warcraft: Forever. Pick the recipes you want to make and the addon works out the materials, shows where each one comes from, and tracks your progress until you can craft.

## What it does

- **Reagent browser.** Every reagent your professions use, with the recipes it goes into, the recipes that make it, and where to find it.
- **Farming list.** Set a goal for an item or for a number of crafts. A small tracker window shows what you have and what is still missing.
- **Crafting window.** Track recipes, see what they require (anvil, cooking fire, tools), and craft from the list once the materials are in your bags.
- **Sources and directions.** Vendors, drops, gathering nodes, fishing spots and trainers, nearest first, with a side map and TomTom arrows. Clicking the arrow of a nearby NPC also targets and marks it.
- **Bag tools.** Coloured borders on reagents by skill-up value, a Bag Reagents window to sell, trade or delete in bulk, and sell protection that asks before a reagent you still need goes to a vendor.
- **Vendor prompt.** When a vendor sells something on your lists, the addon offers to buy the missing amount.

## Install

1. Download the latest release.
2. Extract it so the folder is `World of Warcraft\_forever_\Interface\AddOns\GristForTheMill`.
3. Restart the game.

## Requirements

- World of Warcraft: Forever (interface 16001).
- Optional addons, each adding a feature when installed:
  - **Questie**: where items are sold, dropped and gathered.
  - **TomTom**: direction arrows.
  - **Auctionator**: auction house prices.

## Commands

- `/grist` opens the main window.
- The minimap button opens the main window; right-click it for the Farming, Crafting and Bag Reagents windows.

## Data

- Recipes and map art references are generated from the game's own data tables for World of Warcraft: Forever, exported through [wago.tools](https://wago.tools).
- Source locations are read at run time from Questie when it is installed. Nothing from Questie is included in this addon.
- The required skill for recipes taught by a trainer is not part of the game's client data, so those recipes show no skill requirement.

## Licence

Released under the MIT Licence; see [LICENSE](LICENSE).

World of Warcraft is a trademark of Blizzard Entertainment, Inc. This addon is not affiliated with or endorsed by Blizzard Entertainment.
