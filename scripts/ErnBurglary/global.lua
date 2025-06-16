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
]] local settings = require("scripts.ErnBurglary.settings")
local common = require("scripts.ErnBurglary.common")
local world = require('openmw.world')
local types = require("openmw.types")
local core = require("openmw.core")
local async = require('openmw.async')
local aux_util = require('openmw_aux.util')
local storage = require('openmw.storage')

if require("openmw.core").API_REVISION < 62 then
    error("OpenMW 0.49 or newer is required!")
end

-- Init settings first to init storage which is used everywhere.
settings.initSettings()

local persistedState = {}

local function saveState()
    -- TODO: re-enable
    --return persistedState
end

local function loadState(saved)
    -- TODO: re-enable
    --persistedState = saved
end

local function thieveryKey(cellID, playerID)
    if (cellID == nil) or (cellID == "") then
        error("thieveryKey() bad cellID")
    end
    if (playerID == nil) or (playerID == "") then
        error("thieveryKey() bad playerID")
    end
    return "tk_" .. tostring(playerID) .. "_" .. tostring(cellID)
end

local function newCellState(cellID, playerID)
    local playerKey = playerID
    if playerID.id ~= nil then
        playerKey = playerID.id
    end
    return {
        cellID = cellID,
        playerID = playerKey,
        -- itemIDtoOwnership is map of item instance id to actor id.
        itemIDtoOwnership = {},
        -- spottedByActorId is a map of actor id -> true
        spottedByActorId = {},
        -- newItems is a map of new items the player picked up while in the cell.
        -- item id -> item instance
        newItems = {}
    }
end

local function getCellState(cellID, playerID)
    local playerKey = playerID
    if playerID.id ~= nil then
        playerKey = playerID.id
    end
    local cellState = persistedState[thieveryKey(cellID, playerKey)]
    --settings.debugPrint("getCellState(...) for player: " .. tostring(playerID) .. ", cell: " .. tostring(cellID))
    -- settings.debugPrint("getCellState(" .. tostring(cellID) .. ", " .. tostring(playerID) .. "): " ..
    --                        aux_util.deepToString(cellState, 3))
    if cellState ~= nil then
        return cellState
    end
    return newCellState(cellID, playerKey)
end

local function saveCellState(cellState)
    --settings.debugPrint("saveCellState(...) for player: " .. tostring(cellState.playerID) .. ", cell: " ..
    --                        tostring(cellState.cellID))
    -- settings.debugPrint("saveCellState(" .. aux_util.deepToString(cellState, 3) .. ")")
    persistedState[thieveryKey(cellState.cellID, cellState.playerID)] = cellState
end

local function clearCellState(cellState)
    settings.debugPrint("clearCellState(...) for player: " .. tostring(cellState.playerID) .. ", cell: " .. tostring(cellState.cellID))
    persistedState[thieveryKey(cellState.cellID, cellState.playerID)] = newCellState(cellState.cellID, cellState.playerID)
end

-- trackOwnedItems resets state.itemIDtoOwnership.
local function trackOwnedItems(cellID, playerID)
    settings.debugPrint("trackOwnedItems(" .. tostring(cellID) .. ") start")

    local cell = world.getCellById(cellID)
    if cell == nil then
        error("bad cell " .. cellID)
        return
    end
    settings.debugPrint("Finding owned items in " .. cell.name)

    local cellState = getCellState(cellID, playerID)
    -- reset to empty.
    cellState.itemIDtoOwnership = {}

    -- Save ownership state for loose items and actor inventories.
    for _, item in ipairs(cell:getAll()) do
        if types.Item.objectIsInstance(item) then
            cellState.itemIDtoOwnership[item.id] = common.serializeOwner(item.owner)
        elseif types.NPC.objectIsInstance(item) then
            local backupOwner = {recordId = item.recordId}
            for k, v in pairs(common.getInventoryOwnership(types.NPC.inventory(item), backupOwner)) do
                if v == nil then
                    -- Assume owner is the holder if not explicit.
                    cellState.itemIDtoOwnership[k] = {
                        recordId=item.recordId,
                    }
                else
                    cellState.itemIDtoOwnership[k] = v
                end
            end
        -- could do containers here, but they may not be resolved yet.
        end
    end

    saveCellState(cellState)

    settings.debugPrint("trackOwnedItems(" .. tostring(cellID) .. ") end")
end

local function inferAreaOwner(cellID, playerID)
    local cell = world.getCellById(cellID)
    if cell.isExterior then
        return nil
    end

    local highestCount = 0
    local bestMatch = nil

    local ownerToCount = {}
    local cellState = getCellState(cellID, playerID)
    for _, owner in pairs(cellState.itemIDtoOwnership) do
        local key = common.ownerToString(owner)
        if ownerToCount[key] == nil then
            ownerToCount[key] = 0
        end
        ownerToCount[key] = ownerToCount[key] + 1
        if ownerToCount[key] > highestCount then
            highestCount = ownerToCount[key]
            bestMatch = owner
        end
    end
    return bestMatch
