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
local guarded = {Id = 600001, _listenerCount = 1}
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

local deniedRoute = {Id = 600002, _listenerCount = 1}
deniedRoute._head = {connected = true, callback = function() error("Unprotected command executed") end}
hooks.registerEvent(deniedRoute.Id, deniedRoute)
benchmark("default-deny firewall", PEERS * 40, function()
    for _, player in players do
        for _ = 1, 40 do hooks.dispatchScalar(deniedRoute, player, 1) end
    end
    return PEERS * 40
end)
assert(net.GetStats().SecurityUnprotectedDrops == PEERS * 40, "Unprotected events were not dropped")

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
