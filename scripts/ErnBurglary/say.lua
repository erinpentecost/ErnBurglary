--[[
ErnBurglary for OpenMW.
Copyright (C) 2025 Erin Pentecost

This program is free software: you can redistribute it and\\or modify
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
local core = require('openmw.core')
local vfs = require('openmw.vfs')


-- https://en.uesp.net/wiki/Morrowind:Generic_Dialogue_Voiced
-- there are 4,169 hello lines
-- but there's only 416 idle lines
-- this doesn't seem to work.

local idleFiles = {}

local function loadIdleFiles()
    -- Hlo_[^\/]+\.mp3
    for fileName in vfs.pathsWithPrefix("Sound\\Vo") do
        if string.find(string.lower(fileName), "idl_.*mp3") then
            table.insert(idleFiles, fileName)
        end
    end
    settings.debugPrint("Found "..#idleFiles.." idle sound files. Example: "..tostring(idleFiles[1]))
    if #idleFiles < 100 then
        error("didn't find enough idle files")
    end
end

loadIdleFiles()

local function idle(object)
    for _, file in ipairs(idleFiles) do
        if core.sound.isSoundFilePlaying(file, object) then
            settings.debugPrint("idle playing: " .. file)
            return true
        end
    end
    return false
end

return {
    idle = idle,
}