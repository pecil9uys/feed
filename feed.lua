
repeat task.wait() until game:IsLoaded() and game.Players.LocalPlayer

local Services = {
    RS = game:GetService("ReplicatedStorage"),
    Players = game:GetService("Players"),
    Http = game:GetService("HttpService")
}

Services.Player = Services.Players.LocalPlayer
Services.Events = Services.RS:WaitForChild("Events")

local Cache = {
    data = nil,
    last = 0,
    interval = 1
}

function Cache:get()
    if tick() - self.last > self.interval then
        local ok, res = pcall(function()
            return require(Services.RS.ClientStatCache):Get()
        end)
        if ok then
            self.data = res
            self.last = tick()
        end
    end
    return self.data
end

local Utils = {}

function Utils.deepFind(tbl, key, seen)
    seen = seen or {}
    if seen[tbl] then return end
    seen[tbl] = true

    for k, v in pairs(tbl) do
        if k == key then return v end
        if type(v) == "table" then
            local f = Utils.deepFind(v, key, seen)
            if f then return f end
        end
    end
end

local ITEM_KEYS = {
    ["Moon Charm"] = "MoonCharm",
    ["Pineapple"] = "Pineapple",
    ["Strawberry"] = "Strawberry",
    ["Blueberry"] = "Blueberry",
    ["Sunflower Seed"] = "SunflowerSeed",
    ["Treat"] = "Treat",
    ["Silver"] = "Silver",
    ["Gold"] = "Gold",
    ["Diamond"] = "Diamond",
    ["Star Egg"] = "Star"
}

local BOND_ITEMS = {
    { Name = "Moon Charm", Value = 250 },
    { Name = "Pineapple", Value = 50 },
    { Name = "Strawberry", Value = 50 },
    { Name = "Blueberry", Value = 50 },
    { Name = "Sunflower Seed", Value = 50 },
    { Name = "Treat", Value = 10 }
}

local Inventory = {}

function Inventory:get()
    local cache = Cache:get()
    if not cache or not cache.Eggs then return {} end
    local out = {}
    for name, key in pairs(ITEM_KEYS) do
        out[name] = tonumber(cache.Eggs[key]) or 0
    end
    return out
end

local Bees = {}

