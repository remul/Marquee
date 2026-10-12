local addonName, ns = ...
local L = ns.L

ns.TITLE = "Marquee"
-- Path to the addon's own textures, e.g. ns.MEDIA .. "Icon".
ns.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

-- Defaults are copied into the saved variables on first load and whenever new keys are added.
local DEFAULTS = {
    debug = false,
    -- Filters of the Titles list: expansions (0 = Classic) and activities that are hidden,
    -- [key] = true (see Titles).
    hiddenExpansions = {},
    hiddenActivities = {},
    -- Favourite titles shared by the account's characters, shown first in the Titles list:
    -- [titleID] = true.
    favoriteTitles = {},
    -- What happens when the game puts on an outfit by itself (see SituationTitles): wear its title
    -- with the next "click", "ask" to wear it, or "off".
    situationTitles = "click",
}

local CHAR_DEFAULTS = {
    -- The title to wear with each transmog outfit (outfits are per character): [outfitID] = a
    -- title's ID, or Titles.NO_TITLE / RANDOM / RANDOM_FAVORITE. Outfits without one leave the title.
    outfitTitles = {},
    -- This character's own favourite titles, used instead of the shared ones while
    -- ownFavorites is on (switched in the gear menu above the Titles list).
    ownFavorites = false,
    favoriteTitles = {},
    -- The outfit last seen worn (activeOutfitID, nil until then), to tell when the game puts on
    -- another one (see SituationTitles).
}

local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = type(value) == "table" and CopyTable(value) or value
        elseif type(value) == "table" and type(target[key]) == "table" then
            ApplyDefaults(target[key], value)
        end
    end
end

-- The divider line of Blizzard's own Settings panel (thin, fading out at both ends), as in Lineup.
local DIVIDER_ATLAS = "Options_HorizontalDivider"
local DIVIDER_INFO = C_Texture.GetAtlasInfo(DIVIDER_ATLAS)

-- Makes texture a divider line and returns its thickness; the caller sets the length. Without the
-- atlas it's a thin gold line.
function ns.SetDividerTexture(texture)
    if not DIVIDER_INFO then
        texture:SetColorTexture(1, 0.82, 0, 0.5)
        return 1
    end
    texture:SetAtlas(DIVIDER_ATLAS)
    return DIVIDER_INFO.height
end

-- Rounded card textures (see tools/generate_rounded_textures.py): white, tinted with
-- SetVertexColor, and drawn as nine-slices so the corners keep their size at any card size.
local ROUNDED_FILL = ns.MEDIA .. "RoundedFill"
local ROUNDED_BORDER = ns.MEDIA .. "RoundedBorder"
local ROUNDED_MARGIN = 10

-- A rounded rectangle filling parent (or, with border, its outline), colored r, g, b, a.
function ns.CreateRoundedTexture(parent, layer, subLevel, r, g, b, a, border)
    local texture = parent:CreateTexture(nil, layer, nil, subLevel)
    texture:SetTexture(border and ROUNDED_BORDER or ROUNDED_FILL)
    texture:SetTextureSliceMargins(ROUNDED_MARGIN, ROUNDED_MARGIN, ROUNDED_MARGIN, ROUNDED_MARGIN)
    texture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    texture:SetVertexColor(r, g, b, a)
    texture:SetAllPoints()
    return texture
end

-- Cards (the title rows), as in Lineup: a lightly warm fill with a muted bronze outline, to stand
-- out from the inset's dark background in the colours of Blizzard's frames. The outline brightens
-- while hovered; a gold outline marks the chosen title.
local CARD_FILL = CreateColor(0.40, 0.36, 0.30)
local CARD_FILL_ALPHA = 0.22
local CARD_OUTLINE = CreateColor(0.62, 0.56, 0.46)
local CARD_OUTLINE_ALPHA, CARD_OUTLINE_HOVER_ALPHA = 0.45, 0.85

function ns.CreateCardFill(parent)
    local r, g, b = CARD_FILL:GetRGB()
    return ns.CreateRoundedTexture(parent, "BACKGROUND", 0, r, g, b, CARD_FILL_ALPHA)
end

function ns.CreateCardOutline(parent)
    local r, g, b = CARD_OUTLINE:GetRGB()
    return ns.CreateRoundedTexture(parent, "BORDER", -1, r, g, b, CARD_OUTLINE_ALPHA, true)
end

-- Colours a card outline: gold while active, otherwise the plain one, brighter while hovered.
function ns.UpdateCardOutline(outline, active, hovered)
    if active then
        outline:SetVertexColor(1, 0.82, 0, 0.9)
    else
        outline:SetVertexColor(CARD_OUTLINE.r, CARD_OUTLINE.g, CARD_OUTLINE.b,
            hovered and CARD_OUTLINE_HOVER_ALPHA or CARD_OUTLINE_ALPHA)
    end
end

