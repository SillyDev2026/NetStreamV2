--!strict
-- Run with the matching client in a fresh Studio session with two players.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
local State = NetStream.CreateReplica("AuthorityRegression", {Id = 46100, Fields = {"Coins", "Purchases", "Owner"}})
State:HandleCommand("Buy", {
    Validate = function(player, payload, state)
        for key in pairs(payload) do if key ~= "Item" then return false end end
        return payload.Item == 7 and state.Coins >= 10 and state.Purchases == 0 and state.Owner == player.UserId
    end,
    Reduce = function(player, payload, state) state.Coins -= 10; state.Purchases += 1; return state end,
})
local Done = NetStream.Event("__AuthorityDone", {Id = 46104, Schema = {NetStream.Types.Bool}, MaxPerSecond = 1, Burst = 1})
Done:Connect(function(player, ok)
    local state = State:Get(player)
    assert(ok and state and state.Coins == 90 and state.Purchases == 1 and state.Owner == player.UserId)
    print("NetStream v4.4.0 authoritative replica SERVER PASS", player.UserId)
end)
local function attach(player)
    if not State:Get(player) and player.Parent == Players then State:Attach(player, {Coins = 100, Purchases = 0, Owner = player.UserId}) end
end
Players.PlayerAdded:Connect(attach)
for _, player in ipairs(Players:GetPlayers()) do attach(player) end
