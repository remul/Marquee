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

local function AddSection(name)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
end

-- Called once ns.db is loaded.
function Options:Setup()
    category, layout = Settings.RegisterVerticalLayoutCategory(ns.TITLE)
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
