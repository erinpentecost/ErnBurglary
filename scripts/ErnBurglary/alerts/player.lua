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
local types = require("openmw.types")
local settings = require("scripts.ErnBurglary.settings")
local self = require("openmw.self")
local core = require("openmw.core")
local localization = core.l10n(settings.MOD_NAME)
local ui = require('openmw.ui')

local function alertsOnSpottedChange(data)
    if data.spotted == false then
        for _, spell in pairs(types.Actor.activeSpells(self)) do
            if spell.id == "ernburglary_spotted" then
                types.Actor.activeSpells(self):remove(spell.activeSpellId)
            end
        end

        -- this will execute on every cell change
        settings.debugPrint("showNoWitnessesMessage")
        if (settings.quietMode() ~= true) then
            ui.showMessage(localization("showNoWitnessesMessage", {}))
        end
    else
        types.Actor.activeSpells(self):add({
            id = "ernburglary_spotted",
            effects = {0},
            ignoreResistances = true,
            ignoreSpellAbsorption = true,
            ignoreReflect = true
        })

        local npcName = types.NPC.record(data.npc).name
        if settings.quietMode() ~= true then
            ui.showMessage(localization("showSpottedMessage", {
                actorName = npcName
            }))
        end
    end
end

return {
    eventHandlers = {
        [settings.MOD_NAME .. "alertsOnSpottedChange"] = alertsOnSpottedChange
    }
}
