shared.framework = 'esx' -- force inventory to think we are using esx legacy
lib.load('@es_extended.imports')

---@diagnostic disable-next-line: duplicate-set-field
function client.setPlayerData(key, value)
    PlayerData[key] = value
    ESX.SetPlayerData(key, value)
end

RegisterNetEvent('esx:onPlayerLogout', client.onLogout)

AddEventHandler('esx:setPlayerData', function(key, newValue)
    if not PlayerData.loaded or GetInvokingResource() ~= 'es_extended' then return end

    if key == 'job' then
        key = 'groups'
        local jobObj = { name = newValue.name, grade = newValue.grade }

        newValue = ESX.PlayerData.groups
        newValue[jobObj.name] = jobObj.grade
    elseif key == 'groups' then
        newValue[ESX.PlayerData.job.name] = ESX.PlayerData.job.grade
    end

    PlayerData[key] = newValue
    OnPlayerData(key, newValue)
end)

local Weapon = require 'modules.weapon.client'

RegisterNetEvent('esx_policejob:handcuff', function()
    PlayerData.cuffed = not PlayerData.cuffed
    LocalPlayer.state:set('invBusy', PlayerData.cuffed, true)

    if not PlayerData.cuffed then return end

    Weapon.Disarm()
end)

RegisterNetEvent('esx_policejob:unrestrain', function()
    PlayerData.cuffed = false
    LocalPlayer.state:set('invBusy', PlayerData.cuffed, true)
end)
