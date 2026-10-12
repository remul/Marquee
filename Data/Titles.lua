local _, ns = ...
local L = ns.L

-- Each title's expansion and activity (from Data/TitleData.lua), and the filters that pick titles
-- by them.
local Titles = {}
ns.Titles = Titles

-- Expansions by their number (0 = Classic), as in the game's EXPANSION_NAME0, 1, ...
Titles.NUM_EXPANSIONS = 12

function Titles.GetExpansionName(expansion)
    return _G["EXPANSION_NAME" .. expansion]
end

-- Activities in menu order (the keys used in TitleData.lua). Labels are Blizzard's own text where
-- it has one; the others use the names of Blizzard's achievement categories (see Locales).
Titles.ACTIVITIES = {
    "raid", "dungeon", "delves", "pvp", "worldEvents", "reputation", "quests", "exploration",
    "professions", "petBattles", "skyriding", "collections", "features", "featsOfStrength", "other",
}

local ACTIVITY_LABELS = {
    raid = function() return RAIDS end,
    dungeon = function() return DUNGEONS end,
    delves = function() return DELVES_LABEL end,
    pvp = function() return PVP end,
    worldEvents = function() return L["World Events"] end,
    reputation = function() return REPUTATION end,
    quests = function() return QUESTS_LABEL end,
    exploration = function() return L["Exploration"] end,
    professions = function() return TRADE_SKILLS end,
    petBattles = function() return L["Pet Battles"] end,
    skyriding = function() return MOUNT_JOURNAL_FILTER_DRAGONRIDING end,
    collections = function() return L["Collections"] end,
    features = function() return L["Expansion Features"] end,
    featsOfStrength = function() return L["Feats of Strength"] end,
    other = function() return OTHER end,
}

function Titles.GetActivityName(activity)
    return ACTIVITY_LABELS[activity]()
end

-- A title's expansion (nil if it's newer than the data) and activity ("other" if unknown).
function Titles.GetTags(titleID)
    local tags = ns.TitleData.titles[titleID]
    if tags then
        return tags[1], tags[2]
    end
    return nil, "other"
end

-- Filters: expansions and activities that are hidden ([key] = true), saved for the account. Titles
-- the data doesn't know yet have no expansion, so only the activity filter hides them.
function Titles.IsExpansionShown(expansion)
    return not ns.db.hiddenExpansions[expansion]
end

function Titles.SetExpansionShown(expansion, shown)
    ns.db.hiddenExpansions[expansion] = not shown or nil
end

function Titles.IsActivityShown(activity)
    return not ns.db.hiddenActivities[activity]
end

function Titles.SetActivityShown(activity, shown)
    ns.db.hiddenActivities[activity] = not shown or nil
end

function Titles.SetAllExpansionsShown(shown)
    for expansion = 0, Titles.NUM_EXPANSIONS - 1 do
        Titles.SetExpansionShown(expansion, shown)
    end
end

function Titles.SetAllActivitiesShown(shown)
    for _, activity in ipairs(Titles.ACTIVITIES) do
        Titles.SetActivityShown(activity, shown)
    end
end

-- True while any filter hides something.
function Titles.IsFiltered()
    return next(ns.db.hiddenExpansions) ~= nil or next(ns.db.hiddenActivities) ~= nil
end

function Titles.ResetFilters()
    wipe(ns.db.hiddenExpansions)
    wipe(ns.db.hiddenActivities)
end

-- Lowercase names, so typing in a search doesn't lowercase every title, expansion and activity
-- again: [name] = lowercase.
local lowerNames = {}

local function Contains(name, search)
    local lower = lowerNames[name]
    if not lower then
        lower = name:lower()
        lowerNames[name] = lower
    end
    return lower:find(search, 1, true) ~= nil
end

-- True if the title's name contains the (lowercase) search.
function Titles.NameMatches(name, search)
    return Contains(name, search)
end

