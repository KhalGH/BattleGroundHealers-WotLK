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
}

local WorldFrame = WorldFrame
local UnitName = UnitName
local GetSpellInfo = GetSpellInfo
local RequestBattlefieldScoreData = RequestBattlefieldScoreData
local GetNumBattlefieldScores = GetNumBattlefieldScores
local GetBattlefieldScore = GetBattlefieldScore
local IsInInstance = IsInInstance
local CombatLogClearEntries = CombatLogClearEntries
local LOCALIZED_CLASS_NAMES_MALE = LOCALIZED_CLASS_NAMES_MALE
local LOCALIZED_CLASS_NAMES_FEMALE = LOCALIZED_CLASS_NAMES_FEMALE
local SetMapToCurrentZone = SetMapToCurrentZone
local GetCurrentMapAreaID = GetCurrentMapAreaID
local setmetatable = setmetatable
local print = print
local next = next

local BGHframe = CreateFrame("Frame")
local CLEUframe = CreateFrame("Frame")
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
local TidyPlatesCheck = false
local VirtualPlatesCheck = false
local debugMode = false

BGH_Notifier = BGH_Notifier or {}
BGH_Notifier.OnHealerDetected = ni

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

local function HandleLevelTextOverlap(BGHregion)
    local texture = MarkedNames[BGHregion.activeName]
    if texture then
        if BGHsettings.iconAnchor == "right" then
            local x = BGHsettings.iconXoffset
            local y = BGHsettings.iconYoffset
            local D = BGHsettings.iconSize
            if BGHsettings.iconStyle == "Blizzlike" then
                local r = 0.5 * D
                local R = sqrt(((x + r - 12)/0.8)^2 + (y/0.5)^2)
                local d = abs(1 - 1/R)*sqrt((x + r - 12)^2+(y)^2)
                if d < r or R < 1 then
                    BGHregion.levelRegion:Hide()
                else
                    BGHregion.levelRegion:Show()
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
                    abs(y) >= 8 and abs(y) <= 18 and
                    D >= 3 * abs(y) + 3 and
                    D <= 69 - 5 * x
                )
                if inOverlapDomain and OverlapAdjustment then
                    BGHregion.levelRegion:Hide()
                else
                    BGHregion.levelRegion:Show()
                end
            else
                BGHregion.levelRegion:Show()
            end
        else
            BGHregion.levelRegion:Show()
        end
    else
        BGHregion.levelRegion:Show()
    end
end

------------- Update the icon texture if it changes  -------------
local function UpdateTextures(BGHregion)
    local texture = MarkedNames[BGHregion.activeName]
    local levelRegion = BGHregion.levelRegion
    if texture then
        if texture ~= BGHregion.prevTexture then
            BGHregion.icon:SetTexture(texture)
            BGHregion.icon:Show()
            BGHregion.prevTexture = texture
        end
    else
        BGHregion.icon:Hide()
        BGHregion.prevTexture = nil   
    end
    -- Hide Blizz default plate's level text if it overlaps with the icon
    if BlizzPlates then  
        HandleLevelTextOverlap(BGHregion)
    end
end

------------ Update all mark frames when the configuration changes  ------------
local function UpdateAllMarks()
    for _, BGHregion in pairs(GlobalNamePlates) do
        if BGHregion.icon then
            BGHregion.icon:ClearAllPoints()
            local anchorData = anchorMapping[BGHsettings.iconAnchor or "top"]
            BGHregion.icon:SetPoint(
                anchorData.anchorPoint,
                BGHregion:GetParent(),
                anchorData.relativePoint,
                BGHsettings.iconXoffset + anchorData.xOffset,
                BGHsettings.iconYoffset + anchorData.yOffset
            )
            BGHregion.icon:SetSize(BGHsettings.iconSize, BGHsettings.iconSize)
            UpdateTextures(BGHregion)
        end
    end
end

local function NamePlate_OnShow(BGHregion)
    local name = BGHregion.nameRegion:GetText()
    BGHregion.activeName = name
    ActiveNamePlates[name] = BGHregion
    if MarkedNames[name] then
        UpdateTextures(BGHregion)
    end 
end

local function NamePlate_OnHide(BGHregion)
    BGHregion.icon:Hide()
    ActiveNamePlates[BGHregion.activeName], BGHregion.activeName, BGHregion.prevTexture = nil
