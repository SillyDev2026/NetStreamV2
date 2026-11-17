--!strict
-- Standalone handshake replay regression for StarterPlayerScripts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.8.0", "Expected NetStream 3.8.0")
NetStream.Configure({HandshakeEnabled = true, HandshakeRequireReady = false})
NetStream.Start()
local started = os.clock()
while not NetStream.IsHandshakeReady() and os.clock() - started < 8 do task.wait(0.05) end
assert(NetStream.IsHandshakeReady(), "Initial handshake never became ready")
local folder = ReplicatedStorage:WaitForChild("__NetStream_NetStream")
local remote = folder:WaitForChild("H")
assert(remote:IsA("RemoteEvent"), "Handshake control remote unavailable")
local codec = NetStream.Compression.CodecVersion
local function hello(nonce)
	local value = buffer.create(9)
	buffer.writeu8(value, 0, 1)
	buffer.writeu8(value, 1, 1)
	buffer.writeu16(value, 2, codec)
	buffer.writeu8(value, 4, if NetStream.GetConfig().BitFrameEnabled then 1 else 0)
	buffer.writeu32(value, 5, nonce)
	remote:FireServer(value)
end
hello(391521)
task.wait(0.12)
hello(391522)
task.wait(0.12)
hello(391521) -- must be rejected: this nonce belongs to the previous session.
task.wait(0.12)
NetStream.RetryHandshake()
local retryStarted = os.clock()
while not NetStream.IsHandshakeReady() and os.clock() - retryStarted < 8 do task.wait(0.05) end
assert(NetStream.IsHandshakeReady(), "Handshake failed to recover after nonce replay")
print("NetStream handshake replay client recovery PASS")
