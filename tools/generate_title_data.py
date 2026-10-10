#!/usr/bin/env python3
"""Writes Data/TitleData.lua (each title's expansion and activity) from Blizzard's game data, as
published by wago.tools.

Run it after a patch that adds titles, check the titles it lists as untagged, add them to
OVERRIDES below, and commit the result:

    python3 tools/generate_title_data.py            # current live (retail) build
    python3 tools/generate_title_data.py 12.1.0.69933

Blizzard's data doesn't say where a title comes from, so the tags are worked out in this order
(later steps win):
  1. Titles rewarded by an achievement ("Title: The Kingslayer") take the activity from the
     achievement's category (and its dungeon or raid), and the expansion from the category when
     it names one ("Lich King Raid").
  2. Other titles are matched by name with RULES (e.g. "... Gladiator" is PvP).
  3. OVERRIDES set or correct titles by hand, by their English name.
  4. A title still without an expansion takes it from ID_RANGES: titles were added in release
     order, apart from a few old IDs given to new titles (those are in OVERRIDES).
Titles that are still without an activity show under Other.

The tables used:
  CharTitles            the titles (Mask_ID is the ID the game's title functions use)
  Achievement           achievements with their reward text, category and dungeon or raid
  Achievement_Category  the achievement categories
  Map                   dungeons and raids (to tell raids from dungeons)
"""
import csv
import io
import json
import re
import sys
import urllib.request
from pathlib import Path

WAGO = "https://wago.tools"
OUTPUT = Path(__file__).resolve().parent.parent / "Data" / "TitleData.lua"

# Expansions, as in the game's EXPANSION_NAME0..11.
CLASSIC, TBC, WRATH, CATA, MOP, WOD, LEGION, BFA, SL, DF, TWW, MIDNIGHT = range(12)

# Activities, in the order of the filter menu (see Data/Titles.lua for their names in game).
ACTIVITIES = [
    "raid", "dungeon", "delves", "pvp", "worldEvents", "reputation", "quests", "exploration",
    "professions", "petBattles", "skyriding", "collections", "features", "featsOfStrength", "other",
]

# Achievement categories (top level) and the activity of their titles. Feats of Strength, Legacy
# and Guild are sorted by their subcategory first (see activity_for).
TOP_CATEGORY_ACTIVITY = {
    "Player vs. Player": "pvp",
    "Delves": "delves",
    "World Events": "worldEvents",
    "Reputation": "reputation",
    "Quests": "quests",
    "Exploration": "exploration",
    "Professions": "professions",
    "Pet Battles": "petBattles",
    "Collections": "collections",
    "Expansion Features": "features",
    "Feats of Strength": "featsOfStrength",
    "Legacy": "featsOfStrength",
    "Guild": "other",
    "Housing": "collections",
    "Characters": "other",
}

SUBCATEGORY_ACTIVITY = {
    "Player vs. Player": "pvp",
    "Raids": "raid",
    "Dungeons": "dungeon",
    "Delves": "delves",
    "Reputation": "reputation",
    "Professions": "professions",
    "Quests": "quests",
    "Events": "worldEvents",
    "World Events": "worldEvents",
    "Expansion Features": "features",
    "Skyriding": "skyriding",
}

# The first title ID (CharTitles' ID, not Mask_ID) added in each expansion.
ID_RANGES = [
    (1, CLASSIC), (42, TBC), (72, WRATH), (188, CATA), (303, MOP), (392, WOD), (458, LEGION),
    (524, BFA), (676, SL), (728, DF), (823, TWW), (1020, MIDNIGHT),
]

# Words in category names that name an expansion, checked in this order.
CATEGORY_EXPANSION = [
    ("Burning Crusade", TBC), ("Outland", TBC),
    ("Lich King", WRATH), ("Northrend", WRATH), ("Argent Tournament", WRATH),
    ("Cataclysm", CATA), ("Tol Barad", CATA),
    ("Pandaria", MOP), ("Proving Grounds", MOP),
    ("Draenor", WOD), ("Garrison", WOD),
    ("Legion", LEGION), ("Class Hall", LEGION),
    ("Battle for Azeroth", BFA), ("Battle Dungeon", BFA), ("Battle Raid", BFA),
    ("Island Expeditions", BFA), ("War Effort", BFA), ("Heart of Azeroth", BFA), ("Visions of N'Zoth", BFA),
    ("Shadowlands", SL), ("Torghast", SL), ("Covenant", SL),
    ("Dragonflight", DF), ("Dragon Isle", DF),
    ("War Within", TWW),
    ("Midnight", MIDNIGHT), ("Prey", MIDNIGHT), ("Housing", MIDNIGHT), ("Ritual Sites", MIDNIGHT), ("Void Assaults", MIDNIGHT),
    ("Classic", CLASSIC), ("Eastern Kingdoms", CLASSIC), ("Kalimdor", CLASSIC),
]

