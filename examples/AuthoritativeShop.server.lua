--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local Shop = NetStream.CreateReplica("Shop", {Id = 46000, Fields = {"Coins", "Level"}})
local PRICE = 10
local MAX_LEVEL = 10

Shop:HandleCommand("BuyUpgrade", {
    Rate = 3,
    Burst = 2,
    Validate = function(player, payload, state)
        for key in pairs(payload) do if key ~= "UpgradeId" then return false end end
        return player.Parent == Players and payload.UpgradeId == 1 and state.Level < MAX_LEVEL and state.Coins >= PRICE
    end,
    Reduce = function(player, payload, state)
        state.Coins -= PRICE
        state.Level += 1
        return state
    end,
})

local function attach(player)
    if Shop:Get(player) or player.Parent ~= Players then return end
    -- Demo starting balance. In production attach only after your server profile loads.
    Shop:Attach(player, {Coins = 100, Level = 0})
end
Players.PlayerAdded:Connect(attach)
for _, player in ipairs(Players:GetPlayers()) do attach(player) end
