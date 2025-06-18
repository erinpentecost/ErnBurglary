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
    }
}
