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
]]
local settings = require("scripts.ErnBurglary.settings")

local onSpottedCallbacks = {}
local spottedPlayerStatus = {}

-- onSpottedCallback adds a callback to be invoked whenever the player's Spotted status changes.
-- This could be used to power a trespassing mod or whatever else.
-- The params passed into the callback is a table with these fields:
-- - player
-- - spotted (boolean)
local function onSpottedChangeCallback(callback)
    table.insert(onSpottedCallbacks, callback)
end

local function __onSpotted(player)
    for _, callback in ipairs(onSpottedCallbacks) do
        if (spottedPlayerStatus[player.id] ~= true) then
            spottedPlayerStatus[player.id] = true
            callback({
                player=player,
                spotted=true,
            })
        end
    end
end

local function __onNoWitnesses(player)
    for _, callback in ipairs(onSpottedCallbacks) do
        if (spottedPlayerStatus[player.id] ~= false) then
            spottedPlayerStatus[player.id] = false
            callback({
                player=player,
                spotted=false,
            })
        end
    end
end

local onStolenCallbacks = {}

-- onStolenCallback adds a callback to be invoked whenever the player steals an item.
-- This could be used to power a spawn-detectives mod or whatever.
-- The param is a list of tables. Each table has these fields:
-- - player
-- - itemInstance
-- - itemRecordID
-- - owner
-- - cellID (cell the theft occurred in)
-- - caught (boolean indicating if the player was caught stealing it)
local function onStolenCallback(callback)
    table.insert(onStolenCallbacks, callback)
end

local function __onStolen(data)
    for _, callback in ipairs(onStolenCallbacks) do
        callback(data)
    end
end

-- setItemsAllowed will set the InDialogue flag.
-- While this flag is true, any new items gained will not be counted as stolen.
-- This is not a permanent change. ErnBurglary will reset this flag if
-- the player's UI mode changes into, or out of, "Dialogue" mode.
-- This exists to allow for patching with Pause Control.
local function setItemsAllowed(player, allowed)
    player:sendEvent(settings.MOD_NAME .. "setItemsAllowed", {allowed=allowed})
end

return {
    interfaceName = settings.MOD_NAME,
    interface = {
        version = 1,
        setItemsAllowed = setItemsAllowed,
        onSpottedChangeCallback = onSpottedChangeCallback,
        onStolenCallback = onStolenCallback,
        __onSpotted = __onSpotted,
        __onNoWitnesses = __onNoWitnesses,
        __onStolen = __onStolen,
    }
}
