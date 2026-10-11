local _, ns = ...
local L = ns.L
local Titles = ns.Titles

-- A title for each transmog outfit, chosen in the transmog window's character preview (see
-- OutfitPicker) and worn when the outfit is put on by hand: from the transmog window (its icon, or
-- saving changes to it, which puts it on too), or with the outfit on one of Blizzard's action bars
-- (click or key). Choosing a title for the outfit you're wearing wears it right away. Setting a
-- title needs a click or key press, so outfits the game switches to by itself (situations) wear
-- their title later (see SituationTitles).
local Outfits = {}
ns.Outfits = Outfits

-- The outfit's title: a title's ID, Titles.NO_TITLE, RANDOM or RANDOM_FAVORITE, or Titles.KEEP
-- (the default) to leave the title as it is. Anything else in the saved data counts as KEEP.
function Outfits.GetChoice(outfitID)
    local choice = ns.charDb.outfitTitles[outfitID]
    return type(choice) == "number" and choice or Titles.KEEP
end

function Outfits.SetChoice(outfitID, choice)
    ns.charDb.outfitTitles[outfitID] = choice ~= Titles.KEEP and choice or nil
end

-- The spell that puts an outfit on by hand (it has the outfit's cooldown and the global cooldown).
local OUTFIT_SPELL_ID = Constants.TransmogOutfitDataConsts
    and Constants.TransmogOutfitDataConsts.EQUIP_TRANSMOG_OUTFIT_MANUAL_SPELL_ID

-- How long ago a cooldown may have started to count as started by this click or key press.
local JUST_NOW = 0.1

-- True if the outfit could be put on by this click or key press, judged by its cooldown (a
-- SpellCooldownInfo, read right after using it): none running, or one that started just now (by
-- this use). The cooldown may only start once the server confirms the switch, so usually none runs
-- yet. A cooldown that started earlier (the global cooldown, or the outfit's own) means using the
-- outfit did nothing. Cooldowns the game hides from addons (e.g. in combat) count as running.
local function CouldPutOn(cooldown)
    local start, duration = cooldown.startTime, cooldown.duration
    if issecretvalue(start) or issecretvalue(duration) then
        return false
    end
    local now = GetTime()
    local running = start > 0 and duration > 0 and start + duration > now
    return not running or now - start < JUST_NOW
end

local function DescribeCooldown(cooldown)
    if issecretvalue(cooldown.startTime) or issecretvalue(cooldown.duration) then
        return "hidden"
    end
    return format("start %.2f, duration %.2f, now %.2f", cooldown.startTime, cooldown.duration, GetTime())
end

-- Wears the outfit's title, if it has one. Needs a click or key press.
local function WearOutfitTitle(outfitID)
    local choice = Outfits.GetChoice(outfitID)
    if choice ~= Titles.KEEP then
        ns:Debug("Outfit", outfitID, "wears", Titles.GetChoiceName(choice))
        Titles.Wear(choice)
    end
end

-- An outfit was used by hand: wears its title if the outfit could be put on. cooldown is the
-- outfit's right after using it (nil if unknown: then it's taken as put on). Runs in the click or
-- key press that used the outfit, as a title can only be changed then.
local function OnOutfitUsed(outfitID, cooldown)
    if not outfitID then
        return
    end
    if cooldown and not CouldPutOn(cooldown) then
        ns:Debug("Outfit", outfitID, "is on cooldown (" .. DescribeCooldown(cooldown) .. "); title unchanged")
        return
    end
    -- So the outfit isn't taken for one the game put on by itself (see SituationTitles).
    ns.SituationTitles.NoteManualSwitch(outfitID)
    WearOutfitTitle(outfitID)
end

-- Called when a title is chosen for an outfit, from that click: wears it if it's the outfit worn
-- (the game may hide which one that is, e.g. in combat).
function Outfits.OnChoiceChanged(outfitID)
    local activeID = C_TransmogOutfitInfo.GetActiveOutfitID()
    if not issecretvalue(activeID) and outfitID == activeID then
        ns.SituationTitles.Drop()
        WearOutfitTitle(outfitID)
    end
end

-- "Title: the Kingslayer" in an outfit's tooltip, for outfits with a title.
local function AddTooltipLine(tooltip, outfitID)
    local choice = Outfits.GetChoice(outfitID)
    if choice ~= Titles.KEEP then
        tooltip:AddLine(format(L["Title: %s"], Titles.GetChoiceName(choice)), HIGHLIGHT_FONT_COLOR:GetRGB())
        tooltip:Show()
    end
end

-- The outfit on an action slot, or nil. The game may hide an action's info from addons (e.g. in
-- combat); hidden values can't be compared, so they count as no outfit.
local function GetActionOutfit(slot)
    local actionType, actionID = GetActionInfo(slot)
    if issecretvalue(actionType) or issecretvalue(actionID) or actionType ~= "outfit" then
        return nil
    end
    return actionID
end

-- An action button was used: by a click (PostClick) or its key (TryUseActionButton). Both run on
-- press and on release; the action itself happens on one of them, depending on the "Cast action
-- keybinds on key down" setting, so the title changes only then.
local function OnActionButtonUsed(button, isDown)
    if not button.action or isDown ~= C_CVar.GetCVarBool("ActionButtonUseKeyDown") then
        return
    end
    local outfitID = GetActionOutfit(button.action)
    if outfitID then
        OnOutfitUsed(outfitID, C_ActionBar.GetActionCooldown(button.action))
    end
end

local hookedButtons = {}

local function HookActionButton(button)
    if hookedButtons[button] then
        return
    end
    hookedButtons[button] = true
    button:HookScript("PostClick", function(_, _, down)
        OnActionButtonUsed(button, down)
        -- After the outfit's own title, so an outfit used drops a title waiting for another.
        ns.SituationTitles.OnInput()
    end)
end

function Outfits:Setup()
    -- In the transmog window, clicking an outfit's icon puts it on with this.
    hooksecurefunc(C_TransmogOutfitInfo, "ChangeDisplayedOutfit", function(outfitID)
        OnOutfitUsed(outfitID, OUTFIT_SPELL_ID and C_Spell.GetSpellCooldown(OUTFIT_SPELL_ID))
    end)
    -- Save Outfit ("Save and apply outfit changes", or its gold / discount question) saves the outfit
    -- shown and puts it on. It's only enabled when that can be done, so no cooldown check.
    hooksecurefunc(C_TransmogOutfitInfo, "CommitAndApplyAllPending", function()
        OnOutfitUsed(C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID())
    end)

    -- Blizzard's action bars: clicks, and keys (which don't click the button).
    if ActionBarButtonEventsFrame then
        for _, button in pairs(ActionBarButtonEventsFrame.frames) do
            HookActionButton(button)
        end
        hooksecurefunc(ActionBarButtonEventsFrame, "RegisterFrame", function(_, button)
            HookActionButton(button)
        end)
    end
    hooksecurefunc("TryUseActionButton", OnActionButtonUsed)

    hooksecurefunc(GameTooltip, "SetOutfit", AddTooltipLine)
    hooksecurefunc(GameTooltip, "SetAction", function(tooltip, slot)
        local outfitID = GetActionOutfit(slot)
        if outfitID then
            AddTooltipLine(tooltip, outfitID)
        end
    end)
end
