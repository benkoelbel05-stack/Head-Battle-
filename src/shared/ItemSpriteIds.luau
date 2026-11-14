--!strict
-- Clay Battle: echte Roblox IMAGE-IDs der PNG-Animationsframes.
-- 0 bedeutet NICHT hochgeladen oder nicht freigegeben. Keine IDs erfinden!
-- Die Datei wird durch EXPORT_ITEM_IDS_FUER_CLAUDE.bat nach Upload erzeugt.
local function blank(): { number }
  return { 0, 0, 0, 0, 0, 0, 0, 0 }
end
return {
  grenade_spin = blank(),
  grenade_explosion = blank(),
  thruster_burst = blank(),
  sword_swing = blank(),
  missile_flight = blank(),
  dash_burst = blank(),
} :: { [string]: { number } }
