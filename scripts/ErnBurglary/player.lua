--[[
ErnBurglary for OpenMW.
Copyright (C) 2025 Erin Pentecost

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
]] local interfaces = require("openmw.interfaces")
local settings = require("scripts.ErnBurglary.settings")
local say = require("scripts.ErnBurglary.say")
local types = require("openmw.types")
local nearby = require("openmw.nearby")
local core = require("openmw.core")
local self = require("openmw.self")
local localization = core.l10n(settings.MOD_NAME)
local ui = require('openmw.ui')
local aux_util = require('openmw_aux.util')

interfaces.Settings.registerPage {
    key = settings.MOD_NAME,
    l10n = settings.MOD_NAME,
    name = "name",
    description = "description"
}

-- warnCooldown stops us from spamming people
local warnCooldown = 15

-- lastCellID will be nil if loading from a save game.
-- otherwise, it will be the cell we just moved from.
local lastCellID = nil
-- spottedByActorID deduplicates calls to onSpotted.
local spottedByActorID = {}
-- spotted is used cases where we were spotted before sneaking
local spotted = false
local sneaking = false
local warnCooldownTimer = 0

local noWitnessesMessageReceivedCooldownTimer = 0
local noWitnessesMessageReceived = false

-- forgiveNewItems is set to true when we enter a barter window.
-- it lets us know that we shouldn't count the next batch of new items
-- as stolen.
local forgiveNewItems = false

-- itemsInInventory is used to track changes in the
-- player's inventory.
-- it's a map of item instance id -> instance.
local itemsInInventory = {}
local function trackInventory()
    itemsInInventory = {}
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        itemsInInventory[item.id] = item
    end
end
trackInventory()

local function showWantedMessage(data)
    settings.debugPrint("showWantedMessage")
    ui.showMessage(localization("showWantedMessage", {
        value = data.value
    }))
end

local function showExpelledMessage(data)
    settings.debugPrint("showExpelledMessage")
    local faction = core.factions.records[data.faction]
    ui.showMessage(localization("showExpelledMessage", {
        factionName = data.faction.name
    }))
end

local function registerHandlers()
    local sneakGroups = {"sneakforward", "sneakleft", "sneakright", "sneakback"}
    for _, group in ipairs(sneakGroups) do
        interfaces.AnimationController.addTextKeyHandler(group, function(group, key)
            if (sneaking == false) and spotted and (warnCooldownTimer <= 0) then
                -- just started sneaking, but was spotted earlier.
                ui.showMessage(localization("showWarningMessage", {}))
                warnCooldownTimer = warnCooldown
            end
            sneaking = true
        end)
    end

    local nonSneakGroups = {"walkforward", "walkleft", "walkright", "walkback", "runforward", "runleft", "runright",
                            "runback"}
    for _, group in ipairs(nonSneakGroups) do
        interfaces.AnimationController.addTextKeyHandler(group, function(group, key)
            sneaking = false
        end)
    end
end

registerHandlers()

local function showNoWitnessesMessage(data)
    if spotted then
        noWitnessesMessageReceived = true
    end
end

local infrequentMap = {}
local function addInfrequentUpdateCallback(id, minDelta, callback)
    infrequentMap[id] = {
        sum = math.random(0, minDelta),
        threshold = minDelta,
        callback = callback
    }
end
local function infrequentUpdate(dt)
    for k, v in pairs(infrequentMap) do
        infrequentMap[k].sum = v.sum + dt
        if infrequentMap[k].sum > v.threshold then
            infrequentMap[k].sum = infrequentMap[k].sum - v.threshold
            v.callback(v.threshold)
        end
    end
end

local function allClear(dt)
    noWitnessesMessageReceivedCooldownTimer = noWitnessesMessageReceivedCooldownTimer - dt
    if spotted and noWitnessesMessageReceived then
        settings.debugPrint("showNoWitnessesMessage")
        noWitnessesMessageReceived = false
        spotted = false
        spottedByActorID = {}
        if noWitnessesMessageReceivedCooldownTimer <= 0 then
            ui.showMessage(localization("showNoWitnessesMessage", {}))
            noWitnessesMessageReceivedCooldownTimer = 2
        end
    end
