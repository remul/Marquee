local _, ns = ...

-- What the game client can do, for the versions Marquee runs in (Retail and WoW Forever, the
-- original-era world). The rest of the addon asks for a feature here, never for a version: what a
-- client has is found by looking for its functions, so it holds whatever Blizzard adds or takes
-- away later.
local Client = {}
ns.Client = Client

-- Titles to choose (GetNumTitles, SetCurrentTitle...).
Client.hasTitles = GetNumTitles ~= nil and SetCurrentTitle ~= nil and GetTitleName ~= nil

-- The Titles list in the Character window, which Marquee adds to (see TitlesPane). Known once the
-- Character window has loaded.
function Client.HasTitleList()
    return Client.hasTitles and PaperDollFrame ~= nil and PaperDollFrame.TitleManagerPane ~= nil
        and PaperDollTitlesPane_UpdateScrollBox ~= nil and PaperDollTitlesPane_InitButton ~= nil
end

-- Whether the client has an event, to register only those it knows (an unknown one is an error).
function Client.HasEvent(event)
    return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event)
end

-- How many expansions the game has (1 for the original-era world): what the Filter menu offers.
function Client.GetNumExpansions(max)
    if GetClientDisplayExpansionLevel then
        return math.min(max, GetClientDisplayExpansionLevel() + 1)
    end
    return max
end

-- The expansion that brought transmog outfits as Retail has them (Midnight, patch 12.0).
local OUTFITS_EXPANSION = 11

-- Those outfits, which can have a title each (see Outfits). WoW Forever has the functions too, but
-- its own transmog menu, so the game has to have the outfits' expansion as well.
local outfits = C_TransmogOutfitInfo
Client.hasOutfits = Client.hasTitles and Client.GetNumExpansions(OUTFITS_EXPANSION + 1) > OUTFITS_EXPANSION
    and outfits ~= nil and outfits.GetOutfitsInfo ~= nil
    and outfits.GetOutfitInfo ~= nil and outfits.GetActiveOutfitID ~= nil
    and outfits.GetCurrentlyViewedOutfitID ~= nil and outfits.ChangeDisplayedOutfit ~= nil
    and outfits.CommitAndApplyAllPending ~= nil and GameTooltip.SetOutfit ~= nil
    and Client.HasEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED") and Client.HasEvent("VIEWED_TRANSMOG_OUTFIT_CHANGED")

-- Whether value is one the game hides from addons (e.g. in combat); clients without hidden values
-- have none.
Client.IsSecret = issecretvalue or function()
    return false
end

