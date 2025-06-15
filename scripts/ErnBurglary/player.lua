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

local warnCooldown = 5

-- lastCellID will be nil if loading from a save game.
-- otherwise, it will be the cell we just moved from.
local lastCellID = nil
-- spottedByActorID deduplicates calls to onSpotted.
local spottedByActorID = {}
-- spotted is used cases where we were spotted before sneaking
local spotted = false
local sneaking = false
local warnCooldownTimer = 0

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

local function detectionCheck(dt)
    warnCooldownTimer = warnCooldownTimer - dt
    for _, actor in ipairs(nearby.actors) do
        -- check for detectiong
        if spottedByActorID[actor.id] == nil then
            local isActive = core.sound.isSayActive(actor)
            if isActive then
                spottedByActorID[actor.id] = true
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

addInfrequentUpdateCallback("detection", 0.1, detectionCheck)

local function inventoryChangeCheck(dt)
    -- TODO: skip when in shop UI or dialogue
    local newItemsList = {}
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        if itemsInInventory[item.id] == nil then
            table.insert(newItemsList, item)
            settings.debugPrint("found new item: " .. aux_util.deepToString(item,2))
            -- don't re-add the item
            itemsInInventory[item.id] = item
        end
    end
    if #newItemsList > 0 then
        core.sendGlobalEvent(settings.MOD_NAME .. "onNewItem", {
            player = self,
            cellID = self.cell.id,
            itemsList = newItemsList,
        })
    end
end

addInfrequentUpdateCallback("inventory", 0.1, inventoryChangeCheck)

local function onUpdate(dt)
    if lastCellID ~= self.cell.id then
        settings.debugPrint("cell changed from " .. tostring(lastCellID) .. " to " .. self.cell.id)

        if lastCellID ~= nil then
            -- we loaded from a save.
            core.sendGlobalEvent(settings.MOD_NAME .. "onCellExit", {
                player = self,
                cellID = lastCellID
            })
        end
        core.sendGlobalEvent(settings.MOD_NAME .. "onCellEnter", {
            player = self,
            cellID = self.cell.id
        })
        lastCellID = self.cell.id

        -- reset per-cell state
        spottedByActorID = {}
        spotted = false
        warnCooldownTimer = 0
        trackInventory()

        -- don't run other checks this frame.
        -- fewer frame drops this way.
        return
    end

    infrequentUpdate(dt)
end

return {
    eventHandlers = {
        ernShowWantedMessage = showWantedMessage,
        ernShowExpelledMessage = showExpelledMessage
    },
    engineHandlers = {
        onUpdate = onUpdate
    }
}

