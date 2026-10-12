local _, ns = ...
local L = ns.L
local Titles = ns.Titles
local TitleList = ns.TitleList
local Outfits = ns.Outfits

-- In the transmog window's character preview, top right: the title of the outfit shown, and a
-- picker to choose it, with the Filter button, a search box and the titles as cards like the
-- Titles list in the Character window (favourites first; here they can only be chosen).
local OutfitPicker = {}
ns.OutfitPicker = OutfitPicker

local SELECTOR_WIDTH, SELECTOR_HEIGHT = 220, 26
local PICKER_WIDTH, PICKER_HEIGHT = 260, 420
local PADDING = 10
local CHEVRON_ATLAS = "uitools-icon-chevron-down"

local preview, selector, picker, filterDropdown, searchBox, scrollBox
-- The character's titles ({ id, name }, by name), read when the picker opens or titles change, so
-- typing in the search doesn't read them all again.
local knownTitles = {}
-- The title Enter in the search box chooses (see TitleList.GetEnterChoice).
local enterChoice

local function GetOutfitID()
    local outfitID = C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID()
    if outfitID and outfitID > 0 then
        return outfitID
    end
end

local function GetChoice()
    local outfitID = GetOutfitID()
    return outfitID and Outfits.GetChoice(outfitID) or Titles.KEEP
end

-- The selector shows the outfit's title; there's nothing to choose while no outfit is shown.
local function UpdateSelector()
    local choice = GetChoice()
    local row = choice > 0 and { name = Titles.GetChoiceName(choice) } or TitleList.CreateChoiceRow(choice)
    selector.Text:SetText(row.name)
    TitleList.SetTextColor(selector.Text, choice)
    selector:SetEnabled(GetOutfitID() ~= nil)
    selector:SetAlpha(selector:IsEnabled() and 1 or 0.5)
    ns.UpdateCardOutline(selector.Outline, picker and picker:IsShown(), selector:IsMouseOver())
end

