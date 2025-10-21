-----------------------------------------------------------------------------------------------------
----------------------------------------  BattleGroundHealers  --------------------------------------
-----------------------------------------------------------------------------------------------------
----  Marks BG healer nameplates with a configurable icon.                                       ----                               
----                                                                                             ----
----  Supports two detection methods that can work simultaneously:                               ----
----    - Combat Log    : Detection based on the spells cast and auras applied.                  ----
----                      * Includes optional automatic Combat Log fix.                          ----
----    - BG Scoreboard : Detection based on the ratio between healing and damage.               ----
----                      (healing > h2d * damage  &  healing > hth)                             ----
----                                                                                             ----
----  Allows printing the list of detected healers to personal or public chat channels.          ----
----                                                                                             ----
----  Slash Commands:                                                                            ----
----    - /bgh       : Opens the configuration panel                                             ----
----    - /bgh print : Prints the list of detected healers to the selected channel               ----
----    - /bgh h2d # : Modifies healing-to-damage ratio threshold for BG Scoreboard detection    ----
----    - /bgh hth # : Modifies healing threshold for BG Scoreboard detection                    ----
----    - /bgh debug : Toggles Debug Mode                                                        ----
----                                                                                             ----
----  Designed for WoW 3.3.5a (WotLK)                                                            ----
----  by Khal                                                                                    ----
-----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------

local addonName = ...
local version = GetAddOnMetadata(addonName, "Version")

local DefaultSettings = {
    CLEUtracking = 1,           -- Detect healers via Combat Log (1 = enabled, 0 = disabled)
    CLEUfix = 1,                -- Automatic Combat Log fix (1 = enabled, 0 = disabled)
    WSSFtracking = 1,           -- Detect healers via BG Scoreboard (1 = enabled, 0 = disabled)
    h2dRatio = 2.5,             -- BG Scoreboard healing-to-damage ratio threshold (1 to 5)
    healingThreshold = 50000,   -- BG Scoreboard healing detection threshold (10k to 100k)
    printChannel = "BG",        -- Channel to print the healers list ("BG", "Party", "Guild" or "Self")
    iconStyle = "Blizzlike",    -- Icon style ("Blizzlike" or "Minimalist")
    iconSize = 40,              -- Icon size (20 to 40)
    iconAnchor = "top",         -- Icon anchor relative to the nameplate ("left", "top" or "right")
    iconXoffset = 0,            -- Horizontal offset relative to the icon anchor (-40 to 40)
    iconYoffset = 0,            -- Vertical offset relative to the icon anchor (-40 to 40)
    iconInvertColor = 0,        -- Invert icon colors, by default enemies are red and allies are blue (1 = enabled, 0 = disabled)
    showMessages = 1,           -- Addon chat messages (1 = enabled, 0 = disabled)
}

local setmetatable, print, next, ipairs, pairs, rawget, select, pcall, string_format, string_lower, string_find, table_insert, table_remove, math_sqrt, math_abs, math_floor, math_min, math_max, tonumber =
      setmetatable, print, next, ipairs, pairs, rawget, select, pcall, string.format, string.lower, string.find, table.insert, table.remove, math.sqrt, math.abs, math.floor, math.min, math.max, tonumber
local CreateFrame, GetSpellInfo, GetBattlefieldStatus, SetBattlefieldScoreFaction, RequestBattlefieldScoreData, GetNumBattlefieldScores, GetBattlefieldScore, IsInInstance, CombatLogClearEntries, SetMapToCurrentZone, GetCurrentMapAreaID, SendChatMessage, UnitName, UnitAura, UnitCanAttack, GetTime, wipe =
      CreateFrame, GetSpellInfo, GetBattlefieldStatus, SetBattlefieldScoreFaction, RequestBattlefieldScoreData, GetNumBattlefieldScores, GetBattlefieldScore, IsInInstance, CombatLogClearEntries, SetMapToCurrentZone, GetCurrentMapAreaID, SendChatMessage, UnitName, UnitAura, UnitCanAttack, GetTime, wipe
local UIDropDownMenu_SetWidth, UIDropDownMenu_SetText, UIDropDownMenu_Initialize, UIDropDownMenu_CreateInfo, UIDropDownMenu_AddButton, StaticPopup_Show, InterfaceOptions_AddCategory =
      UIDropDownMenu_SetWidth, UIDropDownMenu_SetText, UIDropDownMenu_Initialize, UIDropDownMenu_CreateInfo, UIDropDownMenu_AddButton, StaticPopup_Show, InterfaceOptions_AddCategory
local LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE, RAID_CLASS_COLORS, WorldFrame, WorldStateScoreFrame =
      LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE, RAID_CLASS_COLORS, WorldFrame, WorldStateScoreFrame

local BGH = CreateFrame("Frame", "BattleGroundHealers")
local CLEUframe = CreateFrame("Frame")
local L = BattleGroundHealers_Localization
local HEX_COLOR_ALLIANCE = "|cff00aeef"
local HEX_COLOR_HORDE = "|cffe63c3c"
local HEX_GREEN = "|cff88FF88"
local HEX_RED = "|cffff4444"
local CLEUhealers = {}
local WSSFhealers = {}
local GlobalNamePlates = {}
local ActiveNamePlates = {}
local MarkedNames = {}
local currentBGplayers = {}
local inBG = false
local CLEUregistered = false
local USSregistered = false
local playerFaction = false
local BlizzPlates = true
local KhalPlatesCheck = false
local TidyPlatesCheck = false
local ElvUICheck = false
local ElvUIdynamicAnchor = true -- Forces the icon to follow ElvUI's HealthBar (it moves or hides with it). Set to false for a static "always show" state.
local KuiNameplatesCheck = false
local AloftCheck = false
local debugMode = false

local BGStatus = {
	[1] = true,
	[2] = true,
	[3] = true
}

BGH.AllianceCount = 0
BGH.HordeCount = 0
BGH_Notifier = BGH_Notifier or {}
BGH_Notifier.OnHealerDetected = nil

local IconTextures = {
    Blizzlike = {
        Blue = "Interface\\AddOns\\BattleGroundHealers\\Artwork\\BlizzBlueIcon.tga",
        Red = "Interface\\AddOns\\BattleGroundHealers\\Artwork\\BlizzRedIcon.tga",
    },
    Minimalist = {
        Blue = "Interface\\AddOns\\BattleGroundHealers\\Artwork\\MiniBlueIcon.tga",
        Red = "Interface\\AddOns\\BattleGroundHealers\\Artwork\\MiniRedIcon.tga",
    }
}

local HealerClasses = {"PALADIN", "SHAMAN", "DRUID", "PRIEST"}
local HCN = {}
for _, className in ipairs(HealerClasses) do
    HCN[LOCALIZED_CLASS_NAMES_MALE[className]] = className
    HCN[LOCALIZED_CLASS_NAMES_FEMALE[className]] = className
end

local HealerSpells = {
    --------------------------------PALADIN--------------------------------
    20473, 20929, 20930, 27174, 33072, 48824, 48825,  -- Holy Shock	
    53563,  -- Beacon of Light
    31842,  -- Divine Illumination
    20216,  -- Divine Favor
    31834,  -- Light's Grace
    53655, 53656, 53657, 54152, 54153,  -- Judgements of the Pure
    53672, 54149,  -- Infusion of Light
    53659,  -- Sacred Cleansing
    --------------------------------SHAMAN---------------------------------
    49284, 49283, 32594, 32593, 974,  -- Earth Shield	
    61301, 61300, 61299, 61295,  -- Riptide
    51886,  -- Cleanse Spirit
    16190,  -- Mana Tide Totem
    16188,  -- Nature's Swiftness
    55198,  -- Tidal Force
    53390,  -- Tidal Waves
    31616,  -- Nature's Guardian
    16177, 16236, 16237, -- Ancestral Fortitude
    ---------------------------------DRUID---------------------------------
    53251, 53249, 53248, 48438,  -- Wild Growth
    33891,  -- Tree of Life
    18562,  -- Swiftmend
    17116,  -- Nature's Swiftness
    48504,  -- Living Seed
    45283, 45282, 45281,  -- Natural Perfection		
    --------------------------------DPRIEST--------------------------------
    47750, 52983, 52984, 52985,  -- Penance
    10060,  -- Power Infusion
    33206,  -- Pain Suppression
    47930,  -- Grace
    59891, 59890, 59889, 59888, 59887,  -- Borrowed Time
    45242, 45241, 45237,  -- Focused Will		
    47753,  -- Divine Aegis
    63944,  -- Renewed Hope	
    --------------------------------HPRIEST--------------------------------	
    48089, 48088, 34866, 34865, 34864, 34863, 34861,  -- Circle of Healing		
    47788,	-- Guardian Spirit	
    48085, 48084, 28276, 27874, 27873, 7001,  -- Lightwell Renew                
    33151,  -- Surge of light	
    65081, 64128,  -- Body and Soul
    33143,  -- Blessed Resilience         
    63725, 63724, 34754,  -- Holy Concentration
    63734, 63735, 63731,  -- Serendipity
    27827,  -- Spirit of Redemption                
}
local healerSpellHash = {}
for _, spellID in ipairs(HealerSpells) do
    healerSpellHash[spellID] = true