# Titles without an achievement, matched by their English name: (pattern, activity, expansion or
# None to take it from the neighbouring titles).
RULES = [
    (r"Gladiator|^Duelist |^Rival |^Challenger |^Combatant |^%s the Elite ", "pvp", None),
    (r"^Grand Master |^Iron Chef |^Doctor ", "professions", None),
    (r" Racer %s$", "skyriding", None),
    (r" Enthusiast %s$", "features", None),
    # The Hall of Fame: the first guilds to defeat a raid's last boss on Mythic.
    (r"^%s, Famed ", "raid", None),
]

# Titles set by hand, by their English name (CharTitles' Name_lang): (activity, expansion), either
# can be None to keep the one found before.
OVERRIDES = {
    # Old IDs given to newer titles.
    "Combatant %s": ("pvp", BFA),
    "Dread Gladiator %s": ("pvp", BFA),
    "Sinister Gladiator %s": ("pvp", BFA),
    "Timerunner %s": ("featsOfStrength", MOP),
    # Legion class hall titles (some reuse old IDs).
    "Archmage %s": ("quests", LEGION),
    "Battlelord %s": ("quests", LEGION),
    "Assassin %s": ("quests", LEGION),
    "Illidari %s": ("quests", LEGION),
    "Highlord %s": ("quests", LEGION),
    "Slayer %s": ("quests", LEGION),
    "Archdruid %s": ("quests", LEGION),
    "Deathlord %s": ("quests", LEGION),
    "Grandmaster %s": ("quests", LEGION),
    "Master Assassin %s": ("quests", LEGION),
    "Huntmaster %s": ("quests", LEGION),
    "Farseer %s": ("quests", LEGION),
    "Netherlord %s": ("quests", LEGION),
    "Shadowblade %s": ("quests", LEGION),
    "High Priest %s": ("quests", LEGION),
    "%s, Guardian of G'Hanir": ("quests", LEGION),
    "%s, Talon's Vengeance": ("quests", LEGION),
    # The Burning Crusade.
    "Scarab Lord %s": ("featsOfStrength", CLASSIC),
    "%s, Champion of the Naaru": ("quests", None),
    "%s, Hand of A'dal": ("quests", None),
    "%s of the Shattered Sun": ("reputation", None),
    # Wrath of the Lich King.
    "%s of the Ebon Blade": ("quests", None),
    "Loremaster %s": ("quests", None),
    "%s the Pilgrim": ("worldEvents", None),
    "Crusader %s": ("features", None),
    "Grand Crusader %s": ("raid", None),
    # Cataclysm.
    "%s, Veteran of the Alliance": ("pvp", None),
    "%s, Veteran of the Horde": ("pvp", None),
    # Mists of Pandaria: the Tillers, and the challenge mode dungeons.
    "Farmer %s": ("reputation", None),
    "%s, Defender of the Wall": ("dungeon", None),
    "Mogu-Slayer %s": ("dungeon", None),
    "Flameweaver %s": ("dungeon", None),
    "Scarlet Commander %s": ("dungeon", None),
    "Darkmaster %s": ("dungeon", None),
    "Purified Defender %s": ("dungeon", None),
    "Siegebreaker %s": ("dungeon", None),
    "Stormbrewer %s": ("dungeon", None),
    "Jade Protector %s": ("dungeon", None),
    "%s the Crazy Cat Man": ("petBattles", None),
    # Warlords of Draenor: reputations, and the challenge mode dungeons.
    "Talon Queen %s": ("reputation", None),
    "%s of the Frostwolves": ("reputation", None),
    "Prelate %s": ("reputation", None),
    "%s, Spear of Vol'jin": ("reputation", None),
    "%s, Sword of Wrynn": ("reputation", None),
    "%s the Mine Master": ("dungeon", None),
    "Dockmaster %s": ("dungeon", None),
    "%s the Soul Preserver": ("dungeon", None),
    "%s, Scion of Rukhmar": ("dungeon", None),
    "Spiritwalker %s": ("dungeon", None),
    "%s, Lord of Blackrock": ("dungeon", None),
    "%s, Lady of Blackrock": ("dungeon", None),
    "%s the Violet Guardian": ("dungeon", None),
    "%s the Grimrail Suplexer": ("dungeon", None),
    # Legion.
    "%s, Lord of the Reins": ("collections", None),
    "%s, No Good, Dirty, Rotten, Candy Stealer!": ("worldEvents", None),
    # Battle for Azeroth.
    "%s the Horde Slayer": ("pvp", None),
    "%s the Alliance Slayer": ("pvp", None),
    "Renowned Explorer %s": ("exploration", None),
    # Shadowlands: covenant renown.
    "%s, Hand of the Archon": ("reputation", None),
    "%s, Disciple of Devotion": ("reputation", None),
    "%s the Ascended": ("reputation", None),
    "Baron %s": ("reputation", None),
    "Baroness %s": ("reputation", None),
    "Count %s": ("reputation", None),
    "Countess %s": ("reputation", None),
    "%s the Avowed": ("reputation", None),
    "Sin Eater %s": ("reputation", None),
    "%s, Winter's Envoy": ("reputation", None),
    "%s, Protector of the Weald": ("reputation", None),
    "Deathbringer %s": ("reputation", None),
    "Abominable %s": ("reputation", None),
    "%s, Sword of the Primus": ("reputation", None),
    # Dragonflight: renown, and Plunderstorm.
    "%s, Honorary Dryad": ("reputation", None),
    "Khansguard %s": ("reputation", None),
    "%s of Iskaara": ("reputation", None),
    "Intrepid Explorer %s": ("exploration", None),
    "%s, Dream Defender": ("quests", None),
    "Legend %s": ("pvp", None),
    "Plunderlord %s": ("pvp", None),
    "Swabbie %s": ("pvp", None),
    "Deck Hand %s": ("pvp", None),
    "Swashbuckler %s": ("pvp", None),
    "Buccaneer %s": ("pvp", None),
    "First Mate %s": ("pvp", None),
    # The War Within: renown, Undermine's cartels and Delves.
    "Machine Whisperer %s": ("reputation", None),
    "Honorary Councilmember %s": ("reputation", None),
    "Lamplighter %s": ("reputation", None),
    "Thread-Spinner %s": ("reputation", None),
    "Anub'%s": ("reputation", None),
    "Landlubber %s": ("reputation", None),
    "%s the Treasured": ("reputation", None),
    "High Roller %s": ("reputation", None),
    "%s the Explosive": ("reputation", None),
    "Darkfuse Diplomat %s": ("reputation", None),
    "Trade-Duke %s": ("reputation", None),
    '%s, "Employee" of the Month': ("reputation", None),
    "%s, Slayer of the Deeps": ("delves", None),
    "%s the Delver Within": ("delves", None),
    "Molten Core Prospector %s": ("worldEvents", None),
    "Karazhan Graduate %s": ("worldEvents", None),
    # Midnight.
    "Honorary Hara'ti %s": ("reputation", None),
    "%s, Chronicler of the Haranir": ("reputation", None),
    "Darkspear Dasher %s": ("skyriding", None),
    "%s the Umbral Contender": ("dungeon", None),
    # Mythic+ titles of Midnight's first season, with IDs from before Midnight's.
    "%s the Umbral": ("dungeon", MIDNIGHT),
    "%s the Umbral Hero": ("dungeon", MIDNIGHT),
    "%s, the Singular": ("reputation", None),
    "%s, Servant of Astalor": ("features", None),
}


