--!strict
-- Wolken und Wasser für den Meer-Hintergrund (Roblox-IMAGE-IDs). 0 = noch keine Image-ID: fehlt dann.
-- Hochgeladen wurden Decal-IDs, umgewandelt mit tools/ConvertArenaDecals.luau (Decal-IDs zur Info):
--   wolken_links 130289073994565, wolken_rechts 126053989467059, wolken_fern_gesamt 75855415667887,
--   wolke_klein_01..08: 73531826914109, 114695650889992, 79818936500332, 93198978993068,
--                       114974578305828, 103860179237170, 103403569038967, 131678906702333
--   ocean_water_base 128025805325965, ocean_water_shimmer 116982427595679

return {
	clouds_left = 82354416602690, -- wolken_links
	clouds_right = 76872067148584, -- wolken_rechts
	clouds_distant = 122542094282066, -- wolken_fern_gesamt
	small = { -- wolke_klein_01 .. 08
		134609706909693,
		130696040835257,
		95456819286112,
		120860966027913,
		98123925647499,
		118994056640091,
		97115192643654,
		106373777785545,
	},
	water_base = 0, -- ocean_water_base: Wasser-Textur, zieht langsam
	water_shimmer = 0, -- ocean_water_shimmer: Glanz darüber, zieht gegenläufig und schimmert
}
