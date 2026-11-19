--!optimize 2
-- Identical cross-branch profile: run on baseline and optimized heads separately.
-- Reports independent CPU timings and source pool hit deltas; no network RTT claims.
local net = loadNetStream()
local codec = net.Codec
local hooks = net.__test
local source = buffer.fromstring("shared:payload")
local medium = {Count = 777, Enabled = false, Tags = {"repeat-word", "repeat-word", "repeat-word"}}
local smallPacket = codec.Encode(7, false, "abc")
local mediumPacket = codec.Encode(999999, -123, 123.25, medium, source)
local function hex(data)
    local out = table.create(buffer.len(data))
    for i = 0, buffer.len(data) - 1 do out[i + 1] = string.format("%02x", buffer.readu8(data, i)) end
    return table.concat(out)
end
print("PACKER_GOLDEN small=" .. hex(smallPacket))
print("PACKER_GOLDEN medium=" .. hex(mediumPacket))
local function bench(label, count, run)
    for i = 1, 700 do run() end
    local fastest = nil
    for sample = 1, 3 do
        local started = os.clock()
        for i = 1, count do run() end
        local elapsed = os.clock() - started
        if not fastest or elapsed < fastest then fastest = elapsed end
    end
    print(string.format("PACKER_PROFILE %-20s %d runs %.6fs %.1f ns/op", label, count, fastest, fastest / count * 1000000000))
end
bench("codec-small-encode", 35000, function() local result = codec.Encode(7, false, "abc"); assert(buffer.len(result) == buffer.len(smallPacket)) end)
bench("codec-small-decode", 35000, function() local a,b,c = codec.Decode(smallPacket); assert(a == 7 and b == false and c == "abc") end)
bench("codec-medium-encode", 9000, function() local result = codec.Encode(999999, -123, 123.25, medium, source); assert(buffer.len(result) == buffer.len(mediumPacket)) end)
bench("codec-medium-decode", 9000, function() local a,b,c,d,e = codec.Decode(mediumPacket); assert(a == 999999 and b == -123 and c == 123.25 and d.Count == 777 and buffer.tostring(e) == "shared:payload") end)
local route = {Id = 77}
hooks.registerEvent(77, route)
bench("bitframe-small-id", 20000, function() local packet = hooks.encodeEventPacket(77, 3); assert(buffer.len(packet) > 0) end)
local stats = net.GetStats()
print(string.format("PACKER_POOLS writerHits=%d readerHits=%d bitWriterHits=%d", stats.WriterPoolHits, stats.ReaderPoolHits, stats.BitFrameWriterPoolHits))
print("PASS PACKER_PROFILE: identical source paths and byte signatures for baseline/optimized comparison")