end

local playerName = UnitName("player")
local playerSpells = setmetatable({}, {
	__index = function(tbl, name)
		local _, _, _, cost, _, powerType = GetSpellInfo(name)
		rawset(tbl, name, not not ((cost and cost > 0) or (powerType and powerType == 5)))
		return rawget(tbl, name)
	end
})

local anchorMapping = {
    ["left"] = {
        anchorPoint = "RIGHT", relativePoint = "LEFT",
        xOffset = 8, yOffset = -9
    },
    ["top"] = {
        anchorPoint = "BOTTOM", relativePoint = "TOP",
        xOffset = 0, yOffset = -7
    },
    ["right"] = {
        anchorPoint = "LEFT", relativePoint = "RIGHT",
        xOffset = -28, yOffset = -9
    },
}

local function InitSettings()
    if not BGHsettings then
        BGHsettings = {}
    end
    for k, v in pairs(DefaultSettings) do
        if BGHsettings[k] == nil then
            BGHsettings[k] = DefaultSettings[k]
        end
    end
    for k in pairs(BGHsettings) do
        if not DefaultSettings[k] then
            BGHsettings[k] = nil
        end
    end
end

local function BGHprint(...)
	print("|cff00FF98[BGH]|r", ...)
end

local function HandleLevelTextOverlap(BGHframe)
    local texture = MarkedNames[BGHframe.activeName]
    local levelRegion = BGHframe.levelRegion
    if texture then
        if BGHsettings.iconAnchor == "right" then
            local x = BGHsettings.iconXoffset
            local y = BGHsettings.iconYoffset
            local D = BGHsettings.iconSize
            if BGHsettings.iconStyle == "Blizzlike" then
                local r = 0.5 * D
                local R = math_sqrt(((x + r - 12)/0.8)^2 + (y/0.5)^2)
                local d = math_abs(1 - 1/R)*math_sqrt((x + r - 12)^2+(y)^2)
                if d < r or R < 1 then
                    levelRegion:Hide()
                else
                    levelRegion:Show()
                end
            elseif BGHsettings.iconStyle == "Minimalist" then
                local inOverlapDomain = (
                    x < -0.2 * D + 14 and 
                    x > -0.8 * D + 14 and 
                    y < 0.325 * D - 0.5 and 
                    y > -0.325 * D + 0.5
                )
                local OverlapAdjustment = not (
                    x >= 0 and x <= 8 and
                    math_abs(y) >= 8 and math_abs(y) <= 18 and
                    D >= 3 * math_abs(y) + 3 and
                    D <= 69 - 5 * x
                )
                if inOverlapDomain and OverlapAdjustment then
                    levelRegion:Hide()
                else
                    levelRegion:Show()
                end
            else
                levelRegion:Show()
            end
        else
            levelRegion:Show()
        end
    else
        levelRegion:Show()
    end
end

------------- Update the icon texture if it changes  -------------
local function UpdateTextures(BGHframe)
    local texture = MarkedNames[BGHframe.activeName]
    if texture then
        if texture ~= BGHframe.prevTexture then
            BGHframe.icon:SetTexture(texture)
            BGHframe.icon:Show()
            BGHframe.prevTexture = texture
        end
    else
        BGHframe.icon:Hide()
        BGHframe.prevTexture = nil   
    end
    -- Hide Blizz default plate's level text if it overlaps with the icon
    if BlizzPlates then  
        HandleLevelTextOverlap(BGHframe)
    end
end

------------ Update all mark frames when the configuration changes  ------------
local function UpdateAllMarks()
    for plate, BGHframe in pairs(GlobalNamePlates) do
        if BGHframe.icon then
            BGHframe.icon:ClearAllPoints()
            local anchorData = anchorMapping[BGHsettings.iconAnchor or "top"]
            BGHframe.icon:SetPoint(
                anchorData.anchorPoint,
                plate,
                anchorData.relativePoint,
                BGHsettings.iconXoffset + anchorData.xOffset,
                BGHsettings.iconYoffset + anchorData.yOffset
            )
            BGHframe.icon:SetSize(BGHsettings.iconSize, BGHsettings.iconSize)
            UpdateTextures(BGHframe)
        end
    end
end

local function BGHonShow(BGHframe)
    local name = BGHframe.nameRegion:GetText()
    BGHframe.activeName = name
    ActiveNamePlates[name] = BGHframe
    if MarkedNames[name] then
        UpdateTextures(BGHframe)
    end 
end

local function BGHonHide(BGHframe)
    BGHframe.icon:Hide()
    ActiveNamePlates[BGHframe.activeName], BGHframe.activeName, BGHframe.prevTexture = nil
end

local function BGHonUpdate(BGHframe)
    if BGHframe.nameRegion:GetText() ~= BGHframe.activeName then
        BGHonHide(BGHframe)
        BGHonShow(BGHframe)
        BGHframe.activeName = BGHframe.nameRegion:GetText()
    end
end

---- Checks if the frame is a nameplate ----
local function IsNamePlate(frame)
    if frame.RealPlate  -- KhalPlates
    or frame.extended   -- TidyPlates
    or frame.UnitFrame  -- ElvUI
    or frame.kui        -- KuiNameplates
    or frame.aloftData  -- Aloft
    then
        return true
    end
    local _, r2 = frame:GetRegions()
    return r2 and r2:GetObjectType() == "Texture" and r2:GetTexture() == "Interface\\Tooltips\\Nameplate-Border"
end

---- Checks and replaces the nameplate anchor if custom ----
local function CheckCustomPlate(nameplate)
    local nameRegion, levelRegion = select(7, nameplate:GetRegions())
    if nameplate.RealPlate then -- KhalPlates
        if not KhalPlatesCheck then
            KhalPlatesCheck = true
            BlizzPlates = false
            anchorMapping = {
                ["left"] = {
                    anchorPoint = "RIGHT", relativePoint = "LEFT",
                    xOffset = 17.5, yOffset = 13
                },
                ["top"] = {
                    anchorPoint = "BOTTOM", relativePoint = "TOP",
                    xOffset = 0, yOffset = 1
                },
                ["right"] = {
                    anchorPoint = "LEFT", relativePoint = "RIGHT",
                    xOffset = -16, yOffset = 13
                },
            }
        end
    elseif nameplate.extended then -- TidyPlates
        nameplate = nameplate.extended
        if not TidyPlatesCheck then
            TidyPlatesCheck = true
            BlizzPlates = false
            anchorMapping = {
                ["left"] = {
                    anchorPoint = "RIGHT", relativePoint = "LEFT",
                    xOffset = 3, yOffset = 0
                },
                ["top"] = {
                    anchorPoint = "BOTTOM", relativePoint = "TOP",
                    xOffset = 0, yOffset = -5
                },
                ["right"] = {
                    anchorPoint = "LEFT", relativePoint = "RIGHT",
                    xOffset = -3, yOffset = 0
                },
            }
        end
    elseif nameplate.UnitFrame then -- ElvUI
        if ElvUIdynamicAnchor and nameplate.UnitFrame.Health then
            nameplate = nameplate.UnitFrame.Health
        else
            nameplate = nameplate.UnitFrame
        end
        if not ElvUICheck then
            ElvUICheck = true
            BlizzPlates = false
            anchorMapping = {
                ["left"] = {
                    anchorPoint = "RIGHT", relativePoint = "LEFT",
                    xOffset = 2, yOffset = 1
                },
                ["top"] = {
                    anchorPoint = "BOTTOM", relativePoint = "TOP",
                    xOffset = 0, yOffset = 12
                },
                ["right"] = {
                    anchorPoint = "LEFT", relativePoint = "RIGHT",
                    xOffset = -2, yOffset = 1
                },
            }
        end
    elseif nameplate.kui then -- KuiNameplates
        nameRegion, levelRegion = nameplate.kui.oldName, nameplate.kui.level
        if not KuiNameplatesCheck then
            KuiNameplatesCheck = true
            BlizzPlates = false
            anchorMapping = {
                ["left"] = {
                    anchorPoint = "RIGHT", relativePoint = "LEFT",
                    xOffset = 38, yOffset = 0
                },
                ["top"] = {
                    anchorPoint = "BOTTOM", relativePoint = "TOP",
                    xOffset = 0, yOffset = -10
                },
                ["right"] = {
                    anchorPoint = "LEFT", relativePoint = "RIGHT",
                    xOffset = -39, yOffset = 0
                },
            }
        end
    elseif nameplate.aloftData then -- Aloft
        if not AloftCheck then
            AloftCheck = true
            BlizzPlates = false
            anchorMapping = {
                ["left"] = {
                    anchorPoint = "RIGHT", relativePoint = "LEFT",
                    xOffset = 4, yOffset = 0
                },
                ["top"] = {
                    anchorPoint = "BOTTOM", relativePoint = "TOP",
                    xOffset = 0, yOffset = -1
                },
                ["right"] = {
                    anchorPoint = "LEFT", relativePoint = "RIGHT",
                    xOffset = -5, yOffset = 0
                },
            }
        end
    end
    return nameplate, nameRegion, levelRegion
