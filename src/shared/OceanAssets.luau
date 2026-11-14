--!strict
-- Wolken für den Meer-Hintergrund (Roblox-IMAGE-IDs). 0 = noch keine Image-ID: die Wolke fehlt dann.
-- Die hochgeladenen IDs sind Decal-IDs und müssen erst umgewandelt werden (tools/ConvertArenaDecals.luau):
--   wolken_links 130289073994565, wolken_rechts 126053989467059, wolken_fern_gesamt 75855415667887,
--   wolke_klein_01..08: 73531826914109, 114695650889992, 79818936500332, 93198978993068,
--                       114974578305828, 103860179237170, 103403569038967, 131678906702333
--   ocean_water_base 128025805325965, ocean_water_shimmer 116982427595679

return {
	clouds_left = 0, -- wolken_links
	clouds_right = 0, -- wolken_rechts
	clouds_distant = 0, -- wolken_fern_gesamt
	small = { 0, 0, 0, 0, 0, 0, 0, 0 }, -- wolke_klein_01 .. 08
	water_base = 0, -- ocean_water_base: Wasser-Textur, zieht langsam
	water_shimmer = 0, -- ocean_water_shimmer: Glanz darüber, zieht gegenläufig und schimmert
}
