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
local common = require("scripts.ErnBurglary.common")
local infrequent = require("scripts.ErnBurglary.infrequent")
local interfaces = require('openmw.interfaces')
local world = require('openmw.world')
local types = require("openmw.types")
local core = require("openmw.core")
local async = require('openmw.async')
local aux_util = require('openmw_aux.util')
local storage = require('openmw.storage')

-- this doesn't seem to work

local originalCrimeInterface = nil
local function commitCrime(player, CommitCrimeInputs)
    if originalCrimeInterface == nil then
        error("no base Crimes interface")
        return
    end

    if CommitCrimeInputs.type == types.OFFENSE_TYPE.Theft then
        settings.debugPrint("theft crime seen")
        settings.debugPrint("commitCrime(player, " ..
            aux_util.deepToString(CommitCrimeInputs, 3) .. ")")
        return {
            wasCrimeSeen = false
        }
    end
    settings.debugPrint("forwarding crime")
    return originalCrimeInterface.commitCrime(player, CommitCrimeInputs)
end

return {
    interfaceName = "Crimes",
    interface = {
        version = 1,
        commitCrime = commitCrime
    },
    engineHandlers = {
        onInterfaceOverride = function(base) originalCrimeInterface = base end,
    }
}
