--!strict
local factory = loadSecureUIController()
local players = {}
local player = {Parent = players}
local allowed, near = false, false
local state = nil
local handlers, listeners = {}, {}
local dead = false
local replica = {}
function replica:Attach(owner, initial)
    assert(owner == player and not state)
    state = table.freeze(table.clone(initial))
    return 1
end
function replica:Update(owner, transform)
    assert(owner == player and state)
    state = table.freeze(table.clone(transform(table.clone(state))))
    for _, callback in ipairs(listeners) do callback(state, 1) end
end
function replica:Get() return state end
function replica:HandleCommand(name, spec) handlers[name] = spec end
function replica:SendCommand(name, payload)
    local spec = handlers[name]
    if not spec or spec.Validate(player, payload, state) ~= true then return false, "Denied" end
    state = table.freeze(table.clone(spec.Reduce(player, payload, table.clone(state))))
    for _, callback in ipairs(listeners) do callback(state, 2) end
    return true, 1
end
function replica:OnChanged(callback)
    listeners[#listeners + 1] = callback
    return {Disconnect = function() end}
end
function replica:OnCommandResult() return {Disconnect = function() end} end
function replica:RequestResync() return true end
function replica:GetStats() return {} end
function replica:Detach() state = nil; return true end
function replica:Destroy() dead = true end
local net = {CreateReplica = function() return replica end, IsDestroyed = function() return dead end}
local server = factory.Create(net, "Shop", {Id = 60000, Fields = {"Open", "Coins"}, CanOpen = function() return allowed and near end}, {Server = true, Players = players})
local client = factory.Create(net, "Shop", {Id = 60000, Fields = {"Open", "Coins"}}, {Server = false, Players = players})
server:Attach(player, {Open = true, Coins = 100})
assert(state.Open == false)
assert(not pcall(function() client:Open(player) end))
assert(not pcall(function() client:Attach(player, {Coins = 1}) end))
assert(not pcall(function() server:SendAction("Buy", {}) end))
assert(client:SendAction("Buy", {}) == false)
assert(server:Open(player) == false)
allowed = true
assert(server:Open(player) == false)
near = true
assert(server:Open(player) == true and state.Open == true)
local gui = {Enabled = true, IsA = function(_, klass) return klass == "ScreenGui" end}
local rendered = 0
client:Bind(gui, function(snapshot) rendered = snapshot.Coins end)
assert(gui.Enabled and rendered == 100)
local applied = 0
server:HandleAction("Buy", {
    Validate = function(_, payload, snapshot)
        for key in pairs(payload) do if key ~= "Item" then return false end end
        return payload.Item == 1 and snapshot.Coins >= 50
    end,
    Reduce = function(_, _, draft) applied += 1; draft.Coins -= 50; return draft end,
})
assert(client:SendAction("Buy", {Item = 2}) == false)
assert(client:SendAction("Buy", {Item = 1, Coins = 999999}) == false)
near = false
assert(client:SendAction("Buy", {Item = 1}) == false)
assert(applied == 0)
near = true
assert(client:SendAction("Buy", {Item = 1}) == true)
assert(applied == 1 and state.Coins == 50 and rendered == 50)
assert(server:Update(player, function(draft) draft.Open = false; return draft end) == false)
assert(server:Close(player) == true and not gui.Enabled)
assert(client:SendAction("Buy", {Item = 1}) == false)
player.Parent = nil
assert(server:Open(player) == false)
dead = true
assert(not pcall(function() client:SendAction("Buy", {}) end))
print("PASS SECURE UI: closed by default, server permissions, payload rejects, revocation, display sync and lifecycle")
