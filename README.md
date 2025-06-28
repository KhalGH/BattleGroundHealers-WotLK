# BattleGroundHealers
**BattleGroundHealers** is a World of Warcraft addon for **Wrath of the Lich King (WotLK) 3.3.5a**  

## Features  
- Marks BG healer nameplates with a configurable icon.  
- Supports two detection methods that can work simultaneously: <br>
  ▸ Combat Log    : Detection based on the spells cast and auras applied. <br>
&nbsp; &nbsp; &nbsp; &nbsp;  &nbsp; * Includes optional automatic Combat Log fix. (recommend disabling if using another CLog fix addon) <br>
  ▸ BG Scoreboard : Detection based on the ratio between healing and damage done. <br>
&nbsp; &nbsp; &nbsp; &nbsp;  &nbsp; * A unit is considered a healer if: (*healing > h2d * damage* &nbsp; & &nbsp; *healing > hth*).
- Allows printing the list of detected healers to personal or public chat channels.
- Implemented callback to provide healer detection data to [BattlegroundTargets](https://github.com/KhalGH/BattlegroundTargets-WotLK).

<p align="center">
  <img src="https://raw.githubusercontent.com/KhalGH/BattleGroundHealers-WotLK/refs/heads/assets/assets/BGHicon200p.png" 
       alt="ItemLevel UI Preview" width="15%">
</p>
<p align="center">
  <img src="https://raw.githubusercontent.com/KhalGH/BattleGroundHealers-WotLK/refs/heads/assets/assets/BattleGroundHealersUI.jpg" 
       alt="ItemLevel UI Preview" width="93%">
</p>

## Chat Commands  
- **`/bgh`** &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; → Opens the configuration panel.  
- **`/bgh print`** &nbsp; &nbsp; → Prints the list of detected healers to the selected channel.
- **`/bgh h2d <#>`** → Modifies healing-to-damage ratio threshold for BG Scoreboard detection
- **`/bgh hth <#>`** → Modifies healing threshold for BG Scoreboard detection    

## Installation  
1. [Download](https://github.com/KhalGH/BattleGroundHealers-WotLK/releases/download/v1.3/BattleGroundHealers-v1.3.zip) the addon
2. Extract the **BattleGroundHealers** folder into `World of Warcraft/Interface/AddOns/`.  
3. Restart the game and enable the addon.  

## Information  
- **Addon Version:** 1.3  
- **Game Version:** 3.3.5a (WotLK)  
- **Author:** Khal  
