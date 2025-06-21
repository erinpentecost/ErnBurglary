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
local infrequent = require("scripts.ErnBurglary.infrequent")
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
    return persistedState
end

local function loadState(saved)
    if saved == nil then
        persistedState = {}
    else
        persistedState = saved
    end
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
        newItems = {},
        -- startingBounty is the player's bounty when they enter a cell.
        startingBounty = 0,
        -- tracks bount at the time of the last red-handed instant resolve
        -- this is done to prevent multiple checks...
        bountyAtLastRedHandedApply = 0
    }
end

local function getCellState(cellID, playerID)
    local playerKey = playerID
    if playerID.id ~= nil then
        playerKey = playerID.id
    end
    local cellState = persistedState[thieveryKey(cellID, playerKey)]
    -- settings.debugPrint("getCellState(...) for player: " .. tostring(playerID) .. ", cell: " .. tostring(cellID))
    -- settings.debugPrint("getCellState(" .. tostring(cellID) .. ", " .. tostring(playerID) .. "): " ..
    --                        aux_util.deepToString(cellState, 3))
    if cellState ~= nil then
        return cellState
    end
    return newCellState(cellID, playerKey)
end

local function saveCellState(cellState)
    -- settings.debugPrint("saveCellState(...) for player: " .. tostring(cellState.playerID) .. ", cell: " ..
    --                        tostring(cellState.cellID))
    -- settings.debugPrint("saveCellState(" .. aux_util.deepToString(cellState, 3) .. ")")
    persistedState[thieveryKey(cellState.cellID, cellState.playerID)] = cellState
end

local function clearCellState(cellState)
    settings.debugPrint("clearCellState(...) for player: " .. tostring(cellState.playerID) .. ", cell: " ..
                            tostring(cellState.cellID))
    persistedState[thieveryKey(cellState.cellID, cellState.playerID)] =
        newCellState(cellState.cellID, cellState.playerID)
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
            local backupOwner = {
                recordId = item.recordId
            }
            for k, v in pairs(common.getInventoryOwnership(types.NPC.inventory(item), backupOwner)) do
                if v == nil then
                    -- Assume owner is the holder if not explicit.
                    cellState.itemIDtoOwnership[k] = {
                        recordId = item.recordId
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

    if types.Player.objectIsInstance(actor) ~= true then
        return
    end

    if types.Container.objectIsInstance(object) then
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
    elseif types.Item.objectIsInstance(object) then
        -- This is for Shop Around compliance.
        -- If we are picking up an item off a shelf, check to see if it still
        -- has ownership. If it doesn't, remove it from the tracked list.
        if common.serializeOwner(object.owner) == nil then
            -- remove from tracker
            local cellState = getCellState(actor.cell.id, actor.id)
            if cellState.itemIDtoOwnership[object.id] ~= nil then
                settings.debugPrint("Removing " .. object.recordId .. " from ownership tracking.")
                cellState.itemIDtoOwnership[object.id] = nil
                saveCellState(cellState)
            end
        end
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
    -- wow this cell state pattern is gross
    local cellState = getCellState(data.cellID, data.player.id)
    clearCellState(cellState)

    -- save bounty
    local cellState = getCellState(data.cellID, data.player.id)
    local bounty = types.Player.getCrimeLevel(data.player)
    settings.debugPrint("read bounty: " .. tostring(bounty))
    cellState.startingBounty = bounty
    cellState.bountyAtLastRedHandedApply = bounty
    saveCellState(cellState)

    -- When we enter a cell, we need to persist ownership data
    -- for all items. We have to do this because ownership data
    -- is lost when the item is placed in the player's inventory.

    trackOwnedItems(data.cellID, data.player.id)

    -- settings.debugPrint("onCellEnter() done. new cell state: " ..
    --                        aux_util.deepToString(getCellState(data.cellID, data.player.id), 3))
end

local function npcIDsToInstances(cellState)
    local cellID = cellState.cellID
    local cell = world.getCellById(cellID)
    if cell == nil then
        error("bad cell " .. tostring(cellID))
    end

    local out = {}
    for _, npc in pairs(cell:getAll(types.NPC)) do
        if cellState.spottedByActorId[npc.id] == true then
            -- settings.debugPrint("found NPC instance " .. npc.id .. ": " .. aux_util.deepToString(npc))
            out[npc.id] = npc
        end
    end
    return out
end

local function filterDeadNPCs(npcIDtoInstanceMap)
    local out = {}
    for id, npcInstance in pairs(npcIDtoInstanceMap) do
        if types.Actor.isDead(npcInstance) or types.Actor.isDeathFinished(npcInstance) then
            settings.debugPrint("npc " .. npcInstance.id .. " is dead")
        else
            -- settings.debugPrint("npc " .. npcInstance.id .. " is NOT dead")
            out[id] = npcInstance
        end
    end
    return out
end

local function guardsExist(npcIDtoInstanceMap)
    for _, npcInstance in pairs(npcIDtoInstanceMap) do
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

local function increaseBounty(player, amount)
    local currentCrime = types.Player.getCrimeLevel(player)
    if amount < 0 then
        error("increaseBounty(player," .. amount .. ") would reduce bounty")
        return
    end
    print("Increased bounty by " .. amount)
    types.Player.setCrimeLevel(player, currentCrime + amount)
end

local function revertBounty(player, cellState)
    if settings.revertBounties() ~= true then
        return
    end

    local startingBounty = cellState.startingBounty
    local currentBounty = types.Player.getCrimeLevel(player)

    if currentBounty <= startingBounty then
        settings.debugPrint("bounty didn't increase, won't do anything")
        return
    end

    print("Reverting bounty from " .. currentBounty .. " to " .. startingBounty .. ".")
    types.Player.setCrimeLevel(player, startingBounty)
end

-- returns bounty to apply
local function handleTheftSeenByGuard(player, value)
    settings.debugPrint("handleTheftSeenByGuard(player, " .. value .. ")")
    local bounty = value * settings.bountyScale()
    print("Theft seen by guard increased bounty by " .. bounty .. ".")
    return bounty
end

-- returns bounty to apply
local function handleTheftFromNPC(player, npc, value)
    settings.debugPrint("handleTheftFromNPC(player, " .. npc.id .. ", " .. value .. ")")
    -- npc is an instance.
    local startDisposition = types.NPC.getBaseDisposition(npc, player)

    local dispoPenalty = math.min(startDisposition, value)
    types.NPC.modifyBaseDisposition(npc, player, -1 * dispoPenalty)

    local bounty = (value - dispoPenalty) * settings.bountyScale()

    print("Theft from " .. npc.recordId .. " dropped disposition by " .. dispoPenalty .. " from " .. startDisposition ..
              ", and increased bounty by " .. bounty .. ".")
    return bounty
end

-- returns bounty to apply
local function handleTheftFromFaction(player, faction, value)
    settings.debugPrint("handleTheftFromFaction(player, " .. faction .. ", " .. value .. ")")

    if settings.lenientFactions() then
        increaseBounty(player, value)
        print("Theft from " .. faction .. ".")
    end

    local startReputation = types.NPC.getFactionReputation(player, faction)

    -- faction reputation is hard to fix. consider making
    -- this less a pain.
    local reputationPenalty = math.min(startReputation, value)
    types.NPC.modifyFactionReputation(player, faction, -1 * reputationPenalty)

    local bounty = (value - reputationPenalty) * settings.bountyScale()

    local expelled = false
    if bounty > 0 then
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
              ". Expelled: " .. tostring(expelled))

    return bounty
