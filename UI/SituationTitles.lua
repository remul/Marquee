local _, ns = ...
local L = ns.L
local Titles = ns.Titles
local Outfits = ns.Outfits

-- Outfits the game puts on by itself (its situations, set in the transmog window: a
-- specialization, a place, an activity) can't change the title right away, as setting one needs
-- a click or key press. Their title waits instead, and is worn depending on the setting
-- (ns.db.situationTitles): with a prompt (ASK), with the next key press or click on the game
-- world or an action button (CLICK), or not at all (OFF). Never in combat: the title waits until it ends. Only the title of
-- the last outfit put on waits.
local SituationTitles = {}
ns.SituationTitles = SituationTitles

SituationTitles.ASK = "ask"
SituationTitles.CLICK = "click"
SituationTitles.OFF = "off"

-- An outfit put on this long after it was used by hand (see NoteManualSwitch) was put on by that
-- use, not by the game. Long enough for the outfit's spell and the server's answer.
local MANUAL_WINDOW = 10

-- The title waiting to be worn: { outfitID = , choice = } (a choice as in Outfits.GetChoice).
local pending
-- The outfit last used by hand, and when (GetTime).
local manualOutfitID, manualTime
-- InCombatLockdown() is still false while PLAYER_REGEN_DISABLED is handled, so the events set this.
local inCombat = false
local listening = false
-- Sees key presses while listening, and passes them on to the game.
local keyListener
local prompt
-- Set while Marquee hides the prompt itself, so hiding it doesn't count as "Not now".
local hidingPrompt = false

local function GetMode()
    local mode = ns.db.situationTitles
    if mode == SituationTitles.ASK or mode == SituationTitles.OFF then
        return mode
    end
    return SituationTitles.CLICK
end

-- The outfit worn (0 for none), or nil if the game hides it from addons (e.g. in combat).
local function GetActiveOutfitID()
    local outfitID = C_TransmogOutfitInfo.GetActiveOutfitID()
    if outfitID == nil or ns.Client.IsSecret(outfitID) then
        return nil
    end
    return outfitID
end

local function GetOutfitName(outfitID)
    local info = C_TransmogOutfitInfo.GetOutfitInfo(outfitID)
    return info and info.name or "?"
end

-- True if the choice is the title worn now. Random choices never are: they change it.
local function IsWorn(choice)
    local current = GetCurrentTitle()
    if choice == Titles.NO_TITLE then
        return current <= 0
    end
    return choice > 0 and current == choice
end

-- True if wearing the choice would change something: a known title, or a random one to pick from.
local function CanWear(choice)
    if choice == Titles.NO_TITLE then
        return true
    elseif choice == Titles.RANDOM or choice == Titles.RANDOM_FAVORITE then
        return Titles.HasRandomChoice(choice == Titles.RANDOM_FAVORITE)
    end
    return choice > 0 and IsTitleKnown(choice)
end

local Update

-- Wears the waiting title. Runs in a click or key press.
local function WearPending()
    local choice = pending.choice
    pending = nil
    Update()
    local titleID = Titles.Wear(choice)
    ns:Debug("Wearing", Titles.GetChoiceName(choice), "for the game's outfit:", titleID or "none to wear")
    if titleID and ns.db.debug then
        -- Shows whether the game took it (it ignores titles set outside a click or key press).
        C_Timer.After(1, function()
            ns:Debug("Title now", GetCurrentTitle(), titleID == GetCurrentTitle() and "(as set)" or "(not as set)")
        end)
    end
    return titleID
end

-- A key press or click wears the waiting title. Only from a frame's script run by the input (a key,
-- a click on the game world or an action button): the game blocks setting a title from events such
-- as GLOBAL_MOUSE_DOWN. Clicks on other windows can't be seen from such a script.
function SituationTitles.OnInput()
    if not listening or not pending or inCombat then
        return
    end
    local titleID = WearPending()
    if titleID then
        ns:Print(format(L["Your title is now %s."], Titles.GetChoiceName(titleID)))
    end
end

-- Made when first needed, out of combat: passing keys on can't be set in combat, and a keyboard
-- frame that doesn't would take all keys from the game.
local function CreateKeyListener()
    keyListener = CreateFrame("Frame", nil, UIParent)
    keyListener:SetPropagateKeyboardInput(true)
    keyListener:EnableKeyboard(true)
    keyListener:SetScript("OnKeyDown", SituationTitles.OnInput)
    keyListener:Hide()
end

local function SetListening(listen)
    listening = listen
    if listen and not keyListener and not InCombatLockdown() then
        CreateKeyListener()
    end
    if keyListener then
        keyListener:SetShown(listen)
    end
end

