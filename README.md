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

### Dungeon Quest helper beside the group finder
Open the group finder and the **wowforeverbuilds - Dungeon Quest helper** panel opens next to it, with a **Quest helper** button above the window to show and hide it.

- Follows what you do: queue for a dungeon, tick one in the finder or walk into one, and the panel switches to it.
- Columns for the quest, where you pick it up, the level you can pick it up at, its experience reward, whether it can be shared, and your progress.
- Quests are grouped: what you still have to do, what you have finished, and the other faction's quests.
- Each quest is marked `[A]`, `[H]` or `[A/H]`, and quests that cannot be shared say why: an item starts them, or they follow another quest.
- Steps that happen inside the dungeon are marked: given inside, drops inside, hand in inside, do inside, or at the entrance.
- Click a quest for the whole chain: where to pick it up, what it asks for, who takes it, and every step with your progress.
- Questlines that open a dungeon chain are listed above it, and your quest log marks those quests with `[D]` or `[D>]`.
- Running totals: what the quests in your log are worth, what the dungeon still owes you, and the full total. Experience figures come from earlier versions of the game and are marked as estimates until real WoW Forever values are collected.

`/wfb quests` opens the panel from chat.

### Route guides with waypoints
`/wfb route` opens a panel that walks you through an errand the quest log does not point you to, stop by stop.

- The current stop gets a map pin, or a TomTom arrow when TomTom is installed.
- Chat tells you what to do when you arrive, and picking up the stop's quest moves you on to the next one.
- Routes can be faction-specific: each character sees only its own faction's version.
- Progress is kept per character.
- **On the world map:** a **Routes** button in the corner picks a route, and its stops show as numbered pins (green = current, gold = still to do, grey = done) on the zone map and on the continent. Hover a pin for what to do there; click it to make it your current stop.

### Minimap icon
Left click opens the route guides; right click opens a menu with the routes, the Dungeon Quest helper, a tick to turn the talent guide on or off, the talent window and the character export. Drag it around the minimap. `/wfb minimap` hides or shows it.

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
