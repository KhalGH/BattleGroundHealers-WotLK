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

local AddonName, BGH = ...
local version = GetAddOnMetadata(AddonName, "Version")

local DefaultSettings = {
    CLEUtracking = 1,           -- Detect healers via Combat Log (1 = enabled, 0 = disabled)
    CLEUfix = 1,                -- Automatic Combat Log fix (1 = enabled, 0 = disabled)
    WSSFtracking = 1,           -- Detect healers via BG Scoreboard (1 = enabled, 0 = disabled)
    h2dRatio = 2.5,             -- BG Scoreboard healing-to-damage ratio threshold (1 to 5)
    healingThreshold = 50000,   -- BG Scoreboard healing detection threshold (10k to 100k)
    printChannel = "BG",        -- Channel to print the healers list ("BG", "Party", "Raid", "Guild" or "Self")
    iconStyle = "Blizzlike",    -- Icon style ("Blizzlike" or "Minimalist")
    iconSize = 40,              -- Icon size (20 to 40)
    iconAnchor = "top",         -- Icon anchor relative to the nameplate ("left", "top" or "right")
    iconXoffset = 0,            -- Horizontal offset relative to the icon anchor (-40 to 40)
    iconYoffset = 0,            -- Vertical offset relative to the icon anchor (-40 to 40)
    iconInvertColor = 0,        -- Invert icon colors, by default enemies are red and allies are blue (1 = enabled, 0 = disabled)
    showMessages = 1,           -- Addon chat messages (1 = enabled, 0 = disabled)
}

local setmetatable, print, next, ipairs, pairs, unpack, rawset, rawget, select, pcall, string_format, string_lower, string_find, table_insert, table_remove, math_sqrt, math_abs, math_floor, math_min, math_max, tonumber =
      setmetatable, print, next, ipairs, pairs, unpack, rawset, rawget, select, pcall, string.format, string.lower, string.find, table.insert, table.remove, math.sqrt, math.abs, math.floor, math.min, math.max, tonumber
local CreateFrame, GetSpellInfo, GetBattlefieldStatus, SetBattlefieldScoreFaction, RequestBattlefieldScoreData, GetNumBattlefieldScores, GetBattlefieldScore, GetNumRaidMembers, GetRaidRosterInfo, IsInInstance, CombatLogClearEntries, GetRealZoneText, SetMapToCurrentZone, GetCurrentMapAreaID, GetPlayerMapPosition, SendChatMessage, UnitName, UnitFactionGroup, UnitAura, UnitCanAttack, GetTime, GetPlayerInfoByGUID, GetWorldStateUIInfo, wipe, GetCVar, SetCVar =
      CreateFrame, GetSpellInfo, GetBattlefieldStatus, SetBattlefieldScoreFaction, RequestBattlefieldScoreData, GetNumBattlefieldScores, GetBattlefieldScore, GetNumRaidMembers, GetRaidRosterInfo, IsInInstance, CombatLogClearEntries, GetRealZoneText, SetMapToCurrentZone, GetCurrentMapAreaID, GetPlayerMapPosition, SendChatMessage, UnitName, UnitFactionGroup, UnitAura, UnitCanAttack, GetTime, GetPlayerInfoByGUID, GetWorldStateUIInfo, wipe, GetCVar, SetCVar
local UIDropDownMenu_SetWidth, UIDropDownMenu_SetText, UIDropDownMenu_Initialize, UIDropDownMenu_CreateInfo, UIDropDownMenu_AddButton, StaticPopup_Show, InterfaceOptions_AddCategory, InterfaceOptionsFrameCancel_OnClick, HideUIPanel =
      UIDropDownMenu_SetWidth, UIDropDownMenu_SetText, UIDropDownMenu_Initialize, UIDropDownMenu_CreateInfo, UIDropDownMenu_AddButton, StaticPopup_Show, InterfaceOptions_AddCategory, InterfaceOptionsFrameCancel_OnClick, HideUIPanel
local LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE, RAID_CLASS_COLORS, WorldFrame, WorldStateScoreFrame =
      LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE, RAID_CLASS_COLORS, WorldFrame, WorldStateScoreFrame

local BGH_Public = CreateFrame("Frame", "BattleGroundHealers")
local EventHandler = CreateFrame("Frame")
local AllNamePlates = {}
local FriendlyPlates = {}
local EnemyPlates = {}
local MarkedNames = {}
local CurrentBGplayers = {}
local FriendlyHealerCandidates = {}
local CLEUhealers = {}
local WSSFhealers = {}
local inBG = false
local CLEUregistered = false
local USSregistered = false
local playerFaction = false
local CustomPlateCheck = false
local lastCLEUtime = nil
local CLEUtimeout = nil
local CLEUcheck = false
local testMode = false
local debugMode = false
local L = BGH.Locale

BGH_Public.AllianceCount = 0
BGH_Public.HordeCount = 0
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

