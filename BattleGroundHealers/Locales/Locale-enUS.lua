
BattleGroundHealers_Localization = {
	["Healer Detection Methods"] = true,
	["Track Healers via Combat Log"] = true,
	["Combat Log tracking"] = true,
	["Automatic Combat Log Fix"] = true,
	["Track Healers via BG Scoreboard"] = true,
	["BG Scoreboard tracking"] = true,
	["Print Healers"] = true,
	["Print failed (not in BG)"] = true,
	["Wait %.1f s to print again."] = true,
	["Channel:"] = true,
	["Self"] = true,
	["Warsong Gulch"] = true,
	["Arathi Basin"] = true,
	["Alterac Valley"] = true,
	["Eye of the Storm"] = true,
	["Strand of the Ancients"] = true,
	["Isle of Conquest"] = true,
	["Healers detected in %s:"] = true,
	["Alliance"] = true,
	["Horde"] = true,
	["Icon Display Settings"] = true,
	["Icon Size"] = true,
	["Icon Style"] = true,
	["Anchor"] = true,
	["X offset"] = true,
	["Y offset"] = true,
	["Invert Icon Color"] = true,
	["Enable Test Mode"] = true,
	["Test mode"] = true,
	["Enabled"] = true,
	["Disabled"] = true,
	["Mark Target"] = true,
	["Reset"] = true,
	["Are you sure you want to reset all settings to default?"] = true,
	["Settings reset to default values."] = true,
	["Yes"] = true,
	["No"] = true,
	["TidyPlates detected, anchors adjusted."] = true,
	["_VirtualPlates detected, anchors adjusted."] = true,
	["%s %s has left the BG, removed from healers list."] = true,
	["Current BG Scoreboard healing-to-damage tracking ratio:"] = true,
	["BG Scoreboard healing-to-damage tracking ratio set to:"] = true,
	["Current BG Scoreboard healing tracking threshold:"] = true,
	["BG Scoreboard healing tracking threshold set to:"] = true,
	["Value is not a number"] = true,
	["Marks BG healer nameplates with a configurable icon.\nSupports two detection methods that can work simultaneously.\n\nAuthor: |cffc41f3bKhal|r\nVersion: %s"] = true,
}

function BattleGroundHealers_Localization:CreateLocaleTable(t)
	for k,v in pairs(t) do
		self[k] = (v == true and k) or v
	end
end

BattleGroundHealers_Localization:CreateLocaleTable(BattleGroundHealers_Localization)