local function ReadKnownTitles()
    knownTitles = {}
    for _, titleID in ipairs(Titles.GetKnownTitleIDs()) do
        knownTitles[#knownTitles + 1] = { id = titleID, name = Titles.GetChoiceName(titleID) }
    end
    table.sort(knownTitles, function(a, b)
        return a.name < b.name
    end)
end

-- The rows: Don't change, No Title, Random, Random Favorite, then the character's titles
-- (favourites first, then by name) that pass the search and filters.
local function Refresh()
    if not picker:IsShown() then
        return
    end
    local favorites, others = TitleList.SplitFavorites(knownTitles, TitleList.GetSearch(searchBox))
    enterChoice = TitleList.GetEnterChoice(searchBox, favorites, others)
    local choices = { TitleList.CreateChoiceRow(Titles.KEEP), TitleList.CreateChoiceRow(Titles.NO_TITLE) }
    for _, row in ipairs(TitleList.GetRandomRows(knownTitles)) do
        choices[#choices + 1] = row
    end
    scrollBox:SetDataProvider(TitleList.CreateDataProvider({ choices, favorites, others }),
        ScrollBoxConstants.RetainScrollPosition)
end

-- Saves the choice for the outfit shown; for the outfit you're wearing, the title changes too.
local function Choose(choice)
    local outfitID = GetOutfitID()
    if outfitID then
        Outfits.SetChoice(outfitID, choice)
        Outfits.OnChoiceChanged(outfitID)
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    picker:Hide()
end

-- A card in the list, like the Titles list's: the chosen one has a gold outline, favourites a star
-- (just a mark here), and long titles end in "..." with the whole title in their tooltip. The title
-- Enter would choose is highlighted like a hovered one.
local function UpdateRow(row)
    ns.UpdateCardOutline(row.Outline, row.choice == GetChoice(),
        row:IsMouseOver() or row.choice == enterChoice)
end

local function InitRow(row, elementData)
    if not row.Outline then
        row.Fill = ns.CreateCardFill(row)
        row.Outline = ns.CreateCardOutline(row)
        TitleList.AnchorToCard(row.Fill)
        TitleList.AnchorToCard(row.Outline)
        row.Star = row:CreateTexture(nil, "ARTWORK")
        row.Star:SetSize(11, 11)
        row.Star:SetPoint("RIGHT", row.Fill, "RIGHT", -9, 0)
        row.Star:SetAtlas("auctionhouse-icon-favorite")
        row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        -- The right side is set by TitleList.FitText.
        row.Text:SetPoint("LEFT", row.Fill, "LEFT", 10, 0)
        row.Text:SetJustifyH("LEFT")
        row.Text:SetWordWrap(false)
        row:SetScript("OnSizeChanged", function()
            TitleList.FitFont(row.Text, row.Fill)
        end)
        row:SetScript("OnClick", function()
            Choose(row.choice)
        end)
        row:SetScript("OnEnter", function()
            UpdateRow(row)
            TitleList.ShowFullTitle(row, row.Text, row.Fill)
        end)
        row:SetScript("OnLeave", function()
            UpdateRow(row)
            GameTooltip_Hide()
        end)
    end
    TitleList.UpdateDivider(row, elementData.dividerAfter == true)
    local title = elementData.playerTitle
    row.choice = title.id
    row.Text:SetText(title.name)
    TitleList.SetTextColor(row.Text, title.id)
    TitleList.FitFont(row.Text, row.Fill)
    local favorite = title.id > 0 and Titles.IsFavorite(title.id)
    row.Star:SetShown(favorite)
    TitleList.FitText(row.Text, row.Fill, favorite)
    UpdateRow(row)
end

local function CreatePicker()
    -- A global name, so Escape closes it (see UISpecialFrames).
    picker = CreateFrame("Frame", "MarqueeOutfitTitlePicker", preview, "TooltipBackdropTemplate")
    picker:SetSize(PICKER_WIDTH, PICKER_HEIGHT)
    picker:SetPoint("TOPRIGHT", selector, "BOTTOMRIGHT", 0, -4)
    -- Solid, not a tooltip's see-through background: the character model is behind it. The tooltip's
    -- centre texture is see-through itself, so a solid layer goes behind it (inside the border).
    local background = picker:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetPoint("TOPLEFT", 3, -3)
    background:SetPoint("BOTTOMRIGHT", -3, 3)
    background:SetColorTexture(0.05, 0.05, 0.05, 1)
    picker:SetFrameStrata("HIGH")
    picker:EnableMouse(true)
    picker:Hide()
    tinsert(UISpecialFrames, picker:GetName())

    filterDropdown = CreateFrame("DropdownButton", nil, picker, "WowStyle1FilterDropdownTemplate")
    filterDropdown:SetHeight(22)
    filterDropdown:SetPoint("TOPLEFT", PADDING, -PADDING)
    filterDropdown:SetPoint("RIGHT", -PADDING, 0)
    TitleList.SetupFilterDropdown(filterDropdown, Refresh)

    searchBox = CreateFrame("EditBox", nil, picker, "SearchBoxTemplate")
    -- The search box's frame starts a little left of its field, so it's moved right to line up.
    searchBox:SetPoint("TOPLEFT", filterDropdown, "BOTTOMLEFT", 6, -6)
    searchBox:SetPoint("RIGHT", filterDropdown, "RIGHT")
    searchBox:SetHeight(22)
    searchBox:SetAutoFocus(false)
    searchBox:HookScript("OnTextChanged", Refresh)
    TitleList.SetupSearchEnter(searchBox, function()
        return enterChoice
    end, Choose, Refresh)

    local view = CreateScrollBoxListLinearView()
    view:SetElementInitializer("Button", InitRow)
    TitleList.SetupView(view, 4, 10, 0, 0)
    scrollBox = CreateFrame("Frame", nil, picker, "WowScrollBoxList")
    -- Some space below the search box, as in the Titles list.
    scrollBox:SetPoint("TOPLEFT", filterDropdown, "BOTTOMLEFT", 0, -40)
    scrollBox:SetPoint("BOTTOMRIGHT", -PADDING - 14, PADDING)
    local scrollBar = CreateFrame("EventFrame", nil, picker, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    picker:SetScript("OnShow", function()
        ReadKnownTitles()
        -- Clearing the search redraws the list; without a search, it's drawn here.
        if searchBox:GetText() ~= "" then
            searchBox:SetText("")
        else
            Refresh()
        end
        UpdateSelector()
    end)
    picker:SetScript("OnHide", UpdateSelector)
end

-- The selector: "Title" above a card with the outfit's title and a chevron; it opens the picker.
local function CreateSelector()
    selector = CreateFrame("Button", nil, preview)
    selector:SetSize(SELECTOR_WIDTH, SELECTOR_HEIGHT)
    selector:SetPoint("TOPRIGHT", -25, -42)
    selector:SetFrameLevel(preview:GetFrameLevel() + 100)
    ns.CreateCardFill(selector)
    selector.Outline = ns.CreateCardOutline(selector)

    selector.Label = selector:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    selector.Label:SetPoint("BOTTOMLEFT", selector, "TOPLEFT", 2, 4)
    selector.Label:SetText(L["Title"])

    selector.Chevron = selector:CreateTexture(nil, "ARTWORK")
    selector.Chevron:SetSize(12, 12)
    selector.Chevron:SetPoint("RIGHT", -10, 0)
    selector.Chevron:SetAtlas(CHEVRON_ATLAS)

    selector.Text = selector:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    selector.Text:SetPoint("LEFT", 10, 0)
    selector.Text:SetPoint("RIGHT", selector.Chevron, "LEFT", -6, 0)
    selector.Text:SetJustifyH("LEFT")
    selector.Text:SetWordWrap(false)

    selector:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        picker:SetShown(not picker:IsShown())
    end)
    selector:SetMotionScriptsWhileDisabled(true)
    selector:SetScript("OnEnter", function()
        UpdateSelector()
        GameTooltip:SetOwner(selector, "ANCHOR_LEFT")
        GameTooltip_SetTitle(GameTooltip, L["Title"])
        GameTooltip_AddNormalLine(GameTooltip, L["The title to wear with this outfit, when you put it on here or from your action bars."])
        GameTooltip:Show()
    end)
    selector:SetScript("OnLeave", function()
        UpdateSelector()
        GameTooltip_Hide()
    end)
end

function OutfitPicker:Setup()
    preview = TransmogFrame.CharacterPreview
    CreateSelector()
    CreatePicker()
    UpdateSelector()

    preview:HookScript("OnShow", UpdateSelector)
    preview:HookScript("OnHide", function()
        picker:Hide()
    end)
    -- Another outfit shown: its title, and the picker closes.
    ns:RegisterEvent("VIEWED_TRANSMOG_OUTFIT_CHANGED", function()
        picker:Hide()
        UpdateSelector()
    end)
    ns:RegisterEvent("KNOWN_TITLES_UPDATE", function()
        if picker:IsShown() then
            ReadKnownTitles()
            Refresh()
        end
        UpdateSelector()
    end)
end
