--!optimize 2

local AuthoritativeState = {}
local MAX_INTEGER = 9007199254740991

local function integer(value, minimum, maximum)
    return type(value) == "number" and value % 1 == 0 and value >= minimum and value <= maximum
end

local function invoke(callback, ...)
    local thread = coroutine.create(callback)
    local ok, value = coroutine.resume(thread, ...)
    if coroutine.status(thread) ~= "dead" then
        coroutine.close(thread)
        return false, "YieldNotAllowed"
    end
    return ok, value
end

function AuthoritativeState.Create(net, name, options, context)
    assert(type(name) == "string" and #name >= 1 and #name <= 64, "Replica name must contain 1..64 bytes")
    assert(type(options) == "table" and integer(options.Id, 1, 2147483644), "Replica requires Id and three following free event IDs")
    local fields = options.Fields
    assert(type(fields) == "table" and #fields >= 1 and #fields <= 32, "Replica requires 1..32 fields")
    local fieldNames = table.clone(fields)
    local fieldSet = {}
    for index, field in pairs(fieldNames) do
        assert(integer(index, 1, #fields) and type(field) == "string" and #field > 0 and #field <= 64 and not fieldSet[field], "Invalid replica field list")
        fieldSet[field] = true
    end
    local codec = net.CreateDeltaCodec(fieldNames)
    local signatureParts = table.create(#fieldNames)
    for index, field in ipairs(fieldNames) do signatureParts[index] = tostring(#field) .. ":" .. field end
    local signature = table.concat(signatureParts)
    local server = context.Server
    local players = context.Players
    local clock = context.Clock
    local sendRate = options.SendRate or 20
    local retryInterval = options.RetryInterval or 2
    local maxStateBytes = options.MaxStateBytes or 8192
    local maxStringBytes = net.GetConfig().MaxStringBytes
    local commandRate = options.CommandRate or 10
    local commandBurst = options.CommandBurst or 5
    assert(integer(sendRate, 1, 60), "Replica SendRate must be 1..60")
    assert(type(retryInterval) == "number" and retryInterval >= 0.25 and retryInterval <= 60, "Replica RetryInterval must be 0.25..60")
    assert(integer(maxStateBytes, 128, 65536), "Replica MaxStateBytes must be 128..65536")
    assert(integer(commandRate, 1, 60) and integer(commandBurst, 1, 60), "Replica command rate/burst must be 1..60")
    local records = {}
    local handlers = {}
    local handlerCount = 0
    local connections = {}
    local listeners = {Changed = {}, Result = {}}
    local listenerCounts = {Changed = 0, Result = 0}
    local destroyed = false
    local nextEpoch = 0
    local clientEpoch = 0
    local retiredEpoch = 0
    local clientRevision = 0
    local clientState = nil
    local commandSequence = 0
    local nextResync = 0
    local elapsed = 0
    local stats = {FullSnapshots = 0, DeltaSnapshots = 0, Retries = 0, Acknowledged = 0, RejectedAcks = 0, Resyncs = 0, CommandsAccepted = 0, CommandsRejected = 0, Replays = 0, RateLimited = 0, CallbackErrors = 0, InvalidFrames = 0, SendFailures = 0}
    local replica = {}

    local function alive()
        assert(not destroyed and not net.IsDestroyed(), "Replica has been destroyed")
    end

    local function connected(player)
        return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == players
    end

    local function copyState(state)
        assert(type(state) == "table" and getmetatable(state) == nil, "Replica state must be a plain table")
        local result = {}
        local bytes, count = 0, 0
        for key, value in pairs(state) do
            count += 1
            assert(count <= #fieldNames and fieldSet[key], "Unknown replica state field")
            local kind = type(value)
            assert(kind == "boolean" or (kind == "number" and math.isfinite(value)) or (kind == "string" and #value <= maxStringBytes), "Replica fields must be finite numbers, booleans, bounded strings or nil")
            bytes += #key + (if kind == "string" then #value else 8)
            assert(bytes <= maxStateBytes, "Replica state exceeds MaxStateBytes")
            result[key] = value
        end
        return table.freeze(result)
    end

    local function copyPayload(payload)
        if type(payload) ~= "table" or getmetatable(payload) ~= nil then return nil end
        local result = {}
        local count, bytes = 0, 0
        for key, value in pairs(payload) do
            count += 1
            if count > 16 or type(key) ~= "string" or #key < 1 or #key > 64 then return nil end
            local kind = type(value)
            if kind ~= "boolean" and not (kind == "number" and math.isfinite(value)) and not (kind == "string" and #value <= 256) then return nil end
            bytes += #key + (if kind == "string" then #value else 8)
            if bytes > 2048 then return nil end
            result[key] = value
        end
        return table.freeze(result)
    end

    local function take(bucket, rate, burst)
        local now = clock()
        bucket.Tokens = math.min(burst, bucket.Tokens + math.max(0, now - bucket.Time) * rate)
        bucket.Time = now
        if bucket.Tokens < 1 then return false end
        bucket.Tokens -= 1
        return true
    end

    local function bucket(burst)
        return {Tokens = burst, Time = clock()}
    end

    local function notify(kind, ...)
        for connection, callback in pairs(listeners[kind]) do
            if connection.Connected then
                local ok = invoke(callback, ...)
                if not ok then stats.CallbackErrors += 1 end
            end
        end
    end

    local function subscribe(kind, callback)
        alive()
        assert(not server and type(callback) == "function", "Replica subscriptions require a client callback")
        assert(listenerCounts[kind] < 64, "Replica listener limit reached")
        local connection = {Connected = true}
        listeners[kind][connection] = callback
        listenerCounts[kind] += 1
        function connection:Disconnect()
            if not self.Connected then return end
            self.Connected = false
            listeners[kind][self] = nil
            listenerCounts[kind] -= 1
        end
        return connection
    end

    local T = net.Types
    local dataRoute = net.Event("__Replica/" .. name .. "/Data", {Id = options.Id, Compression = false, Coalesce = true})
    local controlRoute = net.Event("__Replica/" .. name .. "/Control", {Id = options.Id + 1, Schema = {T.U8, T.VarUInt, T.VarUInt}, Compression = false, MaxPerSecond = 60, Burst = 60})
    local commandRoute = net.Event("__Replica/" .. name .. "/Command", {Id = options.Id + 2, Compression = false, MaxPerSecond = commandRate, Burst = commandBurst})
    local resultRoute = net.Event("__Replica/" .. name .. "/Result", {Id = options.Id + 3, Schema = {T.VarUInt, T.VarUInt, T.Bool, T.String}, Compression = false})

    local function send(route, player, ...)
        if destroyed or net.IsDestroyed() or (server and not connected(player)) then return false end
        local ok, accepted
        if server then ok, accepted = pcall(route.FireClient, route, player, ...) else ok, accepted = pcall(route.FireServer, route, ...) end
        if not ok or not accepted then stats.SendFailures += 1; return false end
        return true
    end

    local function resync()
        if server or destroyed or clock() < nextResync then return false end
        nextResync = clock() + retryInterval
        return send(controlRoute, nil, 2, clientEpoch, clientRevision)
    end

    local function transmit(player, record)
        local pending = record.Pending
        local now = clock()
        if pending then
            if not record.ForceFull and now - pending.SentAt < retryInterval then return end
            if not pending.Frame.Full then pending.Frame = codec:Full(pending.State, pending.Revision) end
            pending.Frame.Schema = signature
            if send(dataRoute, player, record.Epoch, pending.Frame) then stats.Retries += 1 end
            pending.SentAt = now
            record.ForceFull = false
            return
        end
        local frame
        if record.ForceFull or not record.Baseline then
            assert(record.Revision < MAX_INTEGER, "Replica revision exhausted")
            frame = codec:Full(record.State, record.Revision + 1)
        else
            if record.Baseline == record.State then return end
            frame = codec:Diff(record.Baseline, record.State, record.Revision)
            if not frame then record.Baseline = record.State; return end
        end
        -- One pending revision per recipient. Changes while awaiting ACK remain coalesced in State.
        frame.Schema = signature
        record.Pending = {Frame = frame, State = record.State, Revision = frame.Revision, SentAt = now}
        record.ForceFull = false
        if send(dataRoute, player, record.Epoch, frame) then
            if frame.Full then stats.FullSnapshots += 1 else stats.DeltaSnapshots += 1 end
        end
    end

    function replica:Attach(player, initialState)
        alive()
        assert(server and connected(player), "Attach requires a connected Player on the server")
        assert(not records[player], "Player already attached; use Set or Detach")
        assert(nextEpoch < MAX_INTEGER, "Replica epoch exhausted")
        local state = copyState(initialState)
        nextEpoch += 1
        records[player] = {State = state, Epoch = nextEpoch, Revision = 0, Baseline = nil, Pending = nil, ForceFull = true, LastCommand = 0, Busy = false, Commands = bucket(commandBurst), Control = bucket(60), Resync = bucket(2), Rates = {}}
        return nextEpoch
    end

    function replica:Detach(player)
        alive()
        assert(server, "Detach is server-only")
        local record = records[player]
        if not record then return false end
        assert(not record.Busy, "Cannot detach from a command handler")
        records[player] = nil
        dataRoute:CancelQueuedClient(player)
        if connected(player) then send(dataRoute, player, record.Epoch, false) end
        return true
    end

    function replica:Set(player, state)
        alive()
        assert(server, "Set is server-only")
        local record = assert(records[player], "Player is not attached")
        assert(not record.Busy, "Use the command reducer's return value to update state")
        record.State = copyState(state)
    end

    function replica:Update(player, transform)
        alive()
        assert(server and type(transform) == "function", "Update requires a server transform")
        local record = assert(records[player], "Player is not attached")
        assert(not record.Busy, "Nested replica updates are not allowed")
        record.Busy = true
        local ok, state = invoke(transform, table.clone(record.State))
        record.Busy = false
        assert(ok, "Replica Update failed or yielded")
        assert(not destroyed and records[player] == record, "Replica changed during Update")
        record.State = copyState(state)
    end

    function replica:Get(player)
        alive()
        if server then
            local record = records[player]
            return if record then record.State else nil
        end
        assert(player == nil, "Client Get only exposes local replicated state")
        return clientState
    end

    function replica:HandleCommand(commandName, spec)
        alive()
        assert(server, "HandleCommand is server-only")
        assert(type(commandName) == "string" and #commandName > 0 and #commandName <= 64, "Invalid command name")
        assert(type(spec) == "table" and type(spec.Validate) == "function" and type(spec.Reduce) == "function", "Command requires Validate and Reduce callbacks")
        assert(not handlers[commandName] and handlerCount < 32, "Command already registered or limit reached")
        local rate, burst = spec.Rate or 5, spec.Burst or 3
        assert(integer(rate, 1, 60) and integer(burst, 1, 60), "Command rate/burst must be 1..60")
        handlers[commandName] = {Validate = spec.Validate, Reduce = spec.Reduce, Rate = rate, Burst = burst}
        handlerCount += 1
    end

    function replica:SendCommand(commandName, payload)
        alive()
        assert(not server, "SendCommand is client-only")
        if not clientState or commandSequence >= MAX_INTEGER then return false, "NotReady" end
        if type(commandName) ~= "string" or #commandName < 1 or #commandName > 64 then return false, "InvalidCommand" end
        local copied = copyPayload(payload)
        if not copied then return false, "InvalidPayload" end
        local sequence = commandSequence + 1
        if not send(commandRoute, nil, clientEpoch, sequence, commandName, copied) then return false, "QueueRejected" end
        commandSequence = sequence
        return true, sequence
    end

    function replica:RequestResync()
        alive()
        assert(not server, "RequestResync is client-only")
        return resync()
    end

    function replica:OnChanged(callback) return subscribe("Changed", callback) end
    function replica:OnCommandResult(callback) return subscribe("Result", callback) end

    function replica:GetStats(player)
        local result = table.clone(stats)
        if server then
            local count = 0
            for _ in pairs(records) do count += 1 end
            result.TrackedPlayers = count
            local record = records[player]
            if record then
                result.Epoch = record.Epoch
                result.AcknowledgedRevision = record.Revision
                result.PendingRevision = if record.Pending then record.Pending.Revision else 0
                result.LastCommand = record.LastCommand
            end
        else
            result.Epoch = clientEpoch
            result.Revision = clientRevision
            result.Ready = clientState ~= nil
        end
        return result
    end

    function replica:Destroy()
        if destroyed then return end
        if server then
            for player, record in pairs(records) do
                dataRoute:CancelQueuedClient(player)
                if connected(player) then send(dataRoute, player, record.Epoch, false) end
            end
        end
        destroyed = true
        for _, connection in ipairs(connections) do connection:Disconnect() end
        for kind, group in pairs(listeners) do
            for connection in pairs(group) do connection.Connected = false end
            table.clear(group)
            listenerCounts[kind] = 0
        end
        table.clear(records)
        table.clear(handlers)
        table.clear(connections)
        clientState = nil
    end

    if server then
        connections[#connections + 1] = controlRoute:Connect(function(player, op, epoch, revision)
            if destroyed then return end
            local record = records[player]
            if not record or not connected(player) then return end
            if not take(record.Control, 60, 60) then stats.RateLimited += 1; return end
            if not integer(epoch, 0, MAX_INTEGER) or not integer(revision, 0, MAX_INTEGER) then stats.RejectedAcks += 1; return end
            if op == 1 then
                local pending = record.Pending
                if epoch ~= record.Epoch or not pending or revision ~= pending.Revision then stats.RejectedAcks += 1; return end
                record.Baseline = pending.State
                record.Revision = pending.Revision
                record.Pending = nil
                stats.Acknowledged += 1
            elseif op == 2 then
                if not take(record.Resync, 1 / retryInterval, 2) then stats.RateLimited += 1; return end
                -- A reset client may have no epoch. Resync never changes server state or command replay counters.
                record.ForceFull = true
                stats.Resyncs += 1
            else stats.RejectedAcks += 1 end
        end)
        connections[#connections + 1] = commandRoute:Connect(function(player, epoch, sequence, commandName, payload)
            if destroyed then return end
            local record = records[player]
            if not record or not connected(player) then return end
            if not take(record.Commands, commandRate, commandBurst) then stats.RateLimited += 1; return end
            if epoch ~= record.Epoch or not integer(sequence, 1, MAX_INTEGER) or sequence <= record.LastCommand then stats.Replays += 1; return end
            record.LastCommand = sequence
            local handler = if type(commandName) == "string" and #commandName <= 64 then handlers[commandName] else nil
            local copied = copyPayload(payload)
            local function reject(reason)
                stats.CommandsRejected += 1
                send(resultRoute, player, record.Epoch, sequence, false, reason)
            end
            if not handler or not copied then reject("InvalidCommand"); return end
            local rate = record.Rates[commandName]
            if not rate then rate = bucket(handler.Burst); record.Rates[commandName] = rate end
            if not take(rate, handler.Rate, handler.Burst) then stats.RateLimited += 1; reject("RateLimited"); return end
            if record.Busy then reject("Busy"); return end
            record.Busy = true
            local valid, allowed = invoke(handler.Validate, player, copied, record.State)
            local ok, nextState = false, nil
            if valid and allowed == true then
                ok, nextState = invoke(handler.Reduce, player, copied, table.clone(record.State))
                if ok then ok, nextState = pcall(copyState, nextState) end
            end
            record.Busy = false
            if destroyed or records[player] ~= record or not connected(player) then return end
            if not valid or (allowed == true and not ok) then stats.CallbackErrors += 1; reject("HandlerError"); return end
            if allowed ~= true then reject("Denied"); return end
            record.State = nextState
            stats.CommandsAccepted += 1
            send(resultRoute, player, record.Epoch, sequence, true, "Accepted")
        end)
        connections[#connections + 1] = players.PlayerRemoving:Connect(function(player)
            records[player] = nil
        end)
    else
        connections[#connections + 1] = dataRoute:Connect(function(epoch, frame)
            if destroyed or not integer(epoch, 1, MAX_INTEGER) or epoch < clientEpoch or epoch <= retiredEpoch then return end
            if frame == false then
                retiredEpoch, clientEpoch = epoch, epoch
                clientState, clientRevision = nil, 0
                notify("Changed", nil, 0)
                return
            end
            if type(frame) ~= "table" then stats.InvalidFrames += 1; resync(); return end
            if frame.Schema ~= signature then stats.InvalidFrames += 1; resync(); return end
            if epoch > clientEpoch and frame.Full ~= true then stats.InvalidFrames += 1; resync(); return end
            if epoch == clientEpoch and integer(frame.Revision, 1, MAX_INTEGER) and frame.Revision < clientRevision then return end
            if epoch == clientEpoch and frame.Revision == clientRevision and clientState then
                send(controlRoute, nil, 1, epoch, clientRevision)
                return
            end
            local previous = if epoch == clientEpoch then clientState else nil
            local previousRevision = if epoch == clientEpoch and clientRevision > 0 then clientRevision else nil
            -- Malformed or stale frames must not unwind the receive callback.
            local applied, nextState, revision = pcall(codec.Apply, codec, previous, previousRevision, frame)
            if not applied or not nextState then stats.InvalidFrames += 1; resync(); return end
            local valid, copied = pcall(copyState, nextState)
            if not valid then stats.InvalidFrames += 1; resync(); return end
            if epoch ~= clientEpoch then commandSequence = 0 end
            clientEpoch, clientRevision, clientState = epoch, revision, copied
            send(controlRoute, nil, 1, epoch, revision)
            notify("Changed", clientState, clientRevision)
        end)
        connections[#connections + 1] = resultRoute:Connect(function(epoch, sequence, accepted, reason)
            if destroyed or epoch ~= clientEpoch or not integer(sequence, 1, commandSequence) or type(accepted) ~= "boolean" or type(reason) ~= "string" then return end
            notify("Result", sequence, accepted, reason)
        end)
    end
    connections[#connections + 1] = context.Heartbeat:Connect(function(dt)
        if destroyed then return end
        if net.IsDestroyed() then replica:Destroy(); return end
        elapsed += dt
        if elapsed < 1 / sendRate then return end
        elapsed = 0
        if server then
            for player, record in pairs(records) do
                if connected(player) then transmit(player, record) else records[player] = nil end
            end
        elseif not clientState then resync() end
    end)
    return table.freeze(replica)
end

return table.freeze(AuthoritativeState)