end

-- Save ownership data for containers when they are activated.
-- Adds elements to state.itemIDtoOwnership.
local function onActivate(object, actor)
    -- I can't get the owner of a container.

    if types.Player.objectIsInstance(actor) and types.Container.objectIsInstance(object) then
        settings.debugPrint("onActivate(" .. tostring(object.id) .. ", player)")
        local inventory = types.Container.inventory(object)
        if inventory:isResolved() ~= true then
            inventory:resolve()
            settings.debugPrint("resolved container")
            inventory = types.Container.inventory(object)
        end
        
        -- Objects in containers don't have owners.
        local owner = nil
        if common.serializeOwner(object.owner) ~= nil then
            -- This doesn't work (yet?), but would be great.
            owner = common.serializeOwner(object.owner)
            settings.debugPrint("got container owner: " .. aux_util.deepToString(owner))
        elseif settings.inferOwnership() then
            -- Gross workaround to guess the owner.
            owner = inferAreaOwner(actor.cell.id, actor.id)
            settings.debugPrint("inferred area owner: " .. aux_util.deepToString(owner))
        end

        -- track items in the container
        local cellState = getCellState(actor.cell.id, actor.id)
        for k, v in pairs(common.getInventoryOwnership(inventory, owner)) do
            if v ~= nil then
                cellState.itemIDtoOwnership[k] = v
                settings.debugPrint("tracked item in container: " .. k .. " has owner " .. aux_util.deepToString(owner))
            else
                settings.debugPrint("tracked item in container: " .. k .. " has no owner")
            end
        end
        saveCellState(cellState)
    end
end

-- onSpotted is called when a player is spotted by an NPC.
-- params:
-- player
-- cellID
-- npc
local function onSpotted(data)
    settings.debugPrint("onSpotted(" .. aux_util.deepToString(data) .. ")")
    local cellState = getCellState(data.cellID, data.player.id)
    cellState.spottedByActorId[data.npc.id] = true
    saveCellState(cellState)
end

-- params:
-- player
-- cellID
local function onCellEnter(data)
    settings.debugPrint("onCellEnter(" .. aux_util.deepToString(data) .. ")")

    -- clean up new cell
    local cellState = getCellState(data.cellID, data.player.id)
    clearCellState(cellState)

    -- TODO: I'm going crazy
    cellState = getCellState(data.cellID, data.player.id)
    for id, val in pairs(cellState.spottedByActorId) do
        settings.debugPrint("failed to clean "..id..": " .. aux_util.deepToString(val) .. ")")
    end

    -- When we enter a cell, we need to persist ownership data
    -- for all items. We have to do this because ownership data
    -- is lost when the item is placed in the player's inventory.

    -- This is actually totally broken because the item could legitimately
    -- transfer ownership to the player when they buy something.
    -- I have to detect when when the player is in the shop dialogue,
    -- and not count those items.

    trackOwnedItems(data.cellID, data.player.id)
end

local function npcIDsToInstances(cellID, npcIDMap)
    local cell = world.getCellById(cellID)
    if cell == nil then
        error("bad cell " .. tostring(cellID))
    end

    local out = {}
    for _, npc in pairs(cell:getAll(types.NPC)) do
        if npcIDMap[npc.id] ~= true then
            --settings.debugPrint("found NPC instance " .. npc.id .. ": " .. aux_util.deepToString(npc))
            out[npc.id] = npc
        end
    end
    return out
end

local function filterDeadNPCs(npcIDtoInstanceMap)
    local out = {}
    for id, npcInstance in pairs(npcIDtoInstanceMap) do
        if types.Actor.isDead(npcInstance) or types.Actor.isDeathFinished(npcInstance) then
            -- settings.debugPrint("npc " .. npcInstance.id .. " is dead")
        else
            -- settings.debugPrint("npc " .. npcInstance.id .. " is NOT dead")
            out[id] = npcInstance
        end
    end
    return out
end

local function guardsExist(npcIDtoInstanceMap)
    for id, npcInstance in pairs(npcIDtoInstanceMap) do
        local record = types.NPC.record(npcInstance)
        if string.lower(record.class) == "guard" then
            return true
        end
    end
    return false
end

local function factionsOfNPCs(npcIDtoInstanceMap)
    local out = {}
    for _, npcInstance in pairs(npcIDtoInstanceMap) do
        for _, faction in ipairs(types.NPC.getFactions(npcInstance)) do
            out[faction] = true
            -- settings.debugPrint("added faction " .. faction)
        end
    end
    return out
end

