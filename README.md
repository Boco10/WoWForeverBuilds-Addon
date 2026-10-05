# WoW Forever Builds

In-game companion addon for [World of Warcraft: Forever](https://wowforeverbuilds.com). Talent guides in your talent window, a dungeon quest panel beside the group finder, route guides with waypoints, and one-line character export for [wowforeverbuilds.com](https://wowforeverbuilds.com).

Nothing is sent anywhere. The addon reads your own character and the quest log, and every piece of data it needs ships inside it.

## What it does

### Talent guide in your talent window
- Carries the talent build of every leveling and endgame guide from the site.
- The next talent glows, and pulses while you have a point to spend.
- Talents the guide still wants show the level of their next point; ones it does not take show a red **x**.
- A panel beside the talent window lists the whole order, level by level.
- On level up, chat tells you what to take, and warns you when you spend a point off the guide.

`/wfb guide list` lists the guides for your class, `/wfb guide 3` picks one, `/wfb guide off` turns it off.

### Dungeon Journal beside the group finder
Open the group finder and the **Dungeon Journal** opens next to it, with a **Dungeon Journal** button above the window to show and hide it.

- Follows what you do: queue for a dungeon, tick one in the finder or walk into one, and the journal switches to it. The **Dungeons** button picks any other.
- The quest list on the left shows the level you can pick each quest up at, its faction crest, and **YOU HAVE IT**, **TURN IN**, **DONE** or **PRE-QUEST**. The Alliance and Horde crests at the top switch whose quests are listed.
- Click a quest and the right page reads like the quest log: objective, where it starts (with a **Show on Map** button that puts a pin on the world map), who takes it, notes on sharing and what happens inside, the chain before it, and the rewards with their icons and tooltips.
- A **Bosses** tab lists the dungeon's bosses with the quests that need each one.
- Questlines that open a dungeon chain are listed above it, and your quest log marks those quests with `[D]` or `[D>]`.
- XP for your character: the reward and the dungeon total use your level, by the game's rule (full XP up to 5 levels above the quest, then 80%, 60%, 40%, 20%, 10%). Base figures come from the beta client's quest data.

`/wfb quests` opens the panel from chat.

### Route guides with waypoints
`/wfb route` opens a panel that walks you through an errand the quest log does not point you to, stop by stop.

- The current stop gets a map pin, or a TomTom arrow when TomTom is installed.
- Chat tells you what to do when you arrive, and picking up the stop's quest moves you on to the next one.
- Routes can be faction-specific: each character sees only its own faction's version.
- Progress is kept per character.
- **On the world map:** a **Routes** button in the corner picks a route, and its stops show as numbered pins (green = current, gold = still to do, grey = done) on the zone map and on the continent. Hover a pin for what to do there; click it to make it your current stop.

### Minimap icon
Left click opens the route guides; right click opens a menu with the routes, the Dungeon Journal, a tick to turn the talent guide on or off, the talent window and the character export. Drag it around the minimap. `/wfb minimap` hides or shows it.

The first route is the **Cozy Sleeping Bag** (up to 3% more experience while you rest in it). More routes are added in updates as they are found: hidden quest chains, collectibles and other errands worth the trip. `/wfb route list` lists the routes, `/wfb route next` / `/wfb route back` move between stops, `/wfb route stop` clears the waypoint.

### Settings page
The addon has its own page under **Options → AddOns → WoW Forever Builds** (or `/wfb options`): switch each part on or off, pick your talent guide and your route from a dropdown, and open any panel from there. Switches: minimap icon, talent guide, its order panel and chat messages, the quest panel opening with the group finder, the `[D]` marks in the quest log, the Routes button and pins on the world map, arrival chat, and the TomTom arrow.

### Character export
`/wfb` opens a window with a single line: name, realm, class, race, faction, level, talent points per tree, primary professions and whether you are on a Hardcore realm. Copy it, then paste it on [My characters](https://wowforeverbuilds.com/account/characters) to import.

## Install

Unzip into your AddOns folder so you get:

```
World of Warcraft\_classic_era_\Interface\AddOns\WoWForeverBuilds\WoWForeverBuilds.toc
```

If the addon shows as out of date on the character screen, tick **Load out of date AddOns**.

## Data

Quest, talent and dungeon data comes from the WoW Forever beta client and from the guides on [wowforeverbuilds.com](https://wowforeverbuilds.com). Beta data changes, so the addon is updated as the game is.

## Licence

MIT. See [LICENSE](LICENSE).
