--!optimize 2
-- Same-process baseline/new comparison. The baseline helpers reproduce the
-- pre-patch native Writer.new/Reader.new Codec behavior, not Roblox network RTT.
local net = loadNetStream()
local hooks = net.__test
net.Configure({CompressionEnabled = false})
local payload = {Count = 77, Ready = false, Tags = {"repeat", "repeat", "repeat"}}
local embedded = buffer.fromstring("payload-key-123456")
local oldSmall = hooks.baselineCodecEncode(7, false, "abc")
local newSmall = net.Codec.Encode(7, false, "abc")
local oldMedium = hooks.baselineCodecEncode(999999, -123, 123.25, payload, embedded)
local newMedium = net.Codec.Encode(999999, -123, 123.25, payload, embedded)
assert(buffer.tostring(oldSmall) == buffer.tostring(newSmall), "Small native packet bytes changed")
assert(buffer.tostring(oldMedium) == buffer.tostring(newMedium), "Medium native packet bytes changed")
local function measure(count, callback)
    for _ = 1, 1000 do callback() end
    local best = nil
    for _ = 1, 4 do
        local start = os.clock()
        for _ = 1, count do callback() end
        local elapsed = os.clock() - start
        if best == nil or elapsed < best then best = elapsed end
    end
    return best
end
local function compare(name, count, oldCall, newCall)
    local oldSeconds = measure(count, oldCall)
    local newSeconds = measure(count, newCall)
    local improvement = (oldSeconds - newSeconds) * 100 / oldSeconds
    print(string.format("PACKER_COMPARE %-19s old=%.1f ns/op new=%.1f ns/op improvement=%.1f%%", name, oldSeconds / count * 1e9, newSeconds / count * 1e9, improvement))
    return improvement
end
local r1 = compare("small-encode", 35000,
    function() assert(buffer.len(hooks.baselineCodecEncode(7, false, "abc")) == buffer.len(oldSmall)) end,
    function() assert(buffer.len(net.Codec.Encode(7, false, "abc")) == buffer.len(newSmall)) end)
local r2 = compare("small-decode", 35000,
    function() local a, b, c = hooks.baselineCodecDecode(oldSmall); assert(a == 7 and b == false and c == "abc") end,
    function() local a, b, c = net.Codec.Decode(newSmall); assert(a == 7 and b == false and c == "abc") end)
local r3 = compare("medium-encode", 9000,
    function() assert(buffer.len(hooks.baselineCodecEncode(999999, -123, 123.25, payload, embedded)) == buffer.len(oldMedium)) end,
    function() assert(buffer.len(net.Codec.Encode(999999, -123, 123.25, payload, embedded)) == buffer.len(newMedium)) end)
local r4 = compare("medium-decode", 9000,
    function() local a,b,c,d,e = hooks.baselineCodecDecode(oldMedium); assert(a == 999999 and b == -123 and d.Count == 77 and buffer.tostring(e) == "payload-key-123456") end,
    function() local a,b,c,d,e = net.Codec.Decode(newMedium); assert(a == 999999 and b == -123 and d.Count == 77 and buffer.tostring(e) == "payload-key-123456") end)
local stats = net.GetStats()
assert(stats.WriterPoolHits >= 1000 and stats.ReaderPoolHits >= 1000, "Optimized Codec failed to pool wrapper objects")
print(string.format("PACKER_COMPARE pool writer=%d reader=%d args=%d", stats.WriterPoolHits, stats.ReaderPoolHits, stats.ArgsPoolHits))
print("PASS PACKER_COMPARE: exact output parity and same-process public Codec A/B CPU profile")
