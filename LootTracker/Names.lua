local addonName, ns = ...

-- Creature names by NPC ID, shipped with the addon: the Loot Tracker's last
-- fallback (after the names learned in game, LootTrackerNames) for
-- creatures looted where their names are hidden, in instances. Filled from
-- the tracker's menu: Export Name Database, pasted in here.
ns.KNOWN_NAMES = {
}

-- World object names by object ID (chests, containers, nodes, schools,
-- other spawns), the fallback after the names learned in game. Filled the
-- same way, from the export's second list.
ns.KNOWN_OBJECTS = {
}