end

-------- Setup a frame that manages the mark texture parameters  --------
local function SetupNamePlate(nameplate)
    local plate, nameRegion, levelRegion = CheckCustomPlate(nameplate)
    local BGHframe = CreateFrame("Frame", nil, plate)
    plate.BGHframe = BGHframe
    GlobalNamePlates[plate] = BGHframe
    BGHframe.icon = BGHframe:CreateTexture(nil, "OVERLAY")
    BGHframe.icon:ClearAllPoints()
    local anchorData = anchorMapping[BGHsettings.iconAnchor or "top"]
    BGHframe.icon:SetPoint(
        anchorData.anchorPoint,
        plate,
        anchorData.relativePoint,
        BGHsettings.iconXoffset + anchorData.xOffset,
        BGHsettings.iconYoffset + anchorData.yOffset
    )
    BGHframe.icon:SetSize(BGHsettings.iconSize, BGHsettings.iconSize)
    BGHframe.nameRegion = nameRegion
    BGHframe.activeName = nameRegion:GetText()
    ActiveNamePlates[BGHframe.activeName] = plate
    BGHframe.levelRegion = levelRegion
    BGHframe.levelRegion:SetDrawLayer("ARTWORK")
    BGHonShow(BGHframe)
    UpdateTextures(BGHframe)
    BGHframe:SetScript("OnUpdate", BGHonUpdate)
    BGHframe:SetScript("OnShow", BGHonShow)
    BGHframe:SetScript("OnHide", BGHonHide)
end

------ Detects when the number of nameplates in the WorldFrame increases  ------
local ChildCount, NewChildCount = 0
CreateFrame("Frame"):SetScript("OnUpdate", function()
    NewChildCount = WorldFrame:GetNumChildren()
    if ChildCount ~= NewChildCount then
        for i = ChildCount + 1, NewChildCount do
            local child = select(i, WorldFrame:GetChildren())
            -- 1 frame delay to ensure custom nameplate is available --
            CreateFrame("Frame"):SetScript("OnUpdate", function(self)
                self:Hide()
                if IsNamePlate(child) then
                    SetupNamePlate(child)
                end
            end)
        end
        ChildCount = NewChildCount
    end
end)

--------- Assigns a healer mark to a nameplate ---------
local function SetBGHmark(name, texture)
    if texture == "blue" then
        MarkedNames[name] = IconTextures.Blizzlike.Blue
    elseif texture == "red" then
        MarkedNames[name] = IconTextures.Blizzlike.Red
    elseif texture == "miniblue" then
        MarkedNames[name] = IconTextures.Minimalist.Blue
    elseif texture == "minired" then
        MarkedNames[name] = IconTextures.Minimalist.Red
    else
        MarkedNames[name] = texture
    end
    if ActiveNamePlates[name] then
        UpdateTextures(ActiveNamePlates[name])
    end
end

local function ClearHealers(list)
    for name in pairs(list) do
        SetBGHmark(name, nil)
    end
    wipe(list)
end

local function RGBToHex(r, g, b)
    return string_format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

----------- Updates BG players list -----------
local function UpdateCurrentBGplayers()
    currentBGplayers = {}
    for i = 1, GetNumBattlefieldScores() do
        local name, _, _, _, _, faction = GetBattlefieldScore(i)
        if name then
            name = name:match("([^%-]+).*")
            currentBGplayers[name] = true
            if not playerFaction and name == playerName then
                playerFaction = faction
                if debugMode then
                    BGHprint("Debug: Player Faction: ", playerFaction == 1 and "Alliance" or "Horde")
                end
            end
        end
    end
    local function ClearDeserterHealers(healersList)
        for name, data in pairs(healersList) do
            if not currentBGplayers[name] then
                if BGHsettings.showMessages == 1 or debugMode then
                    if data then
                        local class = data.class
                        local color = class and RAID_CLASS_COLORS[class]
                        local coloredName = color and RGBToHex(color.r, color.g, color.b) .. name .. "|r" or name
                        local factionText = data.faction == 1 and HEX_COLOR_ALLIANCE .. "(" .. L["Alliance"] .. ")|r" or HEX_COLOR_HORDE .. "(" .. L["Horde"] .. ")|r"
                        BGHprint(string_format(L["%s %s has left the BG, removed from healers list."], coloredName, factionText))
                    else
                        BGHprint(string_format(L["%s has left the BG, removed from healers list."], name))
                    end
                end
                healersList[name] = nil
                SetBGHmark(name, nil)
            end
        end
    end
    ClearDeserterHealers(WSSFhealers)
    ClearDeserterHealers(CLEUhealers)
end

---------- Updates the list of healers based on the BG Scoreboard (WorldStateScoreFrame), prioritizing the Combat Log healers list if active ----------
local function UpdateWSSFhealers()
    if BGHsettings.WSSFtracking == 1 then
        local name, faction, class, damageDone, healingDone, _
        for i = 1, GetNumBattlefieldScores() do
            name, _, _, _, _, faction, _, _, class, _, damageDone, healingDone = GetBattlefieldScore(i)
            if name then
                name = name:match("([^%-]+).*")
                if healingDone > BGHsettings.h2dRatio * damageDone and healingDone > BGHsettings.healingThreshold and HCN[class] then
                    if not WSSFhealers[name] and not CLEUhealers[name] and playerFaction then
                        WSSFhealers[name] = {class = HCN[class], faction = faction}
                        SetBGHmark(name, ((BGHsettings.iconInvertColor == 1) == (faction == playerFaction)) and IconTextures[BGHsettings.iconStyle].Red or IconTextures[BGHsettings.iconStyle].Blue)
                        if debugMode then
                            BGHprint(string_format("Debug: %s (%s) added to BG Scoreboard healers list.", name, faction == 1 and "Alliance" or "Horde"))
                        end 
                    end
                elseif WSSFhealers[name] then
                    WSSFhealers[name] = nil
                    SetBGHmark(name, nil)
                    if debugMode then
                        BGHprint(string_format("Debug: %s (%s) removed from BG Scoreboard healers list (below healing-to-damage ratio).", name, faction == 1 and "Alliance" or "Horde"))
                    end 
                end
            end
        end
    end
end

----------- Manages Combat Log tracking, considering a player can change specs during the Preparation phase -----------
local function UpdateCLEUstate()
    if BGHsettings.CLEUtracking == 1 then
        local inPreparation = false
        for i = 1, 40 do
            if select(11, UnitAura("player", i)) == 44521 then
                inPreparation = true
                break
            end
        end
        if inPreparation then
            if USSregistered and BGHsettings.CLEUfix == 1 then
                CLEUframe:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                USSregistered = false
                if debugMode then
                    BGHprint("Debug: Automatic Combat Log fix disabled until Preparation phase is over.")
                end
            end
            if CLEUregistered then
                CLEUframe:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                CLEUregistered = false
                ClearHealers(CLEUhealers)
                if debugMode then
                    BGHprint("Debug: Combat Log tracking disabled until Preparation phase is over.")
                end
            end
        else
            if not CLEUregistered then
                CLEUframe:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")    
                CLEUregistered = true        
                if debugMode then
                    BGHprint("Debug: Combat Log tracking enabled.")
                end 
            end
            if not USSregistered and BGHsettings.CLEUfix == 1 then
                CLEUframe:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                USSregistered = true
                if debugMode then
                    BGHprint("Debug: Automatic Combat Log fix enabled.")
                end 
            end
        end
    end
end

