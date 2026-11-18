--!strict
-- StarterPlayerScripts; pair with RPCConcurrencyRegression.server.lua in a fresh Studio Play session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.0")
NetStream.Configure({HandshakeEnabled = false, BandwidthGovernorEnabled = false, MaxConcurrentIncomingCalls = 8, MaxConcurrentIncomingCallsPerPlayer = 2, MaxIncomingCallsPerSecond = 1000, MaxGlobalIncomingCallsPerSecond = 2000, CallTimeout = 3, TransportFastFlushEnabled = true})
local T = NetStream.Types
local Busy = NetStream.Function("__NSRPCBusy43", {Id = 44370, Schema = {T.U16}, Compression = false})
local Report = NetStream.Event("__NSRPCReport43", {Id = 44371, Schema = {T.U16, T.U16}, Compression = false})
local Ack = NetStream.Event("__NSRPCAck43", {Id = 44372, Schema = {T.Bool}, Compression = false})
local finished = false
Ack:Connect(function(ack)
    assert(ack == true, "RPC concurrency acknowledgement malformed")
    task.spawn(function()
        local ok, value = pcall(function() return Busy:InvokeServerNow(65000) end)
        assert(ok and value == 65000, "RPC did not recover after sustained in-flight rejection")
        finished = true
        print("NetStream v4.3.0 RPC concurrency CLIENT PASS")
    end)
end)
task.wait(0.5)
local completed = 0
local successful = 0
local rejected = 0
for i = 1, 16 do
    task.spawn(function()
        local ok, value = pcall(function() return Busy:InvokeServerNow(i) end)
        if ok then assert(value == i, "RPC response was corrupted"); successful += 1 else rejected += 1 end
        completed += 1
        if completed == 16 then assert(Report:FireServerNow(successful, rejected), "RPC summary enqueue failed") end
    end)
end
task.delay(20, function() assert(finished, "RPC concurrency test timed out") end)