local HealerSpells = {
    PALADIN = {
        20473, 20929, 20930, 27174, 33072, 48824, 48825,  -- Holy Shock	
        53563,                                            -- Beacon of Light
        31842,                                            -- Divine Illumination
        20216,                                            -- Divine Favor
        31834,                                            -- Light's Grace
        53655, 53656, 53657, 54152, 54153,                -- Judgements of the Pure
        53672, 54149,                                     -- Infusion of Light
        53659,                                            -- Sacred Cleansing
    },
    SHAMAN = {
        49284, 49283, 32594, 32593, 974,                  -- Earth Shield	
        61301, 61300, 61299, 61295,                       -- Riptide
        51886,                                            -- Cleanse Spirit
        16190,                                            -- Mana Tide Totem
        16188,                                            -- Nature's Swiftness
        55198,                                            -- Tidal Force
        53390,                                            -- Tidal Waves
        31616,                                            -- Nature's Guardian
        16177, 16236, 16237,                              -- Ancestral Fortitude
    },
    DRUID = {
        53251, 53249, 53248, 48438,                       -- Wild Growth
        33891,                                            -- Tree of Life
        18562,                                            -- Swiftmend
        17116,                                            -- Nature's Swiftness
        48504,                                            -- Living Seed
        45283, 45282, 45281,                              -- Natural Perfection		
    },
    PRIEST = {
        -- DISC
        47750, 52983, 52984, 52985,                       -- Penance
        10060,                                            -- Power Infusion
        33206,                                            -- Pain Suppression
        47930,                                            -- Grace
        59891, 59890, 59889, 59888, 59887,                -- Borrowed Time
        45242, 45241, 45237,                              -- Focused Will		
        47753,                                            -- Divine Aegis
        63944,                                            -- Renewed Hope	
        -- HOLY	
        48089, 48088, 34866, 34865, 34864, 34863, 34861,  -- Circle of Healing		
        47788,                                            -- Guardian Spirit	
        48085, 48084, 28276, 27874, 27873, 7001,          -- Lightwell Renew                
        33151,                                            -- Surge of light	
        65081, 64128,                                     -- Body and Soul
        33143,                                            -- Blessed Resilience         
        63725, 63724, 34754,                              -- Holy Concentration
        63734, 63735, 63731,                              -- Serendipity
        27827,                                            -- Spirit of Redemption    
    },
}

--------- Maps localized healer class names to class tokens ---------
local HealerClassTokens = {}
for class in pairs(HealerSpells) do
    HealerClassTokens[LOCALIZED_CLASS_NAMES_MALE[class]] = class
    HealerClassTokens[LOCALIZED_CLASS_NAMES_FEMALE[class]] = class
end

--------- Maps healer spell IDs to their associated class ---------
local HealerSpellMap = {}
for class, spells in pairs(HealerSpells) do
    for _, spellID in ipairs(spells) do
        HealerSpellMap[spellID] = class
    end
end

--------- Lazily caches player spell resource usage information ---------
local playerSpells = setmetatable({}, {
	__index = function(tbl, name)
		local _, _, _, cost, _, powerType = GetSpellInfo(name)
		rawset(tbl, name, not not ((cost and cost > 0) or (powerType and powerType == 5)))
		return rawget(tbl, name)
	end
})

--------- Tracks the state of each BG queue slot ---------
local BGstatus = {}
for i = 1, MAX_BATTLEFIELD_QUEUES do
	BGstatus[i] = true
end

--------- Default icon anchor positions and offsets ---------
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
        xOffset = -5, yOffset = -9
    },
}

--------- Initializes and validates addon settings ---------
local function InitSettings()
    if not BGHchar then
        BGHchar = {}
    end
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

--------- Prints a formatted message with the BGH prefix ---------
local function BGHprint(...)
	print("|cff00FF98[BGH]|r", ...)
end

--------- Determines the unit reaction type from the health bar color ---------
local function ReactionByColor(healthBar)
    local r, g, b = healthBar:GetStatusBarColor()
	if g > .99 and b < .01 then -- Ignored reaction color
		return
    elseif g < .01 then
        if b < .01 then
		    return 1 -- Hostile (red)
        else
            return 2 -- Friendly Player (blue)
        end
    else
	    return 3 -- Hostile Player (class color)
	end
end

--------- Updates the BGH icon anchor position ---------
local function UpdateIconAnchor(BGHframe)
    BGHframe.icon:ClearAllPoints()
    local anchorData = anchorMapping[BGHsettings.iconAnchor or "top"]
    BGHframe.icon:SetPoint(
        anchorData.anchorPoint,
        BGHframe.parentPlate,
        anchorData.relativePoint,
        BGHsettings.iconXoffset + anchorData.xOffset,
        BGHsettings.iconYoffset + anchorData.yOffset
    )
end

--------- Updates the BGH icon size ---------
local function UpdateIconSize(BGHframe)
    BGHframe.icon:SetSize(BGHsettings.iconSize, BGHsettings.iconSize)
end

--------- Updates the BGH icon texture and visibility ---------
local function UpdateIconTexture(BGHframe)
    if not BGHframe then return end
    local name = BGHframe.activeName
    local texture
    if MarkedNames[name] == "FRIEND" and (FriendlyPlates[name] == BGHframe or testMode) then
        texture = BGHsettings.iconInvertColor == 1 and IconTextures[BGHsettings.iconStyle].Red or IconTextures[BGHsettings.iconStyle].Blue
    elseif MarkedNames[name] == "ENEMY" and (EnemyPlates[name] == BGHframe or testMode) then
        texture = BGHsettings.iconInvertColor == 1 and IconTextures[BGHsettings.iconStyle].Blue or IconTextures[BGHsettings.iconStyle].Red
    end
    if texture then
        BGHframe.icon:SetTexture(texture)
        BGHframe.icon:Show()
    else
        BGHframe.icon:SetTexture(nil)
        BGHframe.icon:Hide()
    end
end

--------- Assigns a healer mark to a nameplate ---------
local function SetBGHmark(name, reaction)
    MarkedNames[name] = reaction
    UpdateIconTexture(FriendlyPlates[name])
    UpdateIconTexture(EnemyPlates[name])
