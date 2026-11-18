--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types

NetStream.ConfigureLowTraffic({HandshakeEnabled = false, PerformanceTelemetryEnabled = true})
assert(NetStream.GetVersion() == "4.3.0")
local Value = NetStream.State("__LowTrafficValue", {Id = 38661, Schema = {T.U16}, Coalesce = true, SuppressUnchanged = true, Compression = false})
local StepAck = NetStream.Event("__LowTrafficAck", {Id = 38662, Schema = {T.U8}, Compression = false})
local seen = 0
Value:Connect(function(value)
	seen += 1
	assert(seen <= 3, "Duplicate state was delivered despite suppression")
	assert(value == (if seen == 1 then 17 else 18), "Wrong low-traffic state or changed ordering")
	if seen == 3 then
		print("NetStream 4.3.0 LowTraffic CLIENT PASS", seen)
		assert(StepAck:FireServerNow(seen))
	end
end)

task.delay(10, function()
	assert(seen == 3, "State suppression regression timed out")
end)
