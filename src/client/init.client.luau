--!strict
-- Clay Battle – Client-Einstieg
--
-- Ablauf in jedem Bild (vor dem Rendern, in dieser Reihenfolge):
--   1. PlatformClient  Plattformen weiterrechnen (eigene Simulation)
--   2. HeadController  eigenen Kopf bewegen, Fähigkeiten
--   3. CameraController
--   4. ClayAnimator    Knet-Look aller Köpfe

print("[ClayBattle] Client startet")

local PlatformClient = require(script.PlatformClient)
local HeadController = require(script.HeadController)
local CameraController = require(script.CameraController)
local ClayAnimator = require(script.ClayAnimator)
local RoundUI = require(script.RoundUI)
local StartScreen = require(script.StartScreen)
local MainMenu = require(script.MainMenu)
local BackgroundController = require(script.BackgroundController)
local MapSelectUI = require(script.MapSelectUI)
local AbilityBubbles = require(script.AbilityBubbles)
local OceanScene = require(script.OceanScene)
local AssetPreloader = require(script.AssetPreloader)
local SoundFX = require(script.SoundFX)

PlatformClient.start()
task.spawn(AssetPreloader.start) -- Bilder und Musik vorladen (Menü zuerst)
task.spawn(SoundFX.start)
task.spawn(CameraController.start)
task.spawn(BackgroundController.start)
task.spawn(MapSelectUI.start)
task.spawn(AbilityBubbles.start)
task.spawn(OceanScene.start)
task.spawn(ClayAnimator.start)
task.spawn(HeadController.start)
task.spawn(RoundUI.start)
task.spawn(StartScreen.start)
task.spawn(MainMenu.start)
