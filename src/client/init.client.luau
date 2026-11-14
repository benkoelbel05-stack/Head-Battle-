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
local LoadingScreen = require(script.LoadingScreen)
local SoundFX = require(script.SoundFX)
local ItemAnimations = require(script.ItemAnimations)
local Settings = require(script.Settings)
local StatsDisplay = require(script.StatsDisplay)
local ImageCache = require(script.ImageCache)

task.spawn(Settings.start) -- Optionen: Standardwerte sofort, gespeicherte Werte vom Server kurz danach
task.spawn(LoadingScreen.start) -- Ladebildschirm zuerst: lädt einmal alle Bilder und Klänge vor
task.spawn(ImageCache.start) -- hält Figuren- und Item-Animationsbilder dauerhaft geladen
PlatformClient.start()
task.spawn(SoundFX.start)
task.spawn(ItemAnimations.start)
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
task.spawn(StatsDisplay.start)
