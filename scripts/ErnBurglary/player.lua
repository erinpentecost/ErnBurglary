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
local settings = require("scripts.ErnBurglary.settings")
local infrequent = require("scripts.ErnBurglary.infrequent")
local types = require("openmw.types")
local nearby = require("openmw.nearby")
local core = require("openmw.core")
local self = require("openmw.self")
local localization = core.l10n(settings.MOD_NAME)
local ui = require('openmw.ui')
local aux_util = require('openmw_aux.util')

interfaces.Settings.registerPage {
    key = settings.MOD_NAME,
    l10n = settings.MOD_NAME,
    name = "name",
    description = "description"
}

-- warnCooldown stops us from spamming people
local warnCooldown = 15

-- lastCellID will be nil if loading from a save game.
-- otherwise, it will be the cell we just moved from.
local lastCellID = nil
-- spottedByActorID deduplicates calls to onSpotted.
local spottedByActorID = {}
-- spotted is used cases where we were spotted before sneaking
local spotted = false
local sneaking = false
local warnCooldownTimer = 0

local noWitnessesMessageReceivedCooldownTimer = 0
local noWitnessesMessageReceived = false

-- inDialogue is true while talking to an NPC.
-- this is an attempt to get this working with Pause Control.
local inDialogue = false
-- forgiveNewItems is set to true to skip the next item check.
local forgiveNewItems = false

-- itemsInInventory is used to track changes in the
-- player's inventory.
-- it's a map of item instance id -> instance.
local itemsInInventory = {}
local function trackInventory()
    itemsInInventory = {}
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do

        itemsInInventory[item.id] = item
    end
end
trackInventory()

local function showWantedMessage(data)
    settings.debugPrint("showWantedMessage")
    ui.showMessage(localization("showWantedMessage", {
        value = data.value
    }))
end

local function showExpelledMessage(data)
    settings.debugPrint("showExpelledMessage")
    local faction = core.factions.records[data.faction]
    ui.showMessage(localization("showExpelledMessage", {
        factionName = data.faction.name
    }))
end

local function elusiveness(distance)
    -- https://en.uesp.net/wiki/Morrowind:Sneak
    
    local sneakTerm = types.NPC.stats.skills.sneak(self).modified
    local agilityTerm = types.Actor.stats.attributes.agility(self).modified / 5
    local luckTerm = types.Actor.stats.attributes.luck(self).modified / 10
    local distanceTerm = 0.5 + (distance/500)
    local fatigueStat = types.Actor.stats.dynamic.fatigue(self)
    local fatigueTerm = 0.75 + (0.5 * math.min(1, math.max(0, fatigueStat.current / fatigueStat.base)))
    
    local chameleonEffect = types.Actor.activeEffects(self):getEffect(core.magic.EFFECT_TYPE.Chameleon)
    local chameleon = 0
    if chameleonEffect ~= nil then
        chameleon = chameleonEffect.magnitude
    end

    local elusivenessScore = (sneakTerm+agilityTerm+luckTerm) * distanceTerm * fatigueTerm + chameleon
    settings.debugPrint("elusiveness: ".. elusivenessScore .. " = ".. "("..sneakTerm.."+"..agilityTerm.."+"..luckTerm..") * "..distanceTerm.." * "..fatigueTerm.." + "..chameleon)
    return elusivenessScore
end

local function awareness(actor)
    -- https://en.uesp.net/wiki/Morrowind:Sneak
    local sneakTerm = types.NPC.stats.skills.sneak(actor).modified
    local agilityTerm = types.Actor.stats.attributes.agility(actor).modified / 5
    local luckTerm = types.Actor.stats.attributes.luck(actor).modified / 10

    local fatigueStat = types.Actor.stats.dynamic.fatigue(self)
    local fatigueTerm = 0.75 + (0.5 * math.min(1, math.max(0, fatigueStat.current / fatigueStat.base)))

    -- this can range from 1.5 to 0.5. just assume 1.0 for now.
    local directionMult = 1.0

    local blindEffect = types.Actor.activeEffects(actor):getEffect(core.magic.EFFECT_TYPE.Blind)
    local blind = 0
    if blindEffect ~= nil then
        blind = blindEffect.magnitude
    end

    local awarenessScore = (sneakTerm+agilityTerm+luckTerm-blind) * fatigueTerm * directionMult
    settings.debugPrint("awareness: ".. awarenessScore .. " = ".. "("..sneakTerm.."+"..agilityTerm.."+"..luckTerm.."-"..blind..") * "..fatigueTerm.." * "..directionMult)
    return awarenessScore
