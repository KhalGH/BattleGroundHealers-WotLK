
local BGH = select(2, ...)

BGH.Locale = {}
local L = BGH.Locale

L["Warsong Gulch"] = true
L["Arathi Basin"] = true
L["Alterac Valley"] = true
L["Eye of the Storm"] = true
L["Strand of the Ancients"] = true
L["Isle of Conquest"] = true
L["Alliance"] = true
L["Horde"] = true
L["has left the battleground."] = true
L["Print failed (not in BG)"] = true
L["Wait %.1f s to print again."] = true
L["Are you sure you want to reset all settings to default?"] = true
L["Settings reset to default values."] = true
L["Yes"] = true
L["No"] = true
L["Current BG Scoreboard healing-to-damage tracking ratio:"] = true
L["BG Scoreboard healing-to-damage tracking ratio set to:"] = true
L["Current BG Scoreboard healing tracking threshold:"] = true
L["BG Scoreboard healing tracking threshold set to:"] = true
L["Value is not a number"] = true
L["Marks BG healer nameplates with a configurable icon.\nSupports two detection methods that can work simultaneously.\n\nAuthor: |cffc41f3bKhal|r\nVersion: %s"] = true

L["Healer Detection Methods"] = true
L["Track Healers via Combat Log"] = true
L["Automatic Combat Log Fix"] = true
L["Track Healers via BG Scoreboard"] = true
L["Print Healers"] = true
L["Channel:"] = true
L["Icon Display Settings"] = true
L["Icon Size"] = true
L["Icon Style"] = true
L["Anchor"] = true
L["X offset"] = true
L["Y offset"] = true
L["Invert Icon Color"] = true
L["Enable Test Mode"] = true
L["Test mode"] = true
L["Enabled"] = true
L["Disabled"] = true
L["Mark Target"] = true
L["Reset"] = true

for k, v in pairs(L) do
    if v == true then
        L[k] = k
    end
end