end

local function isTalking(actor)
    return (core.sound.isSayActive(actor)) and (say.idle(actor) ~= true)
end

local function isClose(actor)
    local len = (self.position - actor.position):length()
    --settings.debugPrint("len to "..actor.recordId..": "..tostring(len))
    return len < 200
end

local function detectionCheck(dt)
    allClear(dt)

    warnCooldownTimer = warnCooldownTimer - dt

    -- find out which NPC is talking
    for _, actor in ipairs(nearby.actors) do
        -- check for detection
        if spottedByActorID[actor.id] == nil then
            if isTalking(actor) and isClose(actor) then
                spottedByActorID[actor.id] = true
                settings.debugPrint("sending spotted by event for " .. actor.recordId)
                core.sendGlobalEvent(settings.MOD_NAME .. "onSpotted", {
                    player = self,
                    npc = actor,
                    cellID = self.cell.id
                })
                spotted = true
                -- Send notice if sneaking.
                if sneaking and (warnCooldownTimer <= 0) then
                    warnCooldownTimer = warnCooldown
                    local npcName = types.NPC.record(actor).name
                    ui.showMessage(localization("showSpottedMessage", {
                        actorName = npcName
                    }))
                end
            end
        end
    end
end

addInfrequentUpdateCallback("detection", 0.11, detectionCheck)

local function inventoryChangeCheck(dt)
    local newItemsList = {}
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        if itemsInInventory[item.id] == nil then
            table.insert(newItemsList, item)
            settings.debugPrint("found new item: " .. aux_util.deepToString(item, 2))
            -- don't re-add the item
            itemsInInventory[item.id] = item
        end
    end
    if forgiveNewItems then
        settings.debugPrint("forgave new items")
        forgiveNewItems = false
        return
    end
    if #newItemsList > 0 then
        core.sendGlobalEvent(settings.MOD_NAME .. "onNewItem", {
            player = self,
            cellID = self.cell.id,
            itemsList = newItemsList
        })
    end
end

addInfrequentUpdateCallback("inventory", 0.1, inventoryChangeCheck)

local function updateSpottedSpell()
    if spotted then
        types.Actor.activeSpells(self):add({
            id = "ernburglary_spotted",
            effects = {0},
            ignoreSpellAbsorption = true,
            ignoreReflect = true,
        })
    else
        for _, spell in pairs(types.Actor.activeSpells(self)) do
            if spell.id == "ernburglary_spotted" then
                types.Actor.activeSpells(self):remove(spell.activeSpellId)
            end
        end
    end
end

addInfrequentUpdateCallback("spottedSpell", 0.8, updateSpottedSpell)

local function onUpdate(dt)
    -- this is not called when the game is paused.
    if lastCellID ~= self.cell.id then
        settings.debugPrint("cell changed from " .. tostring(lastCellID) .. " to " .. self.cell.id)

        core.sendGlobalEvent(settings.MOD_NAME .. "onCellChange", {
            player = self,
            lastCellID = lastCellID,
            newCellID = self.cell.id
        })

        lastCellID = self.cell.id

        -- reset per-cell state
        spottedByActorID = {}
        spotted = false
        warnCooldownTimer = 0
        noWitnessesMessageReceivedCooldownTimer = 0
        noWitnessesMessageReceived = false
        trackInventory()

        -- don't run other checks this frame.
        -- fewer frame drops this way.
        return
    end

    infrequentUpdate(dt)
end

local function UiModeChanged(data)
    if data.oldMode == "Dialogue" then
        settings.debugPrint("was in dialogue")
        forgiveNewItems = true
    end
end

return {
    eventHandlers = {
        [settings.MOD_NAME .. "showWantedMessage"] = showWantedMessage,
        [settings.MOD_NAME .. "showExpelledMessage"] = showExpelledMessage,
        [settings.MOD_NAME .. "showNoWitnessesMessage"] = showNoWitnessesMessage,
        UiModeChanged = UiModeChanged
    },
    engineHandlers = {
        onUpdate = onUpdate
    }
}

