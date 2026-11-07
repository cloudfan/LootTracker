# Loot Tracker

What you loot and from what, for World of Warcraft: Forever (`## Interface: 16001`). Standalone: needs no other addon. It bundles LibSharedMedia-3.0, so fonts, bar textures and backgrounds that other addons register (SharedMedia packs, UI suites) can be picked in its settings, beside the game's own. It is the standalone version of [Pillars UI](https://github.com/cloudfan/PillarsUI)'s Loot Tracker module; with that module turned on, this addon stays off (use one of the two).

- **Sources:** creatures (each looted corpse a kill, grouped by creature or listed one by one), their skinning and pickpocketing (their own entries, or in the creature's), chests, lockboxes, resource nodes (Copper Veins together, Peaceblooms together) and fishing (by zone, or schools by type). No combat log: the loot window says where each item and coin came from.
- **Value:** gold beside each source's name, with its items' vendor value, or their auction value from a scan of your realm's auction house (once every 15 minutes, at the auction house).
- **View:** items as a list colored by quality, or a grid of icons, each with its tooltip; background bars; sorting by quality, newest or value; optional round portraits (the creature's model).
- **Names:** creatures and world objects are named by ID, account-wide, even when the game hides names in an instance; hovering a source shows its NPC, object or item ID.
- **Per entry:** a click on a source folds its loot; its X deletes it.
- **Menu (the arrow by the title):** track this session or this instance only, export to a box to copy, export the name database, reset all.
- **Frame:** its own, with an arrow beside it that hides it and pops it out. `/loot unlock` to drag it, `/loot lock` after.

Data is kept per character (`LootTrackerDB`: the last 300 loots, and totals that never drop); names and auction prices are account-wide (`LootTrackerNames`, `LootTrackerPrices`), settings too (`LootTrackerSettings`).

## Settings

Options > AddOns > Loot Tracker, or `/loot`.

| Section | Setting | Default | What it does |
|---|---|---|---|
| Tracking | Grouping | Grouped | Grouped (merged by ID) or Individualized (each loot, the last 300). |
| Tracking | Show | All Time | All Time, This Session (since login) or This Instance (the current run). Also in the title's menu. |
| Tracking | Creatures, Chests, Lockboxes, Disenchanting, Resource Nodes, Fishing | On | What is tracked. Disenchanting's loot goes into one entry, Disenchanted. |
| Tracking | Only What You Receive | On | An item counts only once the game says you received it: in a group, what someone else takes or wins the roll for, and what you leave behind, is not counted; a roll you win counts for its source. Where the game hides those lines, your bag counts stand in. Gold counts as your purse grows: your share in a group. |
| Tracking | Merge Skinning, Merge Pickpocketing | Off | Into the creature's entry instead of their own. |
| Tracking | Fishing Grouping | By Zone | By Zone, or Separated (schools by type). |
| Tracking | Export, Export Name Database, Reset All Loot | | A copy box of the entries; of the learned names; forget everything (asks first). |
| View | Item Value | Vendor Value | Vendor Value, Auction Value or None. |
| View | View | List | List or Icons. |
| View | Update prices while browsing | On | Every item the auction house's Buy page shows, and the listings you open, update its price, with no full scan. |
| View | Scan button on the Buy page | On | A Scan AH button by the auction house's Search button, counting down the game's 15 minutes between scans. |
| View | Scan when the auction house opens, Scan Now | Off | A full scan when you open the auction house (it can stall the game a moment), or now. |
| View | Stack value on item lines | On | List view: each stack's auction value beside its count (gray: vendor value, with Vendor Fallback). |
| View | Price each on item lines | Off | List view: one item's auction price beside its count. |
| View | Stack value on item icons | Off | Icons view: the stack's auction value on each icon. |
| View | Short values | On | Lines and icons: the largest coin only (12g, 34s, 56c). |
| View | Vendor Fallback | On | Items with no auction price show their vendor price, in gray. |
| View | Auction price in item tooltips | On | An item's tooltip: its auction price right under the game's Sell Price, in the same style, or "not listed". |
| View | Stack's auction price in item tooltips | On | A second tooltip line with the looted stack's auction price (Auction Price (x4)), for stacks of more than one. |
| View | Price's age in item tooltips | On | An item's tooltip: how long ago its auction price was seen (browsing or a full scan). |
| View | In every item tooltip | Off | The auction price and last scan's age in every item tooltip (bags, links, the bank, vendors), not only the tracker's; outside the tracker, the price of one item. |
| View | Item Sort, Source Sort | Quality, Newest | Quality / Newest / Value; Newest / Value. |
| View | Item icons in the list, Icon Size | On, 28 | |
| View | Scroll Bar, Scroll Bar Width | On, 6 | |
| View | Portraits (experimental) | Off | |
| Background Bars | Source Row Bars, Item Line Bars | Off, Off | Bars behind source rows (both views) and item lines (List view). |
| Background Bars | Source Row Texture, Item Line Texture | Blizzard | Any SharedMedia bar texture. |
| Background Bars | Source Row Color / Opacity | Bronze, 35% | |
| Background Bars | Line Bar Color, Custom Line Color | Item Quality | |
| Background Bars | Line Bar Length, Line Bar Opacity | Full Width, 25% | Full Width or By Count. |
| Text | Font, Text Shadow | Friz Quadrata, Soft | Any SharedMedia font; None, Soft, Outline, Thick Outline. |
| Text | Text Size | Auto | 0 (Auto) to 24. |
| Frame | Unlock (drag it) | Off | Also `/loot unlock`. |
| Frame | Arrow Side | Right | |
| Frame | Width, Height | 260, 320 | |
| Frame | Border, Background, Background Opacity | On, Solid, 80% | Any SharedMedia background. |
| Frame | Reset Position, Reset All Settings | | |

## Slash commands

- `/loot` or `/loottracker`: settings.
- `/loot show`, `/loot hide`, `/loot toggle`: the tracker.
- `/loot unlock`, `/loot lock`: drag it, then lock it.
- `/loot export`: the entries in a copy box.
- `/loot scan`: scan the auction house (it must be open).
- `/loot probe`: what this client offers, in a copy box.

## Install

Copy the `LootTracker` folder (the one holding `LootTracker.toc`) into `World of Warcraft\_classic_beta_\Interface\AddOns\` and restart the client.