end

-- sneakCheck should return true if the actor can't see the player.
local function sneakCheck(actor)
    local distance = (self.position - actor.position):length()

    -- always pass the check if sufficiently far away.
    if distance > 400 then
        settings.debugPrint("too far away: "..actor.recordId)
        return true
    end

    local invisibilityEffect = types.Actor.activeEffects(self):getEffect(core.magic.EFFECT_TYPE.Invisibility)
    if (invisibilityEffect ~= nil) and (invisibilityEffect.magnitude > 0) then
        settings.debugPrint("invisible; ignoring greeting")
        return true
    end

    -- if we aren't sneaking, then you don't pass the check.
    if sneaking ~= true then
        return false
    end

    local sneakChance = math.min(100, math.max(0, elusiveness(distance) - awareness(actor)))
    local roll = math.random(0, 100)

    settings.debugPrint("sneak chance: "..sneakChance..", roll: "..roll)

    return sneakChance >= roll
end

local function registerHandlers()
    local sneakGroups = {"sneakforward", "sneakleft", "sneakright", "sneakback"}
    for _, group in ipairs(sneakGroups) do
        interfaces.AnimationController.addTextKeyHandler(group, function(group, key)
            if (sneaking == false) and spotted and (warnCooldownTimer <= 0) then
                -- just started sneaking, but was spotted earlier.
                if settings.quietMode() ~= true then
                    ui.showMessage(localization("showWarningMessage", {}))
                end
                warnCooldownTimer = warnCooldown
            end
            sneaking = true
        end)
    end

    local nonSneakGroups = {"walkforward", "walkleft", "walkright", "walkback", "runforward", "runleft", "runright",
                            "runback"}
    for _, group in ipairs(nonSneakGroups) do
        interfaces.AnimationController.addTextKeyHandler(group, function(group, key)
            sneaking = false
        end)
    end
end

registerHandlers()

local function showNoWitnessesMessage(data)
    if spotted then
        noWitnessesMessageReceived = true
    end
end

local infrequentMap = infrequent.FunctionCollection:new()

local function allClear(dt)
    noWitnessesMessageReceivedCooldownTimer = noWitnessesMessageReceivedCooldownTimer - dt
    if spotted and noWitnessesMessageReceived then
        settings.debugPrint("showNoWitnessesMessage")
        noWitnessesMessageReceived = false
        spotted = false
        spottedByActorID = {}
        if noWitnessesMessageReceivedCooldownTimer <= 0 then
            if settings.quietMode() ~= true then
                ui.showMessage(localization("showNoWitnessesMessage", {}))
            end
            noWitnessesMessageReceivedCooldownTimer = 2
        end
    end
end

local function isTalking(actor)
    return (core.sound.isSayActive(actor))
end

local function detectionCheck(dt)
    allClear(dt)

    warnCooldownTimer = warnCooldownTimer - dt

    -- find out which NPC is talking
    for _, actor in ipairs(nearby.actors) do
        -- check for detection
        if spottedByActorID[actor.id] == nil then
            if isTalking(actor) and (sneakCheck(actor) ~= true) then
                spottedByActorID[actor.id] = true
                settings.debugPrint("sending spotted by event for " .. actor.recordId)
                core.sendGlobalEvent(settings.MOD_NAME .. "onSpotted", {
                    player = self,
                    npc = actor,
                    cellID = self.cell.id
                })
                spotted = true
                -- Send notice if sneaking.
                if sneaking and (warnCooldownTimer <= 0) then
                    warnCooldownTimer = warnCooldown
                    local npcName = types.NPC.record(actor).name
                    if settings.quietMode() ~= true then
                        ui.showMessage(localization("showSpottedMessage", {
                            actorName = npcName
                        }))
                    end
                end
            end
        end
    end
end

infrequentMap:addCallback("detection", 0.11, detectionCheck)

