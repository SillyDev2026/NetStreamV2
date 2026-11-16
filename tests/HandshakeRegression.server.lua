--!strict
-- Run by itself in ServerScriptService with ReplicatedStorage.Netstream (+ Compression child).
local Players = game:GetService("Players")
local NetStream = require(game:GetService("ReplicatedStorage"):WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.3.13", "Handshake regression requires NetStream 2.3.13")
local challenge = NetStream.Event("__NSHandshakeRegression", {Id = 34101, Compression = false})
local response = NetStream.Event("__NSHandshakeResponse", {Id = 34102, Compression = false})
local greeted = {}
response:Connect(function(player, token)
	assert(greeted[player] == token, "Handshake token mismatch")
	assert(NetStream.IsPeerReady(player), "Server received application data before READY")
	print("NetStream handshake roundtrip succeeded for", player.Name, NetStream.GetHandshakeStatus(player).Status)
end)
local function watch(player)
	task.spawn(function()
		local deadline = os.clock() + 20
		while player.Parent == Players and os.clock() < deadline do
			if NetStream.IsPeerReady(player) then
				local status = NetStream.GetHandshakeStatus(player)
				assert(status.Status == "ready", "Inconsistent server handshake state")
				local token = "hello-" .. tostring(player.UserId)
				greeted[player] = token
				challenge:FireClient(player, token)
				return
			end
			task.wait(0.05)
		end
		if player.Parent == Players then error("NetStream server handshake did not complete in 20 seconds") end
	end)
end
for _, player in ipairs(Players:GetPlayers()) do watch(player) end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(player) greeted[player] = nil end)
print("NetStream handshake regression server ready")
