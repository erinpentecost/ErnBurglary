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

local thieveryTracker = storage.globalSection(settings.MOD_NAME .. "thieveryTracker")
thieveryTracker:setLifeTime(storage.LIFE_TIME.Temporary)

local function saveState()
    return thieveryTracker:asTable()
end

local function loadState(saved)
    thieveryTracker:reset(saved)
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

local function onGetAllOwnedItems(data)
    settings.debugPrint("onGetAllOwnedItems() start")
    if (data == nil) or (data.cellID == nil) or (data.player == nil) then
        error("onGetAllOwnedItems() bad data")
        return
    end

    if data.fromSave then
        settings.debugPrint("onGetAllOwnedItems() getting ownership from save")
        local ownership = thieveryTracker:get(data.player.id .. data.cellID)
        if ownership ~= nil then
            data.player:sendEvent("ernOwnershipInfo", {
                cellID = data.cellID,
                itemIDtoOwnership = ownership
            })
            settings.debugPrint("onGetAllOwnedItems() end")
        end
    else
        thieveryTracker:set(data.player.id .. data.cellID, nil)
    end

    local cell = world.getCellById(data.cellID)
    if cell == nil then
        error("bad cell " .. data.cellID)
        return
    end
    settings.debugPrint("Finding owned items in " .. cell.name)

    local itemIDtoOwnership = {}
    for _, item in ipairs(cell:getAll()) do
        if types.Item.objectIsInstance(item) then
            itemIDtoOwnership[item.id] = serializeOwner(item.owner)
        elseif types.Container.objectIsInstance(item) then
            for _, itemInContainer in ipairs(types.Container.inventory(item):getAll()) do
                itemIDtoOwnership[itemInContainer.id] = serializeOwner(itemInContainer.owner)
            end
        elseif types.NPC.objectIsInstance(item) then
            for _, itemInNPC in ipairs(types.NPC.inventory(item):getAll()) do
                itemIDtoOwnership[itemInNPC.id] = serializeOwner(itemInNPC.owner)
            end
        end
    end

    thieveryTracker:set(data.player.id .. data.cellID, itemIDtoOwnership)
    data.player:sendEvent("ernOwnershipInfo", {
        cellID = data.cellID,
        itemIDtoOwnership = itemIDtoOwnership
    })
    settings.debugPrint("onGetAllOwnedItems() end")
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
            data.player:sendEvent("ernShowExpelledMessage", {
                faction = faction
            })
            settings.debugPrint("Expelled.")
        end
    end
end

-- onSpotted is called when a player is spotted by an NPC.
-- params:
-- player
-- npc
local function onSpotted(data)
end

-- params:
-- player
-- cellID
local function onCellEnter(data)
end

-- params:
-- player
-- cellID
local function onCellExit(data)
end

-- onReported is called when a player exits a cell.
-- data has params:
-- player, who is the thief
-- cellID the theft occurred in
-- npcThefts, which is a map of npc record id -> value of theft
-- factionThefts, which is a map of faction id -> value of theft
local function onReported(data)
    settings.debugPrint("onReported() start")
    if (data == nil) or (data.player == nil) then
        error("onReported() bad data")
        return
    end

    -- The NPC owner is a record ID instead of an actor instance.
    -- I need the actual instance, though.
    local cell = world.getCellById(data.cellID)
    if cell == nil then
        error("bad cell " .. data.cellID)
        return
    end
    local npcMap = {}
    for _, npc in ipairs(cell:getAll(types.NPC)) do
        npcMap[types.NPC.record(npc).id] = npc
    end

    local totalValue = 0
    for owner, value in pairs(data.npcThefts) do
        local npcInstance = npcMap[owner]

        if (value == nil) or (value <= 0) then
            settings.debugPrint("nil value")
        else
            totalValue = totalValue + value
            handleTheftFromNPC(data.player, npcMap[owner], value)
        end

    end
    for owner, value in pairs(data.factionThefts) do
        -- faction witenesses have already been checked for death.
        if (value == nil) or (value <= 0) then
            settings.debugPrint("nil value")
        else
            totalValue = totalValue + value
            handleTheftFromFaction(data.player, owner, value)
        end
    end

    data.player:sendEvent("ernShowWantedMessage", {
        value = totalValue
    })
    settings.debugPrint("onReported() end")
end

return {
    eventHandlers = {
        [settings.MOD_NAME.."onSpotted"]=onSpotted,
        [settings.MOD_NAME.."onCellEnter"]=onCellEnter,
        [settings.MOD_NAME.."onCellExit"]=onCellExit,
    },
    engineHandlers = {
        onSave = saveState,
        onLoad = loadState
    }
}