function Bees:getAll()
    local cache = Cache:get()
    local out = {}
    if not cache or not cache.Honeycomb then return out end

    for cx, col in pairs(cache.Honeycomb) do
        for cy, bee in pairs(col) do
            if bee and bee.Lvl then
                local x = tonumber(tostring(cx):match("%d+"))
                local y = tonumber(tostring(cy):match("%d+"))
                if x and y then
                    out[#out+1] = { col = x, row = y, level = bee.Lvl }
                end
            end
        end
    end
    return out
end

function Bees:getTop(list, n)
    table.sort(list, function(a,b)
        return a.level > b.level
    end)
    local out = {}
    for i = 1, math.min(n, #list) do
        out[i] = list[i]
    end
    return #out == n and out or nil
end

function Bees:count()
    return #self:getAll()
end

function Bees:findEmpty()
    local cache = Cache:get()
    if not cache or not cache.Honeycomb then return nil end

    for cx, col in pairs(cache.Honeycomb) do
        for cy, bee in pairs(col) do
            if not bee or not bee.Type then
                local x = tonumber(tostring(cx):match("%d+"))
                local y = tonumber(tostring(cy):match("%d+"))
                if x and y then
                    return x, y
                end
            end
        end
    end
end

local function sendWebhook(title, fields)
    local data = {
        content = "<@" .. tostring(getgenv().Config["Ping Id"]) .. ">",
        embeds = {{
            title = title,
            color = 65280,
            fields = fields,
            footer = { text = "made by Jung Ganmyeon" }
        }}
    }

    pcall(function()
        request({
            Url = getgenv().Config["Link Wh"],
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = Services.Http:JSONEncode(data)
        })
    end)
end

local function getBondLeft(col, row)
    local result
    pcall(function()
        result = Services.Events.GetBondToLevel:InvokeServer(col, row)
    end)

    if type(result) == "number" then return result end
    if type(result) == "table" then
        for _, v in pairs(result) do
            if type(v) == "number" then return v end
        end
    end
end

local function buyTreat()
    local cfg = getgenv().Config["Auto Feed"]
    if not cfg or not cfg["Auto Buy Treat"] then return end

    local honeyVal = Services.Player
        and Services.Player:FindFirstChild("CoreStats")
        and Services.Player.CoreStats:FindFirstChild("Honey")

    if not honeyVal or honeyVal.Value < 10000000 then return end

    local args = {
        [1] = "Purchase",
        [2] = {
            ["Type"] = "Treat",
            ["Amount"] = 1000,
            ["Category"] = "Eggs"
        }
    }

    pcall(function()
        Services.Events.ItemPackageEvent:InvokeServer(unpack(args))
    end)
end

local function feedBond(col, row, bondLeft)
    buyTreat()
    local inventory = Inventory:get()
    local remaining = bondLeft
    local cfg = getgenv().Config["Auto Feed"]

    for _, item in ipairs(BOND_ITEMS) do
        if remaining <= 0 then break end
        if cfg["Bee Food"][item.Name] then
            local have = inventory[item.Name] or 0
            if have > 0 then
                local need = math.ceil(remaining / item.Value)
                local use = math.min(have, need)
                if use > 0 then
                    local serverName = ITEM_KEYS[item.Name] or item.Name
                    local args = {
                        [1] = col,
                        [2] = row,
                        [3] = serverName,
                        [4] = use,
                        [5] = false
                    }
                    pcall(function()
                        Services.Events.ConstructHiveCellFromEgg:InvokeServer(unpack(args))
                    end)
                    remaining -= (use * item.Value)
                    task.wait(3)
                end
            end
        end
    end
end

local FEED_DONE = false
local QUEST_DONE = false
local PRINTER_LAST = 0
local lastReported = {}

local function checkStarSign()
    local cache = Cache:get()
    if not cache then return end

    local received = Utils.deepFind(cache, "Received")
    if not received then return end

    for id, amt in pairs(received) do
        local name = tostring(id)
        if name:lower():find("star sign") then
            if not lastReported[name] or amt > lastReported[name] then
                sendWebhook("Star Sign collected!!!", {
                    { name = "Player", value = Services.Player.Name, inline = false },
                    { name = "Star Sign", value = name, inline = false },
                    { name = "Amount", value = tostring(amt), inline = false }
                })
                lastReported[name] = amt
            end
        end
    end
end

local function checkQuest()
    if QUEST_DONE then return end
    if getgenv().Config["Check Quest"] == false then return end

    local cache = Cache:get()
    if not cache then return end

    local completed = Utils.deepFind(cache, "Completed")
    if not completed then return end

    for _, name in pairs(completed) do
        if tostring(name) == "Seven To Seven" then
            sendWebhook("Quest Seven To Seven done!!!!!", {
                { name = "Player", value = Services.Player.Name, inline = false },
                { name = "Bee Count", value = tostring(Bees:count()), inline = false }
            })
            QUEST_DONE = true
            break
        end
    end
end

local function autoFeedStep()
    local cfg = getgenv().Config["Auto Feed"]
    if not cfg or not cfg["Enable"] or FEED_DONE then return end

    local bees = Bees:getAll()
    local group = Bees:getTop(bees, cfg["Bee Amount"])
    if not group then return end

    local done = true
    for _, b in pairs(group) do
        if b.level < cfg["Bee Level"] then
            done = false
            break
        end
    end

    if done then
        FEED_DONE = true
        return
    end

    table.sort(group, function(a,b)
        return a.level < b.level
    end)

    for _, b in pairs(group) do
        if b.level < cfg["Bee Level"] then
            local bondLeft = getBondLeft(b.col, b.row)
            if bondLeft and bondLeft > 0 then
                feedBond(b.col, b.row, bondLeft)
                break
            end
        end
    end
end

local function autoHatchStep()
    local cfg = getgenv().Config["Auto Hatch"]
    if not cfg or not cfg["Enable"] then return end

    local eggs = Inventory:get()
    local col, row = Bees:findEmpty()
    if not col or not row then return end

    for _, egg in ipairs(cfg["Egg Hatch"]) do
        if (eggs[egg] or 0) > 0 then
            local args = {
                [1] = col,
                [2] = row,
                [3] = egg,
                [4] = 1,
                [5] = false
            }
            pcall(function()
                Services.Events.ConstructHiveCellFromEgg:InvokeServer(unpack(args))
            end)
            task.wait(3)
            break
        end
    end
end

local function autoPrinterStep()
    local cfg = getgenv().Config["Auto Printer"]
    if not cfg or not cfg["Enable"] then return end

    if tick() - PRINTER_LAST < 10 then return end

    local inv = Inventory:get()
    if (inv["Star Egg"] or 0) > 0 then
        PRINTER_LAST = tick()
        pcall(function()
            Services.Events.StickerPrinterActivate:FireServer("Star Egg")
        end)

        sendWebhook("Star Egg roll printer!!!", {
            { name = "Player", value = Services.Player.Name, inline = false }
        })
    end
end

while true do
    checkStarSign()
    checkQuest()
    autoFeedStep()
    autoHatchStep()
    autoPrinterStep()
    task.wait(5)
end
