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
local world = require('openmw.world')
local types = require("openmw.types")
local core = require("openmw.core")
local storage = require('openmw.storage')

if require("openmw.core").API_REVISION < 62 then
    error("OpenMW 0.49 or newer is required!")
end

-- Init settings first to init storage which is used everywhere.
settings.initSettings()

-- thieveryTracker persists player+cell namespaced info.
local thieveryTracker = storage.globalSection(settings.MOD_NAME .. "thieveryTracker")
thieveryTracker:setLifeTime(storage.LIFE_TIME.Temporary)

local function saveState()
    return thieveryTracker:asTable()
end

local function loadState(saved)
    thieveryTracker:reset(saved)
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

local function getCellState(cellID, playerID)
    local state = thieveryTracker:get(thieveryKey(cellID, playerID))
    if state ~= nil then
        return state
    end
    return {
        cellID = cellID,
        playerID = playerID,
        -- itemIDtoOwnership is map of item instance id to actor id.
        itemIDtoOwnership = {},
        -- spottedByActorId is a map of actor id -> true
        spottedByActorId = {},
        -- newItems is a list of new items the player picked up while in the cell.
        newItems = {},
    }
end

local function saveCellState(state)
    return thieveryTracker:set(thieveryKey(state.cellID, state.playerID), state)
end

local function serializeOwner(owner)
    if owner == nil then
        error("serializeOwner() nil owner")
    end
    return {
        recordId = owner.recordId,
        factionRank = owner.factionRank,
        factionId = owner.factionId
    }
end

local function getInventoryOwnership(inventory)
    local itemIDtoOwnership = {}
    for _, itemInContainer in ipairs(inventory:getAll()) do
        itemIDtoOwnership[itemInContainer.id] = serializeOwner(itemInContainer.owner)
    end
    return itemIDtoOwnership
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

    local state = getCellState(cellID, playerID)
    -- reset to empty.
    state.itemIDtoOwnership = {}

    -- Save ownership state for loose items and actor inventories.
    for _, item in ipairs(cell:getAll()) do
        if types.Item.objectIsInstance(item) then
            state.itemIDtoOwnership[item.id] = serializeOwner(item.owner)
        elseif types.NPC.objectIsInstance(item) then
            for k, v in pairs(getInventoryOwnership(types.NPC.inventory(item))) do
                state.itemIDtoOwnership[k] = v
            end
        end
    end

    saveCellState(state)

    settings.debugPrint("trackOwnedItems(" .. tostring(cellID) .. ") end")
end

-- Save ownership data for containers when they are activated.
-- Adds elements to state.itemIDtoOwnership.
local function onActivate(object, actor)
    if types.Player.objectIsInstance(actor) and types.Container.objectIsInstance(object) then
        local inventory = types.Container.inventory(object)
        if inventory:isResolved() ~= true then
            inventory:resolve()
            local state = getCellState(actor.cell.id, actor.id)
            for k, v in pairs(getInventoryOwnership(inventory)) do
                state.itemIDtoOwnership[k] = v
            end
            saveCellState(state)
        end
    end
end

-- onSpotted is called when a player is spotted by an NPC.
-- params:
-- player
-- cellID
-- npc
local function onSpotted(data)
    local state = getCellState(data.cellID, data.player.id)
    state.spottedByActorId[data.npc.id] = true
    saveCellState(state)
end

-- params:
-- player
-- cellID
local function onCellEnter(data)
    -- When we enter a cell, we need to persist ownership data
    -- for all items. We have to do this because ownership data
    -- is lost when the item is placed in the player's inventory.

    -- This is actually totally broken because the item could legitimately
    -- transfer ownership to the player when they buy something.
    -- I have to detect when when the player is in the shop dialogue,
    -- and not count those items.

    trackOwnedItems(data.cellID, data.player.id)
end

local function npcIDsToInstances(cellID, npcIDList)
    local cell = world.getCellById(cellID)
    if cell == nil then
        error("bad cell "..tostring(cellID))
    end

    local npcIDMap = {}
    for _, id in npcIDList do
        npcIDMap[id] = true
    end

    local out = {}
    for _, npc in pairs(cell:getAll(types.NPC)) do
        if npcIDMap[npc.id] ~= true then
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
            out[id] = npcInstance
        end
    end
    return out
end

local function factionsOfNPCs(npcIDtoInstanceMap)
    local out = {}
    for _, npcInstance in pairs(npcIDtoInstanceMap) do
        for _, faction in ipairs(types.NPC.getFactions(npcInstance)) do
            out[faction] = true
        end
    end
    return out
end

local function atLeastRank(npc, factionID, rank)
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

