local _, ns = ...
local Titles = ns.Titles

-- What the Titles list in the Character window and the outfit title picker share: their cards (size,
-- dividers), the rows that aren't one title (No Title, Random), the order of the titles (favourites
-- first, then the others, without those the search and filters leave out), and the Filter button.
local TitleList = {}
ns.TitleList = TitleList

-- Title cards: their height and the space between them.
TitleList.CARD_HEIGHT = 24
TitleList.CARD_SPACING = 6
-- Groups (the rows that aren't a title, favourites, other titles) are divided by a line. The last
-- card of a group is a taller row with the line below the card, as the lists only hold one kind of
-- row: this much taller.
local DIVIDER_SPACE = 12

-- "No Title" gets the loot window's Pass mark, the Random rows its dice.
local PASS = "|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:16:16:0:-1|t "
local DICE = "|TInterface\\Buttons\\UI-GroupLoot-Dice-Up:16:16:0:-1|t "
local MARKS = {
    [Titles.NO_TITLE] = PASS,
    [Titles.RANDOM] = DICE,
    [Titles.RANDOM_FAVORITE] = DICE,
}

-- A row for a choice that isn't one title (Titles.KEEP, NO_TITLE, RANDOM, RANDOM_FAVORITE): its
-- name with its mark.
function TitleList.CreateChoiceRow(choice)
    return { id = choice, name = (MARKS[choice] or "") .. Titles.GetChoiceName(choice) }
end

-- The Random rows; Random Favorite only if one of titles (the character's, { id, name } each) is a
-- favourite it can pick (not hidden), whatever the search and filters show.
function TitleList.GetRandomRows(titles)
    local rows = { TitleList.CreateChoiceRow(Titles.RANDOM) }
    for _, title in ipairs(titles) do
        if Titles.IsFavorite(title.id) and not Titles.IsHidden(title.id) then
            rows[#rows + 1] = TitleList.CreateChoiceRow(Titles.RANDOM_FAVORITE)
            break
        end
    end
    return rows
end

-- Splits titles ({ id, name } each, in their order) into favourites and others, leaving out those
-- that don't pass the (lowercase) search and the filters.
function TitleList.SplitFavorites(titles, search)
    local favorites, others = {}, {}
    for _, title in ipairs(titles) do
        if Titles.Passes(title.id, title.name, search) then
            tinsert(Titles.IsFavorite(title.id) and favorites or others, title)
        end
    end
    return favorites, others
end

-- The search box's placeholder: how many titles the list has (that pass the filters), e.g.
-- "Search 142 titles". It only shows while the search is empty, when the list has them all.
function TitleList.UpdateSearchCount(searchBox, favorites, others)
    if TitleList.GetSearch(searchBox) == "" then
        searchBox.Instructions:SetText(format(ns.L["Search %d titles"], #favorites + #others))
    end
end

-- The first of titles ({ id, name } each) whose name contains the search, or nil.
local function FirstNameMatch(titles, search)
    for _, title in ipairs(titles) do
        if Titles.NameMatches(title.name, search) then
            return title
        end
    end
end

-- The title Enter in the search box picks: the first one the search finds (the first favourite, or
-- else the first other title), or nil. Titles found by name come before those found by their
-- expansion or activity. Only while typing a search (the box has focus and some text), so a stray
-- Enter does nothing. Its card is highlighted like a hovered one meanwhile.
function TitleList.GetEnterChoice(searchBox, favorites, others)
    local search = TitleList.GetSearch(searchBox)
    if not searchBox:HasFocus() or search == "" then
        return nil
    end
    local first = FirstNameMatch(favorites, search) or FirstNameMatch(others, search)
        or favorites[1] or others[1]
    return first and first.id
end

-- Sets up a list's search box: Enter calls choose with the title getChoice returns (see
-- GetEnterChoice), and refresh redraws the list when the box gains or loses focus, for the
-- highlight. The choice is read before the box loses focus, which redraws the list without it.
function TitleList.SetupSearchEnter(searchBox, getChoice, choose, refresh)
    searchBox:SetScript("OnEnterPressed", function()
        local choice = getChoice()
        searchBox:ClearFocus()
        if choice then
            choose(choice)
        end
    end)
    searchBox:HookScript("OnEditFocusGained", refresh)
    searchBox:HookScript("OnEditFocusLost", refresh)
end

-- A data provider with the rows of each group in turn, each { index, playerTitle } as Blizzard's
-- Titles list has them. The last row of a group gets dividerAfter when more rows follow.
function TitleList.CreateDataProvider(groups)
    local rows = {}
    for _, group in ipairs(groups) do
        if #group > 0 and #rows > 0 then
            rows[#rows].dividerAfter = true
        end
        for _, row in ipairs(group) do
            rows[#rows + 1] = { index = #rows + 1, playerTitle = row }
        end
    end
    return CreateDataProvider(rows)
end

-- Sets up a list's view: rows as tall as a card, plus the divider's space for the last of a group.
function TitleList.SetupView(view, top, bottom, left, right)
    view:SetElementExtentCalculator(function(_, elementData)
        return TitleList.CARD_HEIGHT + (elementData.dividerAfter and DIVIDER_SPACE or 0)
    end)
    view:SetPadding(top, bottom, left, right, TitleList.CARD_SPACING)
end

-- Puts region (a card's fill or outline) on the card: the top of the row, as tall as a card.
function TitleList.AnchorToCard(region)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT")
    region:SetPoint("TOPRIGHT")
    region:SetHeight(TitleList.CARD_HEIGHT)
end

-- A card's text ends this far from the card's right edge, or as far as the star reaches (with a
-- little space) while the star shows.
local TEXT_INSET = 10
local STAR_SPACE = 24

-- Titles too long for a card get a smaller font, down to this much smaller than the normal one.
local MAX_SHRINK = 2

-- Sets the right side of a card's text (the left is set by the caller): it takes the star's space
-- while the star doesn't show. A title that doesn't fit ends in "...".
function TitleList.FitText(text, fill, starShown)
    text.marqueeRightInset = starShown and STAR_SPACE or TEXT_INSET
    text:SetPoint("RIGHT", fill, "RIGHT", -text.marqueeRightInset, 0)
end

-- The font size each title fits at, so redrawing a list (scrolling, typing a search) doesn't
-- measure it again: [font .. normal size .. width] = { [text] = size }.
local fittedSizes = {}

-- Gives a title too long for its card (fill) a smaller font, so it fits without the star. Showing
-- the star doesn't change the size: the title ends in "..." then. Call it when the text or the
-- card's width changes.
function TitleList.FitFont(text, fill)
    local font, size, flags = text:GetFont()
    if not font then
        return
    end
    -- The normal size, from before any shrinking (rows are reused).
    text.marqueeFontSize = text.marqueeFontSize or size
    local normalSize = text.marqueeFontSize
    local available = fill:GetWidth() - 2 * TEXT_INSET
    -- No width before the list is laid out: fitted again when the card gets its size.
    if available <= 0 then
        text:SetFont(font, normalSize, flags)
        return
    end
    local key = font .. normalSize .. ":" .. floor(available)
    local sizes = fittedSizes[key]
    if not sizes then
        sizes = {}
        fittedSizes[key] = sizes
    end
    local title = text:GetText() or ""
    local fitted = sizes[title]
    if not fitted then
        fitted = normalSize
        text:SetFont(font, fitted, flags)
        while fitted > normalSize - MAX_SHRINK and text:GetUnboundedStringWidth() > available do
            fitted = fitted - 1
            text:SetFont(font, fitted, flags)
        end
        sizes[title] = fitted
    end
    if fitted ~= size then
        text:SetFont(font, fitted, flags)
    end
end

-- On hovering a card: a tooltip with the whole title, if it ends in "..." (see FitText).
function TitleList.ShowFullTitle(owner, text, fill)
    local width = fill:GetWidth() - TEXT_INSET - (text.marqueeRightInset or TEXT_INSET)
    if text:GetUnboundedStringWidth() > width then
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(text:GetText())
        GameTooltip:Show()
    end
end

-- Shows the divider below a row's card, or hides it. The divider's space can't be clicked.
function TitleList.UpdateDivider(row, shown)
    if shown and not row.MarqueeDivider then
        local divider = row:CreateTexture(nil, "ARTWORK")
        divider:SetHeight(ns.SetDividerTexture(divider))
        -- Halfway between this card and the next one (CARD_SPACING further down).
        divider:SetPoint("LEFT", row, "BOTTOMLEFT", 0, (DIVIDER_SPACE - TitleList.CARD_SPACING) / 2)
        divider:SetPoint("RIGHT", row, "BOTTOMRIGHT", 0, (DIVIDER_SPACE - TitleList.CARD_SPACING) / 2)
        row.MarqueeDivider = divider
    end
    if row.MarqueeDivider then
        row.MarqueeDivider:SetShown(shown)
    end
    row:SetHitRectInsets(0, 0, 0, shown and DIVIDER_SPACE or 0)
end

-- Rows that do something rather than being a title (IDs below 1) are white, titles gold, hidden
-- titles (while the Filter menu shows them) grey.
function TitleList.SetTextColor(fontString, choice)
    local color = choice < 1 and HIGHLIGHT_FONT_COLOR or Titles.IsHidden(choice) and GRAY_FONT_COLOR
        or NORMAL_FONT_COLOR
    fontString:SetTextColor(color:GetRGB())
end

-- Counts how many of the character's titles each expansion and activity has, into expansions and
-- activities ([key] = count). Hidden titles count as the Filter menu's Hidden titles choice shows
-- them.
local function CountTitles(expansions, activities)
    wipe(expansions)
    wipe(activities)
    for _, titleID in ipairs(Titles.GetKnownTitleIDs()) do
        if Titles.PassesHidden(titleID) then
            local expansion, activity = Titles.GetTags(titleID)
            if expansion then
                expansions[expansion] = (expansions[expansion] or 0) + 1
            end
            activities[activity] = (activities[activity] or 0) + 1
        end
    end
end

-- Space between a checkbox's box and its name (as Blizzard's MenuVariants.CreateCheckbox sets it),
-- between the name and its number of titles, and the number's grey.
local CHECKBOX_TEXT_GAP = 7
local COUNT_GAP = 12
local COUNT_COLOR = CreateColor(0.7, 0.7, 0.7)

-- Shows an option's number of titles (from counts) in grey at the right edge of the menu, so the
-- numbers line up. Read when the submenu opens, so a change to Hidden titles shows. Returns the
-- checkbox's size, as the menu can't work it out with text on both sides.
local function AddCount(checkbox, counts, option)
    checkbox:AddInitializer(function(button)
        local countText = button:AttachFontString()
        countText:SetHeight(20)
        countText:SetPoint("RIGHT", 0, 1)
        countText:SetJustifyH("RIGHT")
        countText:SetTextColor(COUNT_COLOR:GetRGB())
        countText:SetText(counts[option] or 0)
        local width = button.leftTexture1:GetWidth() + CHECKBOX_TEXT_GAP + button.fontString:GetUnboundedStringWidth()
            + COUNT_GAP + countText:GetUnboundedStringWidth()
        return width, 20
    end)
end

-- Adds Check All / Uncheck All and a checkbox per option to a submenu.
local function AddOptions(menu, changed, options, getName, counts, isShown, setShown, setAllShown)
    menu:CreateButton(CHECK_ALL, function()
        setAllShown(true)
        changed()
        return MenuResponse.Refresh
    end)
    menu:CreateButton(UNCHECK_ALL, function()
        setAllShown(false)
        changed()
        return MenuResponse.Refresh
    end)
    menu:CreateDivider()
    for _, option in ipairs(options) do
        local checkbox = menu:CreateCheckbox(getName(option), function()
            return isShown(option)
        end, function()
            setShown(option, not isShown(option))
            changed()
        end)
        AddCount(checkbox, counts, option)
    end
end

-- Makes dropdown (a WowStyle1FilterDropdownTemplate) the Filter button: expansions and activities,
-- each with how many titles the character has there (not narrowed by the other filter or the
-- search), and whether hidden titles show, with the reset button while something is filtered.
-- changed() runs after every change. The filters are the same everywhere (see Titles).
function TitleList.SetupFilterDropdown(dropdown, changed)
    dropdown:SetText(FILTER)
    dropdown:SetupMenu(function(_, root)
        local expansionCounts, activityCounts = {}, {}
        CountTitles(expansionCounts, activityCounts)
        -- Newest expansion first.
        local expansions = {}
        for expansion = Titles.NUM_EXPANSIONS - 1, 0, -1 do
            expansions[#expansions + 1] = expansion
        end
        AddOptions(root:CreateButton(EXPANSION_FILTER_TEXT), changed, expansions, Titles.GetExpansionName,
            expansionCounts, Titles.IsExpansionShown, Titles.SetExpansionShown, Titles.SetAllExpansionsShown)
        AddOptions(root:CreateButton(ns.L["Activity"]), changed, Titles.ACTIVITIES, Titles.GetActivityName,
            activityCounts, Titles.IsActivityShown, Titles.SetActivityShown, Titles.SetAllActivitiesShown)
        local hidden = root:CreateButton(ns.L["Hidden titles"])
        for _, mode in ipairs({
            { Titles.HIDE_HIDDEN, ns.L["Hide hidden titles"] },
            { Titles.ONLY_HIDDEN, ns.L["Only hidden titles"] },
            { Titles.ALL_TITLES, ns.L["All titles"] },
        }) do
            hidden:CreateRadio(mode[2], function()
                return Titles.GetHiddenMode() == mode[1]
            end, function()
                Titles.SetHiddenMode(mode[1])
                CountTitles(expansionCounts, activityCounts)
                changed()
                return MenuResponse.Refresh
            end)
        end
    end)
    dropdown:SetIsDefaultCallback(function()
        return not Titles.IsFiltered()
    end)
    dropdown:SetDefaultCallback(function()
        Titles.ResetFilters()
        changed()
    end)
end

-- The (lowercase) text in a search box.
function TitleList.GetSearch(searchBox)
    return strtrim(searchBox:GetText()):lower()
end
