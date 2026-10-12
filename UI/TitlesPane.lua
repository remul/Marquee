local _, ns = ...
local Titles = ns.Titles
local TitleList = ns.TitleList

-- A search box and a Filter menu above the Titles list in the Character window, the list's rows
-- drawn as cards like Lineup's, Random rows, and favourite titles at the top. Blizzard's list keeps
-- working as before: Marquee only changes which of its titles show, in which order, and how its
-- rows look.
local TitlesPane = {}
ns.TitlesPane = TitlesPane

-- Height of the rows above the list (filter; search and options; space); the list moves down
-- by this much.
local HEADER_HEIGHT = 68
local pane, searchBox, filterDropdown
-- The title Enter in the search box wears (see TitleList.GetEnterChoice).
local enterChoice

-- Shows "No Title", the Random rows, the favourite titles, then the others (each in Blizzard's
-- order), leaving out the titles that don't pass the search and filters. Blizzard's list of titles
-- isn't changed: "No Title" is a copy with its mark, and the Random rows' IDs (below Blizzard's -1)
-- never reach the game (see OnCardClick).
local function FilterList()
    local titles = {}
    for _, playerTitle in ipairs(pane.titles or {}) do
        if playerTitle.id ~= Titles.NO_TITLE then
            titles[#titles + 1] = playerTitle
        end
    end
    local favorites, others = TitleList.SplitFavorites(titles, TitleList.GetSearch(searchBox))
    enterChoice = TitleList.GetEnterChoice(searchBox, favorites, others)
    local choices = TitleList.GetRandomRows(titles)
    tinsert(choices, 1, TitleList.CreateChoiceRow(Titles.NO_TITLE))
    local dataProvider = TitleList.CreateDataProvider({ choices, favorites, others })
    pane.ScrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition)
end

-- Redraws the list after the search, a filter or a favourite changed.
local function Refresh()
    if pane:IsShown() then
        FilterList()
    end
end

-- The card's outline (gold for the chosen title, light while hovered or picked by Enter in the
-- search box) and its star: always on favourites, and on the others while the card is hovered, to
-- make them one. "No Title" has none.
local function UpdateCard(button)
    local hovered = button:IsMouseOver()
    ns.UpdateCardOutline(button.MarqueeOutline, pane.selected == button.titleId,
        hovered or button.titleId == enterChoice)
    local favorite = Titles.IsFavorite(button.titleId)
    local star = button.MarqueeStar
    -- Only real titles have a star: not "No Title" or the Random rows.
    star:SetShown(button.titleId > 0 and (favorite or hovered))
    star.Icon:SetAtlas(favorite and "auctionhouse-icon-favorite" or "auctionhouse-icon-favorite-off")
    TitleList.FitText(button.text, button.MarqueeFill, star:IsShown())
end

