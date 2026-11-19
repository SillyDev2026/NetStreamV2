--!optimize 2
local failures = 0
local function check(name, callback)
    local ok, err = pcall(callback)
    if ok then print("PASS LIMITS: " .. name) else failures += 1; print("FAIL LIMITS: " .. name .. ": " .. tostring(err)) end
end

check("tiny decoding respects MaxTableEntries", function()
    local net = loadNetStream()
    local data = net.Codec.Encode(1, false)
    net.Configure({MaxTableEntries = 1})
    assert(not net.Codec.TryDecode(data), "tiny tuple bypassed argument limit")
    assert(net.Codec.Decode(net.Codec.Encode(false)) == false)
end)

check("encoding respects the decoder argument limit", function()
    local net = loadNetStream()
    net.Configure({MaxTableEntries = 1})
    for _, args in {table.pack(1, false), table.pack(99, "fallback"), table.pack(nil, nil)} do
        assert(not net.Codec.TryEncode(table.unpack(args, 1, args.n)), "encoder emitted too many arguments")
        assert(not pcall(net.Codec.Encode, table.unpack(args, 1, args.n)))
        assert(not pcall(net.Codec.Analyze, table.unpack(args, 1, args.n)))
    end
    assert(net.Codec.TryEncode(false))
end)

check("scalar writes enforce logical limits inside larger buffers", function()
    local net = loadNetStream()
    for _, item in {{"u8", 1, 7}, {"i16", 2, -7}, {"u16", 2, 7}, {"i32", 4, -7}, {"u32", 4, 7}, {"f32", 4, 1.5}, {"f64", 8, 1.5}, {"varUInt", 1, 7}, {"varUInt", 2, 128}, {"varUInt", 8, 9007199254740991}} do
        local method, width, value = table.unpack(item)
        local writer = net.__test.makeRawWriter(2048, 1024)
        writer.position = 1024 - width
        writer[method](writer, value)
        assert(writer.position == 1024, method .. " rejected exact fit")
        writer.position = 1025 - width
        local before = buffer.tostring(writer.buffer)
        assert(not pcall(writer[method], writer, value), method .. " exceeded configured limit")
        assert(writer.position == 1025 - width and buffer.tostring(writer.buffer) == before, method .. " mutated writer on rejection")
    end
end)

check("pooled writers respect reduced outgoing limits", function()
    local net = loadNetStream()
    net.Configure({CompressionEnabled = false, MaxOutgoingBatchBytes = 4096, BitFrameMaxBytes = 1024})
    local args = table.create(1100, true)
    assert(buffer.len(net.Codec.Encode(table.unpack(args))) > 1024)
    net.Configure({MaxOutgoingBatchBytes = 1024})
    assert(not net.Codec.TryEncode(table.unpack(args)), "reused capacity bypassed reduced output limit")
    assert(net.Codec.Decode(net.Codec.Encode("healthy")) == "healthy")
end)

check("buffer growth respects non-power-of-two limits", function()
    local net = loadNetStream()
    net.Configure({CompressionEnabled = false, MaxOutgoingBatchBytes = 1025, BitFrameMaxBytes = 1024})
    local fits = table.create(1022, true)
    assert(buffer.len(net.Codec.Encode(table.unpack(fits))) == 1025)
    local oversized = table.create(1023, true)
    assert(not net.Codec.TryEncode(table.unpack(oversized)), "rounded capacity bypassed logical limit")
end)

assert(failures == 0, tostring(failures) .. " codec limit regressions")