end

--------- OnShow script handler for BGH frames ---------
local function BGHonShow(BGHframe)
    local reaction = ReactionByColor(BGHframe.healthBar)
    local name = BGHframe.nameRegion:GetText()
    BGHframe.activeName = name
    if reaction == 3 or (reaction == 1 and GetCVar("ShowClassColorInNameplate") == "0") then
        EnemyPlates[name] = BGHframe
    elseif reaction == 2 then
        FriendlyPlates[name] = BGHframe
    end
    UpdateIconTexture(BGHframe)
end

--------- OnHide script handler for BGH frames ---------
local function BGHonHide(BGHframe)
    local name = BGHframe.activeName
    FriendlyPlates[name] = nil
    EnemyPlates[name] = nil
    BGHframe.activeName = nil
    BGHframe.icon:Hide()
end

--------- Anchor offsets for supported custom nameplates ---------
local CustomPlatesOffsets = {
    -- left, top, right
    {"RealPlate", {
        {17.5, 13}, {0, 1}, {-16, 13},
    }},
    {"extended", {
        {3, 0}, {0, -5}, {-3, 0},
    }},
    {"UnitFrame", {
        {2, 1}, {0, 12}, {-2, 1},
    }},
    {"kui", {
        {38, 0}, {0, -10}, {-39, 0},
    }},
    {"npHooked", {
        {1, 0}, {0, 3}, {-1, 0},
    }},
    {"aloftData", {
        {4, 0}, {0, -1}, {-5, 0},
    }},
    {"done", {
        {5, 0}, {0, 2}, {-5, 0},
    }},
    {"myPlate", {
        {14, -2}, {0, 0}, {-14, -2},
    }},
}

--------- Updates the icon anchor mapping for the detected custom nameplate ---------
local function UpdateAnchorMapping(nameplate)
    for _, plate in ipairs(CustomPlatesOffsets) do
        if nameplate[plate[1]] then
            CustomPlateCheck = true
            local offset = plate[2]
            anchorMapping = {
                left = {
                    anchorPoint = "RIGHT",
                    relativePoint = "LEFT",
                    xOffset = offset[1][1],
                    yOffset = offset[1][2],
                },
                top = {
                    anchorPoint = "BOTTOM",
                    relativePoint = "TOP",
                    xOffset = offset[2][1],
                    yOffset = offset[2][2],
                },
                right = {
                    anchorPoint = "LEFT",
                    relativePoint = "RIGHT",
                    xOffset = offset[3][1],
                    yOffset = offset[3][2],
                },
            }
            return
        end
    end
end

---- Checks and replaces the nameplate anchor if custom ----
local function GetPlateElements(nameplate)
    local nameRegion = select(7, nameplate:GetRegions())
    local healthBar = nameplate:GetChildren()
    if nameplate.extended then
        nameplate = nameplate.extended
    elseif nameplate.UnitFrame then
        nameplate = nameplate.UnitFrame.Health or nameplate.UnitFrame
    elseif nameplate.kui then
        nameRegion = nameplate.kui.oldName
        healthBar = nameplate.kui.oldHealth
    elseif nameplate.npHooked then
        nameplate = nameplate.healthBar
    end
    return nameplate, nameRegion, healthBar
end

--------- Allows external addons to override a BGH icon's size and anchor ---------
local function ModifyIcon(self, shouldModify, newParent, iconSize, anchorPoint, relativeFrame, relativePoint, xOffset, yOffset)
    if shouldModify then
        self.icon:ClearAllPoints()
        self.icon:SetPoint(
            anchorPoint,
            relativeFrame,
            relativePoint,
            xOffset,
            yOffset
        )
        self.icon:SetSize(iconSize, iconSize)
        self:SetParent(newParent)
    else
        UpdateIconAnchor(self)
        UpdateIconSize(self)
        self:SetParent(self.parentPlate)
    end
end

-------- Setup a frame that manages the healer mark parameters  --------
local function SetupBGHframe(nameplate)
    if not CustomPlateCheck then
        UpdateAnchorMapping(nameplate)
    end
    local plate, nameRegion, healthBar = GetPlateElements(nameplate)
    local BGHframe = CreateFrame("Frame", nil, plate)
    AllNamePlates[plate] = BGHframe 
    plate.BGHframe = BGHframe
    BGHframe.parentPlate = plate
    BGHframe.nameRegion = nameRegion
    BGHframe.healthBar = healthBar
    BGHframe.icon = BGHframe:CreateTexture(nil, "OVERLAY")
    UpdateIconAnchor(BGHframe)
    UpdateIconSize(BGHframe)
    BGHonShow(BGHframe)
    BGHframe:SetScript("OnShow", BGHonShow)
    BGHframe:SetScript("OnHide", BGHonHide)
    BGHframe.ModifyIcon = ModifyIcon
    if plate.shouldModifyBGH then
        BGHframe:ModifyIcon(unpack(plate.shouldModifyBGH))
        plate.shouldModifyBGH = nil
    end
end

---- Checks if the frame is a nameplate ----
local function IsNamePlate(frame)
    if frame.RealPlate  -- RefinedBlizzPlates
    or frame.extended   -- TidyPlates
    or frame.UnitFrame  -- ElvUI
    or frame.npHooked   -- NotPlater
    or frame.kui        -- KuiNameplates
    or frame.aloftData  -- Aloft
    or frame.done       -- sNamePlates
    or frame.myPlate    -- PrettyNameplates
    then
        return true
    end
    local _, r2 = frame:GetRegions()
    return r2 and r2:GetObjectType() == "Texture" and r2:GetTexture() == "Interface\\Tooltips\\Nameplate-Border"
