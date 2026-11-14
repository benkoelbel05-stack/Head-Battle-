--!strict
-- Verlauf der Kopf-Positionen (letzte 0,6 s) für faire Treffer trotz Verzögerung ("Lag-Ausgleich").
--
-- Ein Spieler sieht die anderen Köpfe immer etwas in der Vergangenheit: Ihre Positionen brauchen
-- eine Weile zu ihm, und sein Angriff braucht eine Weile zurück zum Server. Würde der Server mit den
-- aktuellen Positionen prüfen, gingen Treffer daneben, die auf dem Bildschirm eindeutig sitzen.
-- Deshalb prüft der Server Angriffe von Spielern gegen die Positionen von "damals" (rewindFor).
-- Bots haben keine Verzögerung: für sie wird nicht zurückgespult.

local Workspace = game:GetService("Workspace")

local HeadHistory = {}

type Sample = { t: number, p: Vector3 }

local KEEP = 0.6 -- Sekunden Verlauf
local MAX_REWIND = 0.35 -- höchstens so weit zurück (sonst wäre Ausweichen sinnlos)
local INTERPOLATION = 0.06 -- Roblox zeigt fremde Teile mit etwas Puffer an

local history: { [Model]: { Sample } } = {}

-- Jeden Frame aufrufen
function HeadHistory.record(heads: { [any]: Model })
	local now = Workspace:GetServerTimeNow()
	local present: { [Model]: boolean } = {}
	for _, head in heads do
		local body = head.PrimaryPart
		if body then
			present[head] = true
			local samples = history[head]
			if not samples then
				samples = {}
				history[head] = samples
			end
			table.insert(samples, { t = now, p = body.Position })
			while #samples > 2 and samples[1].t < now - KEEP do
				table.remove(samples, 1)
			end
		end
	end
	for head in history do
		if not present[head] then
			history[head] = nil
		end
	end
end

-- Position eines Kopfes zu einem früheren Zeitpunkt (Server-Zeit), zwischen zwei Messungen überblendet
function HeadHistory.positionAt(head: Model, time: number): Vector3?
	local body = head.PrimaryPart
	local samples = history[head]
	if not body then
		return nil
	end
	if not samples or #samples == 0 or time >= samples[#samples].t then
		return body.Position
	end
	if time <= samples[1].t then
		return samples[1].p
	end
	for i = #samples - 1, 1, -1 do
		local a, b = samples[i], samples[i + 1]
		if a.t <= time then
			local alpha = if b.t > a.t then (time - a.t) / (b.t - a.t) else 1
			return a.p:Lerp(b.p, alpha)
		end
	end
	return body.Position
end

-- Wie weit für die Angriffe dieses Teilnehmers zurückgespult wird (Sekunden)
function HeadHistory.rewindFor(participant: Player | string): number
	if typeof(participant) == "string" then
		return 0
	end
	local ok, ping = pcall(function()
		return (participant :: Player):GetNetworkPing() -- Hin- und Rückweg in Sekunden
	end)
	local roundTrip = if ok and typeof(ping) == "number" then ping else 0.1
	return math.clamp(roundTrip + INTERPOLATION, 0, MAX_REWIND)
end

-- Bequem: alle Köpfe mit ihrer Position aus Sicht dieses Angreifers
function HeadHistory.positionsFor(attacker: Player | string, heads: { [any]: Model }): { [Model]: Vector3 }
	local time = Workspace:GetServerTimeNow() - HeadHistory.rewindFor(attacker)
	local positions: { [Model]: Vector3 } = {}
	for _, head in heads do
		local position = HeadHistory.positionAt(head, time)
		if position then
			positions[head] = position
		end
	end
	return positions
end

return HeadHistory