end

-- params:
-- player
-- cellID
local function resolvePendingTheft(data)
    settings.debugPrint("resolvePendingTheft() start")

    -- This is where the magic happens, when we resolve which items have
    -- been stolen, and from whom.
    local cellState = getCellState(data.cellID, data.player.id)

    -- settings.debugPrint("resolvePendingTheft() cell state: " .. aux_util.deepToString(cellState, 3))

    -- list of living actors that spotted the player.
    local spottedByActorInstance = filterDeadNPCs(npcIDsToInstances(cellState))
    local spottedByFactionID = factionsOfNPCs(spottedByActorInstance)
    -- if guards spotted you, they will always report it.
    local spottedByGuards = guardsExist(spottedByActorInstance)
    if spottedByGuards then
        settings.debugPrint("spotted by guards")
    end
    if data.redHanded then
        settings.debugPrint("caught red-handed, so assume at least guards got us.")
        spottedByGuards = true
    end

    local npcRecordToInstance = {}
    for _, instance in pairs(spottedByActorInstance) do
        -- this is missing people?
        npcRecordToInstance[instance.recordId] = instance
        settings.debugPrint("npcRecordToInstance[" .. instance.recordId .. "] = " .. aux_util.deepToString(instance))
    end

    local totalTheftValue = 0

    -- indexed by npc instance id
    local npcOwnerTheftValue = {}
    -- indexed by faction id
    local factionOwnerTheftValue = {}
    local guardTheftValue = 0

    settings.debugPrint("checking new items for theft...")
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
            settings.debugPrint("assessing new item: " .. itemRecord.name .. "(" .. newItem.id ..
                                    "): not owned by anyone")
        elseif (owner.recordId ~= nil) then
            settings.debugPrint("assessing new item: " .. itemRecord.name .. "(" .. newItem.id .. ") owned by " ..
                                    tostring(owner.recordId) .. "/" .. tostring(owner.factionId) .. "(" ..
                                    tostring(owner.factionRank) .. "), gp value: " .. value)

            -- the item is owned by an individual.
            -- if that individual is alive, they will report.
            -- instance can be nil if the actor is dead.
            local instance = npcRecordToInstance[owner.recordId]
            if (instance == nil) then
                settings.debugPrint("can't find actor instance for " .. tostring(owner.recordId))
                if spottedByGuards then
                    guardTheftValue = guardTheftValue + value
                    settings.debugPrint("theft spotted by guards")
                    totalTheftValue = totalTheftValue + value
                end
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

    local totalBounty = 0

    -- punish for npc theft
    for npcID, value in pairs(npcOwnerTheftValue) do
        totalBounty = totalBounty + handleTheftFromNPC(data.player, spottedByActorInstance[npcID], value)
    end
    -- punish for faction theft
    for factionID, value in pairs(factionOwnerTheftValue) do
        totalBounty = totalBounty + handleTheftFromFaction(data.player, factionID, value)
    end

    if guardTheftValue > 0 then
        totalBounty = totalBounty + handleTheftSeenByGuard(data.player, guardTheftValue)
    end

    if totalBounty > 0 then
        -- this spawns a popup message each time.
        -- that's why we only apply it once.
        increaseBounty(data.player, totalBounty)
    elseif totalTheftValue > 0 then
        -- tell player they were caught (when bounty did not increase).
        data.player:sendEvent(settings.MOD_NAME .. "showWantedMessage", {
            value = totalTheftValue
        })
    end

    -- clear stolen items tracking since we resolved them
    cellState.newItems = {}
    saveCellState(cellState)

