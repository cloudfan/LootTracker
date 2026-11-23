# Loot Tracker

What you loot and from what, for World of Warcraft: Forever (`## Interface: 16001`). Standalone: needs no other addon. It is the standalone version of CRPGui's Loot Tracker module (in [Pillars UI](https://github.com/cloudfan/PillarsUI)); with that module, or Pillars UI's own, turned on, this addon stays off (use one of the two).

- **Sources:** creatures (each looted corpse a kill, grouped by creature or listed one by one), their skinning and pickpocketing (their own entries, or in the creature's), chests, lockboxes, resource nodes (Copper Veins together, Peaceblooms together; each gathering of a node counts, so an ore vein's several loots all do) and fishing (by zone, or schools by type). No combat log: the loot window says where each item and coin came from.
- **Value:** gold beside each source's name, with its items' vendor value, or their auction value from a scan of your realm's auction house (once every 15 minutes, at the auction house).
- **View:** items as a list colored by quality, or a grid of icons, each with its tooltip; any font (it bundles LibSharedMedia-3.0, so fonts SharedMedia packs and other addons register can be picked), shadow and size.
- **Window:** in the look of Blizzard's group loot history window: a flat panel with a scrolling list, a total at the bottom and a resize grip. In its title bar: a close button, a lock button (locked: no dragging by the title, no resizing) and an arrow that opens a menu of the settings used most. Each source has a row with its portrait (the creature's model) or an icon, its name and its value; each item has a row under it, colored by quality, with its tooltip and auction price.
- **Names:** creatures and world objects are named by ID, account-wide, even when the game hides names in an instance; hovering a source shows its NPC, object or item ID.
- **Per entry:** a click on a source folds its loot; its X deletes it.
- **Menu (the arrow in the title bar):** this session or this instance only, grouping, item value, sorting, portraits, scan, export, export the name database, all settings, reset all.

Data is kept per character (`LootTrackerDB`: the last 300 loots, and totals that never drop); names and auction prices are account-wide (`LootTrackerNames`, `LootTrackerPrices`), settings too (`LootTrackerSettings`).

## Settings

Options > AddOns > Loot Tracker, or `/lt`.

| Section | Setting | Default | What it does |
|---|---|---|---|
| Window | Show or Hide the Window |  | Its close button hides it; this (or `/lt show`) brings it back. |
| Window | Lock the window | Off | No dragging by the title, no resizing. Also the lock button in its title bar, and `/lt lock` / `/lt unlock`. |
| Window | Creature portraits | On | A small 3D model of each creature beside its name. |
| Window | Shows | All Time | All Time, This Session (since login; a reload carries on) or This Instance (the current run). Also in the title bar's menu. |
| Window | Grouping | By Source | By Source (merged by ID) or Each Loot (the last 300). |
| Window | Sort Sources, Sort Items | Newest First, By Quality | Newest First / By Value; By Quality / Newest First / By Value. |
| View | View | List | List (a line per item in its quality's color) or Icons (a grid of item icons with their counts). Also in the title bar's menu. |
| View | Item icons in the list | On | List view: each item's icon before its name. |
| View | Icon Size | 24 | Icons view. |
| View | Stack value on item icons | Off | Icons view: the stack's auction value on each icon (gray: vendor price). |
| Text | Font, Text Shadow | Friz Quadrata, Soft | Any font, the game's or one SharedMedia packs add; None, Soft, Outline, Thick Outline. |
| Text | Text Size | Auto | 0 (Auto) to 24: the item lines' size, the rest in step. |
| Window | Reset Position |  | The window back to the right of the screen. |
| What Is Tracked | Only what you receive | On | An item counts once the game says you received it, and gold once your purse grows, so lost rolls and others' shares never count. Where the game hides those lines, your bag counts stand in. |
| What Is Tracked | Creatures, Chests, Lockboxes, Disenchanting, Resource nodes, Fishing | On | What is tracked. Disenchanting's loot goes into one entry, Disenchanted. |
| What Is Tracked | Skinning / Pickpocketing in the creature's entry | Off | Into the creature's entry instead of their own. |
| What Is Tracked | Fishing Entries | By Zone | By Zone, or Schools Separately. |
| Value | Item Value | Auction | Auction (the last scan's lowest buyout, vendor value where there is none), Vendor or None. |
| Value | Scan Now |  | At the auction house: a full scan (the game allows one every 15 minutes). |
| Value | Scan button at the auction house | On | A Scan AH button left of the auction house's filter button, counting down the game's 15 minutes. |
| Value | Scan when the auction house opens | Off | A full scan each time it opens (it can stall the game a moment). |
| Value | Learn prices while browsing | On | Every item the Buy page shows, and the listings you open, update its price. |
| Value | Auction price in our item tooltips | On | Under the game's Sell Price, in the tooltip of an item in the tracker, with the stack's price and the price's age. |
| Value | Auction price in every item tooltip | Off | Those lines in bags, links and everywhere else too. |
| Data | Export, Export Name Database |  | A copy box of the entries; of the learned names. |
| Data | Reset All Loot, Reset All Settings |  | Forget everything tracked on this character; every setting back to its default (both ask first). |

## Slash commands

- `/lt` or `/loottracker`: settings.
- `/lt show`, `/lt hide`, `/lt toggle`: the tracker.
- `/lt unlock`, `/lt lock`: let the window be dragged by its title and resized, or not.
- `/lt export`: the entries in a copy box.
- `/lt scan`: scan the auction house (it must be open).
- `/lt probe`: what this client offers, in a copy box.

## Install

Copy the `LootTracker` folder (the one holding `LootTracker.toc`) into `World of Warcraft\_classic_beta_\Interface\AddOns\` and restart the client.
