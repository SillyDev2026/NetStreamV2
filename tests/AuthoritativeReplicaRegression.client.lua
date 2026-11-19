--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.4.0")
local State = NetStream.CreateReplica("AuthorityRegression", {Id = 46100, Fields = {"Coins", "Purchases", "Owner"}})
local Done = NetStream.Event("__AuthorityDone", {Id = 46104, Schema = {NetStream.Types.Bool}})
local started, finished = false, false
local denied = false
State:OnCommandResult(function(sequence, accepted, reason)
    if sequence == 2 then assert(not accepted and reason == "Denied"); denied = true end
end)
State:OnChanged(function(state, revision)
    if not state then return end
    assert(state.Owner == Players.LocalPlayer.UserId, "Received another player's state")
    assert(not pcall(function() state.Coins = 999999 end), "State getter is mutable")
    if not started then
        started = true
        assert(state.Coins == 100 and state.Purchases == 0)
        assert(State:SendCommand("Buy", {Item = 7}))
        assert(State:SendCommand("Buy", {Item = 99, Coins = 999999}))
    end
end)
task.spawn(function()
    local deadline = os.clock() + 30
    repeat
        task.wait(0.1)
        local state = State:Get()
        if state and state.Coins == 90 and state.Purchases == 1 and denied then
            assert(Done:FireServer(true))
            finished = true
            print("NetStream v4.4.0 authoritative replica CLIENT PASS")
            return
        end
    until os.clock() >= deadline
    assert(finished, "Authoritative replication timed out")
end)
