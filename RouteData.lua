-- Route guides: errands across the world that the quest log does not point you to.
-- Written by hand from the source each route names. Coordinates are map percentages (0-100).
-- map is the Classic uiMapID; the addon checks it against the zone name and searches by name if the
-- Forever client numbers its maps differently.
-- side ("alliance" or "horde") shows a route to that faction only; leave it out for both.
-- links are shown as copyable addresses. quests is how many quests a stop hands out (default 1), so the guide moves on only after the last one.
local _, ns = ...

local SLEEPING_BAG_ABOUT = {
  "Lay the bag down and rest in it: every minute inside adds 1% experience, stacking to 3%.",
  "Stacks with the 5% from cooked food and counts for quest experience too.",
  "One hour cooldown. You lose the buff if you die, so mind it before a dungeon.",
  "Best done around level 20: it is a long run across both continents, and it pays off for the rest of the climb to 60.",
}
-- Shown as copyable text boxes in the panel.
local SLEEPING_BAG_LINKS = {
  { label = "Video by Zen (OSWguild) — the route this guide follows", url = "https://www.youtube.com/watch?v=t3FClbeBIOc" },
  { label = "Our write-up on wowforeverbuilds.com", url = "https://wowforeverbuilds.com/news/the-cozy-sleeping-bag-route-in-wow-forever-five-zones-a-jumping-puzzle-and-a-3-x" },
}
local SLEEPING_BAG_UNCONFIRMED = "Beta route from one tester's video. We have not run it ourselves, and beta content can change before launch."

local STONETALON = "Follow the narrow path up the mountain to an abandoned camp and take the quest there: it gives you the tools to relight the campfire. Then, over the small hill, run and jump along the path to the dirt mound for the next quest (it also hands out a ranged weapon and ammo if your class can use them)."
local HILLSBRAD = "Go to the wall between Hillsbrad and the Arathi Highlands and stay on the Hillsbrad side. Climb the small jumping puzzle (press jump first, then move forward). At the top a small bag hangs on the wall: click it for the Cozy Sleeping Bag."

ns.routes = {
  {
    slug = "cozy-sleeping-bag-alliance",
    side = "alliance",
    name = "Cozy Sleeping Bag",
    level = 20,
    item = "Cozy Sleeping Bag",
    reward = "Cozy Sleeping Bag: +1% experience for each minute you rest in it, up to 3%",
    about = SLEEPING_BAG_ABOUT,
    links = SLEEPING_BAG_LINKS,
    unconfirmed = SLEEPING_BAG_UNCONFIRMED,
    steps = {
      {
        zone = "Westfall", map = 1436, x = 37.0, y = 50.0,
        title = "Alexston Farmstead",
        text = "Your route starts here. In the middle of the ruined farmstead, click the note in the wreckage to get the quest.",
      },
      {
        zone = "The Barrens", map = 1413, x = 46.0, y = 74.0,
        title = "South of Camp Taurajo",
        text = "Horde ground: take the boat to Ratchet and grab the flight path there. Just south of Camp Taurajo there is a patch of wreckage: click the note there for the next quest.",
      },
      {
        zone = "Stonetalon Mountains", map = 1442, x = 40.6, y = 52.4, quests = 2,
        title = "Abandoned camp up the mountain",
        text = STONETALON .. " The entrance from the Barrens is guarded by the Horde, so you can come in through Ashenvale instead.",
      },
      {
        zone = "Loch Modan", map = 1432, x = 49.4, y = 12.9,
        title = "Stonewrought Dam",
        text = "Do not jump straight off the dam. There is one spot to drop down onto, and it is easy to overshoot: drop carefully, then take the quest below.",
      },
      {
        zone = "Hillsbrad Foothills", map = 1424, x = 87.3, y = 49.6,
        title = "The wall at the Arathi border",
        text = HILLSBRAD .. " From the dam, fly to Refuge Pointe or Southshore, or hearth, and ride over.",
      },
    },
  },
  {
    slug = "cozy-sleeping-bag-horde",
    side = "horde",
    name = "Cozy Sleeping Bag",
    level = 20,
    item = "Cozy Sleeping Bag",
    reward = "Cozy Sleeping Bag: +1% experience for each minute you rest in it, up to 3%",
    about = SLEEPING_BAG_ABOUT,
    links = SLEEPING_BAG_LINKS,
    unconfirmed = SLEEPING_BAG_UNCONFIRMED,
    steps = {
      {
        zone = "The Barrens", map = 1413, x = 46.0, y = 74.0,
        title = "South of Camp Taurajo",
        text = "Your route starts here. Just south of Camp Taurajo there is a patch of wreckage: click the note there to get the quest.",
      },
      {
        zone = "Westfall", map = 1436, x = 37.0, y = 50.0,
        title = "Alexston Farmstead",
        text = "Alliance ground: take the boat from Ratchet to Booty Bay and run north through Stranglethorn and Duskwood. In the middle of the ruined farmstead, click the note in the wreckage for the next quest.",
      },
      {
        zone = "Stonetalon Mountains", map = 1442, x = 40.6, y = 52.4, quests = 2,
        title = "Abandoned camp up the mountain",
        text = STONETALON .. " Back on Horde ground: the Barrens entrance is the easy way in, and you probably have the flight paths already.",
      },
      {
        zone = "Loch Modan", map = 1432, x = 49.4, y = 12.9,
        title = "Stonewrought Dam",
        text = "Deep in Alliance ground, so expect guards on the way in. Do not jump straight off the dam: there is one spot to drop down onto, and it is easy to overshoot. Drop carefully, then take the quest below.",
      },
      {
        zone = "Hillsbrad Foothills", map = 1424, x = 87.3, y = 49.6,
        title = "The wall at the Arathi border",
        text = HILLSBRAD .. " Tarren Mill is the closest Horde flight path.",
      },
    },
  },
}
