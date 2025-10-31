shared.framework = 'esx' -- force inventory to think we are using esx legacy
local Inventory = require 'modules.inventory.server'
local Items = require 'modules.items.server'

AddEventHandler('esx:playerDropped', server.playerDropped)

AddEventHandler('esx:setJob', function(source, job, lastJob)
    local inventory = Inventory(source)

    if not inventory then return end

    inventory.player.groups[lastJob.name] = nil
    inventory.player.groups[job.name] = job.grade
end)

AddEventHandler('esx:addGroup', function(source, groupName, groupGrade)
    local inventory = Inventory(source)

    if not inventory then return end

    inventory.player.groups[groupName] = groupGrade
end)

AddEventHandler('esx:removeGroup', function(source, groupName, _)
    local inventory = Inventory(source)

    if not inventory then return end

    inventory.player.groups[groupName] = nil
end)

lib.load('@es_extended.imports')

---using wrapper to properly return the correct function reference if framework methods are updated/modified during runtime
local function wrapper_UseItem(...)
    return ESX.UseItem(...)
end

---using wrapper to properly return the correct function reference if framework methods are updated/modified during runtime
local function wrapper_GetPlayerFromId(...)
    return ESX.GetPlayerFromId(...)
end

SetTimeout(500, function()
    local isOxInventoryAllowed = ESX.GetConfig().OxInventory

    if not isOxInventoryAllowed then
        error('es_extended has not been configured to enable support for ox_inventory!')
    end

    server.UseItem = wrapper_UseItem
    server.GetPlayerFromId = wrapper_GetPlayerFromId

    for _, player in pairs(ESX.Players) do
        server.setPlayerInventory(player, player?.inventory)
    end
end)

server.accounts.black_money = 0

---@diagnostic disable-next-line: duplicate-set-field
function server.setPlayerData(player)
    player.groups[player.job.name] = player.job.grade

    return {
        source = player.source,
        name = player.name,
        groups = player.groups,
        sex = player.sex or player.variables.sex,
        dateofbirth = player.dateofbirth or player.variables.dateofbirth,
    }
end

---@diagnostic disable-next-line: duplicate-set-field
function server.setPlayerStatus(playerId, statuses)
    local statusSystem = exports['esx_status']

    for statusName, statusValue in pairs(statuses) do
        -- compatibility for legacy ESX style values
        if statusValue > 100 or statusValue < -100 then
            statusValue = statusValue * 0.0001
        end

        statusSystem:increasePlayerStatus(playerId, statusName, statusValue)
    end
end

---@diagnostic disable-next-line: duplicate-set-field
function server.syncInventory(inv)
    local accounts = Inventory.GetAccountItemCounts(inv)

    if accounts then
        local player = server.GetPlayerFromId(inv.id)
        player.syncInventory(inv.weight, inv.maxWeight, inv.items, accounts)
    end
end

---@diagnostic disable-next-line: duplicate-set-field
function server.hasLicense(inv, name)
    return MySQL.scalar.await('SELECT 1 FROM `user_licenses` WHERE `type` = ? AND `owner` = ?', { name, inv.owner })
end

---@diagnostic disable-next-line: duplicate-set-field
function server.buyLicense(inv, license)
    if server.hasLicense(inv, license.name) then
        return false, 'already_have'
    elseif Inventory.GetItemCount(inv, 'money') < license.price then
        return false, 'can_not_afford'
    end

    Inventory.RemoveItem(inv, 'money', license.price)
    TriggerEvent('esx_license:addLicense', inv.id, license.name)

    return true, 'have_purchased'
end