-- True if the title passes the filters, and its name, expansion or activity contains the
-- (lowercase) search: "legion" finds Legion's titles, "pvp" the PvP ones.
function Titles.Passes(titleID, name, search)
    local expansion, activity = Titles.GetTags(titleID)
    if expansion and not Titles.IsExpansionShown(expansion) then
        return false
    end
    if not Titles.IsActivityShown(activity) then
        return false
    end
    if search == "" or Contains(name, search) then
        return true
    end
    return (expansion and Contains(Titles.GetExpansionName(expansion), search))
        or Contains(Titles.GetActivityName(activity), search)
end

-- Favourite titles, shown first in the list ([titleID] = true): shared by the account's characters,
-- or, for a character that switched to its own, that character's. Both lists are kept.
local function GetFavorites()
    return ns.charDb.ownFavorites and ns.charDb.favoriteTitles or ns.db.favoriteTitles
end

---@return boolean
function Titles.HasOwnFavorites()
    return ns.charDb.ownFavorites == true
end

function Titles.SetOwnFavorites(own)
    ns.charDb.ownFavorites = own
end

function Titles.IsFavorite(titleID)
    return GetFavorites()[titleID] == true
end

function Titles.SetFavorite(titleID, favorite)
    GetFavorites()[titleID] = favorite or nil
end

-- Choices besides a title's ID, as Blizzard's "No Title" (-1) and Marquee's Random rows use them.
Titles.NO_TITLE = -1
Titles.RANDOM = -2
Titles.RANDOM_FAVORITE = -3
-- For outfits: keep the title worn.
Titles.KEEP = 0

-- The IDs of the titles this character has.
function Titles.GetKnownTitleIDs()
    local ids = {}
    for titleID = 1, GetNumTitles() do
        if IsTitleKnown(titleID) then
            local name, playerTitle = GetTitleName(titleID)
            if name and playerTitle then
                ids[#ids + 1] = titleID
            end
        end
    end
    return ids
end

-- The titles a random one is picked from (with favoritesOnly, the favourites), other than the one
-- worn now if there are others.
local function GetRandomChoices(favoritesOnly)
    local current = GetCurrentTitle()
    local choices, others = {}, {}
    for _, titleID in ipairs(Titles.GetKnownTitleIDs()) do
        if not favoritesOnly or Titles.IsFavorite(titleID) then
            tinsert(titleID == current and choices or others, titleID)
        end
    end
    return #others > 0 and others or choices
end

function Titles.HasRandomChoice(favoritesOnly)
    return #GetRandomChoices(favoritesOnly) > 0
end

-- Wears a random title of this character's (with favoritesOnly, a random favourite), other than
-- the one worn now if there's a choice. Setting a title needs a click or key press, so this must
-- run from one (a button, a slash command, a key binding). Returns the title's ID, or nil if
-- there's none to choose from.
function Titles.WearRandom(favoritesOnly)
    local choices = GetRandomChoices(favoritesOnly)
    if #choices == 0 then
        return nil
    end
    local titleID = choices[random(#choices)]
    SetCurrentTitle(titleID)
    return titleID
end

-- Wears a choice: a title's ID, NO_TITLE, RANDOM or RANDOM_FAVORITE. Needs a click or key press
-- (see WearRandom). Returns the title worn (NO_TITLE for none), or nil if there was none to wear.
function Titles.Wear(choice)
    if choice == Titles.RANDOM or choice == Titles.RANDOM_FAVORITE then
        return Titles.WearRandom(choice == Titles.RANDOM_FAVORITE)
    end
    if choice == Titles.NO_TITLE or IsTitleKnown(choice) then
        SetCurrentTitle(choice)
        return choice
    end
    return nil
end

-- A choice's name: the title, "No Title", "Random" or "Random Favorite".
function Titles.GetChoiceName(choice)
    if choice == Titles.KEEP then
        return L["Don't change"]
    elseif choice == Titles.NO_TITLE then
        return PLAYER_TITLE_NONE
    elseif choice == Titles.RANDOM then
        return L["Random"]
    elseif choice == Titles.RANDOM_FAVORITE then
        return L["Random Favorite"]
    end
    local name = GetTitleName(choice)
    return name and strtrim(name) or "?"
end

