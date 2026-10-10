# Roadmap

Planned features, ideas and open questions for Marquee. Move an entry to
[CHANGELOG.md](CHANGELOG.md) when it ships, and delete it here.

Marquee improves Blizzard's Titles list in the Character window. It doesn't add a window of its own,
and it doesn't track or rate titles (no statistics, rarity or achievements).

## To check in game

- The search row fits the Titles list: the search box and Filter button line up with the list and
  its scroll bar, and the list's last row still has its bottom edge while filtering.
- The filters keep working after choosing a title, earning one, and reopening the window.

- Outfit titles: the Title selector sits well at the top right of the transmog preview (clear of
  the undo button and the slots), its picker opens over the preview and closes with Escape; clicking the outfit's
  icon in the transmog window, clicking it on an action bar and pressing its key all change the
  title once (with "Cast action keybinds on key down" on and off); the tooltip line shows on the
  outfit and on its action button.
- Outfit titles only change when the outfit could be put on: Marquee checks the outfit's cooldown
  right after the click or key press (none running, or one that started just then). Check with
  `/marquee debug`, which prints the cooldown: a normal switch should say "wears ...", using the
  outfit during the global cooldown "is on cooldown". Still to see: whether anything else can stop
  a switch without a cooldown running (moving, casting, in combat), as the title would change then.

## Ideas

- Outfit titles from other action bar addons (Bartender, Dominos, ElvUI): each needs its own hook.
- For outfits the game switches to by itself: a one-click "Wear this outfit's title?" prompt.

## Title data

- About 115 titles have no activity yet and show under Other: titles from quests, events or
  promotions that no achievement rewards, and that weren't clear enough to tag by hand. Run
  `python3 tools/generate_title_data.py` to list them, and add the ones you know to its
  `OVERRIDES`.
- A title's expansion comes from its achievement's category where it names one, otherwise from
  the order titles were added in (`ID_RANGES`). Titles from events that came back later (e.g.
  Remix) may need an override.