end

------ Detects newly created nameplate frames and sets up BGH frames ------
local ChildCount, NewChildCount = 0
CreateFrame("Frame"):SetScript("OnUpdate", function()
    NewChildCount = WorldFrame:GetNumChildren()
    if ChildCount ~= NewChildCount then
        for i = ChildCount + 1, NewChildCount do
            local child = select(i, WorldFrame:GetChildren())
            -- 1 frame delay to ensure custom nameplate is available --
            CreateFrame("Frame"):SetScript("OnUpdate", function(self)
                self:SetScript("OnUpdate", nil)
                self:Hide()
                if IsNamePlate(child) then
                    SetupBGHframe(child)
                end
            end)
        end
        ChildCount = NewChildCount
    end
end)

--------- Converts RGB color values to a hexadecimal code ---------
local function RGBtoHEX(r, g, b)
    return string_format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

--------- Returns the hexadecimal color code associated with a faction ---------
local function GetFactionColorHEX(faction)
    if faction ~= 0 and faction ~= 1 then
        return "|cffffffff"
    end
    local info = ChatTypeInfo[faction == 0 and "BG_SYSTEM_HORDE" or "BG_SYSTEM_ALLIANCE"]
    return string_format("|cff%02x%02x%02x", info.r * 255, info.g * 255, info.b * 255)
end

--------- Removes healers who are no longer present in the Battleground player list ---------
local function ClearDeserterHealers(list)
    for name, healerData in pairs(list) do
        if not CurrentBGplayers[name] then
            if BGHsettings.showMessages == 1 or debugMode then
                if healerData then
                    local color = RAID_CLASS_COLORS[healerData.class]
                    local coloredName = color and RGBtoHEX(color.r, color.g, color.b) .. name .. "|r" or name
                    BGHprint(string_format("%s %s" .. L["has left the battleground."] .. "|r", coloredName, GetFactionColorHEX(healerData.faction)))
                else
                    BGHprint(string_format("%s " .. L["has left the battleground."], name))
                end
            end
            SetBGHmark(name, nil)
            list[name] = nil
        end
    end
end

----- Clears all healers from the specified tracking list -----
local function ClearHealers(list)
    for name in pairs(list) do
        SetBGHmark(name, nil)
        list[name] = nil
    end
end

----------- Updates BG players list -----------
local function UpdateCurrentBGplayers()
    if not (inBG and playerFaction) then return end
    CurrentBGplayers = {}
    local name, class, _
    for i = 1, GetNumBattlefieldScores() do
        name, _, _, _, _, _, _, _, class = GetBattlefieldScore(i)
        if name then
            name = name:match("([^%-]+).*")
            CurrentBGplayers[name] = class
        end
    end
    ClearDeserterHealers(WSSFhealers)
    ClearDeserterHealers(CLEUhealers)
end

---------- Updates the list of healers based on the BG Scoreboard (WorldStateScoreFrame), prioritizing the Combat Log healers list if active ----------
local function UpdateWSSFhealers()
    if not (inBG and playerFaction and BGHsettings.WSSFtracking == 1) then return end
    local name, faction, localizedClass, damageDone, healingDone, reaction, healerClass, _
    for i = 1, GetNumBattlefieldScores() do
        name, _, _, _, _, faction, _, _, localizedClass, _, damageDone, healingDone = GetBattlefieldScore(i)
        if name then
            name = name:match("([^%-]+).*")
            healerClass = HealerClassTokens[localizedClass]
            if healerClass and healingDone > BGHsettings.h2dRatio * damageDone and healingDone > BGHsettings.healingThreshold then      
                if not WSSFhealers[name] and not CLEUhealers[name] then
                    if FriendlyHealerCandidates[name] == healerClass then
                        reaction = "FRIEND"
                        faction = playerFaction
                    else
                        reaction = "ENEMY"
                        faction = math_abs(playerFaction - 1)
                    end
                    SetBGHmark(name, reaction)
                    WSSFhealers[name] = {class = healerClass, faction = faction}
                    if debugMode then
                        BGHprint(string_format("Debug: %s (%s) added to BG Scoreboard healers list.", name, faction == 1 and "Alliance" or "Horde"))
                    end 
                end
            elseif WSSFhealers[name] then
                SetBGHmark(name, nil)
                WSSFhealers[name] = nil
                if debugMode then
                    BGHprint(string_format("Debug: %s (%s) removed from BG Scoreboard healers list (below healing-to-damage ratio).", name, faction == 1 and "Alliance" or "Horde"))
                end 
            end
        end
    end
end

--------- Updates the public healer count by faction from detected healers ---------
local function UpdatePublicHealerCount()
    if inBG and playerFaction then
        local hordeCount, allianceCount = 0, 0
        for _, healerData in pairs(CLEUhealers) do
            if healerData.faction == 0 then
                hordeCount = hordeCount + 1
            elseif healerData.faction == 1 then
                allianceCount = allianceCount + 1
            end
        end
        for _, healerData in pairs(WSSFhealers) do
            if healerData.faction == 0 then
                hordeCount = hordeCount + 1
            elseif healerData.faction == 1 then
                allianceCount = allianceCount + 1
            end
        end
        BGH_Public.AllianceCount = allianceCount
        BGH_Public.HordeCount = hordeCount
    else
        BGH_Public.AllianceCount = 0
        BGH_Public.HordeCount = 0
    end
end