local lastCLEUtime = nil
local CLEUtimeout = nil
local CLEUcheck = false
------------------- Updates the list of healers based on Combat Log Events -------------------
local function CLEUhandler(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        lastCLEUtime = GetTime()
        local _, subEvent, _, sourceName, _, _, _, _, spellID = ...
        if subEvent == "SPELL_CAST_SUCCESS" or subEvent == "SPELL_AURA_APPLIED" then
            if healerSpellHash[spellID] then
                local shortName = sourceName:match("([^%-]+).*")
                if not CLEUhealers[shortName] then
                    if WorldStateScoreFrame:IsShown() and WorldStateScoreFrame.selectedTab and WorldStateScoreFrame.selectedTab > 1 then return end
                    SetBattlefieldScoreFaction()
                    RequestBattlefieldScoreData()
                    for i = 1, GetNumBattlefieldScores() do
                        local name, _, _, _, _, faction, _, _, class = GetBattlefieldScore(i)
                        if name then
                            name = name:match("([^%-]+).*")
                            if name == shortName and HCN[class] and playerFaction then
                                CLEUhealers[name] = {class = HCN[class], faction = faction}
                                SetBGHmark(name, ((BGHsettings.iconInvertColor == 1) == (faction == playerFaction)) and IconTextures[BGHsettings.iconStyle].Red or IconTextures[BGHsettings.iconStyle].Blue)
                                if BGH_Notifier.OnHealerDetected and faction ~= playerFaction then
                                    pcall(BGH_Notifier.OnHealerDetected, sourceName, HCN[class])
                                end
                                if debugMode then
                                    BGHprint(string_format("Debug: %s (%s) added to Combat Log healers list (spellID: %s)", name, faction == 1 and "Alliance" or "Horde", spellID))
                                end 
                                if WSSFhealers[name] then
                                    WSSFhealers[name] = nil
                                    if debugMode then
                                        BGHprint(string_format("Debug: %s (%s) removed from BG Scoreboard healers list (Combat Log list priority).", name, faction == 1 and "Alliance" or "Horde"))
                                    end
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, name = ...
        if unit == "player" and name and playerSpells[name] then
            CLEUcheck = true
            CLEUtimeout = 0.50
        end
    end
end

local function UpdateHealersCount()
    local hordeCount, allianceCount = 0, 0
    for _, data in pairs(CLEUhealers) do
        if data.faction == 0 then
            hordeCount = hordeCount + 1
        elseif data.faction == 1 then
            allianceCount = allianceCount + 1
        end
    end
    for _, data in pairs(WSSFhealers) do
        if data.faction == 0 then
            hordeCount = hordeCount + 1
        elseif data.faction == 1 then
            allianceCount = allianceCount + 1
        end
    end
    BGH.AllianceCount = allianceCount
    BGH.HordeCount = hordeCount
end

local lastUpdateTime = 0
local UPDATE_INTERVAL = 5
---------- Periodically updates healer lists and fix the Combat Log if it's unresponsive ----------
local function OnUpdate(self, elapsed)
    lastUpdateTime = lastUpdateTime + elapsed
    if lastUpdateTime >= UPDATE_INTERVAL then
        if not (WorldStateScoreFrame:IsShown() and WorldStateScoreFrame.selectedTab and WorldStateScoreFrame.selectedTab > 1) then
            SetBattlefieldScoreFaction()
            RequestBattlefieldScoreData()
            UpdateCurrentBGplayers()
            UpdateWSSFhealers()
            UpdateHealersCount()
        end
        UpdateCLEUstate()
        lastUpdateTime = 0
    end
	if CLEUcheck then
		CLEUtimeout = CLEUtimeout - elapsed
		if (CLEUtimeout > 0) then return end
		CLEUcheck = false
		if (lastCLEUtime and ( GetTime() - lastCLEUtime ) <= 1) then return end
		CombatLogClearEntries()
        if debugMode then
            BGHprint("Debug: Combat Log unresponsive. Entries cleared to fix it.")
        end   
	end
end

local lastPrintTime = 0
local printCooldown = 5
---------------- Prints the list of detected healers with a cooldown control ----------------
local function PrintDetectedHealers()
    if not inBG then
        BGHprint(L["Print failed (not in BG)"])
        return
    end
    local currentTime = GetTime()
    if currentTime - lastPrintTime < printCooldown then
        local timeRemaining = printCooldown - (currentTime - lastPrintTime)
        BGHprint(string_format(L["Wait %.1f s to print again."], timeRemaining))
        return
    end
    local allianceHealers = {}
    local allianceHealersColored = {}
    local hordeHealers = {}
    local hordeHealersColored = {}
    local function AppendHealers(healersList)
        for name, data in pairs(healersList) do
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.class]
            local coloredName = color and RGBToHex(color.r, color.g, color.b) .. name .. "|r" or name
            if data.faction == 1 then
                table_insert(allianceHealers, name)
                table_insert(allianceHealersColored, coloredName)
            else
                table_insert(hordeHealers, name)
                table_insert(hordeHealersColored, coloredName)
            end
        end
    end
    if BGHsettings.WSSFtracking == 1 then
        AppendHealers(WSSFhealers)
    end
    if BGHsettings.CLEUtracking == 1 then
        AppendHealers(CLEUhealers)
    end
    local BGNameByID = {
        [444] = L["Warsong Gulch"],
        [462] = L["Arathi Basin"],
        [402] = L["Alterac Valley"],
        [483] = L["Eye of the Storm"],
        [513] = L["Strand of the Ancients"],
        [541] = L["Isle of Conquest"],
    }
    SetMapToCurrentZone()
    local BGName = BGNameByID[GetCurrentMapAreaID()] or "current BG"
    local printChannel
    if BGHsettings.printChannel == "BG" then
        printChannel = "BATTLEGROUND"
    elseif BGHsettings.printChannel == "Party" then
        printChannel = "PARTY"
    elseif BGHsettings.printChannel == "Guild" then
        printChannel = "GUILD"
    else
        printChannel = nil
    end
    if printChannel then
        SendChatMessage(string_format("[BattleGroundHealers] " .. L["Healers detected in %s:"], BGName), printChannel)
        SendChatMessage(string_format(" - %d %s: %s", #allianceHealers, L["Alliance"], table.concat(allianceHealers, ", ")), printChannel)
        SendChatMessage(string_format(" - %d %s: %s", #hordeHealers, L["Horde"], table.concat(hordeHealers, ", ")), printChannel)
    else
        print("|cff00FF98================ BattleGroundHealers ================|r")
        print(string_format(" " .. L["Healers detected in %s:"], "|cffffd100" .. BGName .. "|r"))
        print(string_format("%s  - %d %s:|r %s", HEX_COLOR_ALLIANCE, #allianceHealersColored, L["Alliance"], table.concat(allianceHealersColored, ", ")))
        print(string_format("%s  - %d %s:|r %s", HEX_COLOR_HORDE, #hordeHealersColored, L["Horde"], table.concat(hordeHealersColored, ", ")))
        print("|cff00FF98==================================================|r")
    end
    lastPrintTime = currentTime
end

---------------------------- Creates a panel to manage the configuration settings  ----------------------------
local function ConfigUI()
    if not BGHConfigUIglobalFrame then
        local ConfigUIFrame = CreateFrame("Frame", "BGHConfigUIglobalFrame", UIParent)
        ConfigUIFrame:SetSize(294, 556)
        ConfigUIFrame:SetScale(0.9/UIParent:GetScale())
        ConfigUIFrame:SetPoint("CENTER")
        ConfigUIFrame:SetToplevel(true)
        ConfigUIFrame:Show()
        ConfigUIFrame.Icon = ConfigUIFrame:CreateTexture(nil, "BORDER")
        ConfigUIFrame.Icon:SetTexture("Interface\\AddOns\\BattleGroundHealers\\Artwork\\BGHicon")
        ConfigUIFrame.Icon:SetSize(50, 50)
        ConfigUIFrame.Icon:SetPoint("TOPLEFT")
        ConfigUIFrame.Title = ConfigUIFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ConfigUIFrame.Title:SetText("BattleGroundHealers")
        ConfigUIFrame.Title:SetPoint("TOP", 0, -14)
        ConfigUIFrame.Close = CreateFrame("Button", nil, ConfigUIFrame, "UIPanelCloseButton")
        ConfigUIFrame.Close:SetPoint("TOPRIGHT", -3, -4)
        ConfigUIFrame.TopLeftTex = ConfigUIFrame:CreateTexture(nil, "ARTWORK")
        ConfigUIFrame.TopLeftTex:SetTexture("Interface\\AddOns\\BattleGroundHealers\\Artwork\\BGHTopLeft")
        ConfigUIFrame.TopLeftTex:SetSize(208, 252)
        ConfigUIFrame.TopLeftTex:SetPoint("TOPLEFT")
        ConfigUIFrame.TopLeftTex:SetTexCoord(0.1875, 1, 0.015625, 1)
        ConfigUIFrame.LeftTex = ConfigUIFrame:CreateTexture(nil, "ARTWORK")
        ConfigUIFrame.LeftTex:SetTexture("Interface\\AddOns\\BattleGroundHealers\\Artwork\\BGHBottomLeft")
        ConfigUIFrame.LeftTex:SetSize(208, 120)
        ConfigUIFrame.LeftTex:SetPoint("BOTTOMLEFT", 0, 184)
        ConfigUIFrame.LeftTex:SetTexCoord(0.1875, 1, 0, 0.46875)
        ConfigUIFrame.BottomLeftTex = ConfigUIFrame:CreateTexture(nil, "ARTWORK")
        ConfigUIFrame.BottomLeftTex:SetTexture("Interface\\AddOns\\BattleGroundHealers\\Artwork\\BGHBottomLeft")
        ConfigUIFrame.BottomLeftTex:SetSize(208, 184)
        ConfigUIFrame.BottomLeftTex:SetPoint("BOTTOMLEFT")
        ConfigUIFrame.BottomLeftTex:SetTexCoord(0.1875, 1, 0, 0.71875)
        ConfigUIFrame.TopRightTex = ConfigUIFrame:CreateTexture(nil, "ARTWORK")
        ConfigUIFrame.TopRightTex:SetTexture("Interface\\AddOns\\BattleGroundHealers\\Artwork\\BGHTopRight")
        ConfigUIFrame.TopRightTex:SetSize(80, 252)
        ConfigUIFrame.TopRightTex:SetPoint("TOPLEFT", 208, 0)
        ConfigUIFrame.TopRightTex:SetTexCoord(0, 0.625, 0.015625, 1)
        ConfigUIFrame.RightTex = ConfigUIFrame:CreateTexture(nil, "ARTWORK")
        ConfigUIFrame.RightTex:SetTexture("Interface\\AddOns\\BattleGroundHealers\\Artwork\\BGHBottomRight")
        ConfigUIFrame.RightTex:SetSize(80, 120)
        ConfigUIFrame.RightTex:SetPoint("BOTTOMLEFT", 208, 184)
        ConfigUIFrame.RightTex:SetTexCoord(0, 0.625, 0, 0.46875)
        ConfigUIFrame.BottomRightTex = ConfigUIFrame:CreateTexture(nil, "ARTWORK")
        ConfigUIFrame.BottomRightTex:SetTexture("Interface\\AddOns\\BattleGroundHealers\\Artwork\\BGHBottomRight")
        ConfigUIFrame.BottomRightTex:SetSize(80, 184)
        ConfigUIFrame.BottomRightTex:SetPoint("BOTTOMLEFT", 208, 0)
        ConfigUIFrame.BottomRightTex:SetTexCoord(0, 0.625, 0, 0.71875)
        ConfigUIFrame.DialogBG = ConfigUIFrame:CreateTexture(nil, "BACKGROUND")
        ConfigUIFrame.DialogBG:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-L1")
        ConfigUIFrame.DialogBG:SetSize(265,505)
        ConfigUIFrame.DialogBG:SetPoint("BOTTOM",0, 10)
        ConfigUIFrame.DialogBG:SetTexCoord(0.255, 1, 0.305, 1)
        ConfigUIFrame.DialogBG:SetAlpha(0.85)

        local function CreateSeparatorLine(subtitle)
            local lineWidth = (ConfigUIFrame:GetWidth() - subtitle:GetStringWidth() - 57)/2
            local leftLine = ConfigUIFrame:CreateTexture(nil, "OVERLAY")
            leftLine:SetTexture(0.55, 0.55, 0.55, 1)
            leftLine:SetPoint("LEFT", subtitle, "LEFT", -lineWidth, -1)
            leftLine:SetPoint("RIGHT", subtitle, "LEFT", -5, -1)
            leftLine:SetHeight(1) 
            local rightLine = ConfigUIFrame:CreateTexture(nil, "OVERLAY")
            rightLine:SetTexture(0.55, 0.55, 0.55, 1)
            rightLine:SetPoint("LEFT", subtitle, "RIGHT", 5, -1)
            rightLine:SetPoint("RIGHT", subtitle, "RIGHT", lineWidth, -1)
            rightLine:SetHeight(1) 
            return leftLine, rightLine
        end

        local function invertTextureColor(texture)
            if texture:find("Blue") then
                return texture:gsub("Blue", "Red")
            elseif texture:find("Red") then
                return texture:gsub("Red", "Blue")
            end
            return texture
        end

        ---------- Healer Detection Methods ----------
        ConfigUIFrame.subtitle1 = ConfigUIFrame:CreateFontString(nil,"ARTWORK") 
        ConfigUIFrame.subtitle1:SetFont("Fonts\\FRIZQT__.TTF", 11)
        ConfigUIFrame.subtitle1:SetPoint("TOP", 0, -53)
        ConfigUIFrame.subtitle1:SetText(L["Healer Detection Methods"])
        ConfigUIFrame.subtitle1:SetTextColor(1, 0.82, 0, 1)
        CreateSeparatorLine(ConfigUIFrame.subtitle1)

        -- Automatic Combat Log Fix (Checkbox)
        local CLEUfixCheckbox = CreateFrame("CheckButton", "BGHConfigUICLEUfixCheckbox", ConfigUIFrame, "UICheckButtonTemplate")
        CLEUfixCheckbox:SetPoint("TOPLEFT", 59, -102)
        CLEUfixCheckbox:SetSize(21, 21)
        CLEUfixCheckbox.Text = _G[CLEUfixCheckbox:GetName() .. "Text"]
        CLEUfixCheckbox.Text:SetText(L["Automatic Combat Log Fix"])
        CLEUfixCheckbox.Text:SetPoint("LEFT", CLEUfixCheckbox, "RIGHT", 1, 1) 
        CLEUfixCheckbox.Text:SetFont(CLEUfixCheckbox.Text:GetFont(), 9.5)
        CLEUfixCheckbox.Text:SetTextColor(1, 1, 1, 1)
        CLEUfixCheckbox:SetChecked(BGHsettings.CLEUfix == 1)
        CLEUfixCheckbox:SetScript("OnClick", function(self)
            if self:GetChecked() then
                BGHsettings.CLEUfix = 1
            else
                BGHsettings.CLEUfix = 0
                CLEUframe:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                USSregistered = false
            end
        end)    
        
        -- Combat Log Tracking (Checkbox)
        local CLEUtrackingCheckbox = CreateFrame("CheckButton", "BGHConfigUICLEUtrackingCheckbox", ConfigUIFrame, "UICheckButtonTemplate")
        CLEUtrackingCheckbox:SetPoint("TOPLEFT", 34, -77)
        CLEUtrackingCheckbox:SetSize(24, 24)
        CLEUtrackingCheckbox.Text = _G[CLEUtrackingCheckbox:GetName() .. "Text"]
        CLEUtrackingCheckbox.Text:SetText(L["Track Healers via Combat Log"])
        CLEUtrackingCheckbox.Text:SetPoint("LEFT", CLEUtrackingCheckbox, "RIGHT", 1, 1) 
        CLEUtrackingCheckbox.Text:SetTextColor(1, 1, 1, 1)
        CLEUtrackingCheckbox:SetChecked(BGHsettings.CLEUtracking == 1)
        if BGHsettings.CLEUtracking == 1 then
            CLEUfixCheckbox.Text:SetTextColor(1, 1, 1)
            CLEUfixCheckbox:Enable()
        else
            CLEUfixCheckbox.Text:SetTextColor(0.5, 0.5, 0.5)
            CLEUfixCheckbox:Disable()
        end
        CLEUtrackingCheckbox:SetScript("OnClick", function(self)
            if self:GetChecked() then
                BGHsettings.CLEUtracking = 1
                if inBG then
                    UpdateCurrentBGplayers()
                    UpdateCLEUstate()
                end
                CLEUfixCheckbox.Text:SetTextColor(1, 1, 1)
                CLEUfixCheckbox:Enable()
            else
                BGHsettings.CLEUtracking = 0
                CLEUframe:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                USSregistered = false
                CLEUfixCheckbox.Text:SetTextColor(0.5, 0.5, 0.5)
                CLEUfixCheckbox:Disable()
                CLEUframe:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                CLEUregistered = false
                ClearHealers(CLEUhealers)
                if inBG then
                    UpdateCurrentBGplayers()
                    UpdateWSSFhealers()
                end   
            end
        end)    

        -- BG Scoreboard Tracking (Checkbox)
        local WSSFtrackingCheckbox = CreateFrame("CheckButton", "BGHConfigUIWSSFtrackingCheckbox", ConfigUIFrame, "UICheckButtonTemplate")
        WSSFtrackingCheckbox:SetPoint("TOPLEFT", 34, -127)
        WSSFtrackingCheckbox:SetSize(24, 24)
        WSSFtrackingCheckbox.Text = _G[WSSFtrackingCheckbox:GetName() .. "Text"]
        WSSFtrackingCheckbox.Text:SetText(L["Track Healers via BG Scoreboard"])
        WSSFtrackingCheckbox.Text:SetPoint("LEFT", WSSFtrackingCheckbox, "RIGHT", 1, 1) 
        WSSFtrackingCheckbox.Text:SetTextColor(1, 1, 1, 1)
        WSSFtrackingCheckbox:SetChecked(BGHsettings.WSSFtracking == 1)
        WSSFtrackingCheckbox:SetScript("OnClick", function(self)
            if self:GetChecked() then
                BGHsettings.WSSFtracking = 1
                if inBG then
                    UpdateCurrentBGplayers()
                    UpdateWSSFhealers()
                end
            else
                BGHsettings.WSSFtracking = 0
                ClearHealers(WSSFhealers)
            end
        end) 

        -- Print Channel (Dropdown)
        local printChannelDropdown = CreateFrame("Frame", "BGHConfigUIprintChannelDropdown", ConfigUIFrame, "UIDropDownMenuTemplate")
        printChannelDropdown:SetPoint("TOPRIGHT", -18, -161)
        printChannelDropdown.Label = ConfigUIFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        printChannelDropdown.Label:SetPoint("RIGHT", printChannelDropdown, "LEFT", 14, 3)
        printChannelDropdown.Label:SetText(L["Channel:"])
        printChannelDropdown.Label:SetFont(GameFontNormal:GetFont(), 10.5)
        printChannelDropdown.Font = CreateFont("BGH_PrintChannelFont")
        printChannelDropdown.Font:SetFont(GameFontNormal:GetFont(), 9/UIParent:GetScale())
        printChannelDropdown.Font:SetTextColor(1, 1, 1, 1)
        printChannelDropdown.Text = _G[printChannelDropdown:GetName().."Text"]
        printChannelDropdown.Text:SetFont(printChannelDropdown.Text:GetFont(), 10.5)
        printChannelDropdown.Text:ClearAllPoints()
        printChannelDropdown.Text:SetPoint("CENTER", printChannelDropdown, "CENTER", -5, 3)
        printChannelDropdown.Text:SetJustifyH("CENTER")
        printChannelDropdown.Options = {"BG", "Party", "Guild", L["Self"]}
        UIDropDownMenu_SetWidth(printChannelDropdown, 60)
        UIDropDownMenu_SetText(printChannelDropdown, BGHsettings.printChannel or "BG")
        UIDropDownMenu_Initialize(printChannelDropdown, function(self, level)
            for _, options in ipairs(printChannelDropdown.Options) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = options
                info.checked = (BGHsettings.printChannel == options)
                info.fontObject = printChannelDropdown.Font
                info.func = function()
                    BGHsettings.printChannel = options
                    UIDropDownMenu_SetText(printChannelDropdown, options)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
      
        -- Print Healers (Button)
        local printHealersButton = CreateFrame("Button", "BGHConfigUIprintHealersButton", ConfigUIFrame, "UIPanelButtonTemplate")
        printHealersButton:SetSize(91, 26)
        printHealersButton:GetFontString():SetFont(printHealersButton:GetFontString():GetFont(), 10.5)
        printHealersButton:SetPoint("TOPLEFT", 34, -161)
        printHealersButton:SetText(L["Print Healers"])
        printHealersButton:SetScript("OnClick", function()
            PrintDetectedHealers()
        end)   

        ----------- Icon Display Settings -----------
        ConfigUIFrame.subtitle2 = ConfigUIFrame:CreateFontString(nil,"ARTWORK") 
        ConfigUIFrame.subtitle2:SetFont("Fonts\\FRIZQT__.TTF", 11)
        ConfigUIFrame.subtitle2:SetPoint("TOP", 0, -204)
        ConfigUIFrame.subtitle2:SetText(L["Icon Display Settings"])
        ConfigUIFrame.subtitle2:SetTextColor(1, 0.82, 0, 1)
        CreateSeparatorLine(ConfigUIFrame.subtitle2)

        -- Icon Size (Slider)
        local iconSizeSlider = CreateFrame("Slider", "BGHConfigUIiconSizeSlider", ConfigUIFrame, "OptionsSliderTemplate")
        iconSizeSlider:SetSize(185, 15)
        iconSizeSlider:SetPoint("TOP", 0, -242)
        iconSizeSlider:SetMinMaxValues(20, 60)
        iconSizeSlider:SetValueStep(1)
        iconSizeSlider:SetValue(BGHsettings.iconSize or 40)
        iconSizeSlider.Label = iconSizeSlider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        iconSizeSlider.Label:SetPoint("TOP", iconSizeSlider, "BOTTOM", 0, -1)
        iconSizeSlider.Label:SetText(L["Icon Size"])
        iconSizeSlider.Label:SetFont(GameFontNormal:GetFont(), 10.5)
        iconSizeSlider.Thumb = iconSizeSlider:GetThumbTexture()
        iconSizeSlider.Value = iconSizeSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlight") 
        iconSizeSlider.Value:SetPoint("BOTTOM", iconSizeSlider.Thumb, "TOP", 0, -4)
        iconSizeSlider.Value:SetText(iconSizeSlider:GetValue())
        iconSizeSlider.Value:SetFont(GameFontHighlight:GetFont(), 10.5)
        _G[iconSizeSlider:GetName() .. "Low"]:SetText("20")
        _G[iconSizeSlider:GetName() .. "High"]:SetText("60")
        iconSizeSlider:SetScript("OnValueChanged", function(self, value)
            BGHsettings.iconSize = math_floor(value + 0.5)
            iconSizeSlider.Value:SetText(math_floor(value + 0.5))
            UpdateAllMarks()
        end)

        -- Icon Style (Dropdown)
        local iconStyleDropdown = CreateFrame("Frame", "BGHConfigUIiconStyleDropdown", ConfigUIFrame, "UIDropDownMenuTemplate")
        iconStyleDropdown:SetPoint("TOPLEFT", 18, -292)
        iconStyleDropdown.Label = ConfigUIFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        iconStyleDropdown.Label:SetPoint("BOTTOM", iconStyleDropdown, "TOP", 0, 2)
        iconStyleDropdown.Label:SetText(L["Icon Style"])
        iconStyleDropdown.Label:SetFont(GameFontNormal:GetFont(), 10.5)
        iconStyleDropdown.Font = CreateFont("BGH_iconStyleFont")
        iconStyleDropdown.Font:SetFont(GameFontNormal:GetFont(), 9/UIParent:GetScale())
        iconStyleDropdown.Font:SetTextColor(1, 1, 1, 1)
        iconStyleDropdown.Text = _G[iconStyleDropdown:GetName().."Text"]
        iconStyleDropdown.Text:SetFont(iconStyleDropdown.Text:GetFont(), 10.5)
        iconStyleDropdown.Text:ClearAllPoints()
        iconStyleDropdown.Text:SetPoint("CENTER", iconStyleDropdown, "CENTER", -5, 3)
        iconStyleDropdown.Text:SetJustifyH("CENTER")
        iconStyleDropdown.Options = {"Blizzlike", "Minimalist"}
        UIDropDownMenu_SetWidth(iconStyleDropdown, 85)
        UIDropDownMenu_SetText(iconStyleDropdown, BGHsettings.iconStyle or "Blizzlike")  
        UIDropDownMenu_Initialize(iconStyleDropdown, function(self, level)
            for _, iconStyle in ipairs(iconStyleDropdown.Options) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = iconStyle
                info.checked = (BGHsettings.iconStyle == iconStyle)
                info.fontObject = iconStyleDropdown.Font
                info.func = function()
                    BGHsettings.iconStyle = iconStyle
                    UIDropDownMenu_SetText(iconStyleDropdown, iconStyle)
                    for name, texture in pairs(MarkedNames) do
                        local color = texture:find("Red") and "Red" or "Blue"
                        local newTexture = IconTextures[BGHsettings.iconStyle][color]
                        SetBGHmark(name, newTexture)
                    end
                    UpdateAllMarks()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end) 

        -- Icon X offset (Slider)
        local iconXoffsetSlider = CreateFrame("Slider", "BGHConfigUIiconXoffsetSlider", ConfigUIFrame, "OptionsSliderTemplate")
        iconXoffsetSlider:SetSize(185, 15)
        iconXoffsetSlider:SetPoint("TOP", 0, -343)
        iconXoffsetSlider:SetMinMaxValues(-40, 40)
        iconXoffsetSlider:SetValueStep(1)
        iconXoffsetSlider:SetValue(BGHsettings.iconXoffset or 0)
        iconXoffsetSlider.Label = iconXoffsetSlider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        iconXoffsetSlider.Label:SetPoint("TOP", iconXoffsetSlider, "BOTTOM", 0, -1)
        iconXoffsetSlider.Label:SetText(L["X offset"])
        iconXoffsetSlider.Label:SetFont(GameFontNormal:GetFont(), 10.5)
        iconXoffsetSlider.Thumb = iconXoffsetSlider:GetThumbTexture()
        iconXoffsetSlider.Value = iconXoffsetSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        iconXoffsetSlider.Value:SetPoint("BOTTOM", iconXoffsetSlider.Thumb, "TOP", 0, -4)
        iconXoffsetSlider.Value:SetText(iconXoffsetSlider:GetValue())
        iconXoffsetSlider.Value:SetFont(GameFontHighlight:GetFont(), 10.5)
        _G[iconXoffsetSlider:GetName() .. "Low"]:SetText("-40")
        _G[iconXoffsetSlider:GetName() .. "High"]:SetText("40")
        iconXoffsetSlider:SetScript("OnValueChanged", function(self, value)
            BGHsettings.iconXoffset = math_floor(value + 0.5)
            iconXoffsetSlider.Value:SetText(math_floor(value + 0.5))
            UpdateAllMarks()
        end)

        -- Icon Y offset (Slider)
        local iconYoffsetSlider = CreateFrame("Slider", "BGHConfigUIiconYoffsetSlider", ConfigUIFrame, "OptionsSliderTemplate")
        iconYoffsetSlider:SetSize(185, 15)
        iconYoffsetSlider:SetPoint("TOP", 0, -392)
        iconYoffsetSlider:SetMinMaxValues(-40, 40)
        iconYoffsetSlider:SetValueStep(1)
        iconYoffsetSlider:SetValue(BGHsettings.iconYoffset or 0)
        iconYoffsetSlider.Label = iconYoffsetSlider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        iconYoffsetSlider.Label:SetPoint("TOP", iconYoffsetSlider, "BOTTOM", 0, -1)
        iconYoffsetSlider.Label:SetText(L["Y offset"])
        iconYoffsetSlider.Label:SetFont(GameFontNormal:GetFont(), 10.5)
        iconYoffsetSlider.Thumb = iconYoffsetSlider:GetThumbTexture()
        iconYoffsetSlider.Value = iconYoffsetSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        iconYoffsetSlider.Value:SetPoint("BOTTOM", iconYoffsetSlider.Thumb, "TOP", 0, -4)
        iconYoffsetSlider.Value:SetText(iconYoffsetSlider:GetValue())
        iconYoffsetSlider.Value:SetFont(GameFontHighlight:GetFont(), 10.5)
        _G[iconYoffsetSlider:GetName() .. "Low"]:SetText("-40")
        _G[iconYoffsetSlider:GetName() .. "High"]:SetText("40")
        iconYoffsetSlider:SetScript("OnValueChanged", function(self, value)
            BGHsettings.iconYoffset = math_floor(value + 0.5)
            iconYoffsetSlider.Value:SetText(math_floor(value + 0.5))
            UpdateAllMarks()
        end)

        -- Icon Anchor (Dropdown)
        local iconAnchorDropdown = CreateFrame("Frame", "BGHConfigUIiconAnchorDropdown", ConfigUIFrame, "UIDropDownMenuTemplate")
        iconAnchorDropdown:SetPoint("TOPRIGHT", -18, -292)
        iconAnchorDropdown.Label = ConfigUIFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        iconAnchorDropdown.Label:SetPoint("BOTTOM", iconAnchorDropdown, "TOP", 0, 2)
        iconAnchorDropdown.Label:SetText(L["Anchor"])
        iconAnchorDropdown.Label:SetFont(GameFontNormal:GetFont(), 10.5)
        iconAnchorDropdown.Font = CreateFont("BGH_AnchorFont")
        iconAnchorDropdown.Font:SetFont(GameFontNormal:GetFont(), 9/UIParent:GetScale())
        iconAnchorDropdown.Font:SetTextColor(1, 1, 1, 1)
        iconAnchorDropdown.Text = _G[iconAnchorDropdown:GetName().."Text"]
        iconAnchorDropdown.Text:SetFont(iconAnchorDropdown.Text:GetFont(), 10.5)
        iconAnchorDropdown.Text:ClearAllPoints()
        iconAnchorDropdown.Text:SetPoint("CENTER", iconAnchorDropdown, "CENTER", -5, 3)
        iconAnchorDropdown.Text:SetJustifyH("CENTER")
        iconAnchorDropdown.Options = {"left", "top", "right"}
        UIDropDownMenu_SetWidth(iconAnchorDropdown, 60)
        UIDropDownMenu_SetText(iconAnchorDropdown, BGHsettings.iconAnchor or "top")
        UIDropDownMenu_Initialize(iconAnchorDropdown, function(self, level)
            for _, anchor in ipairs(iconAnchorDropdown.Options) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = anchor
                info.checked = (BGHsettings.iconAnchor == anchor)
                info.fontObject = iconAnchorDropdown.Font
                info.func = function()
                    BGHsettings.iconAnchor = anchor
                    UIDropDownMenu_SetText(iconAnchorDropdown, anchor)
                    BGHsettings.iconXoffset = 0
                    iconXoffsetSlider:SetValue(BGHsettings.iconXoffset)
                    iconXoffsetSlider.Value:SetText(BGHsettings.iconXoffset)
                    BGHsettings.iconYoffset = 0
                    iconYoffsetSlider:SetValue(BGHsettings.iconYoffset)
                    iconYoffsetSlider.Value:SetText(BGHsettings.iconYoffset)
                    UpdateAllMarks()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)       
 
        -- Invert Icon Color (Checkbox)
        local iconInvertColorCheckbox = CreateFrame("CheckButton", "BGHConfigUIiconInvertColorCheckbox", ConfigUIFrame, "UICheckButtonTemplate")
        iconInvertColorCheckbox:SetPoint("TOPLEFT", 34, -432)
        iconInvertColorCheckbox:SetSize(24, 24)
        iconInvertColorCheckbox.Text = _G[iconInvertColorCheckbox:GetName().."Text"]
        iconInvertColorCheckbox.Text:SetText(L["Invert Icon Color"])
        iconInvertColorCheckbox.Text:SetPoint("LEFT", iconInvertColorCheckbox, "RIGHT", 1, 1) 
        iconInvertColorCheckbox.Text:SetTextColor(1, 1, 1, 1)
        iconInvertColorCheckbox:SetChecked(BGHsettings.iconInvertColor == 1)
        iconInvertColorCheckbox:SetScript("OnClick", function(self)
            BGHsettings.iconInvertColor = self:GetChecked() and 1 or 0
            for name, texture in pairs(MarkedNames) do
                MarkedNames[name] = invertTextureColor(texture)
            end
            UpdateAllMarks()
        end)    

        -- Mark Target (Button)
        local testMarkButton = CreateFrame("Button", "BGHConfigUItestMarkButton", ConfigUIFrame, "UIPanelButtonTemplate")
        local testModeMarkedNames = {}
        testMarkButton:SetSize(95, 26)
        testMarkButton:GetFontString():SetFont(testMarkButton:GetFontString():GetFont(), 10.5)
        testMarkButton:SetPoint("TOPRIGHT", -34, -460)
        testMarkButton:SetText(L["Mark Target"])
        testMarkButton:Disable()
        testMarkButton:SetScript("OnClick", function()
            local name = UnitName("target")
            if name then
                if MarkedNames[name] then
                    SetBGHmark(name, nil)
                    for i, markedName in ipairs(testModeMarkedNames) do
                        if markedName == name then
                            table_remove(testModeMarkedNames, i)
                            break
                        end
                    end
                else
                    local isFriendly = not UnitCanAttack("player", "target")
                    SetBGHmark(name, ((BGHsettings.iconInvertColor == 1) == isFriendly) and IconTextures[BGHsettings.iconStyle].Red or IconTextures[BGHsettings.iconStyle].Blue)
                    table_insert(testModeMarkedNames, name)
                end
            end
            UpdateAllMarks()
        end)

        -- Test Mode (Checkbox)
        local testModeCheckbox = CreateFrame("CheckButton", "BGHConfigUItestModeCheckbox", ConfigUIFrame, "UICheckButtonTemplate")
        testModeCheckbox:SetPoint("TOPLEFT", 34, -462)
        testModeCheckbox:SetSize(24, 24)
        testModeCheckbox.Text = _G[testModeCheckbox:GetName().."Text"]
        testModeCheckbox.Text:SetText(L["Enable Test Mode"])
        testModeCheckbox.Text:SetPoint("LEFT", testModeCheckbox, "RIGHT", 1, 1) 
        testModeCheckbox.Text:SetTextColor(1, 1, 1, 1)
        testModeCheckbox:SetChecked(false)
        testModeCheckbox:SetScript("OnClick", function(self)
            if self:GetChecked() then
                testMarkButton:Enable()
            else
                testMarkButton:Disable()
                for _, name in ipairs(testModeMarkedNames) do
                    SetBGHmark(name, nil)
                end
                testModeMarkedNames = {}
                UpdateAllMarks()
            end
        end)    

        -- Reset Settings (Button)
        local resetButton = CreateFrame("Button", "BGHConfigUIresetButton", ConfigUIFrame, "UIPanelButtonTemplate")
        resetButton:SetSize(80, 27)
        resetButton:GetFontString():SetPoint("CENTER", resetButton, "CENTER", 0, 0.5)
        resetButton:GetFontString():SetFont(resetButton:GetFontString():GetFont(), 11.5)
        resetButton:SetPoint("BOTTOM", ConfigUIFrame, "BOTTOM", 0, 20)
        resetButton:SetText(L["Reset"])
        resetButton:SetScript("OnClick", function()
            StaticPopupDialogs["CONFIRM_RESET_BGH_CONFIG"] = {
                text = L["Are you sure you want to reset all settings to default?"],
                button1 = L["Yes"],
                button2 = L["No"],
                OnAccept = function()
                    BGHprint(L["Settings reset to default values."])
                    if BGHsettings.iconInvertColor ~= DefaultSettings.iconInvertColor then
                        for name, texture in pairs(MarkedNames) do
                            MarkedNames[name] = invertTextureColor(texture)
                        end
                    end
                    if BGHsettings.iconStyle ~= DefaultSettings.iconStyle then
                        for name, texture in pairs(MarkedNames) do
                            local color = texture:find("Red") and "Red" or "Blue"
                            local newTexture = IconTextures[DefaultSettings.iconStyle][color]
                            SetBGHmark(name, newTexture)
                        end
                    end
                    for k, v in pairs(DefaultSettings) do
                        BGHsettings[k] = DefaultSettings[k]
                    end
                    if BGHsettings.CLEUfix == 1 then
                        CLEUfixCheckbox:SetChecked(true)
                    else
                        CLEUfixCheckbox:SetChecked(false)
                        CLEUframe:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                        USSregistered = false
                    end
                    if BGHsettings.CLEUtracking == 1 then
                        CLEUtrackingCheckbox:SetChecked(true)
                        CLEUfixCheckbox.Text:SetTextColor(1, 1, 1)
                        CLEUfixCheckbox:Enable()
                        if inBG then
                            UpdateCurrentBGplayers()
                            UpdateCLEUstate()
                        end
                    else
                        CLEUtrackingCheckbox:SetChecked(false)
                        CLEUframe:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                        USSregistered = false
                        CLEUfixCheckbox.Text:SetTextColor(0.5, 0.5, 0.5)
                        CLEUfixCheckbox:Disable()
                        CLEUframe:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                        CLEUregistered = false
                        ClearHealers(CLEUhealers)
                        if inBG then
                            UpdateCurrentBGplayers()
                            UpdateWSSFhealers()
                        end
                    end
                    if BGHsettings.WSSFtracking == 1 then
                        WSSFtrackingCheckbox:SetChecked(true)   
                        if inBG then
                            UpdateCurrentBGplayers()
                            UpdateWSSFhealers()
                        end
                    else
                        WSSFtrackingCheckbox:SetChecked(false)  
                        ClearHealers(WSSFhealers)
                    end  
                    UIDropDownMenu_SetText(printChannelDropdown, BGHsettings.printChannel)  
                    iconSizeSlider:SetValue(BGHsettings.iconSize)
                    UIDropDownMenu_SetText(iconStyleDropdown, BGHsettings.iconStyle)
                    UIDropDownMenu_SetText(iconAnchorDropdown, BGHsettings.iconAnchor)
                    iconXoffsetSlider:SetValue(BGHsettings.iconXoffset)
                    iconYoffsetSlider:SetValue(BGHsettings.iconYoffset)
                    iconInvertColorCheckbox:SetChecked(BGHsettings.iconInvertColor == 1)
                    UpdateAllMarks()
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("CONFIRM_RESET_BGH_CONFIG")
        end)

        -- Script to move and scale ConfigUIFrame
        ConfigUIFrame:SetMovable(true)
        ConfigUIFrame:EnableMouse(true)
        ConfigUIFrame:SetClampedToScreen(true)
        ConfigUIFrame:EnableMouseWheel(true)
        ConfigUIFrame:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" and not self.isMoving then
                self:StartMoving();
                self.isMoving = true;
            end
        end)
        ConfigUIFrame:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and self.isMoving then
                self:StopMovingOrSizing();
                self.isMoving = false;
            end
        end)
        ConfigUIFrame:SetScript("OnHide", function(self)
            if (self.isMoving) then
                self:StopMovingOrSizing();
                self.isMoving = false;
            end
        end)
        ConfigUIFrame:SetScript("OnMouseWheel", function(self, delta)
            local scale = self:GetScale()
            if delta > 0 then
                self:SetScale(math_min(scale + 0.1, 1.3/UIParent:GetScale()))
            else
                self:SetScale(math_max(scale - 0.1, 0.6/UIParent:GetScale()))
            end
        end)

        -- Script to disable Test Mode when ConfigUIFrame is closed
        ConfigUIFrame:HookScript("OnHide", function()
            if testModeCheckbox:GetChecked() then
                testModeCheckbox:SetChecked(false)
                testMarkButton:Disable()
                for _, name in ipairs(testModeMarkedNames) do
                    SetBGHmark(name, nil)
                end
                testModeMarkedNames = {}
                UpdateAllMarks()
            end
        end)
    end
    if not BGHConfigUIglobalFrame:IsShown() then
        BGHConfigUIglobalFrame:ClearAllPoints()
        BGHConfigUIglobalFrame:SetPoint("CENTER")
        BGHConfigUIglobalFrame:SetScale(0.9/UIParent:GetScale())
        BGHConfigUIglobalFrame:Show()
    end
end

------------------- Adds the addon's panel to the game interface options -------------------
local function AddInterfaceOptions()
    local addonPanel = CreateFrame("Frame")
    addonPanel.name = "BattleGroundHealers"
    addonPanel:SetScript("OnShow", function(self)
        local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetFont(GameFontNormalLarge:GetFont(), 18)
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetJustifyH("LEFT")
        title:SetJustifyV("TOP")
        title:SetShadowColor(0, 0, 0)
        title:SetShadowOffset(1, -1)
        title:SetText(self.name)              
        local description = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        description:SetFont(GameFontHighlightSmall:GetFont(), 12)
        description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -18)
        description:SetPoint("RIGHT", self, "RIGHT", -32, 0)
        description:SetJustifyH("LEFT")
        description:SetJustifyV("TOP")
        description:SetShadowColor(0, 0, 0)
        description:SetShadowOffset(1, -1)
        description:SetFormattedText(L["Marks BG healer nameplates with a configurable icon.\nSupports two detection methods that can work simultaneously.\n\nAuthor: |cffc41f3bKhal|r\nVersion: %.1f"], version)
        description:SetNonSpaceWrap(true)
        local settingsButton = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
        settingsButton:SetSize(100, 30)
        settingsButton:SetText("/bgh")
        settingsButton:SetScript("OnClick", function()
            InterfaceOptionsFrameCancel_OnClick()
            HideUIPanel(GameMenuFrame)
            ConfigUI()
        end)
        settingsButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 120, -18)
        settingsButton:GetFontString():SetPoint("CENTER", settingsButton, "CENTER", 0, 1)
        settingsButton:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 14)
        self:SetScript("OnShow", nil)
    end)
    InterfaceOptions_AddCategory(addonPanel)
end

--------- Reset tracking state before joining other BG ---------
local function ResetTrackingState()
    BGH:SetScript("OnUpdate",nil)
    CLEUframe:SetScript("OnEvent", nil)
    CLEUframe:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    CLEUframe:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    CLEUregistered = false
    USSregistered = false
    playerFaction = false  
    currentBGplayers = {} 
    lastUpdateTime = 0
    lastCLEUtime = nil
    CLEUtimeout = nil
    CLEUcheck = false
    ClearHealers(CLEUhealers)
    ClearHealers(WSSFhealers)
    BGH.AllianceCount = 0
    BGH.HordeCount = 0
end

------------------- Script to manage the addon's main frame events -------------------
BGH:RegisterEvent("ADDON_LOADED")
BGH:RegisterEvent("PLAYER_ENTERING_WORLD")
BGH:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
BGH:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and (...) == addonName then
        AddInterfaceOptions()
        InitSettings()
        print(string_format(" |cff00FF98BattleGroundHealers|r v%.1f by |cffc41f3bKhal|r", version))
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        local _, instanceType = IsInInstance()
        if instanceType == "pvp" then
            if not inBG then
                RequestBattlefieldScoreData()
                UpdateCurrentBGplayers()
                UpdateWSSFhealers()
                UpdateCLEUstate()
            end
            inBG = true
            self:SetScript("OnUpdate", OnUpdate) 
            CLEUframe:SetScript("OnEvent", CLEUhandler)
        elseif inBG then
            inBG = false
            ResetTrackingState()
        end
    elseif event == "UPDATE_BATTLEFIELD_STATUS" then
		local bgIndex = ...
		local status = GetBattlefieldStatus(bgIndex)
		if status == "active" then
			if not BGStatus[bgIndex] then
                ResetTrackingState()
			end
			BGStatus[bgIndex] = true
		else
			BGStatus[bgIndex] = false
		end
    end
end)

------------------------ Slash Commands ------------------------
SLASH_BGH1 = "/bgh"
SlashCmdList["BGH"] = function(msg)
    msg = string_lower(msg);
    local _, _, cmd, args = string_find(msg, '%s?(%w+)%s?(.*)')
    if (not msg or msg == "") then
        ConfigUI()
    elseif cmd == "print" then
        PrintDetectedHealers()
    elseif cmd == "msg" then
            BGHsettings.showMessages = BGHsettings.showMessages == 1 and 0 or 1
            BGHprint("Chat messages " .. (BGHsettings.showMessages == 1 and (HEX_GREEN .. "Enabled" .. "|r") or (HEX_RED .. "Disabled" .. "|r")))
    elseif (cmd == "h2d") then
        if (not args or args == "") then
            BGHprint(L["Current BG Scoreboard healing-to-damage tracking ratio:"], BGHsettings.h2dRatio);
        else
            local value = tonumber(args);
            if (value ~= nil) then
                if (value > 5) then value = 5 end
                if (value < 1) then value = 1 end
                BGHsettings.h2dRatio = value;
                BGHprint(L["BG Scoreboard healing-to-damage tracking ratio set to:"], BGHsettings.h2dRatio);       
            else
                BGHprint(L["Value is not a number"]);
            end
        end
    elseif (cmd == "hth") then
        if (not args or args == "") then
            BGHprint(L["Current BG Scoreboard healing tracking threshold:"], BGHsettings.healingThreshold);
        else
            local value = tonumber(args);
            if (value ~= nil) then
                if (value > 100000) then value = 100000 end
                if (value < 10000) then value = 10000 end
                BGHsettings.healingThreshold = value;
                BGHprint(L["BG Scoreboard healing tracking threshold set to:"], BGHsettings.healingThreshold);       
            else
                BGHprint(L["Value is not a number"]);
            end
        end
    elseif cmd == "debug" then
        if debugMode then 
            debugMode = false
            BGHprint("Debug mode " .. HEX_RED .. "Disabled" .. "|r")
        else 
            debugMode = true
            BGHprint("Debug mode " .. HEX_GREEN .. "Enabled" .. "|r")
        end
    end
end
_G.SetBGHmark = SetBGHmark