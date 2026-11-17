--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types

NetStream.ConfigureLowTraffic({HandshakeEnabled = false, BandwidthGovernorEnabled = false, PacketSizeAuditEnabled = true, TransportFastFlushEnabled = false})
assert(NetStream.GetVersion() == "4.1.1")

local Ping32 = NetStream.Event("__PacketAuditU32", {Id = 1001, Schema = {T.U32}, Priority = "Normal", Compression = false})
local Ping16 = NetStream.Event("__PacketAuditU16", {Id = 1002, Schema = {T.U16}, Priority = "Normal", Compression = false})
local PingShort = NetStream.Event("__PacketAuditShort", {Id = 1, Schema = {T.U16}, Priority = "Normal", Compression = false})

local function checkPacket(expectedBytes: number, expectedPayloadBits: number, expectedRouteBits: number, expectedRunBits: number, expectedMessages: number)
	local report = NetStream.GetPacketSizeAudit()
	local last = report.LastPacket
	assert(report.Enabled and last.PhysicalBytes == expectedBytes, "Unexpected physical packet byte length")
	assert(last.PayloadBits == expectedPayloadBits, "Payload bit accounting mismatch")
	assert(last.RouteIdBits == expectedRouteBits and last.RunCountBits == expectedRunBits, "Route or run metadata mismatch")
	assert(last.LogicalMessages == expectedMessages and last.Packets == 1, "Logical message accounting mismatch")
	assert(last.PresenceBits + last.KindBits + last.RouteIdBits + last.RequestIdBits + last.RunMarkerBits + last.RunCountBits + last.PayloadBits + last.EndBits == last.UsefulBits, "Packet audit categories do not balance")
	assert(last.UsefulBits + last.PaddingBits == last.PhysicalBits, "Packet audit padding does not balance")
	print("Packet audit PASS", expectedMessages, "messages", expectedBytes, "bytes", "payload", last.PayloadBits, "metadata", last.UsefulBits - last.PayloadBits)
end

task.wait(1)
NetStream.ResetStats()
assert(Ping32:FireServerNow(65538))
checkPacket(7, 32, 16, 0, 1)
assert(Ping16:FireServerNow(17))
checkPacket(5, 16, 16, 0, 1)
assert(PingShort:FireServerNow(19))
checkPacket(4, 16, 8, 0, 1)

for id = 18, 25 do
	assert(Ping16:FireServer(id))
end
assert(NetStream.FlushTarget(), "Force flush did not drain packet")
checkPacket(20, 128, 16, 8, 8)

local totals = NetStream.GetPacketSizeAudit().Totals
assert(totals.Packets == 4 and totals.LogicalMessages == 11, "Packet audit must count only sent packets")
assert(totals.PhysicalBytes == 36, "Expected 7 + 5 + 4 + 20 total bytes")
print("NetStream 4.1.1 Packet Audit CLIENT PASS", "sent", totals.PhysicalBytes, "bytes", "messages", totals.LogicalMessages)
