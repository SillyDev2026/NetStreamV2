local NetStream = loadNetStream()
local codec = NetStream.CreateDeltaCodec({"Value", "Flag"})
local baseline = {Value = 7, Flag = false}
local full = codec:Full(baseline, 1)
local restored, revision = codec:Apply(nil, nil, full)
assert(restored and restored.Value == 7 and restored.Flag == false and revision == 1)
local failures = 0
local function rejects(frame, reason)
    local value, unchanged, err = codec:Apply(baseline, 1, frame)
    if value ~= nil or unchanged ~= 1 or type(err) ~= "string" then
        print("FAIL", reason)
        failures += 1
    end
    assert(baseline.Value == 7 and baseline.Flag == false, "Mutation on rejection")
end
for _, invalid in {4294967296, 4294967297, math.huge, 0/0, -1, 0.5} do
    local frame = codec:Diff(baseline, {Value = 8, Flag = false}, 1)
    frame.NilMask = invalid
    rejects(frame, "invalid nil mask " .. tostring(invalid))
end
for _, values in {{8, extra = true}, {[1] = 8, [1000] = 9}, {[0] = 9, [1] = 8}, {8, 9}, {}} do
    local frame = codec:Diff(baseline, {Value = 8, Flag = false}, 1)
    frame.Values = values
    rejects(frame, "noncanonical values")
end
local names = {}
for i = 1, 32 do names[i] = "Field" .. i end
local wide = NetStream.CreateDeltaCodec(names)
local state = {}
local currentRevision = 1
local first = wide:Full(state, currentRevision)
state = assert(wide:Apply(nil, nil, first))
for step = 1, 2000 do
    local nextState = table.clone(state)
    local index = (step * 17) % 32 + 1
    local field = names[index]
    nextState[field] = if step % 3 == 0 then nil elseif step % 3 == 1 then false else step
    local frame = wide:Diff(state, nextState, currentRevision)
    if frame then
        local applied, nextRevision = wide:Apply(state, currentRevision, frame)
        assert(applied and nextRevision == currentRevision + 1)
        for _, name in names do assert(applied[name] == nextState[name], name) end
        assert(wide:Apply(applied, nextRevision, frame) == nil, "Replay accepted")
        state, currentRevision = applied, nextRevision
    end
end
assert(failures == 0, tostring(failures) .. " delta validation failures")
print("PASS delta: malformed masks/arrays, 32 fields, 2000 state transitions, replay rejection")
