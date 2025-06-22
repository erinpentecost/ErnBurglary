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
local storage = require("openmw.storage")
local types = require("openmw.types")

local MOD_NAME = "ErnBurglary"

local settingsStore = storage.globalSection("SettingsGlobal" .. MOD_NAME)

local function debugMode()
    return settingsStore:get("debugMode")
end

local function revertBounties()
    return settingsStore:get("revertBounties")
end

local function quietMode()
    return settingsStore:get("quietMode")
end

local function bountyScale()
    return settingsStore:get("bountyScale")
end

local function trespassFine()
    return settingsStore:get("trespassFine")
end

local function lenientFactions()
    return settingsStore:get("lenientFactions")
end

local function debugPrint(str, ...)
    if debugMode() then
        local arg = {...}
        if arg ~= nil then
            print(string.format("DEBUG: " .. str, unpack(arg)))
        else
            print("DEBUG: " .. str)
        end
    end
end

local function initSettings()
    interfaces.Settings.registerGroup {
        key = "SettingsGlobal" .. MOD_NAME,
        l10n = MOD_NAME,
        name = "modSettingsTitle",
        description = "modSettingsDesc",
        page = MOD_NAME,
        permanentStorage = false,
        settings = {{
            key = "bountyScale",
            name = "bountyScale_name",
            description = "bountyScale_description",
            default = 1,
            renderer = "number",
            argument = {
                integer = false,
                min = 0,
                max = 100
            }
        }, {
            key = "trespassFine",
            name = "trespassFine_name",
            description = "trespassFine_description",
            default = 0,
            renderer = "number",
            argument = {
                integer = true,
                min = 0,
                max = 1000
            }
        }, {
            key = "revertBounties",
            name = "revertBounties_name",
            description = "revertBounties_description",
            default = true,
            renderer = "checkbox"
        }, {
            key = "quietMode",
            name = "quietMode_name",
            description = "quietMode_description",
            default = true,
            renderer = "checkbox"
        }, {
            key = "lenientFactions",
            name = "lenientFactions_name",
            description = "lenientFactions_description",
            default = true,
            renderer = "checkbox"
        }, {
            key = "debugMode",
            name = "debugMode_name",
            description = "debugMode_description",
            default = false,
            renderer = "checkbox"
        }}
    }
    print("init settings")
end

return {
    initSettings = initSettings,
    settingsStore = settingsStore,
    MOD_NAME = MOD_NAME,

    revertBounties = revertBounties,
    quietMode = quietMode,
    bountyScale = bountyScale,
    trespassFine = trespassFine,
    lenientFactions = lenientFactions,
    debugMode = debugMode,
    debugPrint = debugPrint
}