end

local function onCellExit(data)
    settings.debugPrint("onCellExit(" .. aux_util.deepToString(data) .. ")")

    -- This is where the magic happens, when we resolve which items have
    -- been stolen, and from whom.
    local cellState = getCellState(data.cellID, data.player.id)

    -- list of living actors that spotted the player.
    local spottedByActorInstance = filterDeadNPCs(npcIDsToInstances(cellState))

    local witnessesExist = false
    for _, instance in pairs(spottedByActorInstance) do
        witnessesExist = true
        break
    end

    -- we have to revert bounties between exiting a cell and entering a cell.
    if witnessesExist ~= true then
        revertBounty(data.player, cellState)
    end

    -- apply theft
    resolvePendingTheft(data)

    -- clean up old cell
    local cellState = getCellState(data.cellID, data.player.id)
    clearCellState(cellState)
end

local function onCellChange(data)
    if (data == nil) or (data.player == nil) then
        error("bad data")
    end
    if data.lastCellID ~= nil then
        onCellExit({
            player = data.player,
            cellID = data.lastCellID
        })
    end
    onCellEnter({
        player = data.player,
        cellID = data.newCellID
    })
end

-- params:
-- player
-- cellID
-- itemsList
local function onNewItems(data)
    -- this is not called when the game is paused.
    settings.debugPrint("onNewItems(" .. aux_util.deepToString(data) .. ")")
    local cellState = getCellState(data.cellID, data.player.id)
    for _, item in ipairs(data.itemsList) do
        if (item == nil) then
            error("item is nil")
        end
        cellState.newItems[item.id] = item
    end
    saveCellState(cellState)
end

local infrequentMap = infrequent.FunctionCollection:new()

-- This just fires off the "no more witnesses" message.
local function noWitnessCheck(dt)
    -- loop through all players and check if they have witnesses
    for _, player in ipairs(world.players) do
        local cellState = getCellState(player.cell.id, player.id)
        local spottedByActorInstance = filterDeadNPCs(npcIDsToInstances(cellState))
        local anyPresent = false
        for _, _ in pairs(spottedByActorInstance) do
            anyPresent = true
            break
        end
        if anyPresent == false then
            player:sendEvent(settings.MOD_NAME .. "showNoWitnessesMessage", {})
        end
    end
end

local function onUpdate(dt)
    infrequentMap:onUpdate(dt)
end

-- monitor for bounty increases. if it goes up, resolve pending thefts.
local function onBountyIncreased(data)
    -- loop through all players and check if they have witnesses

    local cellState = getCellState(data.player.cell.id, data.player.id)
    local bounty = types.Player.getCrimeLevel(data.player)
    -- did bounty go up? if so, we got caught.
    if bounty > cellState.bountyAtLastRedHandedApply then
        settings.debugPrint("bounty increased from " .. cellState.startingBounty .. " to " .. bounty ..
                                ". Checking for stolen items...")
        -- resolvePendingTheft might change bounty
        resolvePendingTheft({
            player = data.player,
            cellID = data.player.cell.id,
            redHanded = true,
        })

        -- save bounty
        local cellState = getCellState(data.player.cell.id, data.player.id)
        cellState.bountyAtLastRedHandedApply = types.Player.getCrimeLevel(data.player)
        saveCellState(cellState)
    end
end

local function onPaidBounty(data)
    settings.debugPrint("detected bounty payoff")
    local cellState = getCellState(data.player.cell.id, data.player.id)
    cellState.bountyAtLastRedHandedApply = 0
    cellState.startingBounty = 0
    saveCellState(cellState)
end

return {
    eventHandlers = {
        [settings.MOD_NAME .. "onSpotted"] = onSpotted,
        [settings.MOD_NAME .. "onCellChange"] = onCellChange,
        [settings.MOD_NAME .. "onNewItem"] = onNewItems,
        [settings.MOD_NAME .. "onPaidBounty"] = onPaidBounty,
        [settings.MOD_NAME .. "onBountyIncreased"] = onBountyIncreased
    },
    engineHandlers = {
        onSave = saveState,
        onLoad = loadState,
        onActivate = onActivate,
        onUpdate = onUpdate
    }
}