end

local function NamePlate_OnUpdate(BGHregion)
    if BGHregion.nameRegion:GetText() ~= BGHregion.activeName then
        NamePlate_OnHide(BGHregion)
        NamePlate_OnShow(BGHregion)
        BGHregion.activeName = BGHregion.nameRegion:GetText()
    end
end


---- Checks if the frame is a nameplate ----
local function IsNamePlate(frame)
    if frame:GetName() then return false end
    local region = select(2, frame:GetRegions())
    return region and region:GetTexture() == "Interface\\Tooltips\\Nameplate-Border"
end

-------- Setup a frame that manages the mark texture parameters  --------
local function SetupNamePlate(plate)
    local _, _, _, _, _, _, nameRegion, levelRegion = plate:GetRegions()
    if plate.extended then -- Using TidyPlates custom frames if available
        plate = plate.extended
        if not TidyPlatesCheck then
            BlizzPlates = false
            TidyPlatesCheck = true
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
            print("|cff00FF98[BGH]|r TidyPlates detected, anchors adjusted.")
        end
    elseif plate.RealPlate then -- Using _VirtualPlates custom frames if available
        if not VirtualPlatesCheck then
            BlizzPlates = false
            VirtualPlatesCheck = true
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
            print("|cff00FF98[BGH]|r _VirtualPlates detected, anchors adjusted.")
        end
    end
    local BGHregion = CreateFrame("Frame", nil, plate)
    GlobalNamePlates[plate] = BGHregion
    BGHregion:SetFrameStrata("TOOLTIP")
    BGHregion.icon = plate:CreateTexture(nil, "OVERLAY")
    BGHregion.icon:ClearAllPoints()
    local anchorData = anchorMapping[BGHsettings.iconAnchor or "top"]
    BGHregion.icon:SetPoint(
        anchorData.anchorPoint,
        BGHregion:GetParent(),
        anchorData.relativePoint,
        BGHsettings.iconXoffset + anchorData.xOffset,
        BGHsettings.iconYoffset + anchorData.yOffset
    )
    BGHregion.icon:SetSize(BGHsettings.iconSize, BGHsettings.iconSize)
    BGHregion.nameRegion = nameRegion
    BGHregion.activeName = nameRegion:GetText()
    ActiveNamePlates[BGHregion.activeName] = plate
    BGHregion.levelRegion = levelRegion
    BGHregion.levelRegion:SetDrawLayer("ARTWORK")
    NamePlate_OnShow(BGHregion)
    UpdateTextures(BGHregion)
    BGHregion:SetScript("OnUpdate", NamePlate_OnUpdate)
    BGHregion:SetScript("OnShow", NamePlate_OnShow)
    BGHregion:SetScript("OnHide", NamePlate_OnHide)
end

