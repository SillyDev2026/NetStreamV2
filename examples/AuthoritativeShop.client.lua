--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local Shop = NetStream.CreateReplica("Shop", {Id = 46000, Fields = {"Coins", "Level"}})

Shop:OnChanged(function(state, revision)
    if not state then print("Shop unavailable"); return end
    print("Server coins:", state.Coins, "Level:", state.Level, "Revision:", revision)
end)
Shop:OnCommandResult(function(sequence, accepted, reason)
    print("Purchase request:", sequence, accepted, reason)
end)
UserInputService.InputBegan:Connect(function(input, processed)
    if processed or input.KeyCode ~= Enum.KeyCode.B then return end
    local queued, sequenceOrReason = Shop:SendCommand("BuyUpgrade", {UpgradeId = 1})
    if not queued then warn("Purchase was not queued:", sequenceOrReason) end
end)