local function CreateStar(button)
    local star = CreateFrame("Button", nil, button)
    star:SetSize(14, 14)
    star.Icon = star:CreateTexture(nil, "ARTWORK")
    -- Smaller than the button, so the star is easy to click.
    star.Icon:SetSize(11, 11)
    star.Icon:SetPoint("CENTER")
    star:SetScript("OnClick", function()
        local favorite = not Titles.IsFavorite(button.titleId)
        Titles.SetFavorite(button.titleId, favorite)
        PlaySound(favorite and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        Refresh()
    end)
    star:SetScript("OnEnter", function()
        GameTooltip:SetOwner(star, "ANCHOR_RIGHT")
        GameTooltip:SetText(Titles.IsFavorite(button.titleId) and BATTLE_PET_UNFAVORITE or BATTLE_PET_FAVORITE)
        GameTooltip:Show()
        UpdateCard(button)
    end)
    star:SetScript("OnLeave", function()
        GameTooltip_Hide()
        UpdateCard(button)
    end)
    return star
end

-- Turns one of Blizzard's title rows into a card, the first time it's shown: the text takes the
-- width the check mark had, a star marks favourites, and the outline shows the chosen title.
-- A Random row wears a random title; the others do what Blizzard's do (wear their title).
local function OnCardClick(button)
    if button.titleId == Titles.RANDOM or button.titleId == Titles.RANDOM_FAVORITE then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        ns.WearRandomTitle(button.titleId == Titles.RANDOM_FAVORITE)
    else
        PlayerTitleButton_OnClick(button)
    end
end

local function CreateCard(button)
    button.MarqueeFill = ns.CreateCardFill(button)
    button.MarqueeOutline = ns.CreateCardOutline(button)
    TitleList.AnchorToCard(button.MarqueeFill)
    TitleList.AnchorToCard(button.MarqueeOutline)
    button.MarqueeStar = CreateStar(button)
    button.MarqueeStar:SetPoint("RIGHT", button.MarqueeFill, "RIGHT", -6, 0)
    button:GetHighlightTexture():SetAlpha(0)
    button:SetScript("OnClick", OnCardClick)
    -- The right side is set by TitleList.FitText.
    button.text:ClearAllPoints()
    button.text:SetPoint("LEFT", button.MarqueeFill, "LEFT", 10, 0)
    -- One line for every title (Blizzard's wrap to two lines when they fit): long ones get a smaller
    -- font, and if that isn't enough end in "...", with the whole title in their tooltip.
    button.text:SetWordWrap(false)
    button:HookScript("OnSizeChanged", function()
        TitleList.FitFont(button.text, button.MarqueeFill)
    end)
    button:HookScript("OnEnter", function()
        UpdateCard(button)
        TitleList.ShowFullTitle(button, button.text, button.MarqueeFill)
    end)
    button:HookScript("OnLeave", function()
        UpdateCard(button)
        GameTooltip_Hide()
    end)
end

-- Blizzard's look of a row, hidden for the card's.
local BLIZZARD_REGIONS = { "BgTop", "BgMiddle", "BgBottom", "Stripe", "Check", "SelectedBar" }

-- Runs after Blizzard set up a row (its title, check mark and stripe): hides Blizzard's look and
-- shows the card's.
local function UpdateButton(button, elementData)
    if not button.MarqueeOutline then
        CreateCard(button)
    end
    TitleList.UpdateDivider(button, elementData.dividerAfter == true)
    for _, key in ipairs(BLIZZARD_REGIONS) do
        button[key]:Hide()
    end
    -- Rows are reused, so titles get their gold back.
    TitleList.SetTextColor(button.text, button.titleId)
    TitleList.FitFont(button.text, button.MarqueeFill)
    UpdateCard(button)
end

-- The gear is grey, and gold (as drawn) while hovered or while its menu is open.
local function UpdateOptionsButton(button, hovered)
    local active = button.menuOpen or hovered
    local texture = button:GetNormalTexture()
    texture:SetDesaturated(not active)
    texture:SetVertexColor(active and 1 or 0.8, active and 1 or 0.8, active and 1 or 0.8)
end

-- The gear next to the search box: this character's settings, and a button at the bottom for the
-- account's settings in Blizzard's Options (which can't be opened in combat).
local function ShowOptionsMenu(button)
    MenuUtil.CreateContextMenu(button, function(_, root)
        root:AddMenuAcquiredCallback(function()
            button.menuOpen = true
            UpdateOptionsButton(button, button:IsMouseOver())
        end)
        root:AddMenuReleasedCallback(function()
            button.menuOpen = false
            UpdateOptionsButton(button, button:IsMouseOver())
        end)
        root:CreateTitle(UnitName("player"))
        local ownFavorites = root:CreateCheckbox(ns.L["Own favorites for this character"], function()
            -- (== true only tells the IDE it's a boolean; it can't follow functions on ns.)
            return Titles.HasOwnFavorites() == true
        end, function()
            Titles.SetOwnFavorites(not Titles.HasOwnFavorites())
            Refresh()
        end)
        ownFavorites:SetTooltip(function(tooltip, elementDescription)
            GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription))
            GameTooltip_AddNormalLine(tooltip, ns.L["This character keeps its own favorite titles. Off: it shares the favorites of your other characters. Both lists are kept when you switch."])
        end)

        root:CreateDivider()
        local open = root:CreateButton(ns.L["Open Options"], function()
            ns.Options:Open()
        end)
        open:SetEnabled(not InCombatLockdown())
        open:SetTooltip(function(tooltip, elementDescription)
            GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription))
            GameTooltip_AddNormalLine(tooltip, ns.L["Marquee's settings for all your characters, in Blizzard's Options."])
            if InCombatLockdown() then
                GameTooltip_AddErrorLine(tooltip, ERR_NOT_IN_COMBAT)
            end
        end)
    end)
end

local function CreateOptionsButton()
    local button = CreateFrame("Button", nil, pane)
    button:SetSize(18, 18)
    button:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", ShowOptionsMenu)
    button:SetScript("OnEnter", function()
        UpdateOptionsButton(button, true)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(OPTIONS)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        UpdateOptionsButton(button, false)
        GameTooltip_Hide()
    end)
    UpdateOptionsButton(button, false)
    return button
end

-- Above the list: the Filter button, then the search box and the options gear (HEADER_HEIGHT
-- leaves some space below them).
local function CreateHeader()
    filterDropdown = CreateFrame("DropdownButton", nil, pane, "WowStyle1FilterDropdownTemplate")
    filterDropdown:SetHeight(22)
    filterDropdown:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -6)
    -- As wide as the list with its scroll bar.
    filterDropdown:SetPoint("RIGHT", pane, "RIGHT", 16, 0)
    TitleList.SetupFilterDropdown(filterDropdown, Refresh)

    local optionsButton = CreateOptionsButton()
    optionsButton:SetPoint("TOPRIGHT", filterDropdown, "BOTTOMRIGHT", 5, -8)

    searchBox = CreateFrame("EditBox", nil, pane, "SearchBoxTemplate")
    -- The search box's frame starts a little left of its field, so it's moved right to line up.
    searchBox:SetPoint("TOPLEFT", filterDropdown, "BOTTOMLEFT", 8, -6)
    searchBox:SetPoint("RIGHT", optionsButton, "LEFT", -2, 0)
    searchBox:SetHeight(22)
    searchBox:SetAutoFocus(false)
    searchBox:HookScript("OnTextChanged", Refresh)
    TitleList.SetupSearchEnter(searchBox, function()
        return enterChoice
    end, function(titleID)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        SetCurrentTitle(titleID)
    end, Refresh)
end

function TitlesPane:Setup()
    pane = PaperDollFrame.TitleManagerPane
    CreateHeader()

    -- Move the list (and with it the scroll bar) below the rows above it.
    local scrollBox = pane.ScrollBox
    local width, height = scrollBox:GetSize()
    scrollBox:ClearAllPoints()
    scrollBox:SetPoint("TOPLEFT", CharacterFrameInsetRight, "TOPLEFT", 4, -4 - HEADER_HEIGHT)
    scrollBox:SetSize(width, height - HEADER_HEIGHT)

    -- Taller rows with space between them (Blizzard's: 22 high, no space), and dividers.
    TitleList.SetupView(scrollBox:GetView(), 4, 10, 5, 0)

    hooksecurefunc("PaperDollTitlesPane_UpdateScrollBox", FilterList)
    hooksecurefunc("PaperDollTitlesPane_InitButton", UpdateButton)
end
