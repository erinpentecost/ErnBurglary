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
local interfaces = require('openmw.interfaces')
local types = require("openmw.types")
local core = require("openmw.core")

-- Track all persistedState we've ever picked up.
-- This is a map of "<player instance id> .. <key record id>" -> true.
-- Also contains "<player instance id>" -> <cell id they are currently trespassing in>
-- This lets us mark a door as safe even if the player removes the key at some point.
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

local function hasKey(door, actor)
    local keyRecord = types.Lockable.getKeyRecord(door)
    if keyRecord == nil then
        -- no key, so never allowed.
        settings.debugPrint("No key exists for door " .. door.id .. ".")
        return false
    end
    -- check if we previously had the key
    local mapKey = actor.id .. keyRecord.id
    if persistedState[mapKey] == true then
        -- we had the key at one point.
        -- let them in.
        return true
    end
    -- check if we have the key right now.
    for _, item in ipairs(types.Actor.inventory(actor):getAll(types.Miscellaneous)) do
        if item.recordId == keyRecord.id then
            -- memorize ownership of the key.
            persistedState[mapKey] = true
            if settings.keyring() then
                -- delete the key
                item:remove()
            end
            -- let them in.
            return true
        end
    end
    return false
end

local function onActivate(object, actor)

    if types.Player.objectIsInstance(actor) ~= true then
        return
    end

    if types.Door.objectIsInstance(object) then
        settings.debugPrint("onActivate(" .. tostring(object.id) .. ", player)")
        if types.Door.isOpen(object) then
            -- this means we are closing the door.
            return
        end
        local doorRecord = types.Door.records[object.recordId]
        if doorRecord.mwscript ~= nil then
            -- don't mess with scripted doors.
            return
        end
        local keyRecord = types.Lockable.getKeyRecord(object)
        if keyRecord == nil then
            -- don't mess with doors that don't have keys
            return
        end

        if settings.keyring() and types.Lockable.isLocked(object) and hasKey(object, actor) then
            -- unlock the door since we had the key at some point.
            settings.debugPrint("Player " .. actor.id .. " unlocked " .. object.recordId .. " (" .. object.id ..
                                    ") with the keyring.")
            types.Lockable.unlock(object)
            types.Lockable.setTrapSpell(object, nil)
            actor:sendEvent(settings.MOD_NAME .. "showUnlockMessage", {
                key = keyRecord.name
            })
            return
        end

        local destCell = types.Door.destCell(object)
        if (types.Lockable.isLocked(object) == false) and types.Door.isTeleport(object) and (destCell ~= nil) and
            (destCell.id ~= actor.cell.id) and (destCell.isExterior ~= true) then
            -- we are about to teleport into an interior cell.
            if hasKey(object, actor) ~= true then
                -- we are trespassing!
                settings.debugPrint("Player " .. actor.id .. " is trespassing in " .. destCell.name .. " (" ..
                                        destCell.id .. ").")
                persistedState[actor.id] = destCell.id
            end
        end
    end
end

local function onCellChange(data)
    local trespassCellID = persistedState[data.player.id]
    if trespassCellID ~= nil then
        if data.newCellID ~= trespassCellID then
            settings.debugPrint("Player " .. data.player.id .. " is no longer trespassing in " .. trespassCellID .. ".")
            persistedState[data.player.id] = nil
        end
    end

end

interfaces.ErnBurglary.onCellChangeCallback(onCellChange)

local function onSpottedChange(data)
    if data.spotted == false then
        return
    end
    settings.debugPrint("Player was spotted.")
    local trespassCellID = persistedState[data.player.id]
    if trespassCellID == nil then
        return
    end
    settings.debugPrint("Player was spotted trespassing in " .. trespassCellID .. ".")

    local fine = settings.trespassFine()
    if fine > 0 then
        local currentCrime = types.Player.getCrimeLevel(data.player)
        types.Player.setCrimeLevel(data.player, currentCrime + fine)
    end
end

interfaces.ErnBurglary.onSpottedChangeCallback(onSpottedChange)

return {
    eventHandlers = {},
    engineHandlers = {
        onSave = saveState,
        onLoad = loadState,
        onActivate = onActivate
    }
}