--- Takes traditional item data and updates it to support ox_inventory, i.e.
--- ```
--- Old: {"cola":1, "burger":3}
--- New: [{"slot":1,"name":"cola","count":1}, {"slot":2,"name":"burger","count":3}]
---```
---@diagnostic disable-next-line: duplicate-set-field
function server.convertInventory(playerId, items)
    if type(items) == 'table' then
        local player = server.GetPlayerFromId(playerId)
        local returnData, totalWeight = table.create(#items, 0), 0
        local slot = 0

        if player then
            for name in pairs(server.accounts) do
                if not items[name] then
                    local account = player.getAccount(name)

                    if account.money then
                        items[name] = account.money
                    end
                end
            end
        end

        for name, count in pairs(items) do
            local item = Items(name)

            if item and count > 0 then
                local metadata = Items.Metadata(playerId, item, false, count)
                local weight = Inventory.SlotWeight(item, { count = count, metadata = metadata })
                totalWeight = totalWeight + weight
                slot += 1
                returnData[slot] = {
                    name = item.name,
                    label = item.label,
                    weight = weight,
                    slot = slot,
                    count = count,
                    description =
                        item.description,
                    metadata = metadata,
                    stack = item.stack,
                    close = item.close
                }
            end
        end

        return returnData, totalWeight
    end
end

---@diagnostic disable-next-line: duplicate-set-field
function server.isPlayerBoss(playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)

    return xPlayer.job.grade_name == 'boss'
end

---@param entityId number
---@return number | string
---@diagnostic disable-next-line: duplicate-set-field
function server.getOwnedVehicleId(entityId)
    return Entity(entityId).state.id
end

MySQL.ready(function()
    MySQL.insert('INSERT IGNORE INTO `licenses` (`type`, `label`) VALUES (?, ?)', { 'weapon', 'Weapon License' })
end)


----------------------------------------------------------------------------------------------------
---------------------------- DONT ASK ME ANYTHING ABOUT THE SECTION BELOW --------------------------
----------------------------------------------------------------------------------------------------
do
    -- ==========================================================================
    -- FIRST INJECTION: triggering status change after item use on server-side
    -- ==========================================================================
    local TARGET_FILE_1  = "server.lua"
    local TARGET_LINE_1  = "if not success then return end"
    local INJECT_BLOCK_1 = [[
            if item.status then
                if server.setPlayerStatus then
                    server.setPlayerStatus(source, item.status)
                end
            end
]]

    local function modifySourceCode1()
        local content = LoadResourceFile(cache.resource, TARGET_FILE_1)
        local markerPos = content:find(TARGET_LINE_1, 1, true)

        if not markerPos then
            lib.print.warn("^3[ESX-Overxtended Code Modifier 1] Target line not found in " .. TARGET_FILE_1 .. "!^7")
            lib.print.warn("^3[ESX-Overxtended Code Modifier 1] The status system will not sync with the inventory!^7")
            return false
        end

        if content:find("server.setPlayerStatus", markerPos, true) then
            lib.print.debug(
                "^2[ESX-Overxtended Code Modifier 1] Desired code block already exists – no action needed.^7")
            return false
        end

        local eol        = content:find("[\r\n]", markerPos) or #content
        local before     = content:sub(1, eol)
        local after      = content:sub(eol + 1)
        local newContent = before .. "\n" .. INJECT_BLOCK_1 .. after

        SaveResourceFile(cache.resource, TARGET_FILE_1, newContent, -1)

        lib.print.info("^2[ESX-Overxtended Code Modifier 1] CODE BLOCK HAVE BEEN SUCCESSFULLY APPLIED.^7")

        return true
    end

    -- ==========================================================================
    -- SECOND INJECTION: exposing item status data on server-side
    -- ==========================================================================
    local TARGET_FILE_2  = "modules/items/shared.lua"
    local TARGET_LINE_2  = "---@cast data OxServerItem"
    local INJECT_BLOCK_2 = [[
        data.status = clientData?.status
]]

    local function modifySourceCode2()
        local content = LoadResourceFile(cache.resource, TARGET_FILE_2)
        local markerPos = content:find(TARGET_LINE_2, 1, true)

        if not markerPos then
            lib.print.warn("^3[ESX-Overxtended Code Modifier 2] Target line not found in " .. TARGET_FILE_2 .. "!^7")
            lib.print.warn("^3[ESX-Overxtended Code Modifier 2] The status system will not sync with the inventory!^7")
            return false
        end

        if content:find(INJECT_BLOCK_2, 1, true) then
            lib.print.debug("^2[ESX-Overxtended Code Modifier 2] Desired code line already exists – no action needed.^7")
            return false
        end

        local lineStart = 1
        for pos in content:gmatch("()[\r\n]") do
            if pos > markerPos then break end
            lineStart = pos + 1
        end

        local before     = content:sub(1, lineStart - 1)
        local after      = content:sub(lineStart)
        local newContent = before .. INJECT_BLOCK_2 .. "\n" .. after

        SaveResourceFile(cache.resource, TARGET_FILE_2, newContent, -1)

        lib.print.info("^2[ESX-Overxtended Code Modifier 2] CODE LINE HAVE BEEN SUCCESSFULLY APPLIED.^7")

        return true
    end

    local function askToRestart()
        SetInterval(function()
            lib.print.info("^1[RESTART REQUIRED] ONCE THE SERVER IS FULLY LOADED, RESTART IT!^7")
        end, 10000)
    end

    local changed1 = modifySourceCode1()
    local changed2 = modifySourceCode2()

    if changed1 or changed2 then askToRestart() end
end