local function atLeastRank(npc, factionID, rank)
    local inFaction = false
    for _, foundID in pairs(types.NPC.getFactions(npc)) do
        if foundID == factionID then
            inFaction = true
            break
        end
    end
    if inFaction == false then
        settings.debugPrint("your rank in " .. factionID .. " is <not a member>")
        return false
    end

    local selfRank = types.NPC.getFactionRank(npc, factionID)
    settings.debugPrint("your rank in " .. factionID .. " is " .. tostring(selfRank))
    if selfRank == nil then
        return false
    elseif (rank == nil) then
        return true
    else
        return selfRank >= rank
    end
end

local function handleTheftSeenByGuard(player, value)
    settings.debugPrint("handleTheftSeenByGuard(player, " .. value .. ")")
    local currentCrime = types.Player.getCrimeLevel(player)
    types.Player.setCrimeLevel(player, currentCrime + value)
end

local function handleTheftFromNPC(player, npc, value)
    settings.debugPrint("handleTheftFromNPC(player, " .. npc.id .. ", " .. value .. ")")
    -- npc is an instance.
    -- always reduce disposition. 2gp == 1 disposition
    local startDisposition = types.NPC.getBaseDisposition(npc, player)

    local dispoPenalty = math.min(startDisposition, value)
    types.NPC.modifyBaseDisposition(npc, player, -1 * dispoPenalty)

    local bountyPenalty = value - dispoPenalty

    -- we have leftover penalty.
    -- for now, just increase crime level
    local currentCrime = types.Player.getCrimeLevel(player)
    types.Player.setCrimeLevel(player, currentCrime + bountyPenalty)

    print("Theft from " .. npc.recordId .. " dropped disposition by " .. dispoPenalty .. " from " .. startDisposition ..
              ", and increased bounty by " .. bountyPenalty .. ".")
end

local function handleTheftFromFaction(player, faction, value)
    settings.debugPrint("handleTheftFromFaction(player, " .. faction .. ", " .. value .. ")")
    local startReputation = types.NPC.getFactionReputation(player, faction)

    local reputationPenalty = math.min(startReputation, value)
    types.NPC.modifyFactionReputation(player, faction, -1 * reputationPenalty)

    local bountyPenalty = value - reputationPenalty

    local currentCrime = types.Player.getCrimeLevel(player)
    types.Player.setCrimeLevel(player, currentCrime + bountyPenalty)

    local expelled = false
    if bountyPenalty > 0 then
        for _, playerFaction in ipairs(types.NPC.getFactions(player)) do
            if playerFaction == faction then
                types.NPC.expel(player, playerFaction)
                player:sendEvent(settings.MOD_NAME .. "showExpelledMessage", {
                    faction = faction
                })
                expelled = true
            end
        end
    end

    print("Theft from " .. faction .. " dropped reputation by " .. reputationPenalty .. " from " .. startReputation ..
              ", and increased bounty by " .. bountyPenalty .. ". Expelled: " .. tostring(expelled))
end

