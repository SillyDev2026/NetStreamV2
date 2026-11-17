--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.0.1")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
local State = NetStream.State("__NSAtomicState", {Id = 35801, Schema = {T.U8}, Compression = false})
local Ack = NetStream.Event("__NSAtomicAck", {Id = 35802, Schema = {T.U8}, Compression = false})
local received = 0
State:Connect(function(player, value)
    received += 1
    assert(value == 25, "A malformed packet was dispatched before tail validation")
    assert(received == 1, "A malformed packet dispatched more than one message")
    local snapshot = NetStream.GetStateSnapshot(player)
    assert(snapshot[State.Id] == 25, "Malformed packet unexpectedly changed persistent state")
    local stats = NetStream.GetStats()
    assert(stats.BitFrameAtomicRejectedPackets >= 1, "Malformed packet did not trigger atomic rejection")
    assert(stats.BitFrameAtomicDiscardedActions >= 1, "Malformed packet did not discard staged state")
    assert(Ack:FireClientNow(player, 1), "Atomic packet ACK failed")
end)
print("NetStream v4.0.1 atomic packet server ready")
