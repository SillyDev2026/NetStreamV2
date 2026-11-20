# Secure UI Controller — Experimental Owner UI Protection

The server can control authorized UI state and actions, but **no Roblox LocalScript or ScreenGui is tamper-proof**. An attacker may hide, duplicate, or modify local pixels. This module prevents untrusted UI changes from granting server currency, inventory, or permissions when the game's server handlers are implemented correctly.

## Installation

In ReplicatedStorage use Netstream as a ModuleScript, with three children named Compression, AuthoritativeState, and SecureUIController, containing the corresponding repository Lua source files. Keep current module versions matching server and client.

Both sides create a controller with identical name, ID and ordered Fields. Fields must contain Open as a boolean; all fields are flat primitives. The controller reserves four consecutive Event IDs. Don't put confidential data into replicated UI fields.

## Server example

    --!strict
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
    local terminal = workspace:WaitForChild("ShopTerminal")

    local Shop = NetStream.CreateSecureUI("Shop", {
        Id = 61000,
        Fields = {"Open", "Coins", "Potions"},
        CanOpen = function(player)
            local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            return root ~= nil and (root.Position - terminal.Position).Magnitude <= 12
        end,
    })

    Shop:HandleAction("BuyPotion", {
        Rate = 3, Burst = 2,
        Validate = function(player, payload, state)
            for key in pairs(payload) do if key ~= "Item" then return false end end
            return payload.Item == 1 and state.Coins >= 50
        end,
        Reduce = function(player, payload, draft)
            draft.Coins -= 50
            draft.Potions += 1
            return draft
        end,
    })

    local function attach(player)
        -- Demo state only; load real values from server-owned profiles first.
        Shop:Attach(player, {Coins = 500, Potions = 0})
    end
    Players.PlayerAdded:Connect(attach)
    for _, player in Players:GetPlayers() do attach(player) end
    terminal.ProximityPrompt.Triggered:Connect(function(player)
        Shop:Open(player)
    end)

Opening requires an explicit server-only CanOpen(player, state) predicate that returns exactly true. When a client sends a command, server-side HandleAction checks: connected Player, Open is true, CanAct or CanOpen is still true, and the action-specific Validate predicate returns true. Only then can Reduce modify replica state. Action handlers must not yield and reducers must be pure state transforms.

CanAct(player, state, payload, name) is optional. By default, the CanOpen predicate is rechecked before *every* action, including after a UI was opened. Make CanOpen check server-owned facts such as distance, profile readiness, cooldown and permissions.

## Client example

Place a Shop ScreenGui in StarterGui with Frame containing CoinsLabel, PotionsLabel and BuyButton, and a LocalScript under the ScreenGui.

    --!strict
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
    local gui = script.Parent
    local Shop = NetStream.CreateSecureUI("Shop", {
        Id = 61000, Fields = {"Open", "Coins", "Potions"}
    })
    Shop:Bind(gui, function(state, revision)
        gui.Frame.CoinsLabel.Text = tostring(state.Coins)
        gui.Frame.PotionsLabel.Text = tostring(state.Potions)
    end)
    gui.Frame.BuyButton.MouseButton1Click:Connect(function()
        local queued, reason = Shop:SendAction("BuyPotion", {Item = 1})
        if not queued then warn("Not queued:", reason) end
    end)
    Shop:OnActionResult(function(sequence, accepted, reason)
        if not accepted then warn("Denied:", reason) end
    end)

Bind initially hides the GUI, then renders server-provided values whenever the replicated state has Open=true. An exploiter can override its GUI visibility or labels. Those changes are not trusted by server handlers. SendAction returning true means locally queued, **not approved**. Watch OnActionResult and OnChanged for server decisions and resulting state.

## API

Server:
- Attach(player, state): attaches with Open forced to false
- Open(player): grants access only when CanOpen approves
- Close(player): revokes Open
- Update(player, transform): updates data fields, but cannot modify Open; use Open/Close
- HandleAction(name, spec): requires non-yielding Validate and Reduce
- Detach(player): revokes the replica; retry tombstone protocol
- Get(player): current frozen server state
- GetStats(player?): replica counters
- Destroy(): closes the controller

Client:
- Bind(gui, render): render and show/hide UI from replicated state
- SendAction(name, payload): queue named action, only when local Open
- OnChanged(callback), OnActionResult(callback), RequestResync()
- Get(): local replica mirror
- GetStats(), Destroy()

## Security limits and verification

This module reuses owner-authoritative replica epochs, revision acknowledgements, resync, replay checks, command rate/size checks, and teardown guards. It does not make client scripts private, prevent local overlays, authenticate by hidden tokens, authorize gameplay automatically, or provide durable database transactions.

For real purchases and persistent inventory, integrate authoritative DataStore/NexusDataStore transactions and durable idempotency outside this module. Re-check mutable game state at commit; never trust a client-submitted price, balance, or item entitlement.

Before production:
- Run node scripts/runtime-tests.mjs.
- Run tests/AuthoritativeReplicaRegression.server.lua and matching client script in Roblox Studio with two players.
- Test invalid/extra payload fields, unauthorized panels, moving out of range, repeat/replay and spam, disconnection while active, resync and missing ACKs.
- Measure script CPU, retained heap, p95/p99 state latency, and recovery in real Studio sessions.

The standalone Luau test uses service doubles; CI success is not independent Studio multiplayer verification.