------ Detects when the number of nameplates in the WorldFrame increases  ------
local prevChildCount = 1
CreateFrame("Frame"):SetScript("OnUpdate", function(self, elapsed)
    if prevChildCount ~= WorldFrame:GetNumChildren() then
        for _, ChildFrame in next, { WorldFrame:GetChildren() }, prevChildCount do
            if IsNamePlate(ChildFrame) then
                -- 1 frame delay to ensure TidyPlates' plate.extended is available --
                CreateFrame("Frame"):SetScript("OnUpdate", function(self, elapsed)
                    self:SetScript("OnUpdate", nil)
                    SetupNamePlate(ChildFrame)
                end)
            end
        end
        prevChildCount = WorldFrame:GetNumChildren()
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
                    print("|cff00FF98[BGH] Debug:|r Player Faction: ", playerFaction == 1 and "Alliance" or "Horde")
                end
            end
        end
    end
    for name in pairs(WSSFhealers) do
        if not currentBGplayers[name] then
            print(string.format("|cff00FF98[BGH]|r %s (%s) has left the BG, removed from healers list.", name, WSSFhealers[name] == 1 and "Alliance" or "Horde"))
            WSSFhealers[name] = nil
            SetBGHmark(name, nil)
        end
    end
    for name in pairs(CLEUhealers) do
        if not currentBGplayers[name] then
            print(string.format("|cff00FF98[BGH]|r %s (%s) has left the BG, removed from healers list.", name, CLEUhealers[name] == 1 and "Alliance" or "Horde"))
            CLEUhealers[name] = nil
            SetBGHmark(name, nil)  
        end
    end  
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
                        WSSFhealers[name] = faction
                        SetBGHmark(name, ((BGHsettings.iconInvertColor == 1) == (faction == playerFaction)) and IconTextures[BGHsettings.iconStyle].Red or IconTextures[BGHsettings.iconStyle].Blue)
                        if debugMode then
                            print(string.format("|cff00FF98[BGH] Debug:|r %s (%s) added to BG Scoreboard healers list.", name, faction == 1 and "Alliance" or "Horde"))
                        end 
                    end
                elseif WSSFhealers[name] then
                    WSSFhealers[name] = nil
                    SetBGHmark(name, nil)
                    if debugMode then
                        print(string.format("|cff00FF98[BGH] Debug:|r %s (%s) removed from BG Scoreboard healers list (below healing-to-damage ratio).", name, faction == 1 and "Alliance" or "Horde"))
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
                    print("|cff00FF98[BGH] Debug:|r Automatic Combat Log fix disabled until Preparation phase is over.")
                end
            end
            if CLEUregistered then
                CLEUframe:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                CLEUregistered = false
                ClearHealers(CLEUhealers)
                if debugMode then
                    print("|cff00FF98[BGH] Debug:|r Combat Log tracking disabled until Preparation phase is over.")
                end
            end
        else
            if not CLEUregistered then
                CLEUframe:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")    
                CLEUregistered = true        
                if debugMode then
                    print("|cff00FF98[BGH] Debug:|r Combat Log tracking enabled.")
                end 
            end
            if not USSregistered and BGHsettings.CLEUfix == 1 then
                CLEUframe:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                USSregistered = true
                if debugMode then
                    print("|cff00FF98[BGH] Debug:|r Automatic Combat Log fix enabled.")
                end 
            end
        end
    end
end

local lastCLEUevent
local CLEUtimeout
local CLEUcheck = false
------------------- Updates the list of healers based on Combat Log Events -------------------
local function CLEUhandler(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        lastCLEUevent = GetTime()
        local _, subEvent, _, sourceName, _, _, _, _, spellID = ...
        if subEvent == "SPELL_CAST_SUCCESS" or subEvent == "SPELL_AURA_APPLIED" then
            if healerSpellHash[spellID] then
                local shortName = sourceName:match("([^%-]+).*")
                if not CLEUhealers[shortName] then
                    for i = 1, GetNumBattlefieldScores() do
                        local name, _, _, _, _, faction, _, _, class = GetBattlefieldScore(i)
                        if name then
                            name = name:match("([^%-]+).*")
                            if name == shortName and HCN[class] and playerFaction then
                                CLEUhealers[name] = faction
                                SetBGHmark(name, ((BGHsettings.iconInvertColor == 1) == (faction == playerFaction)) and IconTextures[BGHsettings.iconStyle].Red or IconTextures[BGHsettings.iconStyle].Blue)
                                if BGH_Notifier.OnHealerDetected and faction ~= playerFaction then
                                    pcall(BGH_Notifier.OnHealerDetected, sourceName, HCN[class])
                                end
                                if debugMode then
                                    print(string.format("|cff00FF98[BGH] Debug:|r %s (%s) added to Combat Log healers list (spellID: %s)", name, faction == 1 and "Alliance" or "Horde", spellID))
                                end 
                                if WSSFhealers[name] then
                                    WSSFhealers[name] = nil
                                    if debugMode then
                                        print(string.format("|cff00FF98[BGH] Debug:|r %s (%s) removed from BG Scoreboard healers list (Combat Log list priority).", name, faction == 1 and "Alliance" or "Horde"))
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

local lastUpdateTime = 0
local UpdateInterval = 5
---------- Periodically updates healer lists and fix the Combat Log if it's unresponsive ----------
local function OnUpdate(self, elapsed)
    lastUpdateTime = lastUpdateTime + elapsed
    if lastUpdateTime >= UpdateInterval then
        UpdateCurrentBGplayers()
        UpdateWSSFhealers()
        UpdateCLEUstate()
        lastUpdateTime = 0
    end
	if CLEUcheck then
		CLEUtimeout = CLEUtimeout - elapsed
		if (CLEUtimeout > 0) then return end
		CLEUcheck = false
		if (lastCLEUevent and ( GetTime() - lastCLEUevent ) <= 1) then return end
		CombatLogClearEntries()
        if debugMode then
            print("|cff00FF98[BGH] Debug:|r Combat Log unresponsive. Entries cleared to fix it.")
        end   
	end
end

local lastPrintTime = 0
local printCooldown = 5
---------------- Prints the list of detected healers with a cooldown control ----------------
local function PrintDetectedHealers()
    if not inBG then
        print("|cff00FF98[BGH]|r Print failed (not in BG)")
        return
    end
    local currentTime = GetTime()
    if currentTime - lastPrintTime < printCooldown then
        local timeRemaining = printCooldown - (currentTime - lastPrintTime)
        print(string.format("|cff00FF98[BGH]|r Wait %.1f s to print again.", timeRemaining))
        return
    end
    local allianceHealers = {}
    local hordeHealers = {}
    if BGHsettings.WSSFtracking == 1 then
        for name, faction in pairs(WSSFhealers) do
            if faction == 1 then
                table.insert(allianceHealers, name)
            else
                table.insert(hordeHealers, name)
            end
        end
    end
    if BGHsettings.CLEUtracking == 1 then
        for name, faction in pairs(CLEUhealers) do
            if faction == 1 then
                table.insert(allianceHealers, name)
            else
                table.insert(hordeHealers, name)
            end
        end
    end 
    local BGNameByID = {
        [444] = "Warsong Gulch",
        [462] = "Arathi Basin",
        [402] = "Alterac Valley",
        [483] = "Eye of the Storm",
        [513] = "Strand of the Ancients",
        [541] = "Isle of Conquest",
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
        SendChatMessage(string.format("[BattleGroundHealers] Healers detected in %s:", BGName), printChannel)
        SendChatMessage(string.format(" %d Alliance: %s", #allianceHealers, #allianceHealers > 0 and table.concat(allianceHealers, ", ") or ""), printChannel)
        SendChatMessage(string.format(" %d Horde: %s", #hordeHealers, #hordeHealers > 0 and table.concat(hordeHealers, ", ") or ""), printChannel)
    else
        print(string.format("|cff00FF98[BattleGroundHealers]|r Healers detected in %s:", BGName))
        print(string.format(" %d Alliance: %s", #allianceHealers, #allianceHealers > 0 and table.concat(allianceHealers, ", ") or ""))
        print(string.format(" %d Horde: %s", #hordeHealers, #hordeHealers > 0 and table.concat(hordeHealers, ", ") or ""))
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
        ConfigUIFrame.TopLeftTex:SetTexture("Interface\\AddOns\\BattleGroundHealers\\Artwork\\BGHframe-TopLeft")
        ConfigUIFrame.TopLeftTex:SetSize(208, 252)
        ConfigUIFrame.TopLeftTex:SetPoint("TOPLEFT")
        ConfigUIFrame.TopLeftTex:SetTexCoord(0.1875, 1, 0.015625, 1)
        ConfigUIFrame.LeftTex = ConfigUIFrame:CreateTexture(nil, "ARTWORK")
        ConfigUIFrame.LeftTex:SetTexture("Interface\\AddOns\\BattleGroundHealers\\Artwork\\BGHframe-BottomLeft")
        ConfigUIFrame.LeftTex:SetSize(208, 120)
        ConfigUIFrame.LeftTex:SetPoint("BOTTOMLEFT", 0, 184)
        ConfigUIFrame.LeftTex:SetTexCoord(0.1875, 1, 0, 0.46875)
        ConfigUIFrame.BottomLeftTex = ConfigUIFrame:CreateTexture(nil, "ARTWORK")
        ConfigUIFrame.BottomLeftTex:SetTexture("Interface\\AddOns\\BattleGroundHealers\\Artwork\\BGHframe-BottomLeft")
        ConfigUIFrame.BottomLeftTex:SetSize(208, 184)
        ConfigUIFrame.BottomLeftTex:SetPoint("BOTTOMLEFT")
        ConfigUIFrame.BottomLeftTex:SetTexCoord(0.1875, 1, 0, 0.71875)
        ConfigUIFrame.TopRightTex = ConfigUIFrame:CreateTexture(nil, "ARTWORK")
        ConfigUIFrame.TopRightTex:SetTexture("Interface\\AddOns\\BattleGroundHealers\\Artwork\\BGHframe-TopRight")
        ConfigUIFrame.TopRightTex:SetSize(80, 252)
        ConfigUIFrame.TopRightTex:SetPoint("TOPLEFT", 208, 0)
        ConfigUIFrame.TopRightTex:SetTexCoord(0, 0.625, 0.015625, 1)
        ConfigUIFrame.RightTex = ConfigUIFrame:CreateTexture(nil, "ARTWORK")
        ConfigUIFrame.RightTex:SetTexture("Interface\\AddOns\\BattleGroundHealers\\Artwork\\BGHframe-BottomRight")
        ConfigUIFrame.RightTex:SetSize(80, 120)
        ConfigUIFrame.RightTex:SetPoint("BOTTOMLEFT", 208, 184)
        ConfigUIFrame.RightTex:SetTexCoord(0, 0.625, 0, 0.46875)
        ConfigUIFrame.BottomRightTex = ConfigUIFrame:CreateTexture(nil, "ARTWORK")
        ConfigUIFrame.BottomRightTex:SetTexture("Interface\\AddOns\\BattleGroundHealers\\Artwork\\BGHframe-BottomRight")
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
        ConfigUIFrame.subtitle1:SetText("Healer Detection Methods")
        ConfigUIFrame.subtitle1:SetTextColor(1, 0.82, 0, 1)
        CreateSeparatorLine(ConfigUIFrame.subtitle1)

        -- Automatic Combat Log Fix (Checkbox)
        local CLEUfixCheckbox = CreateFrame("CheckButton", "BGHConfigUICLEUfixCheckbox", ConfigUIFrame, "UICheckButtonTemplate")
        CLEUfixCheckbox:SetPoint("TOPLEFT", 59, -102)
        CLEUfixCheckbox:SetSize(21, 21)
        CLEUfixCheckbox.Text = _G[CLEUfixCheckbox:GetName() .. "Text"]
        CLEUfixCheckbox.Text:SetText("Automatic Combat Log Fix")
        CLEUfixCheckbox.Text:SetPoint("LEFT", CLEUfixCheckbox, "RIGHT", 1, 1) 
        CLEUfixCheckbox.Text:SetFont(CLEUfixCheckbox.Text:GetFont(), 9.5)
        CLEUfixCheckbox.Text:SetTextColor(1, 1, 1, 1)
        CLEUfixCheckbox:SetChecked(BGHsettings.CLEUfix == 1)
        CLEUfixCheckbox:SetScript("OnClick", function(self)
            if self:GetChecked() then
                print("|cff00FF98[BGH]|r Automatic Combat Log Fix enabled")
                BGHsettings.CLEUfix = 1
                
            else
                print("|cff00FF98[BGH]|r Automatic Combat Log Fix disabled")
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
        CLEUtrackingCheckbox.Text:SetText("Track Healers via Combat Log")
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
                print("|cff00FF98[BGH]|r Combat Log tracking enabled")
                BGHsettings.CLEUtracking = 1
                if inBG then
                    UpdateCurrentBGplayers()
                    UpdateCLEUstate()
                end
                CLEUfixCheckbox.Text:SetTextColor(1, 1, 1)
                CLEUfixCheckbox:Enable()
            else
                print("|cff00FF98[BGH]|r Combat Log tracking disabled")
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
        WSSFtrackingCheckbox.Text:SetText("Track Healers via BG Scoreboard")
        WSSFtrackingCheckbox.Text:SetPoint("LEFT", WSSFtrackingCheckbox, "RIGHT", 1, 1) 
        WSSFtrackingCheckbox.Text:SetTextColor(1, 1, 1, 1)
        WSSFtrackingCheckbox:SetChecked(BGHsettings.WSSFtracking == 1)
        WSSFtrackingCheckbox:SetScript("OnClick", function(self)
            if self:GetChecked() then
                print("|cff00FF98[BGH]|r BG Scoreboard tracking enabled")
                BGHsettings.WSSFtracking = 1
                if inBG then
                    UpdateCurrentBGplayers()
                    UpdateWSSFhealers()
                end
            else
                print("|cff00FF98[BGH]|r BG Scoreboard tracking disabled")
                BGHsettings.WSSFtracking = 0
                ClearHealers(WSSFhealers)
            end
        end) 

        -- Print Channel (Dropdown)
        local printChannelDropdown = CreateFrame("Frame", "BGHConfigUIprintChannelDropdown", ConfigUIFrame, "UIDropDownMenuTemplate")
        printChannelDropdown:SetPoint("TOPRIGHT", -18, -161)
        printChannelDropdown.Label = ConfigUIFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        printChannelDropdown.Label:SetPoint("RIGHT", printChannelDropdown, "LEFT", 14, 3)
        printChannelDropdown.Label:SetText("Channel:")
        printChannelDropdown.Label:SetFont(GameFontNormal:GetFont(), 10.5)
        printChannelDropdown.Font = CreateFont("BGH_PrintChannelFont")
        printChannelDropdown.Font:SetFont(GameFontNormal:GetFont(), 9/UIParent:GetScale())
        printChannelDropdown.Font:SetTextColor(1, 1, 1, 1)
        printChannelDropdown.Text = _G[printChannelDropdown:GetName().."Text"]
        printChannelDropdown.Text:SetFont(printChannelDropdown.Text:GetFont(), 10.5)
        printChannelDropdown.Text:ClearAllPoints()
        printChannelDropdown.Text:SetPoint("CENTER", printChannelDropdown, "CENTER", -5, 3)
        printChannelDropdown.Text:SetJustifyH("CENTER")
        printChannelDropdown.Options = {"BG", "Party", "Guild", "Self"}
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
        printHealersButton:SetSize(86, 26)
        printHealersButton:GetFontString():SetFont(printHealersButton:GetFontString():GetFont(), 10.5)
        printHealersButton:SetPoint("TOPLEFT", 34, -161)
        printHealersButton:SetText("Print Healers")
        printHealersButton:SetScript("OnClick", function()
            PrintDetectedHealers()
        end)   

        ----------- Icon Display Settings -----------
        ConfigUIFrame.subtitle2 = ConfigUIFrame:CreateFontString(nil,"ARTWORK") 
        ConfigUIFrame.subtitle2:SetFont("Fonts\\FRIZQT__.TTF", 11)
        ConfigUIFrame.subtitle2:SetPoint("TOP", 0, -204)
        ConfigUIFrame.subtitle2:SetText("Icon Display Settings")
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
        iconSizeSlider.Label:SetText("Icon Size")
        iconSizeSlider.Label:SetFont(GameFontNormal:GetFont(), 10.5)
        iconSizeSlider.Thumb = iconSizeSlider:GetThumbTexture()
        iconSizeSlider.Value = iconSizeSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlight") 
        iconSizeSlider.Value:SetPoint("BOTTOM", iconSizeSlider.Thumb, "TOP", 0, -4)
        iconSizeSlider.Value:SetText(iconSizeSlider:GetValue())
        iconSizeSlider.Value:SetFont(GameFontHighlight:GetFont(), 10.5)
        _G[iconSizeSlider:GetName() .. "Low"]:SetText("20")
        _G[iconSizeSlider:GetName() .. "High"]:SetText("60")
        iconSizeSlider:SetScript("OnValueChanged", function(self, value)
            BGHsettings.iconSize = math.floor(value + 0.5)
            iconSizeSlider.Value:SetText(math.floor(value + 0.5))
            UpdateAllMarks()
        end)

        -- Icon Style (Dropdown)
        local iconStyleDropdown = CreateFrame("Frame", "BGHConfigUIiconStyleDropdown", ConfigUIFrame, "UIDropDownMenuTemplate")
        iconStyleDropdown:SetPoint("TOPLEFT", 18, -292)
        iconStyleDropdown.Label = ConfigUIFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        iconStyleDropdown.Label:SetPoint("BOTTOM", iconStyleDropdown, "TOP", 0, 2)
        iconStyleDropdown.Label:SetText("Icon Style")
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
        iconXoffsetSlider.Label:SetText("X offset")
        iconXoffsetSlider.Label:SetFont(GameFontNormal:GetFont(), 10.5)
        iconXoffsetSlider.Thumb = iconXoffsetSlider:GetThumbTexture()
        iconXoffsetSlider.Value = iconXoffsetSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        iconXoffsetSlider.Value:SetPoint("BOTTOM", iconXoffsetSlider.Thumb, "TOP", 0, -4)
        iconXoffsetSlider.Value:SetText(iconXoffsetSlider:GetValue())
        iconXoffsetSlider.Value:SetFont(GameFontHighlight:GetFont(), 10.5)
        _G[iconXoffsetSlider:GetName() .. "Low"]:SetText("-40")
        _G[iconXoffsetSlider:GetName() .. "High"]:SetText("40")
        iconXoffsetSlider:SetScript("OnValueChanged", function(self, value)
            BGHsettings.iconXoffset = math.floor(value + 0.5)
            iconXoffsetSlider.Value:SetText(math.floor(value + 0.5))
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
        iconYoffsetSlider.Label:SetText("Y offset")
        iconYoffsetSlider.Label:SetFont(GameFontNormal:GetFont(), 10.5)
        iconYoffsetSlider.Thumb = iconYoffsetSlider:GetThumbTexture()
        iconYoffsetSlider.Value = iconYoffsetSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        iconYoffsetSlider.Value:SetPoint("BOTTOM", iconYoffsetSlider.Thumb, "TOP", 0, -4)
        iconYoffsetSlider.Value:SetText(iconYoffsetSlider:GetValue())
        iconYoffsetSlider.Value:SetFont(GameFontHighlight:GetFont(), 10.5)
        _G[iconYoffsetSlider:GetName() .. "Low"]:SetText("-40")
        _G[iconYoffsetSlider:GetName() .. "High"]:SetText("40")
        iconYoffsetSlider:SetScript("OnValueChanged", function(self, value)
            BGHsettings.iconYoffset = math.floor(value + 0.5)
            iconYoffsetSlider.Value:SetText(math.floor(value + 0.5))
            UpdateAllMarks()
        end)

        -- Icon Anchor (Dropdown)
        local iconAnchorDropdown = CreateFrame("Frame", "BGHConfigUIiconAnchorDropdown", ConfigUIFrame, "UIDropDownMenuTemplate")
        iconAnchorDropdown:SetPoint("TOPRIGHT", -18, -292)
        iconAnchorDropdown.Label = ConfigUIFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        iconAnchorDropdown.Label:SetPoint("BOTTOM", iconAnchorDropdown, "TOP", 0, 2)
        iconAnchorDropdown.Label:SetText("Anchor")
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
        iconInvertColorCheckbox.Text:SetText("Invert Icon Color")
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
        testMarkButton:SetSize(90, 26)
        testMarkButton:GetFontString():SetFont(testMarkButton:GetFontString():GetFont(), 10.5)
        testMarkButton:SetPoint("TOPRIGHT", -34, -460)
        testMarkButton:SetText("Mark Target")
        testMarkButton:Disable()
        testMarkButton:SetScript("OnClick", function()
            local name = UnitName("target")
            if name then
                if MarkedNames[name] then
                    SetBGHmark(name, nil)
                    for i, markedName in ipairs(testModeMarkedNames) do
                        if markedName == name then
                            table.remove(testModeMarkedNames, i)
                            break
                        end
                    end
                else
                    local isFriendly = UnitReaction("player", "target") >= 5
                    SetBGHmark(name, ((BGHsettings.iconInvertColor == 1) == isFriendly) and IconTextures[BGHsettings.iconStyle].Red or IconTextures[BGHsettings.iconStyle].Blue)
                    table.insert(testModeMarkedNames, name)
                end
            end
            UpdateAllMarks()
        end)

        -- Test Mode (Checkbox)
        local testModeCheckbox = CreateFrame("CheckButton", "BGHConfigUItestModeCheckbox", ConfigUIFrame, "UICheckButtonTemplate")
        testModeCheckbox:SetPoint("TOPLEFT", 34, -462)
        testModeCheckbox:SetSize(24, 24)
        testModeCheckbox.Text = _G[testModeCheckbox:GetName().."Text"]
        testModeCheckbox.Text:SetText("Enable Test Mode")
        testModeCheckbox.Text:SetPoint("LEFT", testModeCheckbox, "RIGHT", 1, 1) 
        testModeCheckbox.Text:SetTextColor(1, 1, 1, 1)
        testModeCheckbox:SetChecked(false)
        testModeCheckbox:SetScript("OnClick", function(self)
            if self:GetChecked() then
                print("|cff00FF98[BGH]|r Test mode enabled")
                testMarkButton:Enable()
            else
                print("|cff00FF98[BGH]|r Test mode disabled")
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
        resetButton:SetText("Reset")
        resetButton:SetScript("OnClick", function()
            StaticPopupDialogs["CONFIRM_RESET_BGH_CONFIG"] = {
                text = "Are you sure you want to reset all settings to default?",
                button1 = "Yes",
                button2 = "No",
                OnAccept = function()
                    print("|cff00FF98[BGH]|r Settings reset to default values.")
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
                self:SetScale(math.min(scale + 0.1, 1.3/UIParent:GetScale()))
            else
                self:SetScale(math.max(scale - 0.1, 0.6/UIParent:GetScale()))
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
                print("|cff00FF98[BGH]|r Test mode disabled")
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
        description:SetFormattedText("Marks BG healer nameplates with a configurable icon.\nSupports two detection methods that can work simultaneously.\n\nAuthor: |cffc41f3bKhal|r\nVersion: %.1f", version)
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

------------------- Script to manage the addon's main frame events -------------------
BGHframe:RegisterEvent("ADDON_LOADED")
BGHframe:RegisterEvent("PLAYER_ENTERING_WORLD")
BGHframe:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and (...) == addonName then
        AddInterfaceOptions()
        InitSettings()
        print(string.format("|cff00FF98[BGH]|r BattleGroundHealers v%.1f by |cffc41f3bKhal|r", version))
    elseif event == "PLAYER_ENTERING_WORLD" then
        local _, instance = IsInInstance()
        if instance == "pvp" then
            RequestBattlefieldScoreData()
            UpdateCurrentBGplayers()
            UpdateWSSFhealers()
            UpdateCLEUstate()
            self:SetScript("OnUpdate", OnUpdate) 
            CLEUframe:SetScript("OnEvent", CLEUhandler)
            inBG = true
        elseif inBG then
            self:SetScript("OnUpdate",nil)
            CLEUframe:SetScript("OnEvent", nil)
            CLEUframe:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            CLEUframe:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
            CLEUregistered = false
            USSregistered = false
            inBG = false
            playerFaction = false  
            currentBGplayers = {} 
            lastUpdateTime = 0
            ClearHealers(CLEUhealers)
            ClearHealers(WSSFhealers)
        end
    end
end)

------------------------ Slash Commands ------------------------
SLASH_BGH1 = "/bgh"
SlashCmdList["BGH"] = function(msg)
    msg = string.lower(msg);
    local _, _, cmd, args = string.find(msg, '%s?(%w+)%s?(.*)')
    if (not msg or msg == "") then
        ConfigUI()
    elseif cmd == "print" then
        PrintDetectedHealers()
    elseif (cmd == "h2d") then
        if (not args or args == "") then
            print("|cff00FF98[BGH]|r Current BG Scoreboard healing-to-damage tracking ratio: " .. BGHsettings.h2dRatio);
        else
            local value = tonumber(args);
            if (value ~= nil) then
                if (value > 5) then value = 5 end
                if (value < 1) then value = 1 end
                BGHsettings.h2dRatio = value;
                print("|cff00FF98[BGH]|r BG Scoreboard healing-to-damage tracking ratio set to: " .. BGHsettings.h2dRatio);       
            else
                print("|cff00FF98[BGH]|r Value is not a number");
            end
        end
    elseif (cmd == "hth") then
        if (not args or args == "") then
            print("|cff00FF98[BGH]|r Current BG Scoreboard healing tracking threshold: " .. BGHsettings.healingThreshold);
        else
            local value = tonumber(args);
            if (value ~= nil) then
                if (value > 100000) then value = 100000 end
                if (value < 10000) then value = 10000 end
                BGHsettings.healingThreshold = value;
                print("|cff00FF98[BGH]|r BG Scoreboard healing tracking threshold set to: " .. BGHsettings.healingThreshold);       
            else
                print("|cff00FF98[BGH]|r Value is not a number");
            end
        end
    elseif cmd == "debug" then
        if debugMode then 
            debugMode = false
            print("|cff00FF98[BGH]|r Debug mode disabled")
        else 
            debugMode = true
            print("|cff00FF98[BGH]|r Debug mode enabled")
        end
    end
end
_G.SetBGHmark = SetBGHmark