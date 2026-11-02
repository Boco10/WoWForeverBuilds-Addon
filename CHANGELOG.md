# Changelog

## 1.7.2

- Paladin, Druid, Mage, Holy and Discipline Priest and Beast Mastery Hunter guides are re-planned around the live talents instead of only patched to stay legal: Shieldsworn for Protection, Oath of Light for Holy, Unsealed Wrath and Champion of the Light for Retribution, Lacerate for bears, Bloom for Restoration, Arcane Wrath and Precision for Mage, Holy Binding for group Priests.
- Duo guides no longer say Paladins are Alliance-only or Shamans Horde-only.

## 1.7.1

- Talent guides follow the live launch client (1.60.1.70707) and its server hotfixes. Those hotfixes rework the Paladin and Druid trees and retune Mage, Priest and Hunter talents. Every affected built-in order has been refitted, including all Paladin and Mage endgame guides.
- Dungeon Journal: Upper Blackrock Spire has its own page, with the Classic quest list by faction. The quest-giver notes are filled in for Dalaran, the Drowned City, Razorfen Downs, Uldaman, the Scarlet Monastery wings and Blackrock Depths. Three quests whose XP the client no longer lists show no XP.

## 1.7.0

- Talent guides follow the final beta talent trees (client 1.60.1.70532). Talents that were removed or moved have been replaced with the closest talent still in the tree, so 95 of the 140 built-in orders changed.
- The nine class leveling guides now run from level 10 to 60 with all 51 points. Levels 31-60 are projected from the final beta client and have not been played yet.
- Dungeon Journal quest data refreshed to quest cache build 70338: 159 Forever quests, 4 of them new. Quests whose XP the source no longer lists show no XP instead of an old value.

## 1.6.1

- Cozy Sleeping Bag route: the Stonewrought Dam stop now names the chain's quests (Wet Bags, then Eagle's Fist) and warns about the missing-quest bug, the Horde route flags the two guarded stretches into Loch Modan, and the notes cover the layer-change bug that leaves the bag behind with its cooldown still running, plus the chain's 12-slot bag and Student Fodder.

## 1.6.0

- The Dungeon Quest helper is now the **Dungeon Journal**: a two-page window with the dungeon's quests on the left and the picked quest on a parchment page on the right, laid out like the quest log.
- The quest page shows the objective, where it starts with a **Show on Map** button (a map pin when our notes give coordinates, otherwise the zone), who takes it, notes on sharing, the chain before it, and the rewards with item icons, tooltips and shift-click links.
- Alliance and Horde crests at the top of the list switch whose quests are shown; quests both factions can take are always listed.
- New **Bosses** tab: the dungeon's bosses (the Classic list, or the encounter names from the beta client for new dungeons) and the quests that need each one.
- **XP for your character**: the reward and the "to earn" total now use your level, by the game's rule (full XP up to 5 levels above the quest, then 80%, 60%, 40%, 20%, 10%; none at the level cap). The "XP is inaccurate" note is gone: the base XP comes from the beta client's quest data.
- **Show on Map** now puts a quest pin on the world map (hover for who and where, right click to remove), plus a TomTom arrow when TomTom is installed. Quest givers the beta has been seen with have exact spots; the turn-in NPC gets its own button. Quests without a known spot show **Show zone** and only open the zone.
- Quest data refreshed to beta quest cache build 70170: 37 more quests, including Scarlet Monastery, Razorfen Kraul, City of Dalaran and the Excavation Site.

## 1.5.2

- Fixed: shift-clicking a quest in the Dungeon Quest helper sent plain white text. Quests in your log now go out as a real quest link; the server does not allow links to other quests, so those send the quest name and its wowforeverbuilds.com address instead.
- 14 dungeon quests now show the pre-quest you need first, e.g. Raptor Horns before Smart Drinks (Wailing Caverns), The Day After before Gnogaine (Gnomeregan), and several in Blackrock Depths, Lower Blackrock Spire, Dire Maul and Stratholme.

## 1.5.1

- Dungeon Quest helper: **shift-click** a quest to put its link in chat, **ctrl-click** it for a box with its wowforeverbuilds.com page to copy with Ctrl+C. The open quest also shows its web address.
- The helper sits a little further from the group finder, so the finder's side tabs are no longer covered.

## 1.5.0