local function inventoryChangeCheck(dt)
    local newItemsList = {}
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        if itemsInInventory[item.id] == nil then
            table.insert(newItemsList, item)
            settings.debugPrint("found new item: " .. aux_util.deepToString(item, 2))
            -- don't re-add the item
            itemsInInventory[item.id] = item
        end
    end
    if forgiveNewItems then
        settings.debugPrint("forgave new items")
        forgiveNewItems = false
        return
    end
    
    if #newItemsList > 0 then
        if inDialogue then
            settings.debugPrint("forgave new items")
            return
        end
        core.sendGlobalEvent(settings.MOD_NAME .. "onNewItem", {
            player = self,
            cellID = self.cell.id,
            itemsList = newItemsList
        })
    end
end

infrequentMap:addCallback("inventory", 0.1, inventoryChangeCheck)

local function updateSpottedSpell()
    if spotted then
        types.Actor.activeSpells(self):add({
            id = "ernburglary_spotted",
            effects = {0},
            ignoreSpellAbsorption = true,
            ignoreReflect = true
        })
    else
        for _, spell in pairs(types.Actor.activeSpells(self)) do
            if spell.id == "ernburglary_spotted" then
                types.Actor.activeSpells(self):remove(spell.activeSpellId)
            end
        end
    end
end

infrequentMap:addCallback("spottedSpell", 0.8, updateSpottedSpell)


local bounty = 0

local function onUpdate(dt)
    -- this is not called when the game is paused.
    if lastCellID ~= self.cell.id then
        settings.debugPrint("cell changed from " .. tostring(lastCellID) .. " to " .. self.cell.id)
        
        -- run all checks since we don't want to lose info
        infrequentMap:callAll()

        -- now process cell change

        core.sendGlobalEvent(settings.MOD_NAME .. "onCellChange", {
            player = self,
            lastCellID = lastCellID,
            newCellID = self.cell.id
        })

        lastCellID = self.cell.id

        -- reset per-cell state
        spottedByActorID = {}
        spotted = false
        warnCooldownTimer = 0
        noWitnessesMessageReceivedCooldownTimer = 0
        noWitnessesMessageReceived = false
        trackInventory()

        return
    end

    local newBounty = types.Player.getCrimeLevel(self)
    if bounty < newBounty then
        settings.debugPrint("detected bounty increase")
        -- we got caught!
        -- run all checks since we don't want to lose info.
        -- hopefully, this executes before the red-handed global check.
        infrequentMap:callAll()
        
        -- notify global that we got caught.
        core.sendGlobalEvent(settings.MOD_NAME .. "onBountyIncreased", {
            player = self,
            oldBounty=bounty,
            newBounty=newBounty,
        })

        bounty = newBounty
        return
    end
    
    -- run periodically
    infrequentMap:onUpdate(dt)
end

local function UiModeChanged(data)
    if data.newMode == "Dialogue" then
        settings.debugPrint("in dialogue")
        -- this is for a pause control patch
        inDialogue = true
        bounty = types.Player.getCrimeLevel(self)
    elseif data.oldMode == "Dialogue" then
        settings.debugPrint("was in dialogue")
        inDialogue = false
        -- ensure we skip the NEXT item check.
        -- the item check is not done while paused in vanilla.
        forgiveNewItems = true

        -- detect bounty payoffs
        local newBounty = types.Player.getCrimeLevel(self)
        if (newBounty == 0) and (bounty ~= 0) then
            bounty = 0
            -- we paid off our bounty.
            core.sendGlobalEvent(settings.MOD_NAME .. "onPaidBounty", {
                player = self,
                previousBounty = bounty,
            })
        end
    end
end

local function setItemsAllowed(data)
    if (data == nil) or (data.allowed == nil) then
        error("bad data")
    end
    settings.debugPrint("overriding inDialogue to" .. tostring(data.allowed))
    inDialogue = data.allowed
end

return {
    eventHandlers = {
        [settings.MOD_NAME .. "showWantedMessage"] = showWantedMessage,
        [settings.MOD_NAME .. "showExpelledMessage"] = showExpelledMessage,
        [settings.MOD_NAME .. "showNoWitnessesMessage"] = showNoWitnessesMessage,
        [settings.MOD_NAME .. "setItemsAllowed"] = setItemsAllowed,
        UiModeChanged = UiModeChanged
    },
    engineHandlers = {
        onUpdate = onUpdate
    }
}

