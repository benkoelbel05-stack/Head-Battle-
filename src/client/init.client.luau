--!strict
-- Head Battle – Client-Einstieg

print("[HeadBattle] Client startet")

local HeadController = require(script.HeadController)
local CameraController = require(script.CameraController)
local ClayAnimator = require(script.ClayAnimator)

task.spawn(CameraController.start)
task.spawn(ClayAnimator.start)
task.spawn(HeadController.start)
