# Loot Tracker

A World of Warcraft: Forever addon (`## Interface: 16001`, Lua 5.1). Standalone: it depends on no other addon; it bundles LibStub, CallbackHandler-1.0 and LibSharedMedia-3.0 under `LootTracker/Libs` (loaded first; `## OptionalDeps: LibSharedMedia-3.0, SharedMedia` so another copy loads before it). The addon folder is `LootTracker/`. It is the standalone version of Pillars UI's Loot Tracker module (cloudfan/PillarsUI, `PillarsUI_LootTracker`): `Names.lua`, `Tracking.lua`, `Auction.lua` and `View.lua` are that module's files with `local API = ns.API` and the global names renamed (`LootTracker...`); keep them in step with the module.

## Layout

- `LootTracker/Core.lua`: `ns.API`, the framework calls those files make, written for this addon alone: settings by section (`RegisterDefaults`, `Get` / `Set`, `ClearSection`; only changed values kept, in `LootTrackerSettings`), events (`On`, one frame) and messages (`Listen` / `Fire`), `OnReady`, `Print`, `IsSecret` / `Plain`, colors (`ResolveColor`, color settings `{ preset = ... }`), media through LibSharedMedia (`API.LSM`; `MediaList` is its list, `Fetch` its file; the game's own fonts, bar textures and backgrounds in `MEDIA` are registered into it where it lacks their file, and still resolve by our names; with no LSM, `MEDIA` alone; `ApplyFont`), a bordered panel (`CreateInsetBorder`: a tooltip-style backdrop), dragging (`RegisterMover` / `RefreshMover`: a handle over the frame while unlocked, `SetUnlocked`, positions in the `positions` section), `NewScrollBar` (Pillars UI's) and `ShowCopyBox`. Pillars UI-only calls (`RegisterAnchor`, `RegisterBoxPanel`, `IsModuleLoaded`) do nothing, so the Data Box placement never applies.
- `LootTracker/Settings.lua`: the settings, a canvas panel in Blizzard's options (`Settings.RegisterCanvasLayoutCategory`, else `InterfaceOptions_AddCategory`) with controls of our own, in a scroll frame; `/lt` and `/loottracker` (the game keeps `/loot` for its own loot window).
- `LootTracker/Media/PortraitRing.tga`: Pillars UI's portrait ring.

## Rules

- No combat log, no `GetSpellInfo` / `GetItemInfo` (vendor value is `C_Item.GetItemInfo`'s sell price). Guard secret values with `API.IsSecret` / `API.Plain`.
- With Pillars UI's Loot Tracker module loaded (`PillarsUI_LootTracker`), this addon stands down (`ns.standingDown`, checked on every event): no tracking, its frame hidden.
- Saved data is its own (`LootTrackerDB` per character; `LootTrackerNames`, `LootTrackerPrices`, `LootTrackerSettings` account-wide); it never reads Pillars UI's (the owner's choice).
- Keep the README's settings table in step with the defaults in `View.lua` and the controls in `Settings.lua`.
- Check syntax with `luac5.1 -p` on every Lua file before committing.
- Releases: bump `## Version` in `LootTracker/LootTracker.toc`.
