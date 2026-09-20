# WoW Forever Builds

In-game companion addon for [World of Warcraft: Forever](https://wowforeverbuilds.com). Talent guides in your talent window, a dungeon quest panel beside the group finder, and one-line character export for [wowforeverbuilds.com](https://wowforeverbuilds.com).

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
