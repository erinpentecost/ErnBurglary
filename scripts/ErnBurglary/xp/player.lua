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
local self     = require('openmw.self')
local types    = require("openmw.types")
local core     = require("openmw.core")
local aux_util = require('openmw_aux.util')

local function xpOnStolenCallback(data)
    -- just allow one level up at a time.
    -- do this because progress needs to scale based on current sneak level.
    -- this is not ideal.
    local sneakSkill = types.Player.stats.skills.sneak(self)
    local additional = data / (sneakSkill.base ^ 1.7)
    sneakSkill.progress = math.min(1.0001, sneakSkill.progress + additional)

    settings.debugPrint("xpOnStolenCallback(" ..
        tostring(data) ..
        "): sneak skill is now " ..
        tostring(sneakSkill.progress) .. " after adding " .. tostring(additional) .. " (stole " .. data .. ")")
end

return {
    eventHandlers = {
        [settings.MOD_NAME .. "xpOnStolenCallback"] = xpOnStolenCallback,
    }
}
