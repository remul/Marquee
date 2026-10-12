local _, ns = ...
local L = ns.L
local Titles = ns.Titles

-- A title for each transmog outfit, chosen in the transmog window's character preview (see
-- OutfitPicker) and worn when the outfit is put on by hand: from the transmog window (its icon, or
-- saving changes to it, which puts it on too), or with the outfit on an action bar (click or key):
-- Blizzard's, Dominos', or one made with LibActionButton (Bartender, ElvUI). Choosing a title for the outfit you're wearing wears it right away. Setting a
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

-- True if a button acts on press (isDown) rather than release: its own setting, or else the "Cast
-- action keybinds on key down" setting.
local function ActsOn(button, isDown)
    local onDown = button:GetAttribute("useOnKeyDown")
    if onDown == nil then
        onDown = C_CVar.GetCVarBool("ActionButtonUseKeyDown")
    end
    return isDown == (onDown and true or false)
end

-- An action slot was used from button: by a click (PostClick) or its key (TryUseActionButton for
-- Blizzard's bars, a click for the others). Both run on press and on release; the action itself
-- happens on one of them, so the title changes only then.
local function OnActionUsed(button, slot, isDown)
    if not slot or not ActsOn(button, isDown) then
        return
    end
    local outfitID = GetActionOutfit(slot)
    if outfitID then
        OnOutfitUsed(outfitID, C_ActionBar.GetActionCooldown(slot))
    end
end

local function OnActionButtonUsed(button, isDown)
    OnActionUsed(button, button.action, isDown)
end

local hookedButtons = {}

-- Hooks a button's clicks; getSlot(button) gives the action slot it uses (nil for none).
local function HookButton(button, getSlot)
    if hookedButtons[button] then
        return
    end
    hookedButtons[button] = true
    button:HookScript("PostClick", function(_, _, down)
        OnActionUsed(button, getSlot(button), down)
        -- After the outfit's own title, so an outfit used drops a title waiting for another.
        ns.SituationTitles.OnInput()
    end)
end

local function GetButtonAction(button)
    return button.action
end

local function HookActionButton(button)
    HookButton(button, GetButtonAction)
end

-- Dominos: its buttons are Blizzard's kind, and their keys click a hidden button on each (bind)
-- that uses its parent's action.
local function GetParentAction(bind)
    return bind:GetParent().action
end

local function HookDominosButton(button)
    HookActionButton(button)
    if button.bind then
        HookButton(button.bind, GetParentAction)
    end
end

local function SetupDominos()
    local buttons = Dominos and Dominos.ActionButtons
    if not buttons or not buttons.AddCastOnKeyPressSupport then
        return
    end
    for button in pairs(buttons.buttons or {}) do
        HookDominosButton(button)
    end
    -- Buttons made later get their key's button here.
    hooksecurefunc(buttons, "AddCastOnKeyPressSupport", function(_, button)
        HookDominosButton(button)
    end)
end

-- LibActionButton (Bartender, and ElvUI's own copy): keys click the buttons too. A button's
-- action is only an action slot while it holds one (it can also hold a spell, item, ...).
local function GetLibAction(button)
    local kind, action = button:GetAction()
    if kind == "action" then
        return action
    end
end

local function SetupLibActionButton(name)
    local lib = LibStub and LibStub(name, true)
    if not lib or not lib.buttonRegistry or not lib.RegisterCallback then
        return
    end
    for button in pairs(lib.buttonRegistry) do
        HookButton(button, GetLibAction)
    end
    lib.RegisterCallback(Outfits, "OnButtonCreated", function(_, button)
        HookButton(button, GetLibAction)
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

    -- Other action bars, only if they're loaded: Dominos once it is, and the libraries once all
    -- addons are (they come with the addons that use them).
    EventUtil.ContinueOnAddOnLoaded("Dominos", SetupDominos)
    EventUtil.ContinueOnPlayerLogin(function()
        SetupLibActionButton("LibActionButton-1.0")
        SetupLibActionButton("LibActionButton-1.0-ElvUI")
    end)

    hooksecurefunc(GameTooltip, "SetOutfit", AddTooltipLine)
    hooksecurefunc(GameTooltip, "SetAction", function(tooltip, slot)
        local outfitID = GetActionOutfit(slot)
        if outfitID then
            AddTooltipLine(tooltip, outfitID)
        end
    end)
end
