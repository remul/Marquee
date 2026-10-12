# Roadmap

Planned features, ideas and open questions for Marquee. Move an entry to
[CHANGELOG.md](CHANGELOG.md) when it ships, and delete it here.

Marquee improves Blizzard's Titles list in the Character window. It doesn't add a window of its own,
and it doesn't track or rate titles (no statistics, rarity or achievements).

## Ideas

- Outfit titles from other action bar addons (Bartender, Dominos, ElvUI): each needs its own hook.

## Title data

- About 115 titles have no activity yet and show under Other: titles from quests, events or
  promotions that no achievement rewards, and that weren't clear enough to tag by hand. Run
  `python3 tools/generate_title_data.py` to list them, and add the ones you know to its
  `OVERRIDES`.
- A title's expansion comes from its achievement's category where it names one, otherwise from
  the order titles were added in (`ID_RANGES`). Titles from events that came back later (e.g.
  Remix) may need an override.
