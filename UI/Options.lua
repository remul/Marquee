local _, ns = ...
local L = ns.L

-- Marquee's category in Blizzard's Options (AddOns tab), with the account's settings in ns.db,
-- grouped under section headers. Settings for one character are in the gear menu above the Titles
-- list instead (see TitlesPane).
local Options = {}
ns.Options = Options

local category, layout

local function Register(key, varType, label, default)
    return Settings.RegisterAddOnSetting(category, "Marquee_" .. key, key, ns.db, varType, label, default)
end

local function AddCheckbox(key, label, tooltip)
    Settings.CreateCheckbox(category, Register(key, Settings.VarType.Boolean, label, false), tooltip)
end

-- A dropdown; options is a list of { value, label, tooltip }. Returns the setting.
local function AddDropdown(key, label, default, options, tooltip)
    local setting = Register(key, Settings.VarType.String, label, default)
    Settings.CreateDropdown(category, setting, function()
        local container = Settings.CreateControlTextContainer()
        for _, option in ipairs(options) do
            container:Add(option[1], option[2], option[3])
        end
        return container:GetData()
    end, tooltip)
    return setting
end

local function AddSection(name)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
end

-- Called once ns.db is loaded.
function Options:Setup()
    category, layout = Settings.RegisterVerticalLayoutCategory(ns.TITLE)
    local SituationTitles = ns.SituationTitles
    AddSection(L["Outfit titles"])
    local situationTitles = AddDropdown("situationTitles", L["When the game changes your outfit"],
        SituationTitles.CLICK, {
            { SituationTitles.CLICK, L["On your next key or click"],
                L["Your next key press, or click on the game world or an action button, wears the outfit's title."] },
            { SituationTitles.ASK, L["Ask"], L["A prompt asks whether to wear the outfit's title."] },
            { SituationTitles.OFF, L["Don't change the title"],
                L["The title only changes when you put an outfit on yourself."] },
        }, L["In some situations the game puts on an outfit by itself (set in the transmog window). Addons can only change your title with a click or key press, so the outfit's title waits for one. Never in combat."])
    situationTitles:SetValueChangedCallback(SituationTitles.OnModeChanged)

    AddSection(L["Development"])
    AddCheckbox("debug", L["Debug messages in chat"], L["Shows details in chat, for troubleshooting."])

    Settings.RegisterAddOnCategory(category)
end

-- Blizzard's Options can't be opened in combat.
function Options:Open()
    if InCombatLockdown() then
        return
    end
    Settings.OpenToCategory(category:GetID())
end