----------- Manages Combat Log tracking, considering a player can change specs during the Preparation phase -----------
local function UpdateCLEUstate()
    if inBG and BGHsettings.CLEUtracking == 1 then
        local inPreparation = false
        for i = 1, 40 do
            if select(11, UnitAura("player", i)) == 44521 then
                inPreparation = true
                break
            end
        end
        if inPreparation then
            if USSregistered and BGHsettings.CLEUfix == 1 then
                EventHandler:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                USSregistered = false
                if debugMode then
                    BGHprint("Debug: Automatic Combat Log fix disabled until Preparation phase is over.")
                end
            end
            if CLEUregistered then
                EventHandler:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                CLEUregistered = false
                ClearHealers(CLEUhealers)
                if debugMode then
                    BGHprint("Debug: Combat Log tracking disabled until Preparation phase is over.")
                end
            end
        else
            if not CLEUregistered then
                EventHandler:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")    
                CLEUregistered = true        
                if debugMode then
                    BGHprint("Debug: Combat Log tracking enabled.")
                end 
            end
            if not USSregistered and BGHsettings.CLEUfix == 1 then
                EventHandler:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                USSregistered = true
                if debugMode then
                    BGHprint("Debug: Automatic Combat Log fix enabled.")
                end 
            end
        end
    else
        EventHandler:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        USSregistered = false
        EventHandler:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        CLEUregistered = false    
    end
end

--------- Requests BG scoreboard data ---------
local function BattlefieldScoreRequest()
	if WorldStateScoreFrame and WorldStateScoreFrame:IsShown() then return end
	SetBattlefieldScoreFaction()
	RequestBattlefieldScoreData()
end

--------- Updates BG scoreboard player and related healer data ---------
local function BattlefieldScoreUpdate()
    if not playerFaction then return end
    if not (WorldStateScoreFrame and WorldStateScoreFrame:IsShown() and WorldStateScoreFrame.selectedTab and WorldStateScoreFrame.selectedTab > 1) then
        UpdateCurrentBGplayers()
        UpdateWSSFhealers()
        UpdatePublicHealerCount()
    end
end

---------- Periodically requests BG Score and fix the Combat Log if it's unresponsive ----------
local lastUpdateTime = 0
local function BGupdater(self, elapsed)
    lastUpdateTime = lastUpdateTime + elapsed
    if lastUpdateTime >= 5 then
        BattlefieldScoreRequest()
        BattlefieldScoreUpdate()
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

--------- Updates the friendly player class cache for healer-capable classes ---------
local function UpdateFriendlyHealerCandidates()
	wipe(FriendlyHealerCandidates)
    local name, class, _
	for i = 1 , GetNumRaidMembers() do
		name, _, _, _, _, class = GetRaidRosterInfo(i)
		if name and class and HealerSpells[class] then
			name = name:match("([^%-]+).*")
            FriendlyHealerCandidates[name] = class
		end
	end
end

--------- Maps Battleground IDs to their English names ---------
local BGNameByID = {
	[444] = "Warsong Gulch",
	[462] = "Arathi Basin",
	[402] = "Alterac Valley",
	[483] = "Eye of the Storm",
	[513] = "Strand of the Ancients",
	[541] = "Isle of Conquest",
}

--------- Maps localized Battleground names to their English equivalents ---------
local BGName = {}
for _, englishName in pairs(BGNameByID) do
    BGName[L[englishName]] = englishName
end

--------- Returns the current Battleground name in English ---------
local function GetBGName()
    if not inBG then return end
    for i = 1, MAX_BATTLEFIELD_QUEUES do
        local queueStatus, queueMapName = GetBattlefieldStatus(i)
        if queueStatus == "active" then
            return BGName[queueMapName]
        end
    end
    local bgName = BGName[GetRealZoneText()]
    if not bgName then
        SetMapToCurrentZone()
        bgName = BGNameByID[GetCurrentMapAreaID()]
    end
    return bgName
end

--------- Sets the player's BG faction and stores it across relogs during the current BG session ---------
local function SetPlayerFaction(faction)
    faction = faction or (UnitFactionGroup("player") == "Horde" and 0 or 1)
    playerFaction = faction
    BGHchar.bgFaction = faction
    if debugMode then
        BGHprint(GetBGName(), "-", GetFactionColorHEX(playerFaction) .. (playerFaction == 1 and "Alliance|r" or "Horde|r"))
    end
end

--------- Alliance starting coordinates for each BG map ---------
local startMapCoordsA = {
	["Warsong Gulch"]           = {0.488647907972340, 0.135069295763970},
	["Arathi Basin"]            = {0.311796873807910, 0.166063979268070},
	["Alterac Valley"]          = {0.536291122436520, 0.075191102921963},
	["Eye of the Storm"]        = {0.468470871448520, 0.260840028524400},
	["Isle of Conquest"]        = {0.529043495655060, 0.809421181678770},
}

--------- Horde starting coordinates for each BG map ---------
local startMapCoordsH = {
	["Warsong Gulch"]           = {0.530568122863770, 0.907359302043910},
	["Arathi Basin"]            = {0.670242488384250, 0.704044997692110},
	["Alterac Valley"]          = {0.564327776432040, 0.893128037452700},
	["Eye of the Storm"]        = {0.493651777505870, 0.733544349670410},
	["Isle of Conquest"]        = {0.505528688430790, 0.229658007621770},
}

--------- Checks whether a value is within the specified range ---------
local function inRange(val, min, max)
	return min <= val and val <= max
end

