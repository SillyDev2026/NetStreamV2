--!strict
-- Pair with MixedFixedSchemaRegression.server.lua; run alone in a Studio Play session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.2.0")
NetStream.Configure({HandshakeEnabled = false, BandwidthGovernorEnabled = false, TransportFastFlushEnabled = false, TransportBatchWindowSeconds = 0.05})
local T = NetStream.Types
local Mixed = NetStream.Event("__NSMixedFixed42", {Id = 36420, Compression = false, Schema = {T.Bool, T.U8, T.U16, T.I16, T.U32, T.I32, T.Bool, T.U8, T.U16, T.I16, T.U32, T.I32}})
local Ack = NetStream.Event("__NSMixedFixedAck42", {Id = 36421, Compression = false})
local echoes = 0
local serverReads = nil
local completed = false
local function verify(i, a, b, c, d, e, f, g, h, j, k, l, m)
    assert(a == (i % 2 == 0) and b == 0 and c == 65535 and d == -32768, "Mixed fixed prefix corrupted")
    assert(e == 4294967295 and f == -2147483648 and g == (i % 2 == 1) and h == 255, "Mixed fixed boundaries corrupted")
    assert(j == i and k == -i and l == 2147483648 and m == 2147483647, "Mixed fixed signed/unsigned suffix corrupted")
end
local function finish()
    if echoes ~= 40 or not serverReads or completed then return end
    local stats = NetStream.GetStats()
    assert(serverReads >= 40 and stats.BitFrameFixedSchemaFastReads >= 40, "Mixed reader fast paths not used")
    assert(stats.BitFrameFixedSchemaFastWrites >= 40, "Mixed writer fast path not used")
    assert(stats.PackedSchemaRunAppends > 0, "12-field packed runs were not batched")
    assert(stats.DecodeErrors == 0, "Client mixed packet decode errors")
    completed = true
    print("NetStream v4.2.0 mixed fixed schema regression PASS", stats.BitFrameFixedSchemaFastWrites, stats.BitFrameFixedSchemaFastReads)
end
Mixed:Connect(function(a, b, c, d, e, f, g, h, j, k, l, m)
    echoes += 1
    assert(j == echoes, "Mixed echo FIFO order changed")
    verify(echoes, a, b, c, d, e, f, g, h, j, k, l, m)
    finish()
end)
Ack:Connect(function(reads)
    serverReads = reads
    finish()
end)
for i = 1, 40 do
    assert(Mixed:FireServer(i % 2 == 0, 0, 65535, -32768, 4294967295, -2147483648, i % 2 == 1, 255, i, -i, 2147483648, 2147483647), "Mixed request enqueue failed")
end
task.delay(40, function() assert(completed, "Mixed fixed schema regression timed out") end)