-- params:
-- player
-- cellID
local function onCellExit(data)
    settings.debugPrint("onCellExit(" .. aux_util.deepToString(data) .. ")")
    -- This is where the magic happens, when we resolve which items have
    -- been stolen, and from whom.
    local cellState = getCellState(data.cellID, data.player.id)

    -- list of living actors that spotted the player.
    local spottedByActorInstance = filterDeadNPCs(npcIDsToInstances(data.cellID, cellState.spottedByActorId))
    local spottedByFactionID = factionsOfNPCs(spottedByActorInstance)
    -- if guards spotted you, they will always report it.
    local spottedByGuards = guardsExist(spottedByActorInstance)
    settings.debugPrint("spotted by guards")

    local npcRecordToInstance = {}
    for _, instance in pairs(spottedByActorInstance) do
        npcRecordToInstance[instance.recordId] = instance
        settings.debugPrint("npcRecordToInstance[" .. instance.recordId .. "] = " .. aux_util.deepToString(instance))
    end

    local totalTheftValue = 0

    -- indexed by npc instance id
    local npcOwnerTheftValue = {}
    -- indexed by faction id
    local factionOwnerTheftValue = {}

    -- build up value of all stolen goods
    for newItemID, newItem in pairs(cellState.newItems) do
        if newItem == nil then
            error("newItem is nil for id " .. tostring(newItemID))
        end
        if (newItem.type == nil) then
            error("newItem is bad for id " .. tostring(newItemID) .. ": " .. aux_util.deepToString(newItem, 2))
        end
        -- This is the non-deprecated way to get an object record:
        -- local objectRecord = object.type.records[object.recordId]
        local itemRecord = newItem.type.records[newItem.recordId]
        if (itemRecord == nil) then
            error("failed to get valid record for item: " .. aux_util.deepToString(newItem, 2))
        end
        local value = itemRecord.value
        if value == nil then
            error("value for " .. itemRecord.name .. " is nil")
        end

        local owner = cellState.itemIDtoOwnership[newItem.id]

        if (owner == nil) then
            -- the item is not owned.
        elseif (owner.recordId ~= nil) then
            settings.debugPrint("assessing new item: " .. itemRecord.name .. "(" .. newItem.id .. ") owned by " ..
                                tostring(owner.recordId) .. "/" .. tostring(owner.factionId) .. "(" ..
                                tostring(owner.factionRank) .. "), gp value: " .. value)

            -- the item is owned by an individual.
            -- if that individual is alive, they will report.
            -- instance can be nil if the actor is dead.
            local instance = npcRecordToInstance[owner.recordId]
            if (instance == nil) and spottedByGuards then
                settings.debugPrint("owner is dead, but spotted by guards")
                handleTheftSeenByGuard(data.player, value)
            elseif (spottedByActorInstance[instance.id]) then
                settings.debugPrint("you were spotted taking " .. itemRecord.name)
                totalTheftValue = totalTheftValue + value
                if npcOwnerTheftValue[instance.id] == nil then
                    npcOwnerTheftValue[instance.id] = 0
                end
                npcOwnerTheftValue[instance.id] = npcOwnerTheftValue[instance.id] + value
            end
        elseif (owner.factionId ~= nil) and (atLeastRank(data.player, owner.factionId, owner.factionRank) == false) then
            settings.debugPrint("assessing new item: " .. itemRecord.name .. "(" .. newItem.id .. ") owned by " ..
                                tostring(owner.recordId) .. "/" .. tostring(owner.factionId) .. "(" ..
                                tostring(owner.factionRank) .. "), gp value: " .. value)

            -- the item is owned by a faction.
            -- if any members of the faction spotted the player,
            -- they will report it.
            if ((spottedByFactionID[owner.factionId] == true) or spottedByGuards) then
                settings.debugPrint("you were spotted taking " .. itemRecord.name)
                totalTheftValue = totalTheftValue + value
                if factionOwnerTheftValue[owner.factionId] == nil then
                    factionOwnerTheftValue[owner.factionId] = 0
                end
                factionOwnerTheftValue[owner.factionId] = factionOwnerTheftValue[owner.factionId] + value
            end
        end
    end

    -- punish for npc theft
    for npcID, value in pairs(npcOwnerTheftValue) do
        handleTheftFromNPC(data.player, spottedByActorInstance[npcID], value)
    end
    -- punish for faction theft
    for factionID, value in pairs(factionOwnerTheftValue) do
        handleTheftFromFaction(data.player, factionID, value)
    end

    if totalTheftValue > 0 then
        data.player:sendEvent(settings.MOD_NAME .. "showWantedMessage", {
            value = totalTheftValue
        })
    end

    -- clean up old cell
    clearCellState(cellState)
end

local function onCellChange(data)
    if (data == nil) or (data.player == nil) then
        error("bad data")
    end
    if data.lastCellID ~= nil then
        onCellExit({player=data.player,cellID=data.lastCellID})
    end
    onCellEnter({player=data.player,cellID=data.newCellID})
end

-- params:
-- player
-- cellID
-- itemsList
local function onNewItems(data)
    -- this is not called when the game is paused.
    settings.debugPrint("onNewItems(" .. aux_util.deepToString(data) .. ")")
    local cellState = getCellState(data.cellID, data.player.id)
    for id, item in ipairs(data.itemsList) do
        if (id == nil) then
            error("id is nil")
        end
        if (item == nil) then
            error("item is nil")
        end
        cellState.newItems[id] = item
    end
    saveCellState(cellState)
end

-- This just fires off the "no more witnesses" message.
local updateDelay = 0
local function onUpdate(dt)
    updateDelay = updateDelay + dt
    if updateDelay > 1.5 then
        updateDelay = updateDelay - 1.5
        -- loop through all players and check if they have witnesses
        for _, player in ipairs(world.players) do
            local cellState = getCellState(player.cell.id, player.id)
            local spottedByActorInstance = filterDeadNPCs(npcIDsToInstances(player.cell.id, cellState.spottedByActorId))
            local anyPresent = false
            for _,  _ in pairs(spottedByActorInstance) do
                anyPresent = true
                break
            end
            if anyPresent == false then
                player:sendEvent(settings.MOD_NAME .. "showNoWitnessesMessage", {})
            end
        end
    end
end

return {
    eventHandlers = {
        [settings.MOD_NAME .. "onSpotted"] = onSpotted,
        [settings.MOD_NAME .. "onCellChange"] = onCellChange,
        [settings.MOD_NAME .. "onNewItem"] = onNewItems
    },
    engineHandlers = {
        onSave = saveState,
        onLoad = loadState,
        onActivate = onActivate,
        -- TODO: re-enable after debugging
        --onUpdate = onUpdate,
    }
}