--------- Checks if coordinates match the Alliance starting position of a BG ---------
local function isAllyStartPosition(x, y, mapName)
    local cords = startMapCoordsA[mapName]
    if not cords then return end
	if inRange(x, cords[1] - 0.002, cords[1] + 0.002) and inRange(y, cords[2] - 0.004, cords[2] + 0.004) then
		return true
	end
end

--------- Checks if coordinates match the Horde starting position of a BG ---------
local function isHordeStartPosition(x, y, mapName)
    local cords = startMapCoordsH[mapName]
    if not cords then return end
	if inRange(x, cords[1] - 0.002, cords[1] + 0.002) and inRange(y, cords[2] - 0.004, cords[2] + 0.004) then
		return true
	end
end

--------- Checks if coordinates match the Strand of the Ancients defender starting position ---------
local function isSotaDefenderPosition(x, y)
    if inRange(x, 0.48, 0.50) and inRange(y, 0.565, 0.595) then
        return true
    end
end

--------- Detects faction from the BG scoreboard as a fallback method ---------
local scoreboardFactionDetector = CreateFrame("Frame")
scoreboardFactionDetector:Hide()
scoreboardFactionDetector:SetScript("OnUpdate", function(self, elapsed)
	if inBG and GetNumBattlefieldScores() == 0 then return end
	self:Hide()
	if not inBG then return end
    local name, faction, _
    local playerName = UnitName("player")
    for i = 1, GetNumBattlefieldScores() do
        name, _, _, _, _, faction = GetBattlefieldScore(i)
        if playerName == name then
            SetPlayerFaction(faction)
            break
        end
    end
end)
local function DetectFactionFromScoreboard()
    if scoreboardFactionDetector:IsShown() then return end
    BattlefieldScoreRequest()
    scoreboardFactionDetector:Show()
end

--------- Detects faction in Strand of the Ancients using starting coordinates ---------
local SotAFactionDetector = CreateFrame("Frame")
SotAFactionDetector:Hide()
SotAFactionDetector:SetScript("OnUpdate", function(self, elapsed)
    self.timer = (self.timer or 0) + elapsed
    if self.timer < 0.4 then return end
    self:Hide()
    self.timer = 0
    if not inBG or playerFaction then return end
    local faction
    if select(2, GetWorldStateUIInfo(2)) == 0 then
        -- Ally Defending SotA
        if isSotaDefenderPosition(self.x, self.y) then
            faction = 1
        else
            faction = 0
        end
    else
        -- Horde Defending SotA
        if isSotaDefenderPosition(self.x, self.y) then
            faction = 0
        else
            faction = 1
        end
    end
    SetPlayerFaction(faction)
end)
local function DetectSotAFaction(x, y)
    if SotAFactionDetector:IsShown() then return end
    SotAFactionDetector.x = x
    SotAFactionDetector.y = y
    SotAFactionDetector.timer = 0
    SotAFactionDetector:Show()
end

--------- Detects faction from starting coordinates to support any cross-faction system ---------
local factionDetector = CreateFrame("Frame")
factionDetector:Hide()
factionDetector:SetScript("OnUpdate", function(self, elapsed)
    self.timer = (self.timer or 0) + elapsed
    if self.timer < 0.1 then return end
    self:Hide()
    self.timer = 0
    if not inBG or playerFaction then return end
	if BGHchar.bgFaction then
        SetPlayerFaction(BGHchar.bgFaction)
	else
        local bgName = GetBGName()
        local x, y = GetPlayerMapPosition("player")
        if not (bgName and x and y) then
            DetectFactionFromScoreboard()
            return
        end
        if bgName == "Strand of the Ancients" then
            DetectSotAFaction(x, y)
            return
        end
        local faction
        if isAllyStartPosition(x, y, bgName) then 	
            faction = 1
        elseif isHordeStartPosition(x, y, bgName) then
            faction = 0
        end
        if not faction then
            DetectFactionFromScoreboard()
            return
        end
        SetPlayerFaction(faction)
	end
end)
local function DetectFaction()
    if factionDetector:IsShown() then return end
    factionDetector.timer = 0
    factionDetector:Show()
end

--------- Init tracking state when joining a BG ---------
local function InitTrackingState()
    UpdateFriendlyHealerCandidates()
    BattlefieldScoreRequest()
    DetectFaction()
    EventHandler:SetScript("OnUpdate", BGupdater) 
end

--------- Reset tracking state before joining other BG ---------
local function ResetTrackingState()
    EventHandler:SetScript("OnUpdate",nil)
    EventHandler:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    EventHandler:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    CLEUregistered = false
    USSregistered = false
    scoreboardFactionDetector:Hide()
    SotAFactionDetector:Hide()
    factionDetector:Hide()
    playerFaction = false
    BGHchar.bgFaction = nil
    CurrentBGplayers = {} 
    lastUpdateTime = 0
    lastCLEUtime = nil
    CLEUtimeout = nil
    CLEUcheck = false
    wipe(FriendlyHealerCandidates)
    ClearHealers(CLEUhealers)
    ClearHealers(WSSFhealers)
    BGH_Public.AllianceCount = 0
    BGH_Public.HordeCount = 0
end

local function UpdateAllIconAnchors()
    for plate, BGHframe in pairs(AllNamePlates) do
        if BGHframe.icon then
            UpdateIconAnchor(BGHframe)
        end
    end
end

local function UpdateAllIconSizes()
    for plate, BGHframe in pairs(AllNamePlates) do
        if BGHframe.icon then
            UpdateIconSize(BGHframe)
        end
    end
end

