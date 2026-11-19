--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
NetStream.Configure({HandshakeEnabled = false})
local T = NetStream.Types
local Ready = NetStream.Event("__TicketReady", {Id = 36801, Schema = {T.Bool}, Compression = false})
local Offer = NetStream.Event("__TicketOffer", {Id = 36802, Schema = {T.U32}, Compression = false})
local Accept = NetStream.Event("__TicketAccept", {Id = 36803, Schema = {T.U32}, Compression = false})
local Result = NetStream.Event("__TicketResult", {Id = 36804, Schema = {T.Bool}, Compression = false})
local approved = 0
local rejected = 0
Result:Connect(function(ok)
    if ok then approved += 1 else rejected += 1 end
    if approved + rejected == 3 then
        assert(approved == 1 and rejected == 2, "Replay or forged ID bypassed server")
        print("NetStream ticket CLIENT PASS", approved, rejected)
    end
end)
Offer:Connect(function(id)
    assert(Accept:FireServer(id))
    assert(Accept:FireServer(id))
    assert(Accept:FireServer(id + 1))
end)
assert(Ready:FireServer(true))
task.delay(20, function() assert(approved == 1 and rejected == 2, "Ticket regression timed out") end)