function ns:Print(...)
    print("|cff33ff99" .. ns.TITLE .. "|r:", ...)
end

function ns:Debug(...)
    if self.db and self.db.debug then
        self:Print("|cff888888[debug]|r", ...)
    end
end

-- Event dispatch: ns:RegisterEvent("EVENT_NAME", callback) calls callback(...) when it fires.
-- Without a callback, ns:EVENT_NAME(...) is called. An event can have several callbacks.
local frame = CreateFrame("Frame")
-- [event] = { { key = callback or METHOD, run = function(...) } }. Lists are replaced, not changed
-- in place, so a callback can unregister itself while the event is being dispatched.
local callbacks = {}
local METHOD = {} -- key for the ns:EVENT_NAME handler

frame:SetScript("OnEvent", function(_, event, ...)
    local list = callbacks[event]
    if list then
        for _, entry in ipairs(list) do
            entry.run(...)
        end
    end
end)

local function AddCallback(event, callback)
    local list = CopyTable(callbacks[event] or {}, true)
    tinsert(list, {
        key = callback or METHOD,
        run = callback or function(...)
            -- Calls the ns:EVENT_NAME handler; the IDE can't tell which method that is.
            ---@diagnostic disable-next-line: param-type-mismatch
            ns[event](ns, ...)
        end,
    })
    callbacks[event] = list
end

function ns:RegisterEvent(event, callback)
    AddCallback(event, callback)
    frame:RegisterEvent(event)
end

-- Removes the callback given to RegisterEvent (without one: the ns:EVENT_NAME handler). Other
-- callbacks for the event keep running.
function ns:UnregisterEvent(event, callback)
    local key = callback or METHOD
    local list = {}
    for _, entry in ipairs(callbacks[event] or {}) do
        if entry.key ~= key then
            list[#list + 1] = entry
        end
    end
    if #list > 0 then
        callbacks[event] = list
    else
        callbacks[event] = nil
        frame:UnregisterEvent(event)
    end
end

-- The Titles list is the second sidebar tab of the Character window (see PAPERDOLL_SIDEBARS).
local TITLES_SIDEBAR = 2

-- Opens the Character window on its Titles list.
function ns.OpenTitles()
    ToggleCharacter("PaperDollFrame", true)
    PaperDollFrame_SetSidebar(nil, TITLES_SIDEBAR)
end

-- Wears a random title (or favourite) and says which, or why there's none. Needs a click or key
-- press (see Titles.WearRandom).
function ns.WearRandomTitle(favoritesOnly)
    local titleID = ns.Titles.WearRandom(favoritesOnly)
    if titleID then
        ns:Print(format(L["Your title is now %s."], ns.Titles.GetChoiceName(titleID)))
    elseif favoritesOnly then
        ns:Print(L["None of your titles is a favorite yet: click a title's star in the Titles list."])
    else
        ns:Print(L["You don't have any titles yet."])
    end
end

-- Lifecycle
function ns:ADDON_LOADED(loadedName)
    if loadedName ~= addonName then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")

    MarqueeDB = MarqueeDB or {}
    MarqueeCharDB = MarqueeCharDB or {}
    ApplyDefaults(MarqueeDB, DEFAULTS)
    ApplyDefaults(MarqueeCharDB, CHAR_DEFAULTS)
    self.db = MarqueeDB
    self.charDb = MarqueeCharDB
    ns.Options:Setup()

    -- The Character window comes with Blizzard_UIPanels_Game.
    EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", function()
        ns.TitlesPane:Setup()
    end)
    ns.Outfits:Setup()
    ns.SituationTitles:Setup()
    -- The transmog window is loaded when it's first opened.
    EventUtil.ContinueOnAddOnLoaded("Blizzard_Transmog", function()
        ns.OutfitPicker:Setup()
    end)
end

ns:RegisterEvent("ADDON_LOADED")

-- Global so the TOC's AddonCompartmentFunc can find it.
_G.Marquee_OnAddonCompartmentClick = function()
    ns.OpenTitles()
end

-- Slash commands
SLASH_MARQUEE1 = "/marquee"

SlashCmdList.MARQUEE = function(msg)
    local cmd = strtrim(msg or ""):lower()

    if cmd == "" then
        ns.OpenTitles()
    elseif cmd == "random" then
        ns.WearRandomTitle(false)
    elseif cmd:match("^random%s+fav") then
        ns.WearRandomTitle(true)
    elseif cmd == "debug" then
        ns.db.debug = not ns.db.debug
        ns:Print(L["Debug"], ns.db.debug and L["enabled"] or L["disabled"])
    else
        ns:Print(L["Commands:"])
        print(L["  /marquee - open your titles"])
        print(L["  /marquee random - wear a random title"])
        print(L["  /marquee random favorite - wear a random favorite title"])
        print(L["  /marquee debug - toggle debug output"])
    end
end
