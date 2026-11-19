--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
NetStream.Configure({HandshakeEnabled = false})
local T = NetStream.Types
local Ready = NetStream.Event("__TicketReady", {Id = 36801, Schema = {T.Bool}, Compression = false})
local Offer = NetStream.Event("__TicketOffer", {Id = 36802, Schema = {T.U32}, Compression = false})
local Accept = NetStream.Event("__TicketAccept", {Id = 36803, Schema = {T.U32}, Compression = false, MaxPerSecond = 10, Burst = 10})
local Result = NetStream.Event("__TicketResult", {Id = 36804, Schema = {T.Bool}, Compression = false})
local Gate = NetStream.CreateActionGate({TTLSeconds = 15, MaxTicketsPerPlayer = 8})
local authorized = 0
local denied = 0
NetStream.SetServerPolicy(Ready, {Validate = function(_, ready) return ready == true end})
NetStream.SetServerPolicy(Accept, {Validate = function(_, id) return type(id) == "number" and id >= 1 end})
NetStream.RequireServerPolicies(true)
Ready:Connect(function(player)
    local id = Gate:Issue(player, "Equip", 17)
    assert(id, "Failed to issue test ticket")
    assert(Offer:FireClient(player, id))
end)
Accept:Connect(function(player, id)
    local accepted, result = Gate:Redeem(player, id, "Equip", function(_, itemId)
        assert(itemId == 17)
        authorized += 1
        return true
    end)
    if not accepted then denied += 1 end
    Result:FireClient(player, accepted and result == true)
end)
Players.PlayerRemoving:Connect(function(player) Gate:ClearPlayer(player) end)
task.delay(20, function()
    assert(authorized == 1 and denied == 2, "Unexpected one-use ticket counts")
    print("NetStream ticket SERVER PASS", authorized, denied)
end)