local function handleTheftFromNPC(player, npc, value)
    settings.debugPrint("handleTheftFromNPC(player, " .. npc.id .. ", " .. value .. ")")
    -- npc is an instance.
    -- always reduce disposition. 2gp == 1 disposition
    local startDisposition = types.NPC.getDisposition(npc, player)
    local penalty = value
    if startDisposition >= 0.5 * penalty then
        -- absorb the cost just in disposition.
        settings.debugPrint("Partially dropped disposition.")
        types.NPC.modifyBaseDisposition(npc, player, -0.5 * penalty)
        return
    else
        types.NPC.setBaseDisposition(npc, player, 0)
        penalty = penalty - 2 * startDisposition
        settings.debugPrint("Fully dropped disposition.")
    end
    -- we have leftover penalty.
    -- for now, just increase crime level
    local currentCrime = types.Player.getCrimeLevel(player)
    types.Player.setCrimeLevel(player, currentCrime + penalty)
    settings.debugPrint("Increased bounty by " .. penalty)
end

local function handleTheftFromFaction(player, faction, value)
    settings.debugPrint("handleTheftFromFaction(player, " .. faction .. ", " .. value .. ")")
    local startReputation = types.NPC.getFactionReputation(player, faction)
    local penalty = value
    if startReputation >= 0.1 * penalty then
        -- absorb the cost just in disposition.
        settings.debugPrint("Partially dropped reputation.")
        types.NPC.modifyFactionReputation(player, faction, -0.1 * penalty)
        return
    else
        settings.debugPrint("Fully dropped reputation.")
        types.NPC.setFactionReputation(player, faction, 0)
        penalty = penalty - 10 * startReputation
    end
    -- we have leftover penalty.
    for _, playerFaction in ipairs(types.NPC.getFactions(player)) do
        if playerFaction == faction then
            types.NPC.expel(player, playerFaction)
            player:sendEvent("ernShowExpelledMessage", {
                faction = faction
            })
            settings.debugPrint("Expelled.")
        end
    end
end

-- params:
-- player
-- cellID
local function onCellExit(data)
    -- This is where the magic happens, when we resolve which items have
    -- been stolen, and from whom.
    local state = getCellState(data.cellID, data.player.id)

    -- list of living actors that spotted the player.
    local spottedByActorInstance = filterDeadNPCs(npcIDsToInstances(data.cellID, state.spottedByActorId))
    local spottedByFactionID = factionsOfNPCs(spottedByActorInstance)

    local npcRecordToInstance = {}
    for _, instance in ipairs(spottedByActorInstance) do
        npcRecordToInstance[instance.recordId] = instance
    end

    local totalTheftValue = 0

    -- indexed by npc instance id
    local npcOwnerTheftValue = {}
    -- indexed by faction id
    local factionOwnerTheftValue = {}

    -- build up value of all stolen goods
    for _, newItem in ipairs(state.newItems) do
        local itemRecord = newItem.type.record(newItem)
        local owner = state.itemIDtoOwnership[newItem]
        if (owner == nil) then
            -- the item is not owned.
        elseif (owner.recordId ~= nil) then
            -- the item is owned by an individual.
            -- if that individual is alive, they will report.
            local instance = npcRecordToInstance[owner.recordId]
            if (instance ~= nil) and (spottedByActorInstance[instance.id]) then
                local value = tonumber(itemRecord.value)
                totalTheftValue = totalTheftValue + value
                npcOwnerTheftValue[instance.id] = npcOwnerTheftValue[instance.id] + value
            end
        elseif (owner.factionId ~= nil) and atLeastRank(data.player, owner.factionId, owner.factionRank) then
            -- the item is owned by a faction.
            -- if any members of the faction spotted the player,
            -- they will report it.
            if spottedByFactionID[owner.factionId] then
                local value = tonumber(itemRecord.value)
                totalTheftValue = totalTheftValue + value
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
        handleTheftFromFaction(data.player, factionOwnerTheftValue[factionID], value)
    end

    if totalTheftValue > 0 then
        data.player:sendEvent("ernShowWantedMessage", {
            value = totalTheftValue
        })
    end
end

-- params:
-- player
-- cellID
-- itemsList
local function onNewItems(data)
    local state = getCellState(data.cellID, data.player.id)
    for _, item in data.itemsList do
        table.insert(state.newItems, item)
    end
    saveCellState(state)
end

return {
    eventHandlers = {
        [settings.MOD_NAME .. "onSpotted"] = onSpotted,
        [settings.MOD_NAME .. "onCellEnter"] = onCellEnter,
        [settings.MOD_NAME .. "onCellExit"] = onCellExit,
        [settings.MOD_NAME .. "onNewItem"] = onNewItems
    },
    engineHandlers = {
        onSave = saveState,
        onLoad = loadState,
        onActivate = onActivate
    }
}
