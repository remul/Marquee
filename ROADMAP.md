# Roadmap

Planned features, ideas and open questions for Marquee. Move an entry to
[CHANGELOG.md](CHANGELOG.md) when it ships, and delete it here.

Marquee improves Blizzard's Titles list in the Character window. It doesn't add a window of its own,
and it doesn't track or rate titles (no statistics, rarity or achievements).

## WoW Forever

Marquee is linked into WoW Forever's beta (interface 16001, in the TOC). What a client can do is
in `Compat.lua` (`ns.Client`), found by looking for its functions; the rest asks it for features,
never for a version. Without Retail's Titles list or transmog outfits, those parts switch off.

- Check in Forever: whether the Character window has the Titles list (then search, filters and
  favourites work there), how titles are chosen otherwise, its transmog (outfits?), and the
  Filter menu's expansions and activities (only Classic's).
- Then release with 16001 in the TOC, so CurseForge lists Marquee for Forever.

## Title data

- About 115 titles have no activity yet and show under Other: titles from quests, events or
  promotions that no achievement rewards, and that weren't clear enough to tag by hand. Run
  `python3 tools/generate_title_data.py` to list them, and add the ones you know to its
  `OVERRIDES`.
- A title's expansion comes from its achievement's category where it names one, otherwise from
  the order titles were added in (`ID_RANGES`). Titles from events that came back later (e.g.
  Remix) may need an override.
