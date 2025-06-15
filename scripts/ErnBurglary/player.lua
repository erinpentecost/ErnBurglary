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

local lastCellID = nil

-- spottedBy is an actorRecord.id or factionID or actor.id to true.
local spottedByActorRecordID = {}
-- spottedByFactionID is a map of factionID -> list of actors
local spottedByFactionID = {}
-- itemsInCellOwnership is a map of item.id to ownership info.
-- I need to pre-fetch this info because it is stripped after the player
-- picks the item up.
local itemsInCellOwnership = {}
local actorRecordIDtoInstance = {}
local spotted = false
local sneaking = false

local warnCooldownTimer = 0

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

local function anyNPCsAlive(listOfNPCs)
    if listOfNPCs == nil then
        return false
    end
    for _, npcInstance in ipairs(listOfNPCs) do
        if types.Actor.isDead(npcInstance) or types.Actor.isDeathFinished(npcInstance) then
            settings.debugPrint("npc " .. npcInstance.id .. " is dead")
        else
            return true
        end
    end
    return false
end

local function atLeastRank(factionID, rank)
    local selfRank = types.NPC.getFactionRank(self, factionID)
    settings.debugPrint("your rank in " .. factionID .. " is " .. tostring(selfRank))
    if selfRank == nil then
        return false
    elseif (rank == nil) then
        return true
    else
        return selfRank >= rank
    end
end

local function calculateTheft()
    settings.debugPrint("calculateTheft() start for " .. lastCellID)
    -- report a table of ObjectOwner -> value of stolen goods
    local npcThefts = {}
    local factionThefts = {}
    local didTheft = false
    -- check for any new items the player stole
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        local owner = itemsInCellOwnership[item.id]
        if (owner ~= nil) then
            -- this is a new stolen item
            local record = item.type.record(item)
            settings.debugPrint("new owned item: " .. record.name .. "(" .. item.id .. ") by " ..
                                    tostring(owner.recordId) .. "/" .. tostring(owner.factionId) .. "(" ..
                                    tostring(owner.factionRank) .. ")")
            -- don't penalize for individual AND faction ownership because of 
            -- double jeopardy.
            if (owner.recordId ~= nil) and (spottedByActorRecordID[owner.recordId]) and
                anyNPCsAlive({actorRecordIDtoInstance[owner.recordId]}) then
                settings.debugPrint("you were reported for stealing " .. tostring(record.name) .. " from " ..
                                        owner.recordId)
                -- track NPC owners
                if npcThefts[owner.recordId] == nil then
                    npcThefts[owner.recordId] = 0
                end
                if (record ~= nil) and (record.value ~= nil) then
                    npcThefts[owner.recordId] = npcThefts[owner.recordId] + record.value
                    didTheft = true
                end
            elseif (owner.factionId ~= nil) and (atLeastRank(owner.factionId, owner.factionRank) ~= true) then
                settings.debugPrint("you stole from " .. owner.factionId)
                if anyNPCsAlive(spottedByFactionID[owner.factionId]) then
                    -- check if the PC is allowed to have it.
                    settings.debugPrint("you were reported for stealing " .. tostring(record.name) .. " from " ..
                                            owner.factionId)
                    -- track faction owners
                    if factionThefts[owner.factionId] == nil then
                        factionThefts[owner.factionId] = 0
                    end
                    if (record ~= nil) and (record.value ~= nil) then
                        factionThefts[owner.factionId] = factionThefts[owner.factionId] + record.value
                        didTheft = true
                    end
                end
            end
        end
    end
    if (didTheft) then
        core.sendGlobalEvent("ernOnReported", {
            player = self,
            cellID = lastCellID,
            npcThefts = npcThefts,
            factionThefts = factionThefts
        })
    end
    settings.debugPrint("calculateTheft() end")
end

local function cellChanged()
    local firstRun = lastCellID == nil
    settings.debugPrint("cellChanged() start. firstRun="..tostring(firstRun))
    -- first, check for theft.
    if firstRun ~= true then
        calculateTheft()
    end

    -- reset for new cell.
    lastCellID = self.cell.id
    spottedByActorRecordID = {}
    actorRecordIDtoInstance = {}
    spottedByFactionID = {}
    spotted = false
    warnCooldownTimer = 0

    -- add ownership for all items in cell
    core.sendGlobalEvent("ernOnGetAllOwnedItems", {
        player = self,
        cellID = self.cell.id,
        fromSave = firstRun
    })
    settings.debugPrint("cellChanged() end")
end

local function ownershipInfo(data)
    settings.debugPrint("ownershipInfo(" .. data.cellID .. ") start")
    if data.cellID == self.cell.id then
        itemsInCellOwnership = data.itemIDtoOwnership
    end
    settings.debugPrint("ownershipInfo() end")
end

local function onUpdate(dt)
    if lastCellID ~= self.cell.id then
        settings.debugPrint("cell changed from " .. tostring(lastCellID) .. " to " .. self.cell.id)
        -- cell change
        cellChanged()
    end

    warnCooldownTimer = warnCooldownTimer - dt

    for _, actor in ipairs(nearby.actors) do
        -- check for detectiong
        if spottedByActorRecordID[actor.id] == nil then
            local isActive = core.sound.isSayActive(actor)
            if isActive then
                local actorRecord = types.NPC.record(actor)
                if actorRecord ~= nil then
                    spottedByActorRecordID[actor.id] = true
                    spottedByActorRecordID[actorRecord.id] = true
                    actorRecordIDtoInstance[actorRecord.id] = actor
                    settings.debugPrint("added " .. actorRecord.id .. " to spotted map.")
                    -- also track for all factions
                    for _, factionId in pairs(types.NPC.getFactions(actor)) do
                        if spottedByFactionID[factionId] == nil then
                            spottedByFactionID[factionId] = {}
                        end
                        table.insert(spottedByFactionID[factionId], actor)
                        settings.debugPrint(
                            "added " .. actorRecord.id .. " to " .. factionId .. " spotted list. size: " ..
                                #spottedByFactionID[factionId])
                    end
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
end

return {
    eventHandlers = {
        ernShowWantedMessage = showWantedMessage,
        ernShowExpelledMessage = showExpelledMessage,
        ernOwnershipInfo = ownershipInfo
    },
    engineHandlers = {
        onUpdate = onUpdate
    }
}