- New: **route guides**. `/wfb route` opens a panel that walks you through an errand stop by stop, with a map pin (or a TomTom arrow) on the current stop. Chat tells you what to do when you arrive, and picking up the stop's quest moves you on. Progress is kept per character.
- The world map gets a **Routes** button: pick a route there and its stops show as numbered pins on the zone and continent maps. Hover a pin for what to do, click it to make it your current stop.
- New **minimap icon**: left click opens the route guides, right click a menu with everything the addon does (routes, Dungeon Quest helper, talent guide on/off, talent window, character export). Drag to move it; `/wfb minimap` hides or shows it.
- New **settings page** under Options → AddOns → WoW Forever Builds (or `/wfb options`): on/off switches for the minimap icon, the talent guide and its panel and chat messages, the quest panel opening with the group finder, the `[D]` quest log marks, the world map pins, arrival chat and the TomTom arrow — plus dropdowns to pick your talent guide and your route.
- Fixed: the Dungeon Quest helper opened from chat, the minimap or the settings page closed itself straight away when the group finder was not open. It now stays open until you close it.
- The talent window button on the settings page and in the minimap menu opens the Forever talent window (the Talents tab of the new spellbook).
- The route panel is laid out for reading: a progress bar, numbered stop cards (the current one open, the rest open on click, done ones ticked), a solid background, and the video and write-up links in text boxes you can copy with Ctrl+C.
- The Dungeon Quest helper gets the same look as the route panel: a solid background, the dungeon name as a large title, a progress bar for the quests you have done, card rows with the quests you are on highlighted, and gold section headings.
- First route: the **Cozy Sleeping Bag** — Westfall, the Barrens, Stonetalon, Loch Modan and the Hillsbrad jumping puzzle, as separate Alliance and Horde routes: each faction only sees its own. Rest in the bag for up to 3% more experience. The route comes from Zen's (OSWguild) beta video and is not confirmed by us yet.

## 1.4.1

- The level 20 beta talent guides follow what players found on the first beta weekend: Frost Mages take the Frostbite and Ice Lance build, and Feral Druids level in Bear Form until Cat Form arrives at 20.

## 1.4.0

- The quest panel now covers every dungeon on the chart up to level 60: Uldaman, Zul'Farrak, Maraudon, Sunken Temple, Blackrock Depths, Lower Blackrock Spire, all three Dire Maul wings, Scholomance, both sides of Stratholme, Razorfen Downs and the four Scarlet Monastery wings. 27 dungeons and 326 quests, up from 10 and 66.
- The beta has not shown those instances yet, so their lists come from the Classic quest database and the panel says so: the dungeon line reads "Classic list, not seen on the beta yet". Where the beta covers a dungeon only partly — Gnomeregan, Razorfen Kraul, the Stockade, Blackfathom Deeps — the filled-in quests carry a "from the Classic list" tag of their own.
- Class-only quests, such as the Dire Maul librams and the warlock and paladin dungeon quests, are tagged with the class that can take them.

## 1.3.5

- Fixed the Lua error that appeared every time you accepted a quest ("QuestLogTags.lua:154: attempt to call a nil value"). Accepting a quest now simply re-marks the dungeon quests in the log.

## 1.3.4

- Quest data refreshed from the beta: the panel now knows 66 dungeon quests instead of 56.
- New in the panel: the four Stormwind Stockade quests (What Comes Around..., Crime and Punishment, Quell the Uprising, The Color of Blood), both Allegiance to the Old Gods steps in Blackfathom Deeps, A Fine Mess and Gnomer-gooooone! in Gnomeregan, Willix the Importer in Razorfen Kraul, and the second version of The Glowing Shard for Wailing Caverns.
- Chain information filled in for The Unsent Letter, The Stockade Riots and Chief Engineer Scooty, so their prerequisites and follow-ups now show.

## 1.3.3

- Built for WoW Forever only: the addon now declares game version 1.60.1 and no longer lists Classic Era 1.15.7.

## 1.3.2

- Registered on CurseForge, so releases upload there as well as to GitHub.

## 1.3.1

- The quest panel is now called **wowforeverbuilds - Dungeon Quest helper**, and its button on the group finder reads **Quest helper**.
- The XP column is marked with an asterisk and the panel says the figures are inaccurate: they come from earlier versions of the game, and real WoW Forever values will replace them.

## 1.3.0 — first public release

Everything the addon does today, released together.

### Dungeon quest panel
- Opens beside the group finder, with a **Dungeon quests** button above the window to show and hide it.
- Follows the dungeon you queue for, tick in the finder, or walk into.
- Columns: quest, where to pick it up, pick-up level, experience, sharing and status.
- Quests you cannot share are marked with the reason: an item starts them, or they follow another quest.
- Faction markers on every quest, with the other faction's quests listed separately.
- Steps that happen inside the dungeon are marked, including quest-starting items that drop inside.
- Click a quest for its whole chain, including the questline that opens it.
- Finished quests move into their own block, and the quest log marks dungeon quests with `[D]` or `[D>]`.
- Running experience totals for the quests in your log, what is left and the dungeon's full total.

### Talent guide
- Every leveling and endgame build from wowforeverbuilds.com, shown in the talent window.
- Next talent glows, off-guide picks are warned about, and a panel lists the order level by level.

### Character export
- `/wfb` gives one line to paste into My characters on the site.
- Reads WoW Forever's C_Traits talents and the retail-style profession API.
- Multi-word character names are supported.
