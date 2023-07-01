local ESX = exports.es_extended:getSharedObject()
local utils = require 'client.utils'
local groups = { 'job', 'job2' }
local playerGroups = {}
local playerItems = utils.getItems()
local usingOxInventory = utils.hasExport('ox_inventory.Items')

local function setPlayerData(playerData)
    table.wipe(playerGroups)
    table.wipe(playerItems)

    for i = 1, #groups do
        local group = groups[i]
        local data = playerData[group]

        if data then
            playerGroups[group] = data
        end
    end

    if usingOxInventory or not playerData.inventory then return end

    for _, v in pairs(playerData.inventory) do
        if v.count > 0 then
            playerItems[v.name] = v.count
        end
    end
end

if ESX.PlayerLoaded then
    setPlayerData(ESX.PlayerData)
end

AddEventHandler('esx:playerLoaded', function(data)
    setPlayerData(data)
end)

AddEventHandler('esx:setJob', function(job)
    playerGroups.job = job
end)

AddEventHandler('esx:setJob2', function(job)
    playerGroups.job2 = job
end)

AddEventHandler('esx:addInventoryItem', function(name, count)
    playerItems[name] = count
end)

AddEventHandler('esx:removeInventoryItem', function(name, count)
    playerItems[name] = count
end)

---@diagnostic disable-next-line: duplicate-set-field
function utils.hasPlayerGotGroup(filter)
    local _type = type(filter)
    for i = 1, #groups do
        local group = groups[i]

        if _type == 'string' then
            local data = playerGroups[group]

            if filter == data?.name then
                return true
            end
        elseif _type == 'table' then
            local tabletype = table.type(filter)

            if tabletype == 'hash' then
                for name, grade in pairs(filter) do
                    local data = playerGroups[group]

                    if data?.name == name and grade <= data.grade then
                        return true
                    end
                end
            elseif tabletype == 'array' then
                for j = 1, #filter do
                    local name = filter[j]
                    local data = playerGroups[group]

                    if data?.name == name then
                        return true
                    end
                end
            end
        end
    end
end
