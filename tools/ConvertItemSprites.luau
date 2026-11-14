-- Wandelt die Decal-IDs der Item-Animationen (je 8 Bilder) in Image-IDs um.
-- Benutzung: in Roblox Studio (angemeldet mit dem Konto, dem die Bilder gehören) den ganzen Inhalt in
-- die Befehlsleiste kopieren (Ansicht -> Befehlsleiste), Enter. Im Output stehen danach 6 Zeilen
-- "name = { ... }," – die an Claude schicken (sie gehören nach src/shared/ItemSpriteIds.luau).
-- "FEHLER" = Bild ist noch in Prüfung bei Roblox (ein paar Minuten warten und nochmal ausführen).

local InsertService = game:GetService("InsertService")
local SEQUENCES = {
	{ "dash_burst", { 76782106144330, 134700389998243, 85706260699160, 132748892379271, 95192481564712, 113716852642204, 100891205679808, 81847156268903 } },
	{ "grenade_explosion", { 77386893725652, 131591773019718, 118580286649704, 118270085158061, 116443174452721, 89710984533877, 92005348229298, 92459816781478 } },
	{ "grenade_spin", { 113270869035697, 82745205645439, 89146465373904, 111880851014672, 105978771059524, 123964147665579, 91133390629903, 119238212675004 } },
	{ "missile_flight", { 130619900964205, 95341611840159, 125549468210185, 140467890300206, 72444101148792, 72498566853046, 73477041631532, 97573828240084 } },
	{ "sword_swing", { 102744252402533, 105995708642530, 123831290805624, 104367357126418, 90373932925532, 122162479005986, 100532423899265, 77347777665629 } },
	{ "thruster_burst", { 112732634558189, 129279730946723, 99470365332407, 91153873772087, 117711758120997, 112977946871268, 79688086646933, 117940541903999 } },
}
for _, entry in SEQUENCES do
	local name, ids = entry[1], entry[2]
	local out = {}
	for _, id in ids do
		local ok, result = pcall(function()
			return InsertService:LoadAsset(id)
		end)
		if ok then
			local decal = result:FindFirstChildWhichIsA("Decal", true)
			table.insert(out, decal and string.match(decal.Texture, "%d+") or "KEINE")
			result:Destroy()
		else
			table.insert(out, "FEHLER")
		end
		task.wait(0.05)
	end
	print(name .. " = { " .. table.concat(out, ", ") .. " },")
end
