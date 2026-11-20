local production = loadNetStream()
local factory = loadAuthoritativeState()
local ID = 45000
local passed = 0
local function signal()
    local callbacks = {}
    local result = {}
    function result:Connect(callback)
        local connection = {Connected = true}
        callbacks[connection] = callback
        function connection:Disconnect() self.Connected = false; callbacks[self] = nil end
        return connection
    end
    function result:Fire(...)
        for connection, callback in pairs(table.clone(callbacks)) do if connection.Connected then callback(...) end end
    end
    function result:Count()
        local count = 0
        for _ in pairs(callbacks) do count += 1 end
        return count
    end
    return result
end

local function world()
    local w = {Now = 0, Queue = {}, Delivered = {}, ServerRoutes = {}, ClientRoutes = {}, Clients = {}, Reject = false, Drop = nil}
    w.Players = {PlayerRemoving = signal()}
    w.Heartbeat = signal()
    w.A = {__player = true, Parent = w.Players, UserId = 1, IsA = function(_, name) return name == "Player" end}
    w.B = {__player = true, Parent = w.Players, UserId = 2, IsA = w.A.IsA}
    local function enqueue(sender, target, id, latest, ...)
        if w.Reject then return false end
        local args = table.pack(production.Codec.Decode(production.Codec.Encode(...)))
        if latest then
            for i = #w.Queue, 1, -1 do
                local p = w.Queue[i]
                if p.Sender == sender and p.Target == target and p.Id == id then table.remove(w.Queue, i) end
            end
        end
        w.Queue[#w.Queue + 1] = {Sender = sender, Target = target, Id = id, Args = args}
        return true
    end
    function w:Net(player)
        local api = {Types = production.Types, GetConfig = production.GetConfig, CreateDeltaCodec = production.CreateDeltaCodec, Dead = false}
        function api.IsDestroyed() return api.Dead end
        function api.Event(name, options)
            local route = {Signal = signal(), Options = options}
            function route:Connect(callback) return self.Signal:Connect(callback) end
            function route:FireClient(target, ...)
                assert(player == nil)
                return enqueue(nil, target, options.Id, options.Coalesce, ...)
            end
            function route:FireServer(...)
                assert(player ~= nil)
                return enqueue(player, nil, options.Id, options.Coalesce, ...)
            end
            function route:CancelQueuedClient(target)
                for i = #w.Queue, 1, -1 do if w.Queue[i].Target == target and w.Queue[i].Id == options.Id then table.remove(w.Queue, i) end end
            end
            if player then
                w.ClientRoutes[player] = w.ClientRoutes[player] or {}
                w.ClientRoutes[player][options.Id] = route
            else w.ServerRoutes[options.Id] = route end
            return route
        end
        return api
    end
    local function options() return {Id = ID, Fields = {"Coins", "Wins", "Title", "Ready"}} end
    w.ServerNet = w:Net(nil)
    w.Server = factory.Create(w.ServerNet, "Account", options(), {Server = true, Players = w.Players, Heartbeat = w.Heartbeat, Clock = function() return w.Now end})
    function w:Client(player)
        local api = self:Net(player)
        local controller = factory.Create(api, "Account", options(), {Server = false, Players = self.Players, Heartbeat = self.Heartbeat, Clock = function() return self.Now end})
        self.Clients[player] = controller
        return controller
    end
    function w:Flush()
        local iterations = 0
        while #self.Queue > 0 do
            iterations += 1
            assert(iterations < 1000, "Unbounded message feedback")
            local packet = table.remove(self.Queue, 1)
            if not self.Drop or not self.Drop(packet) then
                self.Delivered[#self.Delivered + 1] = packet
                local routes = if packet.Sender then self.ServerRoutes else self.ClientRoutes[packet.Target]
                local route = routes and routes[packet.Id]
                if route then
                    if packet.Sender then route.Signal:Fire(packet.Sender, table.unpack(packet.Args, 1, packet.Args.n)) else route.Signal:Fire(table.unpack(packet.Args, 1, packet.Args.n)) end
                end
            end
        end
    end
    function w:Tick(dt)
        self.Now += dt or 0.1
        self.Heartbeat:Fire(dt or 0.1)
        self:Flush()
    end
    function w:Inject(player, id, ...) enqueue(player, nil, id, false, ...); self:Flush() end
    function w:Ready(two)
        self.CA = self:Client(self.A)
        self.Server:Attach(self.A, {Coins = 100, Wins = 0, Title = "Start", Ready = false})
        if two then
            self.CB = self:Client(self.B)
            self.Server:Attach(self.B, {Coins = 200, Wins = 0, Ready = false})
        end
        self:Tick()
        self:Tick()
        assert(self.CA:Get().Coins == 100 and self.Server:GetStats(self.A).PendingRevision == 0)
    end
    function w:BuyHandler()
        self.Server:HandleCommand("Buy", {
            Validate = function(player, payload, state)
                for key in pairs(payload) do if key ~= "Item" then return false end end
                return payload.Item == 7 and state.Coins >= 10
            end,
            Reduce = function(player, payload, state) state.Coins -= 10; state.Wins += 1; return state end,
        })
    end
    return w
end

local function test(name, callback)
    callback()
    passed += 1
    print("PASS replica", name)
end

test("owner isolation, frozen copies, deltas and coalescing", function()
    local w = world()
    w:Ready(true)
    assert(w.CB:Get().Coins == 200)
    assert(not pcall(function() w.CA:Get().Coins = 999 end))
    assert(not pcall(function() w.CA:Set(w.A, {Coins = 999}) end))
    assert(not pcall(function() w.CA:Attach(w.A, {}) end))
    assert(not pcall(function() w.CA:HandleCommand("Hack", {}) end))
    assert(not pcall(function() w.CA:Get(w.B) end))
    assert(not pcall(function() w.Server:Set(w.A, {Unknown = 1}) end))
    local state = {Coins = 98, Wins = 0, Ready = false}
    w.Server:Set(w.A, state)
    state.Coins = 9999
    w.Server:Update(w.A, function(draft) draft.Coins -= 1; return draft end)
    local before = w.Server:GetStats().DeltaSnapshots
    w:Tick()
    assert(w.CA:Get().Coins == 97 and w.CA:Get().Title == nil and w.CA:Get().Ready == false)
    assert(w.CB:Get().Coins == 200 and w.Server:Get(w.A).Coins == 97)
    assert(w.Server:GetStats().DeltaSnapshots == before + 1)
    local count = #w.Delivered
    for _ = 1, 100 do w:Tick() end
    assert(#w.Delivered == count, "Idle state generated traffic")
end)

test("lost ACK, bounded pending baseline and full retry", function()
    local w = world()
    w:Ready()
    w.Drop = function(packet) return packet.Sender and packet.Id == ID + 1 and packet.Args[1] == 1 end
    w.Server:Set(w.A, {Coins = 90})
    w:Tick()
    local pending = w.Server:GetStats(w.A).PendingRevision
    for value = 89, 50, -1 do w.Server:Set(w.A, {Coins = value}) end
    w:Tick(0.5)
    assert(w.Server:GetStats(w.A).PendingRevision == pending and w.CA:Get().Coins == 90)
    w.Drop = nil
    w:Tick(2)
    assert(w.Server:GetStats(w.A).AcknowledgedRevision == pending and w.CA:Get().Coins == 90)
    w:Tick()
    assert(w.CA:Get().Coins == 50 and w.Server:GetStats().Retries >= 1)
end)

test("queue rejection and late client recover automatically", function()
    local w = world()
    w.Server:Attach(w.A, {Coins = 12})
    w.Reject = true
    w:Tick()
    assert(w.Server:GetStats().SendFailures == 1)
    w.Reject = false
    local client = w:Client(w.A)
    for _ = 1, 5 do w:Tick(1) end
    assert(client:Get().Coins == 12 and w.Server:GetStats(w.A).PendingRevision == 0)
end)

test("bad baseline requests full resync", function()
    local w = world()
    w:Ready()
    local changed = false
    w.Drop = function(packet)
        if not packet.Sender and packet.Id == ID and type(packet.Args[2]) == "table" and packet.Args[2].Full == false and not changed then
            packet.Args[2].Base = 999
            changed = true
        end
        return false
    end
    w.Server:Set(w.A, {Coins = 40})
    w:Tick()
    assert(w.CA:Get().Coins == 100 and w.CA:GetStats().InvalidFrames == 1)
    for _ = 1, 5 do w:Tick(1) end
    assert(w.CA:Get().Coins == 40 and w.Server:GetStats().Resyncs >= 1)
end)

test("forged state, ACKs and other-player epochs cannot change authority", function()
    local w = world()
    w:Ready(true)
    local a, b = w.Server:GetStats(w.A), w.Server:GetStats(w.B)
    w:Inject(w.A, ID, a.Epoch, {Full = true, Coins = 999999})
    w:Inject(w.A, ID + 1, 1, a.Epoch, 999999)
    w:Inject(w.A, ID + 1, 1, b.Epoch, 1)
    w:Inject(w.A, ID + 1, 2, b.Epoch, 1)
    w:Tick()
    assert(w.Server:Get(w.A).Coins == 100 and w.Server:Get(w.B).Coins == 200)
    assert(w.CB:Get().Coins == 200 and w.Server:GetStats().RejectedAcks >= 2)
end)

test("validated command, result feedback, replay and forgery rejection", function()
    local w = world()
    w:Ready(true)
    w:BuyHandler()
    local results = {}
    w.CA:OnCommandResult(function(sequence, ok, reason) results[sequence] = {ok, reason} end)
    local ok, sequence = w.CA:SendCommand("Buy", {Item = 7})
    assert(ok and sequence == 1)
    w:Flush()
    assert(w.Server:Get(w.A).Coins == 90 and w.Server:Get(w.A).Wins == 1)
    assert(results[1][1] == true and results[1][2] == "Accepted")
    local epoch = w.Server:GetStats(w.A).Epoch
    w:Inject(w.A, ID + 2, epoch, sequence, "Buy", {Item = 7})
    w:Inject(w.A, ID + 2, epoch, sequence + 1, "SetCoins", {Coins = 999})
    w:Inject(w.A, ID + 2, epoch, sequence + 2, "Buy", {Item = 99})
    w:Inject(w.A, ID + 2, w.Server:GetStats(w.B).Epoch, sequence + 3, "Buy", {Item = 7})
    assert(w.Server:Get(w.A).Coins == 90 and w.Server:Get(w.B).Coins == 200)
    assert(w.Server:GetStats().Replays >= 2 and w.Server:GetStats().CommandsRejected >= 2)
    w:Tick()
    assert(w.CA:Get().Coins == 90)
end)

test("malformed payloads and bounded rate limits", function()
    local w = world()
    w:Ready()
    w:BuyHandler()
    assert(w.CA:SendCommand("Buy", {Nested = {Coins = 999}}) == false)
    assert(w.CA:SendCommand("Buy", {Item = 0/0}) == false)
    assert(w.CA:SendCommand("Buy", {Text = string.rep("x", 257)}) == false)
    local epoch = w.Server:GetStats(w.A).Epoch
    w:Inject(w.A, ID + 2, epoch, 1, "Buy", {Nested = {Item = 7}})
    for sequence = 2, 100 do w:Inject(w.A, ID + 2, epoch, sequence, "Buy", {Item = 7}) end
    assert(w.Server:Get(w.A).Coins == 70 and w.Server:GetStats().RateLimited > 0)
    w:Tick(2)
    w:Inject(w.A, ID + 2, epoch, 101, "Buy", {Item = 7})
    assert(w.Server:Get(w.A).Coins == 60, "Rate limiter did not recover")
    for _ = 1, 100 do w:Inject(w.A, ID + 1, 2, epoch, 1) end
    local before = w.Server:GetStats().FullSnapshots
    w:Tick()
    assert(w.Server:GetStats().FullSnapshots <= before + 1, "Resync amplified traffic")
end)

test("yielding/errors/invalid reducers never partially commit", function()
    local w = world()
    w:Ready()
    w.Server:HandleCommand("Yield", {Validate = function() return true end, Reduce = function(_, _, state) state.Coins = 999; coroutine.yield(); return state end})
    w.Server:HandleCommand("Error", {Validate = function() return true end, Reduce = function(_, _, state) state.Coins = 999; error("bad") end})
    w.Server:HandleCommand("Invalid", {Validate = function() return true end, Reduce = function() return {Coins = math.huge} end})
    w.Server:HandleCommand("Mutate", {Validate = function(_, _, state) state.Coins = 999; return true end, Reduce = function(_, _, state) return state end})
    for _, name in {"Yield", "Error", "Invalid", "Mutate"} do assert(w.CA:SendCommand(name, {})); w:Flush() end
    assert(w.Server:Get(w.A).Coins == 100 and w.Server:GetStats().CallbackErrors == 4)
    assert(not pcall(function() w.Server:Update(w.A, function(state) state.Coins = 999; coroutine.yield(); return state end) end))
    assert(w.Server:Get(w.A).Coins == 100)
    w:BuyHandler()
    w:Tick(2)
    assert(w.CA:SendCommand("Buy", {Item = 7})); w:Flush()
    assert(w.Server:Get(w.A).Coins == 90)
end)

test("detach/reattach reject old epochs and disconnect frees records", function()
    local w = world()
    w:Ready()
    w:BuyHandler()
    local oldEpoch = w.Server:GetStats(w.A).Epoch
    local oldFrame = production.CreateDeltaCodec({"Coins", "Wins", "Title", "Ready"}):Full({Coins = 888}, 99)
    w.Server:Detach(w.A); w:Flush()
    assert(w.CA:Get() == nil and w.CA:SendCommand("Buy", {Item = 7}) == false)
    w.ClientRoutes[w.A][ID].Signal:Fire(oldEpoch, oldFrame)
    assert(w.CA:Get() == nil, "Detached state resurrected")
    local epoch = w.Server:Attach(w.A, {Coins = 25, Wins = 0})
    assert(epoch > oldEpoch)
    w:Tick()
    w:Inject(w.A, ID + 2, oldEpoch, 1, "Buy", {Item = 7})
    assert(w.Server:Get(w.A).Coins == 25 and w.CA:Get().Coins == 25)
    w.ClientRoutes[w.A][ID].Signal:Fire(oldEpoch, oldFrame)
    assert(w.CA:Get().Coins == 25)
    w.A.Parent = nil
    w.Players.PlayerRemoving:Fire(w.A)
    assert(w.Server:GetStats().TrackedPlayers == 0)
end)

test("destroy cleans listeners and net shutdown stops all work", function()
    local w = world()
    w:Ready()
    local called = 0
    local connection = w.CA:OnChanged(function() called += 1 end)
    w.Server:Destroy(); w:Flush()
    assert(w.CA:Get() == nil and called == 1)
    assert(w.Server:GetStats().TrackedPlayers == 0 and w.Players.PlayerRemoving:Count() == 0)
    w.CA:Destroy()
    assert(not connection.Connected and w.Heartbeat:Count() == 0)
    w:Tick(10)
    local other = world()
    other:Ready()
    other.ServerNet.Dead = true
    other:Tick()
    assert(other.Server:GetStats().TrackedPlayers == 0)
end)

test("schema mismatch never acknowledges mislabelled state", function()
    local w = world()
    w:Ready()
    w.Server:Set(w.A, {Coins = 55})
    w.Drop = function(packet)
        if not packet.Sender and packet.Id == ID then packet.Args[2].Schema = "wrong schema" end
        return false
    end
    w:Tick()
    assert(w.CA:Get().Coins == 100 and w.Server:GetStats(w.A).PendingRevision > 0)
    w.Drop = nil
    for _ = 1, 5 do w:Tick(1) end
    assert(w.CA:Get().Coins == 55)
end)

test("2000 update steps under deterministic loss eventually converge", function()
    local w = world()
    w:Ready(true)
    local packets = 0
    w.Drop = function(packet)
        packets += 1
        return packets % 5 == 0 or packets % 7 == 0
    end
    for step = 1, 2000 do
        w.Server:Set(w.A, {Coins = step, Ready = step % 2 == 0})
        if step % 3 == 0 then w.Server:Set(w.B, {Coins = step * 2}) end
        w:Tick(0.05)
        local s = w.Server:GetStats(w.A)
        assert(s.PendingRevision == 0 or s.PendingRevision == s.AcknowledgedRevision + 1)
    end
    w.Drop = nil
    for _ = 1, 20 do w:Tick(0.5) end
    assert(w.CA:Get().Coins == w.Server:Get(w.A).Coins)
    assert(w.CB:Get().Coins == w.Server:Get(w.B).Coins)
    assert(w.Server:GetStats(w.A).PendingRevision == 0)
end)


test("public API through real BitFrame encode/decode/dispatch and shutdown", function()
    local heartbeat = signal()
    local players = {PlayerRemoving = signal()}
    local player = {__player = true, Parent = players, UserId = 1, IsA = function(_, name) return name == "Player" end}
    local server = loadNetStream({RunService = {IsServer = function() return true end, Heartbeat = heartbeat}, Players = players, ReplicatedStorage = {}})
    local client = loadNetStream({RunService = {IsServer = function() return false end, Heartbeat = heartbeat}, Players = players, ReplicatedStorage = {}})
    server.Configure({HandshakeEnabled = false, CompressionEnabled = false, BandwidthGovernorEnabled = false})
    client.Configure({HandshakeEnabled = false, CompressionEnabled = false, BandwidthGovernorEnabled = false})
    server.__test.startWithoutTransport({FireClient = function(_, target, packet) assert(target == player); client.__test.receive(nil, packet) end})
    client.__test.startWithoutTransport({FireServer = function(_, packet) server.__test.receive(player, packet) end})
    local options = {Id = ID, Fields = {"Coins", "Wins"}}
    local authoritative = server.CreateReplica("Account", options)
    local mirror = client.CreateReplica("Account", options)
    server.RequireServerPolicies(true)
    -- Replica-internal client command and control routes must be admitted
    -- by explicit server policies even with application-wide default deny.
    assert(not pcall(server.CreateReplica, "Account", {Id = ID + 10, Fields = {"Coins"}}))
    assert(not pcall(server.CreateReplica, "Collision", options))
    local function pump()
        heartbeat:Fire(0.1)
        server.FlushTarget(player)
        client.__test.dispatchPump()
        client.FlushTarget()
        server.__test.dispatchPump()
    end
    authoritative:Attach(player, {Coins = 10, Wins = 0})
    pump()
    assert(mirror:Get() and mirror:Get().Coins == 10)
    authoritative:HandleCommand("Buy", {Validate = function(_, payload, state) return payload.Item == 1 and state.Coins >= 2 end, Reduce = function(_, _, draft) draft.Coins -= 2; draft.Wins += 1; return draft end})
    assert(mirror:SendCommand("Buy", {Item = 1}))
    pump(); pump()
    assert(authoritative:Get(player).Coins == 8 and mirror:Get().Coins == 8)
    -- Existing event APIs cannot make a Data event authoritative on the server.
    client.Event("__Replica/Account/Data", {Id = ID}):FireServer(1, {Coins = 999999})
    pump()
    assert(authoritative:Get(player).Coins == 8)
    assert(server.GetStats().DecodeErrors == 0 and client.GetStats().DecodeErrors == 0)
    authoritative:Detach(player)
    pump()
    assert(mirror:Get() == nil)
    authoritative:Attach(player, {Coins = 20})
    pump()
    assert(mirror:Get().Coins == 20)
    server.Destroy(); client.Destroy()
    assert(heartbeat:Count() == 0 and players.PlayerRemoving:Count() == 0)
    assert(not pcall(server.CreateReplica, "AfterDestroy", {Id = ID + 20, Fields = {"Coins"}}))
end)

test("malformed replication frames are rejected without unwinding callbacks", function()
    local w = world()
    w:Ready()
    local before = w.CA:GetStats().InvalidFrames
    local epoch = w.Server:GetStats(w.A).Epoch
    local revision = w.CA:GetStats().Revision
    -- Construct an otherwise valid next revision, then corrupt its mask.
    local previous = w.CA:Get()
    local nextState = table.clone(previous)
    nextState.Coins = 999
    local broken = production.CreateDeltaCodec({"Coins", "Wins", "Title", "Ready"}):Diff(previous, nextState, revision)
    assert(broken, "Failed to construct malformed-frame fixture")
    broken.Schema = "5:Coins4:Wins5:Title5:Ready"
    broken.Mask = 0/0
    local success = pcall(function() w.ClientRoutes[w.A][ID].Signal:Fire(epoch, broken) end)
    assert(success, "Malformed frame escaped the client listener")
    local after = w.CA:GetStats().InvalidFrames
    assert(after > before, string.format("Malformed frame was not rejected (before=%d after=%d epoch=%d clientEpoch=%d revision=%d)", before, after, epoch, w.CA:GetStats().Epoch, revision))
    assert(w.CA:Get().Coins == 100, "Malformed frame altered client state")
end)

print("PASS authoritative replication suites:", passed)