def fetch(path):
    request = urllib.request.Request(WAGO + path, headers={"User-Agent": "Marquee title data generator"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read().decode("utf-8")


def table(name, build):
    return list(csv.DictReader(io.StringIO(fetch(f"/db2/{name}/csv?build={build}"))))


def live_build():
    return json.loads(fetch("/api/builds/latest"))["wow"]["version"]


def normalize(name):
    """A title's or reward's name without the player's name, commas and case."""
    return re.sub(r"\s+", " ", name.replace("%s", "").replace(",", "")).strip().lower()


def rewarded_title_names(reward):
    """The title names an achievement's reward text gives, e.g. "Title: Matron/Patron"."""
    match = re.match(r"\s*(?:Seasonal )?(?:Character )?Titles?:\s*(.+)", reward or "")
    if not match:
        return []
    names = [match.group(1)] + re.split(r"\s*(?:/| or )\s*", match.group(1))
    return [normalize(name) for name in names]


def category_path(categories, category_id):
    """["Dungeons & Raids", "Lich King Raid"] for a category ID."""
    path = []
    while category_id in categories:
        category = categories[category_id]
        path.insert(0, category["Name_lang"])
        category_id = category["Parent"]
    return path


def activity_for(path, instance):
    top = path[0] if path else ""
    sub = path[1] if len(path) > 1 else ""
    if top == "Dungeons & Raids" or sub == "Dungeons & Raids":
        if "Raid" in sub:
            return "raid"
        if "Dungeon" in sub:
            return "dungeon"
        return "raid" if instance and instance["InstanceType"] == "2" else "dungeon"
    if top == "Expansion Features" and sub in SUBCATEGORY_ACTIVITY:
        return SUBCATEGORY_ACTIVITY[sub]
    if top in ("Feats of Strength", "Legacy", "Guild") and sub in SUBCATEGORY_ACTIVITY:
        return SUBCATEGORY_ACTIVITY[sub]
    return TOP_CATEGORY_ACTIVITY.get(top, "other")


def expansion_for(path):
    for name in reversed(path):
        for word, expansion in CATEGORY_EXPANSION:
            if word in name:
                return expansion
    return None


def expansion_by_id(title_id):
    return max(expansion for first_id, expansion in ID_RANGES if first_id <= title_id)


def main():
    args = [arg for arg in sys.argv[1:] if not arg.startswith("--")]
    build = args[0] if args else live_build()
    titles = table("CharTitles", build)
    achievements = table("Achievement", build)
    categories = {row["ID"]: row for row in table("Achievement_Category", build)}
    maps = {row["ID"]: row for row in table("Map", build)}

    # The first (lowest ID) achievement that rewards each title name.
    rewarding = {}
    for achievement in sorted(achievements, key=lambda row: int(row["ID"])):
        for name in rewarded_title_names(achievement["Reward_lang"]):
            rewarding.setdefault(name, achievement)

    names = {title["Name_lang"] for title in titles}
    unknown = sorted(set(OVERRIDES) - names)
    if unknown:
        sys.exit(f"OVERRIDES has titles that don't exist in build {build}: {unknown}")

    tags = {}  # [CharTitles ID] = [activity, expansion, how]
    for title in titles:
        name = title["Name_lang"]
        activity = expansion = None
        how = "rule"
        candidates = [normalize(name), normalize(title["Name1_lang"])]
        candidates.append(re.sub(r"^the ", "", candidates[0]))
        achievement = next((rewarding[c] for c in candidates if c in rewarding), None)
        if achievement:
            path = category_path(categories, achievement["Category"])
            instance = maps.get(achievement["Instance_ID"])
            activity, expansion = activity_for(path, instance), expansion_for(path)
            how = "achievement " + achievement["ID"] + " (" + " > ".join(path) + ")"
        else:
            for pattern, rule_activity, rule_expansion in RULES:
                if re.search(pattern, name):
                    activity, expansion = rule_activity, rule_expansion
                    break
        # An achievement can sort a title under Other (e.g. Characters); a rule may know better.
        if activity == "other":
            for pattern, rule_activity, _ in RULES:
                if re.search(pattern, name):
                    activity = rule_activity
                    break
        if name in OVERRIDES:
            override_activity, override_expansion = OVERRIDES[name]
            activity = override_activity or activity
            expansion = override_expansion if override_expansion is not None else expansion
            how = "override"
        tags[int(title["ID"])] = [activity, expansion, how]

    for id_, tag in tags.items():
        if tag[1] is None:
            tag[1] = expansion_by_id(id_)
            tag[2] += ", expansion from ID order"

    by_id = {int(title["ID"]): title for title in titles}
    untagged = [by_id[id_]["Name_lang"] for id_, tag in sorted(tags.items()) if tag[0] is None]

    lines = [
        "local _, ns = ...",
        "",
        f"-- Generated by tools/generate_title_data.py from Blizzard's game data (build {build}).",
        "-- Don't edit by hand; change the script's rules or overrides and run it again.",
        "-- [title mask ID, as used by GetTitleName] = { expansion (0 = Classic), activity }",
        "ns.TitleData = {",
        f'    build = "{build}",',
        "    titles = {",
    ]
    for id_ in sorted(tags, key=lambda id_: int(by_id[id_]["Mask_ID"])):
        activity, expansion, _ = tags[id_]
        title = by_id[id_]
        lines.append(f'        [{title["Mask_ID"]}] = {{ {expansion}, "{activity or "other"}" }}, '
                     f'-- {title["Name_lang"]}')
    lines += ["    },", "}", ""]
    OUTPUT.parent.mkdir(exist_ok=True)
    OUTPUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {OUTPUT} ({len(tags)} titles, build {build}).")

    if "--report" in sys.argv:
        for id_, (activity, expansion, how) in sorted(tags.items()):
            print(f"{id_}\t{expansion}\t{activity}\t{by_id[id_]['Name_lang']}\t{how}")
    if untagged:
        print(f"{len(untagged)} titles have no activity yet (they show under Other); add them to OVERRIDES:")
        for name in untagged:
            print("   ", name)


if __name__ == "__main__":
    main()
