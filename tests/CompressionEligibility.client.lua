--!strict
-- Standalone LocalScript in StarterPlayerScripts; pair with CompressionEligibility.server.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.3.31")
NetStream.Configure({CompressionEnabled = true, CompressionCpuBudgetEnabled = false, CompressionMinStringBytes = 6})
local Payload = NetStream.Event("__NSEligibility", {Id = 35311})
local Ack = NetStream.Event("__NSEligibilityAck", {Id = 35312, Compression = false})
local done = false
Ack:Connect(function(n)
    assert(n == 96, "Some messages did not reach server")
    local stats = NetStream.GetCompressionStats()
    assert(stats.EligibilityShortScans >= 96, "Short eligibility path was not reached")
    assert(stats.EligibilityShortSkips >= 64, "Ineligible payloads did not use allocation-free rejection")
    local counters = NetStream.GetStats()
    assert(counters.DecodeErrors == 0, "Compressed/dynamic packet decode failed")
    done = true
    print("NetStream v2.3.31 compression short-path PASS", stats.EligibilityShortScans, stats.EligibilityShortSkips)
end)
for i = 1, 64 do assert(Payload:FireServer(i, "unique" .. i, i), "Unique payload enqueue failed") end
local repeated = string.rep("match", 8)
for i = 65, 96 do assert(Payload:FireServer(i, repeated, repeated), "Repeated payload enqueue failed") end
task.delay(40, function() assert(done, "Compression eligibility regression timed out") end)