-- The prompt: a dialog like the game's own (Blizzard's StaticPopup isn't used, as an addon's
-- dialogs there can break the game's own ones). Escape closes it like "Not now".
local function CreatePrompt()
    prompt = CreateFrame("Frame", "MarqueeSituationPrompt", UIParent)
    prompt:SetWidth(320)
    prompt:SetPoint("TOP", UIParent, "TOP", 0, -135)
    prompt:SetFrameStrata("DIALOG")
    prompt:SetToplevel(true)
    prompt:EnableMouse(true)
    prompt:Hide()

    local border = CreateFrame("Frame", nil, prompt, "DialogBorderTemplate")
    border:SetAllPoints()

    prompt.Text = prompt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    prompt.Text:SetPoint("TOP", 0, -18)
    prompt.Text:SetWidth(280)

    local wear = CreateFrame("Button", nil, prompt, "UIPanelButtonTemplate")
    wear:SetSize(128, 22)
    wear:SetPoint("BOTTOMRIGHT", prompt, "BOTTOM", -6, 16)
    wear:SetText(L["Wear"])
    wear:SetScript("OnClick", function()
        if pending then
            WearPending()
        end
    end)

    local notNow = CreateFrame("Button", nil, prompt, "UIPanelButtonTemplate")
    notNow:SetSize(128, 22)
    notNow:SetPoint("BOTTOMLEFT", prompt, "BOTTOM", 6, 16)
    notNow:SetText(L["Not now"])
    notNow:SetScript("OnClick", function()
        prompt:Hide()
    end)

    prompt:SetScript("OnHide", function()
        -- Still shown itself while the whole interface is hidden (Alt+Z, a cinematic): that isn't
        -- "Not now".
        if not hidingPrompt and pending and not prompt:IsShown() then
            ns:Debug("Not wearing", Titles.GetChoiceName(pending.choice))
            pending = nil
            Update()
        end
    end)
    tinsert(UISpecialFrames, prompt:GetName())
end

local function ShowPrompt()
    if not prompt then
        CreatePrompt()
    end
    local outfitName = NORMAL_FONT_COLOR:WrapTextInColorCode(GetOutfitName(pending.outfitID))
    local titleName = NORMAL_FONT_COLOR:WrapTextInColorCode(Titles.GetChoiceName(pending.choice))
    prompt.Text:SetText(format(L["The game put on your outfit %s. Wear its title, %s?"], outfitName, titleName))
    prompt:SetHeight(prompt.Text:GetStringHeight() + 72)
    prompt:Show()
end

-- Hides the prompt and keeps the title waiting.
local function HidePrompt()
    if prompt and prompt:IsShown() then
        hidingPrompt = true
        prompt:Hide()
        hidingPrompt = false
    end
end

-- Shows the prompt or listens for a click while a title waits (and not in combat), and stops
-- otherwise.
function Update()
    local mode = GetMode()
    local waiting = pending ~= nil and not inCombat
    SetListening(waiting and mode == SituationTitles.CLICK)
    if waiting and mode == SituationTitles.ASK then
        ShowPrompt()
    else
        HidePrompt()
    end
end

-- The game put an outfit on: its title waits, if it has one that isn't worn yet. Otherwise a
-- title that waited for the outfit before is dropped.
local function OnOutfitPutOn(outfitID)
    local choice = Outfits.GetChoice(outfitID)
    if GetMode() == SituationTitles.OFF or choice == Titles.KEEP or IsWorn(choice) or not CanWear(choice) then
        ns:Debug("The game put on outfit", outfitID, "- title unchanged")
        pending = nil
    else
        ns:Debug("The game put on outfit", outfitID, "- waiting to wear", Titles.GetChoiceName(choice))
        pending = { outfitID = outfitID, choice = choice }
    end
    Update()
end

-- Compares the outfit worn with the one before (saved, so a switch during a loading screen or
-- while logged out counts too).
local function Check()
    local outfitID = GetActiveOutfitID()
    if outfitID == nil then
        -- Checked again after combat.
        return
    end
    local previous = ns.charDb.activeOutfitID
    ns.charDb.activeOutfitID = outfitID
    if previous == nil or outfitID == previous then
        return
    end
    if outfitID == manualOutfitID and GetTime() - manualTime < MANUAL_WINDOW then
        -- Its title was worn by the click or key press that put it on (see Outfits).
        manualOutfitID = nil
        SituationTitles.Drop()
        return
    end
    OnOutfitPutOn(outfitID)
end

-- Drops the waiting title: another one was just worn.
function SituationTitles.Drop()
    if pending then
        pending = nil
        Update()
    end
end

-- Called by Outfits when an outfit is put on by hand: its title is worn by that click.
function SituationTitles.NoteManualSwitch(outfitID)
    manualOutfitID, manualTime = outfitID, GetTime()
    SituationTitles.Drop()
end

-- Called when the setting changes: a title waiting is dropped when it's turned off, and shown or
-- listened for in the new way otherwise.
function SituationTitles.OnModeChanged()
    if GetMode() == SituationTitles.OFF then
        pending = nil
    end
    Update()
end

function SituationTitles:Setup()
    inCombat = InCombatLockdown()
    -- The event may come before the hooks that note an outfit put on by hand have run (they run
    -- after the call that puts it on), so the check waits a frame.
    ns:RegisterEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED", function()
        C_Timer.After(0, Check)
    end)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", Check)
    ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        inCombat = true
        Update()
    end)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        inCombat = false
        Check()
        Update()
    end)
    -- Clicks on the game world (also to turn the camera). Clicks on action buttons come from
    -- Outfits, which hooks them.
    WorldFrame:HookScript("OnMouseDown", SituationTitles.OnInput)
end