local function UpdateAllIconTextures()
    for plate, BGHframe in pairs(AllNamePlates) do
        if BGHframe.icon then
            UpdateIconTexture(BGHframe)
        end
    end
end

--------- Reports the list of detected healers in the specified chat channel ---------
local lastPrintTime = 0
local function PrintDetectedHealers()
    if not inBG then
        BGHprint(L["Print failed (not in BG)"])
        return
    end
    local currentTime = GetTime()
    if currentTime - lastPrintTime < 5 then
        local timeRemaining = 5 - (currentTime - lastPrintTime)
        BGHprint(string_format(L["Wait %.1f s to print again."], timeRemaining))
        return
    end
    local allianceHealers = {}
    local allianceHealersColored = {}
    local hordeHealers = {}
    local hordeHealersColored = {}
    local function AppendHealers(healersList)
        for name, healerData in pairs(healersList) do
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[healerData.class]
            local coloredName = color and RGBtoHEX(color.r, color.g, color.b) .. name .. "|r" or name
            if healerData.faction == 1 then
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
    local bgName = GetBGName() or "[unknown BG]"
    local printChannel
    if BGHsettings.printChannel == "BG" then
        printChannel = "BATTLEGROUND"
    elseif BGHsettings.printChannel == "Party" then
        printChannel = "PARTY"
    elseif BGHsettings.printChannel == "Raid" then
        printChannel = "RAID"
    elseif BGHsettings.printChannel == "Guild" then
        printChannel = "GUILD"
    else
        printChannel = nil
    end
    if printChannel then
        SendChatMessage(string_format("[BattleGroundHealers] Healers detected in %s:", bgName), printChannel)
        SendChatMessage(string_format(" - %d Alliance: %s", #allianceHealers, table.concat(allianceHealers, ", ")), printChannel)
        SendChatMessage(string_format(" - %d Horde: %s", #hordeHealers, table.concat(hordeHealers, ", ")), printChannel)
    else
        print("|cff00FF98================ BattleGroundHealers ================|r")
        print(string_format(" Healers detected in |cffffd100%s|r:", bgName))
        print(string_format("  |cff00aeef- %d Alliance:|r %s", #allianceHealersColored, table.concat(allianceHealersColored, ", ")))
        print(string_format("  |cffe63c3c- %d Horde:|r %s", #hordeHealersColored, table.concat(hordeHealersColored, ", ")))
        print("|cff00FF98==================================================|r")
    end
    lastPrintTime = currentTime
end

---------------------------- Configuration settings UI ----------------------------
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

        ---------- Healer Detection Methods ----------
        ConfigUIFrame.subtitle1 = ConfigUIFrame:CreateFontString(nil,"ARTWORK") 
        ConfigUIFrame.subtitle1:SetFont(GameFontNormal:GetFont(), 11)
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
                EventHandler:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
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
                UpdateCurrentBGplayers()
                UpdateCLEUstate()
                CLEUfixCheckbox.Text:SetTextColor(1, 1, 1)
                CLEUfixCheckbox:Enable()
            else
                BGHsettings.CLEUtracking = 0
                EventHandler:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                USSregistered = false
                CLEUfixCheckbox.Text:SetTextColor(0.5, 0.5, 0.5)
                CLEUfixCheckbox:Disable()
                EventHandler:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                CLEUregistered = false
                ClearHealers(CLEUhealers)
                UpdateCurrentBGplayers()
                UpdateWSSFhealers()
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
                UpdateCurrentBGplayers()
                UpdateWSSFhealers()
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
        printChannelDropdown.Options = {"BG", "Party", "Raid", "Guild", "Self"}
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
        printHealersButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("/bgh print")
            GameTooltip:Show()
        end)
        printHealersButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        ----------- Icon Display Settings -----------
        ConfigUIFrame.subtitle2 = ConfigUIFrame:CreateFontString(nil,"ARTWORK") 
        ConfigUIFrame.subtitle2:SetFont("Fonts\\FRIZQT__.TTF", 11)
        ConfigUIFrame.subtitle2:SetFont(GameFontNormal:GetFont(), 11)
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
            UpdateAllIconSizes()
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
                    UpdateAllIconTextures()
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
            UpdateAllIconAnchors()
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
            UpdateAllIconAnchors()
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
                    UpdateAllIconAnchors()
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
            UpdateAllIconTextures()
        end)    

        -- Mark Target (Button)
        local testMarkButton = CreateFrame("Button", "BGHConfigUItestMarkButton", ConfigUIFrame, "UIPanelButtonTemplate")
        local testModeMarks = {}
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
                    testModeMarks[name] = nil
                else
                    SetBGHmark(name, UnitCanAttack("player", "target") and "ENEMY" or "FRIEND")
                    testModeMarks[name] = true
                end
            end
            UpdateAllIconTextures()
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
                testMode = true
            else
                testMarkButton:Disable()
                testMode = false
                for name in pairs(testModeMarks) do
                    SetBGHmark(name, nil)
                    testModeMarks[name] = nil
                end
                UpdateAllIconTextures()
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
                    for k, v in pairs(DefaultSettings) do
                        BGHsettings[k] = DefaultSettings[k]
                    end
                    if BGHsettings.CLEUfix == 1 then
                        CLEUfixCheckbox:SetChecked(true)
                    else
                        CLEUfixCheckbox:SetChecked(false)
                        EventHandler:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                        USSregistered = false
                    end
                    if BGHsettings.CLEUtracking == 1 then
                        CLEUtrackingCheckbox:SetChecked(true)
                        CLEUfixCheckbox.Text:SetTextColor(1, 1, 1)
                        CLEUfixCheckbox:Enable()
                        UpdateCurrentBGplayers()
                        UpdateCLEUstate()
                    else
                        CLEUtrackingCheckbox:SetChecked(false)
                        EventHandler:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                        USSregistered = false
                        CLEUfixCheckbox.Text:SetTextColor(0.5, 0.5, 0.5)
                        CLEUfixCheckbox:Disable()
                        EventHandler:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                        CLEUregistered = false
                        ClearHealers(CLEUhealers)
                        UpdateCurrentBGplayers()
                        UpdateWSSFhealers()
                    end
                    if BGHsettings.WSSFtracking == 1 then
                        WSSFtrackingCheckbox:SetChecked(true)
                        UpdateCurrentBGplayers()
                        UpdateWSSFhealers()
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
                    UpdateAllIconAnchors()
                    UpdateAllIconSizes()
                    UpdateAllIconTextures()
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
                testMode = false
                for name in pairs(testModeMarks) do
                    SetBGHmark(name, nil)
                    testModeMarks[name] = nil
                end
                UpdateAllIconTextures()
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
        description:SetFormattedText(L["Marks BG healer nameplates with a configurable icon.\nSupports two detection methods that can work simultaneously.\n\nAuthor: |cffc41f3bKhal|r\nVersion: %s"], version)
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
        settingsButton:GetFontString():SetFont(GameFontNormal:GetFont(), 14)
        self:SetScript("OnShow", nil)
    end)
    InterfaceOptions_AddCategory(addonPanel)
end

------------------- Event Handler -------------------
function EventHandler:ADDON_LOADED(event, ...)
    local addon = ...
	if addon == AddonName then
        InitSettings()
        print(string_format(" |cff00FF98BattleGroundHealers|r v%s by |cffc41f3bKhal|r", version))
        self:UnregisterEvent(event)
        self[event] = nil
	end
end

function EventHandler:PLAYER_LOGIN(event)
    AddInterfaceOptions()
    SetCVar("ShowClassColorInNameplate", 1)
    self:UnregisterEvent(event)
    self[event] = nil
end

function EventHandler:PLAYER_ENTERING_WORLD()
    local _, instanceType = IsInInstance()
    if instanceType == "pvp" then
        inBG = true
        InitTrackingState()
    elseif inBG or BGHchar.bgFaction then
        inBG = false
        ResetTrackingState()
    end
end

function EventHandler:RAID_ROSTER_UPDATE()
    if not inBG then return end
    UpdateFriendlyHealerCandidates()
end

function EventHandler:UPDATE_BATTLEFIELD_STATUS(event, ...)
    local bgIndex = ...
    if GetBattlefieldStatus(bgIndex) == "active" then
        if not BGstatus[bgIndex] then
            ResetTrackingState()
        end
        BGstatus[bgIndex] = true
    else
        BGstatus[bgIndex] = false
    end
end

function EventHandler:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    lastCLEUtime = GetTime()
    if not playerFaction then return end
    local _, subEvent, sourceGUID, sourceName, _, _, _, _, spellID = ...
    if subEvent == "SPELL_CAST_SUCCESS" or subEvent == "SPELL_AURA_APPLIED" then
        if not HealerSpellMap[spellID] then return end
        local name = sourceName:match("([^%-]+).*")
        if CLEUhealers[name] then return end
        local _, class = GetPlayerInfoByGUID(sourceGUID)
        if not HealerSpells[class] then return end
        local faction, reaction
        if FriendlyHealerCandidates[name] == class then
            reaction = "FRIEND"
            faction = playerFaction
        else
            reaction = "ENEMY"
            faction = math_abs(playerFaction - 1)
            if BGH_Notifier.OnHealerDetected then
                pcall(BGH_Notifier.OnHealerDetected, sourceName, class)
            end
        end
        SetBGHmark(name, reaction)
        CLEUhealers[name] = {class = class, faction = faction}
        if debugMode then
            BGHprint(string_format("Debug: %s (%s) added to Combat Log healers list (spellID: %s)", name, faction == 1 and "Alliance" or "Horde", spellID))
        end 
        if WSSFhealers[name] then
            WSSFhealers[name] = nil
            if debugMode then
                BGHprint(string_format("Debug: %s (%s) removed from BG Scoreboard healers list (Combat Log list priority).", name, faction == 1 and "Alliance" or "Horde"))
            end
        end
    end
end

function EventHandler:UNIT_SPELLCAST_SUCCEEDED(event, ...)
    local unit, name = ...
    if unit == "player" and name and playerSpells[name] then
        CLEUcheck = true
        CLEUtimeout = 0.50
    end
end

function EventHandler:OnEvent(event, ...)
	if self[event] then
		return self[event](self, event, ...)
	end
end

EventHandler:SetScript("OnEvent", EventHandler.OnEvent)
EventHandler:RegisterEvent("ADDON_LOADED")
EventHandler:RegisterEvent("PLAYER_LOGIN")
EventHandler:RegisterEvent("PLAYER_ENTERING_WORLD")
EventHandler:RegisterEvent("RAID_ROSTER_UPDATE")
EventHandler:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")

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
            BGHprint("Chat messages " .. (BGHsettings.showMessages == 1 and "|cff88FF88Enabled|r" or "|cffff4444Disabled|r"))
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
            BGHprint("Debug mode |cffff4444Disabled|r")
        else 
            debugMode = true
            BGHprint("Debug mode |cff88FF88Enabled|r")
        end
    end
end
