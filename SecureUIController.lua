--!strict
-- No client-rendered GUI is tamper-proof. All authority stays on the server.
local SecureUI = {}

function SecureUI.Create(net, name, options, context)
    assert(type(options) == "table" and type(options.Fields) == "table", "SecureUI requires Fields")
    local server, players = context.Server, context.Players
    local includesOpen = false
    for _, field in ipairs(options.Fields) do if field == "Open" then includesOpen = true end end
    assert(includesOpen, "SecureUI Fields must include Open")
    if server then assert(type(options.CanOpen) == "function", "Server requires CanOpen") end
    if options.CanAct ~= nil then assert(type(options.CanAct) == "function", "CanAct must be a function") end
    local replica = net.CreateReplica(name, {
        Id = options.Id, Fields = options.Fields,
        SendRate = options.SendRate, RetryInterval = options.RetryInterval,
        MaxStateBytes = options.MaxStateBytes,
        CommandRate = options.CommandRate, CommandBurst = options.CommandBurst,
    })
    local ui = {}
    local destroyed = false
    local function alive() assert(not destroyed and not net.IsDestroyed(), "SecureUI destroyed") end
    local function connected(player) return player ~= nil and player.Parent == players end

    function ui:Attach(player, initial)
        alive()
        assert(server and type(initial) == "table", "Attach requires server state table")
        local state = table.clone(initial)
        state.Open = false
        return replica:Attach(player, state)
    end
    function ui:Open(player)
        alive()
        assert(server, "Open is server-only")
        if not connected(player) or not replica:Get(player) then return false, "NotAttached" end
        local granted = false
        local ok = pcall(function()
            replica:Update(player, function(draft)
                if options.CanOpen(player, draft) ~= true then return draft end
                draft.Open = true
                granted = true
                return draft
            end)
        end)
        if not ok then return false, "UpdateFailed" end
        return if granted then true else false, if granted then nil else "Denied"
    end
    function ui:Close(player)
        alive()
        assert(server, "Close is server-only")
        if not connected(player) or not replica:Get(player) then return false, "NotAttached" end
        local ok = pcall(function()
            replica:Update(player, function(draft) draft.Open = false; return draft end)
        end)
        return ok, if ok then nil else "UpdateFailed"
    end
    function ui:Update(player, transform)
        alive()
        assert(server and type(transform) == "function", "Update requires server transform")
        if not connected(player) or not replica:Get(player) then return false, "NotAttached" end
        local ok = pcall(function()
            replica:Update(player, function(draft)
                local oldOpen = draft.Open
                local nextState = transform(draft)
                assert(type(nextState) == "table" and nextState.Open == oldOpen, "Use Open or Close to change visibility")
                return nextState
            end)
        end)
        return ok, if ok then nil else "UpdateFailed"
    end
    function ui:HandleAction(name, spec)
        alive()
        assert(server, "HandleAction is server-only")
        assert(type(spec) == "table" and type(spec.Validate) == "function" and type(spec.Reduce) == "function", "Action needs Validate and Reduce")
        local canAct = options.CanAct or options.CanOpen
        return replica:HandleCommand(name, {
            Rate = spec.Rate, Burst = spec.Burst,
            Validate = function(player, payload, state)
                if not connected(player) or state.Open ~= true then return false end
                if canAct(player, state, payload, name) ~= true then return false end
                return spec.Validate(player, payload, state) == true
            end,
            Reduce = spec.Reduce,
        })
    end
    function ui:SendAction(name, payload)
        alive()
        assert(not server, "SendAction is client-only")
        local state = replica:Get()
        if not state or state.Open ~= true then return false, "NotOpen" end
        return replica:SendCommand(name, payload)
    end
    function ui:Get(player)
        alive()
        if server then return replica:Get(player) end
        assert(player == nil, "Client cannot read another player")
        return replica:Get()
    end
    function ui:OnChanged(callback)
        alive()
        assert(not server, "OnChanged is client-only")
        return replica:OnChanged(callback)
    end
    function ui:OnActionResult(callback)
        alive()
        assert(not server, "OnActionResult is client-only")
        return replica:OnCommandResult(callback)
    end
    function ui:Bind(gui, render)
        alive()
        assert(not server, "Bind is client-only")
        assert(gui and (gui:IsA("ScreenGui") or gui:IsA("GuiObject")), "Bind needs ScreenGui or GuiObject")
        assert(type(render) == "function", "Bind needs renderer")
        local screen = gui:IsA("ScreenGui")
        if screen then gui.Enabled = false else gui.Visible = false end
        local function apply(state, revision)
            local open = state ~= nil and state.Open == true
            if screen then gui.Enabled = open else gui.Visible = open end
            if open then render(state, revision) end
        end
        local connection = replica:OnChanged(apply)
        apply(replica:Get(), 0)
        return connection
    end
    function ui:RequestResync()
        alive()
        assert(not server, "RequestResync is client-only")
        return replica:RequestResync()
    end
    function ui:Detach(player)
        alive()
        assert(server, "Detach is server-only")
        return replica:Detach(player)
    end
    function ui:GetStats(player) alive(); return replica:GetStats(player) end
    function ui:Destroy()
        if destroyed then return end
        destroyed = true
        replica:Destroy()
    end
    return table.freeze(ui)
end

return SecureUI
