--!optimize 2
-- Deterministic standalone Luau simulation of the production server-side core.
-- No Roblox transport, heartbeat, DataStore, ping, bandwidth, or live clients are emulated.
local net = loadNetStream()
local hooks = net.__test
local PEERS = 96
local COMMANDS_PER_PEER = 800
local TICKETS_PER_PEER = 240
local DELTAS_PER_PEER = 180
local CODEC_ROUNDS = 3000
local FUZZ_CASES = 3000
local players = table.create(PEERS)
local active = {}
local state = {}
for index = 1, PEERS do
    local player = {Parent = hooks.players, __player = true, IsA = function(_, kind) return kind == "Player" end}
    players[index] = player
    active[player] = index % 16 ~= 0
    state[player] = {Coins = 1000, Events = 0, Purchases = 0}
end
local metrics = {}
local function mockDisconnectAll(self)
    self._head = nil
    self._tail = nil
    self._listenerCount = 0
end
local function benchmark(name, expected, callback)
    local started = os.clock()
    local count = callback()
    local elapsed = os.clock() - started
    assert(count == expected, name .. ": expected " .. tostring(expected) .. ", got " .. tostring(count))
    metrics[#metrics + 1] = {Name = name, Operations = count, Seconds = elapsed}
    print(string.format("STRESS %-24s %8d operations %.4fs", name, count, elapsed))
end

local calls = 0
local accepted = 0
local rejected = 0
local guarded = {Id = 600001, _listenerCount = 1, DisconnectAll = mockDisconnectAll}
guarded._head = {connected = true, once = false, callback = function(player, amount)
    assert(amount == 1, "Invalid amount reached server gameplay")
    local profile = state[player]
    profile.Events += 1
    profile.Coins += amount
    calls += 1
end}
hooks.registerEvent(guarded.Id, guarded)
net.RequireServerPolicies(true)
net.SetServerPolicy(guarded, {
    Validate = function(_, amount) return type(amount) == "number" and amount == 1 end,
    Authorize = function(player) return active[player] == true end,
})
benchmark("server command firewall", PEERS * COMMANDS_PER_PEER, function()
    for _, player in players do
        for operation = 1, COMMANDS_PER_PEER do
            local amount = if operation % 11 == 0 then 999 else 1
            if active[player] and amount == 1 then accepted += 1 else rejected += 1 end
            if operation % 2 == 0 then
                hooks.dispatchScalar(guarded, player, amount)
            else
                hooks.dispatch(guarded, player, table.pack(amount))
            end
        end
    end
    return accepted + rejected
end)
assert(calls == accepted, "Rejected command bypassed authoritative server policy")
local stats = net.GetStats()
assert(stats.SecurityPolicyChecks == accepted + rejected)
assert(stats.SecurityPolicyAccepted == accepted)
assert(stats.SecurityPolicyRejects == rejected)
print("PASS firewall: accepted=" .. accepted .. " rejected=" .. rejected)

local deniedRoute = {Id = 600002, _listenerCount = 1, DisconnectAll = mockDisconnectAll}
deniedRoute._head = {connected = true, callback = function() error("Unprotected command executed") end}
hooks.registerEvent(deniedRoute.Id, deniedRoute)
benchmark("default-deny firewall", PEERS * 40, function()
    for _, player in players do
        for _ = 1, 40 do hooks.dispatchScalar(deniedRoute, player, 1) end
    end
    return PEERS * 40
end)
assert(net.GetStats().SecurityUnprotectedDrops == PEERS * 40, "Unprotected events were not dropped")

local ingressCount = 0
local ingress = {Id = 600003, _listenerCount = 1, DisconnectAll = mockDisconnectAll}
ingress._head = {connected = true, once = false, callback = function(player, value)
    assert(active[player] == true and value == 2, "Untrusted packet changed authoritative state")
    ingressCount += 1
end}
hooks.registerEvent(ingress.Id, ingress)
net.SetServerPolicy(ingress, {
    Validate = function(_, value) return value == 2 end,
    Authorize = function(player) return active[player] == true end,
})
hooks.startWithoutTransport()
local baselineReceived = net.GetStats().ReceivedMessages
local baselineAtomicDrops = net.GetStats().BitFrameAtomicRejectedPackets
local validPackets, maliciousPackets = 0, 0
benchmark("real BitFrame ingress", PEERS * 24, function()
    for _, player in players do
        for iteration = 1, 24 do
            local value = if iteration % 7 == 0 then 65535 else 2
            hooks.receivePacket(player, hooks.encodeEventPacket(ingress.Id, value))
            if active[player] and value == 2 then validPackets += 1 else maliciousPackets += 1 end
        end
    end
    return PEERS * 24
end)
while net.GetStats().DispatchBacklog > 0 do hooks.drainDispatch() end
assert(ingressCount == validPackets, "BitFrame ingress bypassed policy or lost accepted packets")
assert(net.GetStats().ReceivedMessages == baselineReceived + PEERS * 24, "Valid BitFrame packets not decoded")

local validPair = hooks.encodeTwoEvents(ingress.Id, 2, 2)
local corrupted = buffer.create(buffer.len(validPair) + 1)
buffer.copy(corrupted, 0, validPair)
buffer.writeu8(corrupted, buffer.len(validPair), 255)
hooks.receivePacket(players[1], corrupted)
while net.GetStats().DispatchBacklog > 0 do hooks.drainDispatch() end
assert(ingressCount == validPackets, "Malformed batch partially applied authenticated events")
assert(net.GetStats().BitFrameAtomicRejectedPackets == baselineAtomicDrops + 1, "Malformed batch did not stage-rollback")
assert(net.GetStats().DispatchBacklog == 0, "BitFrame callback backlog leaked")
print("PASS wire: " .. validPackets .. " valid accepted, " .. maliciousPackets .. " policy-denied, malformed batch rolled back")

local rpcRuns = 0
local rpc = {Id = 600004, _callback = function(player, value)
    assert(active[player] ~= nil, "Unknown RPC player")
    coroutine.yield()
    rpcRuns += 1
    return value + 1
end}
hooks.registerFunction(rpc.Id, rpc)
net.SetServerPolicy(rpc, {
    Validate = function(_, value) return type(value) == "number" and value > 0 end,
    Authorize = function(player) return active[player] ~= nil end,
})
local pendingRPCs = table.create(512)
benchmark("concurrent RPC admission", 512, function()
    for index = 1, 512 do
        local player = players[(index - 1) % PEERS + 1]
        assert(hooks.charge(player), "RPC slot denied before configured cap")
        local thread = coroutine.create(hooks.run)
        local ok, err = coroutine.resume(thread, player, rpc.Id, index, table.pack(index))
        assert(ok, tostring(err))
        assert(coroutine.status(thread) == "suspended", "Expected an in-flight RPC")
        pendingRPCs[index] = thread
    end
    assert(net.GetRPCStats().Active == 512, "In-flight RPC count incorrect at saturation")
    assert(not hooks.charge(players[1]), "Global RPC concurrency cap bypassed")
    for _, thread in pendingRPCs do
        local ok, err = coroutine.resume(thread)
        assert(ok and coroutine.status(thread) == "dead", tostring(err))
    end
    assert(net.GetRPCStats().Active == 0 and rpcRuns == 512, "RPC completion leaked capacity or lost handler results")
    assert(net.GetRPCStats().ExecutionErrors == 0, "Successful RPCs reported callback errors")
    return rpcRuns
end)
print("PASS RPC: 512 in-flight callbacks saturated global cap and returned all slots")

local tracebackSecret = "PRIVATE_SERVER_TRACE_SHOULD_NOT_LEAK"
local failingRPC = {Id = 600006, _callback = function() error(tracebackSecret) end}
hooks.registerFunction(failingRPC.Id, failingRPC)
net.SetServerPolicy(failingRPC, {Authorize = function() return true end})
assert(hooks.charge(players[1]))
hooks.run(players[1], failingRPC.Id, 900001, table.pack(1))
local failureReply = hooks.peekRPCReply(players[1])
assert(failureReply and failureReply[1] == false and failureReply[2] == "Remote callback failed", "RPC handler leaked error or traceback to client")
assert(not string.find(failureReply[2], tracebackSecret, 1, true), "Sensitive server error content was returned")
assert(net.GetRPCStats().CallbackErrors == 1, "RPC application error was not counted")
local invalidRPC = {Id = 600007, _callback = function() return math.huge end}
hooks.registerFunction(invalidRPC.Id, invalidRPC)
net.SetServerPolicy(invalidRPC, {Authorize = function() return true end})
assert(hooks.charge(players[1]))
hooks.run(players[1], invalidRPC.Id, 900002, table.pack(1))
local invalidReply = hooks.peekRPCReply(players[1])
assert(invalidReply and invalidReply[1] == false and invalidReply[2] == "Remote callback returned invalid data", "Invalid server results leaked implementation details")
assert(net.GetRPCStats().InvalidResults == 1, "Invalid callback return was not counted")
print("PASS RPC: server exception tracebacks and invalid result internals never reach the client")

local gate = net.CreateActionGate({TTLSeconds = 120, MaxTicketsPerPlayer = 16})
local ticketSuccess, ticketReplays, ticketWrongPlayer = 0, 0, 0
benchmark("action ticket cycles", PEERS * TICKETS_PER_PEER, function()
    for index, player in players do
        for value = 1, TICKETS_PER_PEER do
            local ticket = gate:Issue(player, "Buy", value)
            assert(ticket, "Ticket cap leaked after redemption")
            if index % 8 == 0 then
                local other = players[if index == PEERS then 1 else index + 1]
                local ok, why = gate:Redeem(other, ticket, "Buy", function() error("Cross-player accepted") end)
                assert(not ok and why == "Unknown", "Cross-player ticket used")
                ticketWrongPlayer += 1
            end
            local ok, answer = gate:Redeem(player, ticket, "Buy", function(owner, price)
                assert(owner == player and price == value, "Ticket payload was forged")
                state[player].Purchases += 1
                return price
            end)
            assert(ok and answer == value, "Valid action ticket rejected")
            ticketSuccess += 1
            local duplicate, reason = gate:Redeem(player, ticket, "Buy", function() error("Duplicate ticket redeemed") end)
            assert(not duplicate and (reason == "Duplicate" or reason == "Unknown"), "Replay not rejected")
            ticketReplays += 1
        end
    end
    return ticketSuccess
end)
assert(ticketReplays == PEERS * TICKETS_PER_PEER)
assert(net.GetStats().SecurityTicketsRedeemed == ticketSuccess)
assert(net.GetStats().SecurityTicketsRejected >= ticketReplays + ticketWrongPlayer)
print("PASS tickets: issues=" .. ticketSuccess .. " replayRejected=" .. ticketReplays .. " foreignRejected=" .. ticketWrongPlayer)

local idem = net.CreateIdempotencyGuard({TTLSeconds = 120, MaxEntriesPerPlayer = 12})
benchmark("idempotent transactions", PEERS * 120, function()
    local executed = 0
    for _, player in players do
        for batch = 1, 10 do
            for value = 1, 12 do
                local key = batch * 100 + value
                local ok = idem:Execute(player, key, function() executed += 1; return true end)
                assert(ok, "Idempotent handler unexpectedly rejected")
                local duplicate, why = idem:Execute(player, key, function() error("Idempotency bypass") end)
                assert(not duplicate and why == "Duplicate", "Idempotency key replay accepted")
            end
            idem:ClearPlayer(player)
        end
    end
    return executed
end)
local codec = net.CreateDeltaCodec({"Coins", "Ready"})
local deltaCount = 0
benchmark("delta replication", PEERS * DELTAS_PER_PEER, function()
    for _, player in players do
        local revision = 1
        local current = {Coins = 0, Ready = false}
        local snapshot = codec:Full(current, revision)
        local restored, restoredRevision = codec:Apply(nil, nil, snapshot)
        assert(restored and restoredRevision == revision)
        for operation = 1, DELTAS_PER_PEER do
            local nextState = {Coins = operation, Ready = operation % 2 == 0}
            local frame = codec:Diff(current, nextState, revision)
            assert(frame, "Missing change")
            local after, newRevision = codec:Apply(restored, revision, frame)
            assert(after and newRevision == revision + 1 and after.Coins == operation, "Delta update failed")
            local stale = codec:Apply(after, newRevision, frame)
            assert(stale == nil, "Delta replay applied")
            revision, current, restored = newRevision, nextState, after
            deltaCount += 1
        end
        local fresh, resyncRevision = codec:Apply(nil, nil, codec:Full(current, revision + 1))
        assert(fresh and resyncRevision == revision + 1)
    end
    return deltaCount
end)

benchmark("codec round-trips", CODEC_ROUNDS, function()
    for operation = 1, CODEC_ROUNDS do
        local packet = net.Codec.Encode(operation, -operation, false, nil, "repeat:" .. (operation % 9), {Count = operation, Enabled = false}, buffer.fromstring("secure"))
        local decoded = table.pack(net.Codec.Decode(packet))
        assert(decoded.n == 7 and decoded[1] == operation and decoded[3] == false and decoded[4] == nil and decoded[6].Count == operation, "Codec corrupted field")
        assert(buffer.tostring(decoded[7]) == "secure", "Codec corrupted buffer")
    end
    return CODEC_ROUNDS
end)

local seed = 1337
local function nextByte()
    seed = (seed * 1664525 + 1013904223) % 4294967296
    return seed % 256
end
local malformedRejected = 0
benchmark("malformed packet fuzz", FUZZ_CASES, function()
    for index = 1, FUZZ_CASES do
        local size = 1 + (index % 48)
        local packet = buffer.create(size)
        for byte = 0, size - 1 do buffer.writeu8(packet, byte, nextByte()) end
        local ok, decoded = net.Codec.TryDecode(packet)
        if ok then
            assert(type(decoded) == "table" and type(decoded.n) == "number", "Decoded malformed payload not canonical")
        else
            malformedRejected += 1
        end
    end
    return FUZZ_CASES
end)
assert(malformedRejected > FUZZ_CASES * 0.95, "Unexpectedly many random payloads were accepted")
print("PASS fuzz: rejected=" .. malformedRejected .. " out of " .. FUZZ_CASES .. " random buffers")

local incomingBefore = ingressCount
local fuzzDecodeBefore = net.GetStats().DecodeErrors
benchmark("BitFrame network fuzz", 2400, function()
    for iteration = 1, 2400 do
        local packetSize = 1 + iteration % 36
        local randomPacket = buffer.create(packetSize)
        for byte = 0, packetSize - 1 do buffer.writeu8(randomPacket, byte, nextByte()) end
        hooks.receivePacket(players[(iteration - 1) % PEERS + 1], randomPacket)
    end
    return 2400
end)
while net.GetStats().DispatchBacklog > 0 do hooks.drainDispatch() end
assert(ingressCount == incomingBefore, "Random BitFrame packets invoked authorized gameplay")
assert(net.GetStats().DecodeErrors > fuzzDecodeBefore, "Malformed inbound BitFrame packets were not rejected")
assert(net.GetStats().DispatchBacklog == 0, "Malformed packets leaked callback backlog")
print("PASS network fuzz: inbound BitFrame decoder rejected malformed payloads without dispatching gameplay")

local legacy = loadNetStream()
legacy.Configure({BitFrameEnabled = false, CompressionEnabled = false, HandshakeEnabled = false})
local legacyHooks = legacy.__test
local legacyCallbacks = 0
local legacyRoute = {Id = 700001, _listenerCount = 1, DisconnectAll = mockDisconnectAll}
legacyRoute._head = {connected = true, once = false, callback = function(_, amount)
    assert(amount == 1, "Forged legacy payload reached gameplay")
    legacyCallbacks += 1
end}
legacyHooks.registerEvent(legacyRoute.Id, legacyRoute)
local legacyPlayers = table.create(64)
local legacyAllowed = {}
for index = 1, 64 do
    local player = {Parent = legacyHooks.players, __player = true, IsA = function(_, kind) return kind == "Player" end}
    legacyPlayers[index] = player
    legacyAllowed[player] = index % 13 ~= 0
end
legacy.SetServerPolicy(legacyRoute, {
    Validate = function(_, amount) return amount == 1 end,
    Authorize = function(player) return legacyAllowed[player] == true end,
})
legacy.RequireServerPolicies(true)
legacyHooks.startWithoutTransport()
local legacyExpected = 0
benchmark("legacy transport fallback", 64 * 24, function()
    for _, player in legacyPlayers do
        for operation = 1, 24 do
            local amount = if operation % 7 == 0 then 99 else 1
            if legacyAllowed[player] and amount == 1 then legacyExpected += 1 end
            local payload = legacyHooks.encodeTransportEvent(legacyRoute.Id, amount)
            legacyHooks.receivePacket(player, payload)
        end
    end
    return 64 * 24
end)
while legacy.GetStats().DispatchBacklog > 0 do legacyHooks.drainDispatch() end
assert(legacyCallbacks == legacyExpected, "Legacy encoder/decoder bypassed or lost an accepted command")
assert(legacy.GetStats().ReceivedMessages == 64 * 24, "Legacy transport lost packet counts")
assert(legacy.GetStats().DecodeErrors == 0, "Legacy transport rejected valid packets")
print("PASS legacy: authenticated and malformed requests respected server policies")
legacy.Destroy()

for index, player in players do
    assert(state[player].Purchases == TICKETS_PER_PEER, "Lost/duplicated server-side transactions")
    if index % 16 ~= 0 then assert(state[player].Events > 0) else assert(state[player].Events == 0) end
    gate:ClearPlayer(player)
    idem:ClearPlayer(player)
end
assert(net.GetStats().SecurityIdempotencyDuplicates == PEERS * 120, "Idempotency metrics mismatch")
assert(net.GetStats().SecurityTicketsHandlerErrors == 0, "Unexpected ticket callback error")
assert(net.GetStats().SecurityPolicyErrors == 0, "Unexpected authorization callback error")
print("PASS server stress: 96 simulated clients; deterministic commands/tickets/idempotency/delta/codec/fuzz completed")
