--!native
--!optimize 2

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Compression = require(assert(script:WaitForChild("Compression", 10), "NetStream v2.1.0 requires a child ModuleScript named Compression (v2.9.0)"))
assert(type(Compression) == "table" and type(Compression.Version) == "function" and Compression.Version() == "2.9.0", "NetStream v2.1.0 requires Compression v2.9.0")
local IS_SERVER = RunService:IsServer()
local ALL = {}
local Internal = {}
Internal.BufferUtil = require(assert(script:WaitForChild("BufferUtil", 10), "NetStream v2.1.0 requires child BufferUtil v1.1.0+"))
assert(type(Internal.BufferUtil) == "table" and type(Internal.BufferUtil.VERSION) == "string", "NetStream v2.1.0 requires BufferUtil")
local VERSION = "2.1.0"
-- Legacy byte protocols are retained only for BitFrameEnabled=false fallback.
-- Keep them on Internal so BitFrame does not spend top-level Luau registers.
Internal.LEGACY_PROTOCOL = 0x30
Internal.LEGACY_PROTOCOL_SINGLE = 0x31
Internal.LEGACY_PROTOCOL_COMPACT_TABLE = 0x32
Internal.LEGACY_PROTOCOL_FAST_SCHEMA = 0x33
local LOG_PREFIX = "[NetStream v" .. VERSION .. "]"
local KIND_EVENT = 0
local KIND_CALL = 1
local KIND_RETURN = 2
local KIND_STATE = 3
local MAX_SAFE_INTEGER = 9007199254740991
local MAX_SAFE_VARINT_MAGNITUDE = math.floor(MAX_SAFE_INTEGER / 2)
local MAX_FLOAT32 = 3.4028234663852886e38

local TYPE_NIL = 0
local TYPE_BOOL = 1
local TYPE_UINT = 2
local TYPE_SINT = 3
local TYPE_F32 = 4
local TYPE_F64 = 5
local TYPE_STRING = 6
local TYPE_STRING_REF = 7
local TYPE_VECTOR3 = 8
local TYPE_CFRAME = 9
local TYPE_ARRAY = 10
local TYPE_MAP = 11
local TYPE_COLOR3 = 12
local TYPE_VECTOR2 = 13
local TYPE_BUFFER = 14
local TYPE_EXTENDED = 15

local EXT = table.freeze({
	RAW_STRING = 0,
	UDIM = 1,
	UDIM2 = 2,
	RECT = 3,
	NUMBER_RANGE = 4,
	BRICK_COLOR = 5,
	DATETIME = 6,
})

local DEFAULTS = {
	Namespace = "NetStream",
	RemoteWaitTimeout = 10,
	FlushRate = 60,
	MaxBatchMessages = 256,
	MaxOutgoingBatchBytes = 2 * 1024 * 1024,
	MaxIncomingPacketBytes = 2 * 1024 * 1024,
	MaxBatchesPerFlush = 8,
	MaxDispatchPerCycle = 2048,
	MaxDispatchBacklog = 16384,
	DispatchBudgetSeconds = 0.0025,
	FlushBudgetSeconds = 0.003,
	ImmediateFlushBudgetSeconds = 0.004,
	TimeoutSweepInterval = 0.25,
	MaxPoolSize = 2048,
	MaxPooledArgs = 32,
	MaxPooledWriterBytes = 128 * 1024,
	MaxPooledStrings = 2048,
	MaxBatchPoolSize = 64,
	MaxWriterPoolSize = 32,
	MaxScratchWriterPoolSize = 16,
	InitialWriterBytes = 1024,
	MaxTargetsPerFlush = 128,
	MaxIncomingMessagesPerSecond = 30000,
	MaxIncomingBytesPerSecond = 2 * 1024 * 1024,
	MaxIncomingBatchesPerSecond = 240,
	MaxGlobalIncomingMessagesPerSecond = 120000,
	MaxGlobalIncomingBytesPerSecond = 8 * 1024 * 1024,
	MaxGlobalIncomingBatchesPerSecond = 8192,
	MaxIncomingCallsPerSecond = 240,
	MaxGlobalIncomingCallsPerSecond = 4096,
	MaxReliableQueue = 8192,
	MaxUnreliableQueue = 2048,
	UnreliableMaxBytes = 900,
	CallTimeout = 8,
	VectorPrecision = 100,
	MaxIncomingMessages = 512,
	MaxStringBytes = 1024 * 1024,
	MaxBufferBytes = 1024 * 1024,
	MaxTableEntries = 8192,
	MaxDepth = 32,
	CompressionEnabled = true,
	CompressionMinSavingsBytes = 1,
	CompressionMinStringBytes = 6,
	CompressionStringStrategy = "Auto",
	CompressionUseStringDictionary = true,
	CompressionTableCompression = true,
	CompressionTableStrategy = "Auto",
	CompressionHomogeneousArrays = true,
	CompressionDeltaArrays = true,
	CompressionRunLengthArrays = true,
	CompressionCompactMapKeys = true,
	CompressionTableKeyMapping = true,
	CompressionMappedKeyMinUses = 2,
	CompressionMaxMappedKeys = 255,
	CompressionCompressBuffers = true,
	CompressionMinBufferBytes = 6,
	CompressionBufferStrategy = "Auto",
	CompressionEntropyCoding = true,
	CompressionEntropyStrategy = "Auto",
	CompressionHuffmanMinBytes = 256,
	CompressionRouteStrategyCache = true,
	CompressionRouteStrategyWarmup = 3,
	CompressionRouteStrategyResample = 64,
	CompressionHuffmanMinSavings = 2,
	CompressionHuffmanMaxCodeBits = 32,
	CompressionAllowExpansion = false,
	BandwidthGovernorEnabled = true,
	BandwidthLimitBytesPerSecond = 32 * 1024,
	BandwidthMaxPacketBytes = 1200,
	BandwidthMaxPacketsPerSecond = 60,
	BandwidthMaxReliableQueue = 2048,
	BandwidthMaxUnreliableQueue = 512,
	BandwidthDropUnreliableOnPressure = true,
	BandwidthWarnAtUtilization = 0.85,
	TransportAdaptiveBatching = true,
	TransportBatchWindowSeconds = 1 / 60,
	TransportRealtimeBatchWindowSeconds = 0,
	TransportEstimatedPacketOverheadBytes = 96,
	TransportTargetMessagesPerPacket = 16,
	FastSchemaEnabled = true,
	FastSchemaMaxBytes = 512,
	FastSchemaAllowHeaderExpansion = false,
	PackedSchemaRunEnabled = true,
	PackedSchemaRunMaxFields = 8,
	BitPacketEnabled = true,
	BitPacketCompressedCalls = true,
	HybridCodecEnabled = true,
	HybridSmallScalarEnabled = true,
	HybridSmallPacketMaxBits = 256,
	HybridSmallStringMaxBytes = 31,
	HybridCompressionThresholdBits = 512,
	HybridMinPhysicalSavingsBytes = 1,
	BitFrameEnabled = true,
	BitFrameMaxBytes = 2 * 1024 * 1024,
	BitFrameTinyScalarEnabled = true,
	Debug = false,
}

local Config = table.clone(DEFAULTS)
local started = false
local destroyed = false
local reliableRemote = nil
local unreliableRemote = nil
local heartbeatConnection = nil
local playerRemovingConnection = nil
local receiveConnections = {}
local accumulator = 0
local timeoutAccumulator = 0
local requestId = 0
local pending = {}
local targetBuckets = {}
local activeTargets = {}
local activeTargetHead = 1
local activeTargetTail = 0
local incomingRates = {}
local clientBucket = nil
local broadcastBucket = nil
local eventRoutes = {}
local functionRoutes = {}
local stateRoutes = {}
local eventNames = {}
local functionNames = {}
local stateNames = {}
local peerStates = {}
local fallbackCallHandler = nil
local dispatchRoutes = {}
local dispatchPlayers = {}
local dispatchArgs = {}
local dispatchScalarFlags = {}
local dispatchScalarValues = {}
local dispatchCount = 0
local dispatchHead = 1
local lastPacketBytes = 0
local overflowWarned = false
local writerPool = {}
local scratchWriterPool = {}
local readerPool = {}
local messagePool = {}
local argsPool = {}
local batchPool = {}
local packedValuePool = {}
local globalIncomingRate = nil
Internal.bandwidthStates = {}
Internal.trafficWindowEstimatedTransportBytes = 0
local trafficWindowStarted = os.clock()
local trafficWindowSentBytes = 0
local trafficWindowReceivedBytes = 0
local trafficWindowSentMessages = 0
local trafficWindowReceivedMessages = 0
local trafficWindowSentBatches = 0
local trafficWindowReceivedBatches = 0
local trafficSnapshot = {
	SentBytesPerSecond = 0,
	ReceivedBytesPerSecond = 0,
	SentMessagesPerSecond = 0,
	ReceivedMessagesPerSecond = 0,
	SentBatchesPerSecond = 0,
	ReceivedBatchesPerSecond = 0,
	BandwidthLimitBytesPerSecond = 0,
	BandwidthUtilization = 0,
	BandwidthHeadroomBytesPerSecond = 0,
	EstimatedTransportBytesPerSecond = 0,
	EstimatedTransportUtilization = 0,
	EstimatedTransportHeadroomBytesPerSecond = 0,
}

local EMPTY_ARGS = table.freeze({ n = 0 })
local TRUE_ARGS = table.freeze({ true, n = 1 })
local FALSE_ARGS = table.freeze({ false, n = 1 })

local Stats = {
	SentBatches = 0,
	SentBytes = 0,
	ReceivedBatches = 0,
	ReceivedBytes = 0,
	FallbackReliable = 0,
	DroppedUnreliable = 0,
	RejectedReliable = 0,
	DecodeErrors = 0,
	CallsTimedOut = 0,
	SentMessages = 0,
	ReceivedMessages = 0,
	SchemaMessages = 0,
	DynamicMessages = 0,
	CoalescedLatest = 0,
	MessagePoolHits = 0,
	ArgsPoolHits = 0,
	WriterPoolHits = 0,
	ReaderPoolHits = 0,
	RateLimitedBatches = 0,
	GlobalRateLimitedBatches = 0,
	RateLimitedCalls = 0,
	GlobalRateLimitedCalls = 0,
	RejectedMessages = 0,
	RejectedMalformedPackets = 0,
	RejectedOversizedPackets = 0,
	DroppedDispatch = 0,
	BatchPoolHits = 0,
	ManualFlushes = 0,
	ImmediateFlushes = 0,
	CancelledLatest = 0,
	CancelledQueued = 0,
	RouteRateLimited = 0,
	TrafficSnapshots = 0,
	CompressionAttempts = 0,
	CompressionUsed = 0,
	CompressionRejected = 0,
	CompressionErrors = 0,
	CompressionNoGain = 0,
	CompressionDecodeCount = 0,
	CompressionInputBytes = 0,
	CompressionOutputBytes = 0,
	CompressionSavedBytes = 0,
	CompressionInputBits = 0,
	CompressionUsefulBits = 0,
	CompressionPhysicalBits = 0,
	CompressionPaddingBits = 0,
	CompressionUsefulBitsSaved = 0,
	CompressionBitPackedPackets = 0,
	CompressionNativeSizeEstimates = 0,
	CompressionNativeScratchAvoided = 0,
	CompressionOptionsCacheHits = 0,
	CompressionStrategyCacheHits = 0,
	CompressionStrategyCacheMisses = 0,
	CompressionStrategyCacheLocks = 0,
	CompressionStrategyCacheResamples = 0,
	CompressionStrategyCacheResets = 0,
	CompressionCompactTableUsed = 0,
	CompressionDynamicTableUsed = 0,
	CompressionDirectTableUsed = 0,
	CompressionTailLengthElisions = 0,
	CompressionCompactSingleSent = 0,
	CompressionCompactSingleReceived = 0,
	CompressionFramingBytesSaved = 0,
	CompressionEstimatedNetBytesSaved = 0,
	SingleMessagePackets = 0,
	SingleMessageHeaderBytesSaved = 0,
	CompressedSchemaStrings = 0,
	SchemaStringBytesSaved = 0,
	CompressedSchemaBuffers = 0,
	SchemaBufferBytesSaved = 0,
	CompressionMappedTableUsed = 0,
	BandwidthGovernedBatches = 0,
	BandwidthGovernedBytes = 0,
	BandwidthDeferredFlushes = 0,
	BandwidthDeferredBatches = 0,
	BandwidthDeferredBytes = 0,
	BandwidthDroppedUnreliableMessages = 0,
	BandwidthQueuePressureDrops = 0,
	BandwidthOversizedPackets = 0,
	BandwidthBatchSplits = 0,
	BandwidthThrottleEvents = 0,
	TransportLogicalMessagesQueued = 0,
	TransportBatchHolds = 0,
	TransportCriticalMessagesQueued = 0,
	TransportNormalMessagesQueued = 0,
	TransportRealtimeMessagesQueued = 0,
	TransportEstimatedOverheadBytes = 0,
	TransportEstimatedBytes = 0,
	TransportTargetFlushes = 0,
	TransportImmediateDeferred = 0,
	FastSchemaSent = 0,
	FastSchemaReceived = 0,
	FastSchemaBytes = 0,
	FastSchemaHeaderBytesSaved = 0,
	FixedSchemaFastWrites = 0,
	FixedSchemaFastReads = 0,
	ScratchWriterPoolHits = 0,
	PackedSchemaRunItems = 0,
	PackedSchemaRunMessages = 0,
	PackedSchemaRunAppends = 0,
	PackedValuePoolHits = 0,
	ScalarDispatches = 0,
	BitPacketCallsSent = 0,
	BitPacketCallsReceived = 0,
	BitPacketHeaderBits = 0,
	BitPacketHeaderBitsSaved = 0,
	BitPacketPaddingBits = 0,
	HybridBufferUtilSent = 0,
	HybridBufferUtilReceived = 0,
	HybridBufferUtilUsefulBits = 0,
	HybridBufferUtilPhysicalBits = 0,
	HybridBufferUtilPaddingBits = 0,
	HybridBufferUtilBytesSaved = 0,
	HybridCompressionThresholdSkips = 0,
	HybridCompressionThresholdAttempts = 0,
	BitFramePacketsEncoded = 0,
	BitFramePacketsSent = 0,
	BitFramePacketsReceived = 0,
	BitFrameMessagesEncoded = 0,
	BitFrameMessagesDecoded = 0,
	BitFrameUsefulBits = 0,
	BitFramePhysicalBits = 0,
	BitFramePaddingBits = 0,
	BitFrameProtocolBytesElided = 0,
	BitFrameBatchCountBytesElided = 0,
	BitFrameTinyValues = 0,
	BitFrameNativeValues = 0,
	BitFrameCompressedValues = 0,
}

local Float32Tag = {}
local RawStringTag = {}

Internal._compressionOptionsCache = nil
Internal._lastEncodedUsefulBits = 0
Internal._lastEncodedCodec = "None"
Internal._lastEncodedProtocolBytesElided = 0
Internal._lastEncodedBatchCountBytesElided = 0
Internal.LastSendStats = {
	Bytes = 0,
	PhysicalBits = 0,
	UsefulBits = 0,
	PaddingBits = 0,
	Codec = "None",
}
Internal.BIT_CALL_MARKER = 0
Internal.HYBRID_EVENT_STATE_MARKER = 1
Internal.HYBRID_CALL_MARKER = 2
Internal.HYBRID_RETURN_MARKER = 3

function Internal.compressionOptions()
	local cached = Internal._compressionOptionsCache
	if cached ~= nil then
		Stats.CompressionOptionsCacheHits += 1
		return cached
	end
	local options = {
		Mode = "Binary",
		CompressStrings = true,
		StringMinLength = Config.CompressionMinStringBytes,
		StringStrategy = Config.CompressionStringStrategy,
		UseStringDictionary = Config.CompressionUseStringDictionary,
		TableCompression = Config.CompressionTableCompression,
		TableStrategy = Config.CompressionTableStrategy,
		HomogeneousArrays = Config.CompressionHomogeneousArrays,
		DeltaArrays = Config.CompressionDeltaArrays,
		RunLengthArrays = Config.CompressionRunLengthArrays,
		CompactMapKeys = Config.CompressionCompactMapKeys,
		TableKeyMapping = Config.CompressionTableKeyMapping,
		MappedKeyMinUses = Config.CompressionMappedKeyMinUses,
		MaxMappedKeys = Config.CompressionMaxMappedKeys,
		CompressBuffers = Config.CompressionCompressBuffers,
		BufferMinLength = Config.CompressionMinBufferBytes,
		BufferStrategy = Config.CompressionBufferStrategy,
		EntropyCoding = Config.CompressionEntropyCoding,
		EntropyStrategy = Config.CompressionEntropyStrategy,
		HuffmanMinBytes = Config.CompressionHuffmanMinBytes,
		HuffmanMinSavings = Config.CompressionHuffmanMinSavings,
		HuffmanMaxCodeBits = Config.CompressionHuffmanMaxCodeBits,
		AllowExpansion = Config.CompressionAllowExpansion,
	}
	Internal._compressionOptionsCache = options
	return options
end
-- Records v2.9 logical bit usage separately from physical wire bytes.
-- Framing bytes added by NetStream are counted as fully useful because they
-- carry protocol information; Compression padding is the only removable tail.
function Internal.recordCompressionPacketBits(packet, inputBytes, outputBytes)
	if type(packet) ~= "table" or typeof(packet.Data) ~= "buffer" then
		return
	end
	local payloadPhysicalBits = packet.PhysicalBits or buffer.len(packet.Data) * 8
	local payloadUsefulBits = packet.UsefulBits or packet.Bits or payloadPhysicalBits
	local outputPhysicalBits = math.max(0, outputBytes) * 8
	local framingBits = math.max(0, outputPhysicalBits - payloadPhysicalBits)
	local outputUsefulBits = payloadUsefulBits + framingBits
	local paddingBits = packet.PaddingBits or math.max(0, payloadPhysicalBits - payloadUsefulBits)
	local inputBits = math.max(0, inputBytes) * 8

	Stats.CompressionInputBits += inputBits
	Stats.CompressionUsefulBits += outputUsefulBits
	Stats.CompressionPhysicalBits += outputPhysicalBits
	Stats.CompressionPaddingBits += paddingBits
	if paddingBits > 0 or payloadUsefulBits < payloadPhysicalBits then
		Stats.CompressionBitPackedPackets += 1
	end
	local saved = inputBits - outputUsefulBits
	if saved > 0 then
		Stats.CompressionUsefulBitsSaved += saved
	end
end

function Internal.varUIntByteLength(value)
	local bytes = 1
	while value >= 128 do
		value = math.floor(value / 128)
		bytes += 1
	end
	return bytes
end


-- Packet-level LSB-first bit primitives used by the v1.8 compact call path.
-- These deliberately operate on a final Roblox buffer: only the very end of
-- the packet is rounded to a whole byte.
function Internal.packetWriteBits(data, bitPosition, value, count)
	Internal.BufferUtil.writeBits(data, bitPosition, count, value)
	return bitPosition + count
end

function Internal.packetReadBits(data, bitPosition, count)
	if bitPosition + count > buffer.len(data) * 8 then error("NetStream bit packet ended unexpectedly", 0) end
	return Internal.BufferUtil.readBits(data, bitPosition, count), bitPosition + count
end

function Internal.packetAdaptiveUIntBitLength(value)
	if value == 0 then return 1 end
	if value <= 8 then return 5 end
	if value <= 40 then return 8 end
	return 3 + Internal.varUIntByteLength(value) * 8
end

function Internal.packetWriteAdaptiveUInt(data, bitPosition, value)
	if value == 0 then
		return Internal.packetWriteBits(data, bitPosition, 0, 1)
	elseif value <= 8 then
		bitPosition = Internal.packetWriteBits(data, bitPosition, 1, 2)
		return Internal.packetWriteBits(data, bitPosition, value - 1, 3)
	elseif value <= 40 then
		bitPosition = Internal.packetWriteBits(data, bitPosition, 3, 3)
		return Internal.packetWriteBits(data, bitPosition, value - 9, 5)
	end
	bitPosition = Internal.packetWriteBits(data, bitPosition, 7, 3)
	repeat
		local byte = value % 128
		value = math.floor(value / 128)
		if value > 0 then byte += 128 end
		bitPosition = Internal.packetWriteBits(data, bitPosition, byte, 8)
	until value == 0
	return bitPosition
end

function Internal.packetReadAdaptiveUInt(data, bitPosition)
	local bit
	bit, bitPosition = Internal.packetReadBits(data, bitPosition, 1)
	if bit == 0 then return 0, bitPosition end
	bit, bitPosition = Internal.packetReadBits(data, bitPosition, 1)
	if bit == 0 then
		local payload
		payload, bitPosition = Internal.packetReadBits(data, bitPosition, 3)
		return payload + 1, bitPosition
	end
	bit, bitPosition = Internal.packetReadBits(data, bitPosition, 1)
	if bit == 0 then
		local payload
		payload, bitPosition = Internal.packetReadBits(data, bitPosition, 5)
		return payload + 9, bitPosition
	end
	local result = 0
	local multiplier = 1
	for _ = 1, 8 do
		local byte
		byte, bitPosition = Internal.packetReadBits(data, bitPosition, 8)
		result += (byte % 128) * multiplier
		if byte < 128 then return result, bitPosition end
		multiplier *= 128
	end
	error("NetStream bit packet contains an invalid VarUInt", 0)
end

function Internal.packetAppendBufferBits(out, bitPosition, payload)
	for i = 0, buffer.len(payload) - 1 do
		bitPosition = Internal.packetWriteBits(out, bitPosition, buffer.readu8(payload, i), 8)
	end
	return bitPosition
end

function Internal.packetReadBufferBits(data, bitPosition, byteCount)
	local out = buffer.create(byteCount)
	for i = 0, byteCount - 1 do
		local byte
		byte, bitPosition = Internal.packetReadBits(data, bitPosition, 8)
		buffer.writeu8(out, i, byte)
	end
	return out, bitPosition
end

local isInteger
local isFiniteNumber
local clampInteger

Internal.HYBRID_NIL = 0
Internal.HYBRID_BOOL = 1
Internal.HYBRID_UINT = 2
Internal.HYBRID_SINT = 3
Internal.HYBRID_F32 = 4
Internal.HYBRID_F64 = 5
Internal.HYBRID_STRING = 6
Internal.HYBRID_COLOR3 = 7
Internal.HYBRID_FLOAT_SCRATCH = buffer.create(8)

function Internal.hybridScalarBitLength(value)
	if value == nil then return 3 end
	local t, rt = type(value), typeof(value)
	if t == "boolean" then return 4 end
	if t == "number" then
		if isInteger(value) and value >= 0 and value <= MAX_SAFE_INTEGER then return 3 + Internal.packetAdaptiveUIntBitLength(value) end
		if isInteger(value) and value < 0 and -value <= MAX_SAFE_VARINT_MAGNITUDE then return 3 + Internal.packetAdaptiveUIntBitLength(-value * 2 - 1) end
		if isFiniteNumber(value) then return 67 end
		return nil
	end
	if t == "string" then
		if #value > Config.HybridSmallStringMaxBytes then return nil end
		return 3 + Internal.packetAdaptiveUIntBitLength(#value) + #value * 8
	end
	if rt == "Color3" then return 27 end
	if t == "table" and getmetatable(value) == Float32Tag then
		local n = value[1]
		if isFiniteNumber(n) and math.abs(n) <= MAX_FLOAT32 then return 35 end
	end
	return nil
end

function Internal.hybridWriteScalar(data, bitPosition, value)
	if value == nil then return Internal.packetWriteBits(data, bitPosition, Internal.HYBRID_NIL, 3) end
	local t, rt = type(value), typeof(value)
	if t == "boolean" then
		bitPosition = Internal.packetWriteBits(data, bitPosition, Internal.HYBRID_BOOL, 3)
		return Internal.packetWriteBits(data, bitPosition, value and 1 or 0, 1)
	elseif t == "number" then
		if isInteger(value) and value >= 0 and value <= MAX_SAFE_INTEGER then
			bitPosition = Internal.packetWriteBits(data, bitPosition, Internal.HYBRID_UINT, 3)
			return Internal.packetWriteAdaptiveUInt(data, bitPosition, value)
		elseif isInteger(value) and value < 0 and -value <= MAX_SAFE_VARINT_MAGNITUDE then
			bitPosition = Internal.packetWriteBits(data, bitPosition, Internal.HYBRID_SINT, 3)
			return Internal.packetWriteAdaptiveUInt(data, bitPosition, -value * 2 - 1)
		end
		bitPosition = Internal.packetWriteBits(data, bitPosition, Internal.HYBRID_F64, 3)
		buffer.writef64(Internal.HYBRID_FLOAT_SCRATCH, 0, value)
		bitPosition = Internal.packetWriteBits(data, bitPosition, buffer.readu32(Internal.HYBRID_FLOAT_SCRATCH, 0), 32)
		return Internal.packetWriteBits(data, bitPosition, buffer.readu32(Internal.HYBRID_FLOAT_SCRATCH, 4), 32)
	elseif t == "string" then
		bitPosition = Internal.packetWriteBits(data, bitPosition, Internal.HYBRID_STRING, 3)
		bitPosition = Internal.packetWriteAdaptiveUInt(data, bitPosition, #value)
		for i = 1, #value do bitPosition = Internal.packetWriteBits(data, bitPosition, string.byte(value, i), 8) end
		return bitPosition
	elseif rt == "Color3" then
		bitPosition = Internal.packetWriteBits(data, bitPosition, Internal.HYBRID_COLOR3, 3)
		bitPosition = Internal.packetWriteBits(data, bitPosition, clampInteger(math.floor(value.R * 255 + 0.5), 0, 255), 8)
		bitPosition = Internal.packetWriteBits(data, bitPosition, clampInteger(math.floor(value.G * 255 + 0.5), 0, 255), 8)
		return Internal.packetWriteBits(data, bitPosition, clampInteger(math.floor(value.B * 255 + 0.5), 0, 255), 8)
	elseif t == "table" and getmetatable(value) == Float32Tag then
		bitPosition = Internal.packetWriteBits(data, bitPosition, Internal.HYBRID_F32, 3)
		buffer.writef32(Internal.HYBRID_FLOAT_SCRATCH, 0, value[1])
		return Internal.packetWriteBits(data, bitPosition, buffer.readu32(Internal.HYBRID_FLOAT_SCRATCH, 0), 32)
	end
	error("NetStream hybrid scalar encoder unsupported value", 0)
end

function Internal.hybridReadScalar(data, bitPosition)
	local tag; tag, bitPosition = Internal.packetReadBits(data, bitPosition, 3)
	if tag == Internal.HYBRID_NIL then return nil, bitPosition end
	if tag == Internal.HYBRID_BOOL then local v; v, bitPosition = Internal.packetReadBits(data, bitPosition, 1); return v ~= 0, bitPosition end
	if tag == Internal.HYBRID_UINT then return Internal.packetReadAdaptiveUInt(data, bitPosition) end
	if tag == Internal.HYBRID_SINT then
		local z; z, bitPosition = Internal.packetReadAdaptiveUInt(data, bitPosition)
		return (if z % 2 == 0 then z / 2 else -((z + 1) / 2)), bitPosition
	end
	if tag == Internal.HYBRID_F32 then
		local bits; bits, bitPosition = Internal.packetReadBits(data, bitPosition, 32)
		buffer.writeu32(Internal.HYBRID_FLOAT_SCRATCH, 0, bits)
		local value = buffer.readf32(Internal.HYBRID_FLOAT_SCRATCH, 0)
		if not isFiniteNumber(value) then error("NetStream hybrid float32 is not finite", 0) end
		return value, bitPosition
	end
	if tag == Internal.HYBRID_F64 then
		local lo, hi; lo, bitPosition = Internal.packetReadBits(data, bitPosition, 32); hi, bitPosition = Internal.packetReadBits(data, bitPosition, 32)
		buffer.writeu32(Internal.HYBRID_FLOAT_SCRATCH, 0, lo); buffer.writeu32(Internal.HYBRID_FLOAT_SCRATCH, 4, hi)
		local value = buffer.readf64(Internal.HYBRID_FLOAT_SCRATCH, 0)
		if not isFiniteNumber(value) then error("NetStream hybrid float64 is not finite", 0) end
		return value, bitPosition
	end
	if tag == Internal.HYBRID_STRING then
		local len; len, bitPosition = Internal.packetReadAdaptiveUInt(data, bitPosition)
		if len > Config.HybridSmallStringMaxBytes or len > Config.MaxStringBytes then error("NetStream hybrid string too large", 0) end
		local chars = table.create(len)
		for i = 1, len do local b; b, bitPosition = Internal.packetReadBits(data, bitPosition, 8); chars[i] = string.char(b) end
		return table.concat(chars), bitPosition
	end
	if tag == Internal.HYBRID_COLOR3 then
		local r,g,b; r,bitPosition=Internal.packetReadBits(data,bitPosition,8); g,bitPosition=Internal.packetReadBits(data,bitPosition,8); b,bitPosition=Internal.packetReadBits(data,bitPosition,8)
		return Color3.fromRGB(r,g,b), bitPosition
	end
	error("NetStream invalid hybrid scalar tag", 0)
end

function Internal.hybridCompressionAllowed(item, rawBits)
	if not Config.HybridCodecEnabled then return true end
	local route = Internal.routeForItem(item)
	if route and route.Compression == true then Stats.HybridCompressionThresholdAttempts += 1; return true end
	if rawBits < Config.HybridCompressionThresholdBits then Stats.HybridCompressionThresholdSkips += 1; return false end
	Stats.HybridCompressionThresholdAttempts += 1
	return true
end

function Internal.recordHybridPacket(usefulBits, physicalBytes, nativeBytes)
	local physicalBits = physicalBytes * 8
	Stats.HybridBufferUtilSent += 1
	Stats.HybridBufferUtilUsefulBits += usefulBits
	Stats.HybridBufferUtilPhysicalBits += physicalBits
	Stats.HybridBufferUtilPaddingBits += math.max(0, physicalBits - usefulBits)
	Stats.HybridBufferUtilBytesSaved += math.max(0, nativeBytes - physicalBytes)
end

function Internal.canCompressionRoundTrip(value, seen)
	local kind = typeof(value)
	if kind == "nil" or kind == "boolean" or kind == "number" or kind == "string"
		or kind == "buffer" or kind == "Vector2" or kind == "Vector3" or kind == "Color3" or kind == "CFrame"
		or kind == "UDim" or kind == "UDim2" or kind == "Rect" or kind == "NumberRange"
		or kind == "BrickColor" or kind == "DateTime" then
		return true
	elseif kind ~= "table" then
		return false
	end

	local mt = getmetatable(value)
	if mt == Float32Tag or mt == RawStringTag then
		return false
	end

	seen = seen or {}
	if seen[value] then
		return false
	end
	seen[value] = true
	for key, child in pairs(value) do
		if not Internal.canCompressionRoundTrip(key, seen) or not Internal.canCompressionRoundTrip(child, seen) then
			seen[value] = nil
			return false
		end
	end
	seen[value] = nil
	return true
end

function Internal.shouldAttemptCompression(args)
	if not Internal.canCompressionRoundTrip(args, {}) then
		return false
	end
	for i = 1, args.n do
		local value = args[i]
		local kind = typeof(value)
		if kind == "string" and #value >= Config.CompressionMinStringBytes then
			return true
		elseif kind == "buffer" and Config.CompressionCompressBuffers and buffer.len(value) >= Config.CompressionMinBufferBytes then
			return true
		elseif kind == "table" then
			return true
		end
	end
	return false
end

local SCHEMA_BOOL = 1
local SCHEMA_U8 = 2
local SCHEMA_U16 = 3
local SCHEMA_I16 = 4
local SCHEMA_U32 = 5
local SCHEMA_I32 = 6
local SCHEMA_VARUINT = 7
local SCHEMA_VARINT = 8
local SCHEMA_F32 = 9
local SCHEMA_F64 = 10
local SCHEMA_STRING = 11
local SCHEMA_BUFFER = 12
local SCHEMA_VECTOR3Q = 13
local SCHEMA_VECTOR2Q = 14
local SCHEMA_CFRAMEQ = 15
local SCHEMA_COLOR3 = 16
local SCHEMA_EXT = table.freeze({
	UDIM = 17,
	UDIM2 = 18,
	RECT = 19,
	NUMBER_RANGE = 20,
	BRICK_COLOR = 21,
	DATETIME = 22,
})

function Internal.schemaType(kind, name, precision)
	return table.freeze({
		_netstreamSchemaType = true,
		Kind = kind,
		Name = name,
		Precision = precision,
	})
end

local Types = {
	Bool = Internal.schemaType(SCHEMA_BOOL, "Bool"),
	U8 = Internal.schemaType(SCHEMA_U8, "U8"),
	U16 = Internal.schemaType(SCHEMA_U16, "U16"),
	I16 = Internal.schemaType(SCHEMA_I16, "I16"),
	U32 = Internal.schemaType(SCHEMA_U32, "U32"),
	I32 = Internal.schemaType(SCHEMA_I32, "I32"),
	VarUInt = Internal.schemaType(SCHEMA_VARUINT, "VarUInt"),
	VarInt = Internal.schemaType(SCHEMA_VARINT, "VarInt"),
	F32 = Internal.schemaType(SCHEMA_F32, "F32"),
	F64 = Internal.schemaType(SCHEMA_F64, "F64"),
	String = Internal.schemaType(SCHEMA_STRING, "String"),
	Buffer = Internal.schemaType(SCHEMA_BUFFER, "Buffer"),
	Color3 = Internal.schemaType(SCHEMA_COLOR3, "Color3"),
	UDim = Internal.schemaType(SCHEMA_EXT.UDIM, "UDim"),
	UDim2 = Internal.schemaType(SCHEMA_EXT.UDIM2, "UDim2"),
	Rect = Internal.schemaType(SCHEMA_EXT.RECT, "Rect"),
	NumberRange = Internal.schemaType(SCHEMA_EXT.NUMBER_RANGE, "NumberRange"),
	BrickColor = Internal.schemaType(SCHEMA_EXT.BRICK_COLOR, "BrickColor"),
	DateTime = Internal.schemaType(SCHEMA_EXT.DATETIME, "DateTime"),
}

function Types.Vector3Q(precision)
	precision = precision or 100
	assert(type(precision) == "number" and precision == precision and precision > 0 and precision ~= math.huge, "Vector3Q precision must be a finite number > 0")
	return Internal.schemaType(SCHEMA_VECTOR3Q, "Vector3Q", precision)
end

function Types.Vector2Q(precision)
	precision = precision or 100
	assert(type(precision) == "number" and precision == precision and precision > 0 and precision ~= math.huge, "Vector2Q precision must be a finite number > 0")
	return Internal.schemaType(SCHEMA_VECTOR2Q, "Vector2Q", precision)
end

function Types.CFrameQ(precision)
	precision = precision or 100
	assert(type(precision) == "number" and precision == precision and precision > 0 and precision ~= math.huge, "CFrameQ precision must be a finite number > 0")
	return Internal.schemaType(SCHEMA_CFRAMEQ, "CFrameQ", precision)
end

function Internal.debugWarn(...)
	if Config.Debug then
		warn(LOG_PREFIX, ...)
	end
end

isInteger = function(n)
	return n == math.floor(n)
end

isFiniteNumber = function(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function quantizedComponentIsSafe(n, precision)
	return isFiniteNumber(n) and math.abs(n * precision) <= MAX_SAFE_VARINT_MAGNITUDE
end

local function cframeIsFinite(value, precision)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()
	if not quantizedComponentIsSafe(x, precision) or not quantizedComponentIsSafe(y, precision) or not quantizedComponentIsSafe(z, precision) then
		return false
	end
	return isFiniteNumber(r00) and isFiniteNumber(r01) and isFiniteNumber(r02)
		and isFiniteNumber(r10) and isFiniteNumber(r11) and isFiniteNumber(r12)
		and isFiniteNumber(r20) and isFiniteNumber(r21) and isFiniteNumber(r22)
end

clampInteger = function(n, minValue, maxValue)
	if n < minValue then
		return minValue
	elseif n > maxValue then
		return maxValue
	end
	return n
end

local function roundScaled(n, scale)
	local scaled = n * scale
	if scaled >= 0 then
		return math.floor(scaled + 0.5)
	end
	return math.ceil(scaled - 0.5)
end

function Internal.hashName(name)
	local hash = 5381
	for i = 1, #name do
		hash = (hash * 33 + string.byte(name, i)) % 2147483647
	end
	if hash == 0 then
		hash = 1
	end
	return hash
end

function Internal.resolveId(nameOrId, names, prefix, explicitId)
	if type(nameOrId) == "number" then
		assert(isInteger(nameOrId) and nameOrId > 0 and nameOrId <= 2147483647, "NetStream route id must be an integer from 1 to 2147483647")
		return nameOrId, names[nameOrId] or tostring(nameOrId)
	end
	assert(type(nameOrId) == "string" and #nameOrId > 0, "NetStream route must be a non-empty string or positive integer")
	local id
	if explicitId ~= nil then
		assert(type(explicitId) == "number" and isInteger(explicitId) and explicitId > 0 and explicitId <= 2147483647, "NetStream explicit route Id must be an integer from 1 to 2147483647")
		id = explicitId
	else
		id = Internal.hashName(prefix .. nameOrId)
	end
	local existing = names[id]
	if existing and existing ~= nameOrId then
		error(string.format("NetStream route hash collision between %q and %q. Use explicit numeric ids for one of them.", existing, nameOrId), 3)
	end
	names[id] = nameOrId
	return id, nameOrId
end

local Writer = {}
Writer.__index = Writer

function Writer.new(capacity, maxBytes)
	capacity = capacity or 256
	return setmetatable({
		buffer = buffer.create(capacity),
		capacity = capacity,
		maxBytes = maxBytes,
		position = 0,
		strings = {},
		stringToIndex = {},
		lastEventRoute = nil,
		lastCallRoute = nil,
		lastStateRoute = nil,
	}, Writer)
end

function Writer:reset()
	self.position = 0
	if #self.strings > Config.MaxPooledStrings then
		self.strings = {}
		self.stringToIndex = {}
	else
		table.clear(self.strings)
		table.clear(self.stringToIndex)
	end
	self.lastEventRoute = nil
	self.lastCallRoute = nil
	self.lastStateRoute = nil
end

function Writer:ensure(bytes)
	local needed = self.position + bytes
	if self.maxBytes and needed > self.maxBytes then
		error("NetStream batch exceeds MaxOutgoingBatchBytes", 0)
	end
	if needed <= self.capacity then
		return
	end
	local newCapacity = self.capacity
	while newCapacity < needed do
		newCapacity *= 2
	end
	local nextBuffer = buffer.create(newCapacity)
	if self.position > 0 then
		buffer.copy(nextBuffer, 0, self.buffer, 0, self.position)
	end
	self.buffer = nextBuffer
	self.capacity = newCapacity
end

function Writer:u8(value)
	self:ensure(1)
	buffer.writeu8(self.buffer, self.position, value)
	self.position += 1
end

function Writer:i16(value)
	self:ensure(2)
	buffer.writei16(self.buffer, self.position, value)
	self.position += 2
end

function Writer:u16(value)
	self:ensure(2)
	buffer.writeu16(self.buffer, self.position, value)
	self.position += 2
end

function Writer:i32(value)
	self:ensure(4)
	buffer.writei32(self.buffer, self.position, value)
	self.position += 4
end

function Writer:u32(value)
	self:ensure(4)
	buffer.writeu32(self.buffer, self.position, value)
	self.position += 4
end

function Writer:f32(value)
	self:ensure(4)
	buffer.writef32(self.buffer, self.position, value)
	self.position += 4
end

function Writer:f64(value)
	self:ensure(8)
	buffer.writef64(self.buffer, self.position, value)
	self.position += 8
end

function Writer:rawString(value)
	local length = #value
	self:ensure(length)
	if length > 0 then
		buffer.writestring(self.buffer, self.position, value)
		self.position += length
	end
end

function Writer:rawBuffer(value)
	local length = buffer.len(value)
	self:ensure(length)
	if length > 0 then
		buffer.copy(self.buffer, self.position, value, 0, length)
		self.position += length
	end
end

function Writer:varUInt(value)
	assert(value >= 0 and value <= MAX_SAFE_INTEGER and isInteger(value), "NetStream varuint expects a non-negative safe integer")
	repeat
		local byte = value % 128
		value = math.floor(value / 128)
		if value > 0 then
			byte += 128
		end
		self:u8(byte)
	until value == 0
end

function Writer:varInt(value)
	local zigzag
	if value >= 0 then
		zigzag = value * 2
	else
		zigzag = -value * 2 - 1
	end
	self:varUInt(zigzag)
end

function Writer:finish()
	local out = buffer.create(self.position)
	if self.position > 0 then
		buffer.copy(out, 0, self.buffer, 0, self.position)
	end
	return out
end

function Internal.acquireScratchWriter(minCapacity)
	local writer = scratchWriterPool[#scratchWriterPool]
	if writer then
		scratchWriterPool[#scratchWriterPool] = nil
		writer.maxBytes = Config.MaxOutgoingBatchBytes
		writer:reset()
		Stats.ScratchWriterPoolHits += 1
	else
		writer = Writer.new(math.max(128, minCapacity or 128), Config.MaxOutgoingBatchBytes)
	end
	if minCapacity and minCapacity > 0 then
		writer:ensure(minCapacity)
	end
	return writer
end

function Internal.releaseScratchWriter(writer)
	if writer and writer.capacity <= Config.MaxPooledWriterBytes and #scratchWriterPool < Config.MaxScratchWriterPoolSize then
		scratchWriterPool[#scratchWriterPool + 1] = writer
	end
end

local Reader = {}
Reader.__index = Reader

function Reader.new(data)
	return setmetatable({
		buffer = data,
		position = 0,
		length = buffer.len(data),
		strings = {},
		lastEventRoute = nil,
		lastCallRoute = nil,
		lastStateRoute = nil,
	}, Reader)
end

function Reader:reset(data)
	self.buffer = data
	self.position = 0
	self.length = buffer.len(data)
	table.clear(self.strings)
	self.lastEventRoute = nil
	self.lastCallRoute = nil
	self.lastStateRoute = nil
end

function Reader:need(bytes)
	if self.position + bytes > self.length then
		error("NetStream decode overflow", 0)
	end
end

function Reader:u8()
	self:need(1)
	local value = buffer.readu8(self.buffer, self.position)
	self.position += 1
	return value
end

function Reader:i16()
	self:need(2)
	local value = buffer.readi16(self.buffer, self.position)
	self.position += 2
	return value
end

function Reader:u16()
	self:need(2)
	local value = buffer.readu16(self.buffer, self.position)
	self.position += 2
	return value
end

function Reader:i32()
	self:need(4)
	local value = buffer.readi32(self.buffer, self.position)
	self.position += 4
	return value
end

function Reader:u32()
	self:need(4)
	local value = buffer.readu32(self.buffer, self.position)
	self.position += 4
	return value
end

function Reader:f32()
	self:need(4)
	local value = buffer.readf32(self.buffer, self.position)
	self.position += 4
	return value
end

function Reader:f64()
	self:need(8)
	local value = buffer.readf64(self.buffer, self.position)
	self.position += 8
	return value
end

function Reader:rawString(length)
	self:need(length)
	local value = if length == 0 then "" else buffer.readstring(self.buffer, self.position, length)
	self.position += length
	return value
end

function Reader:rawBuffer(length)
	self:need(length)
	local out = buffer.create(length)
	if length > 0 then
		buffer.copy(out, 0, self.buffer, self.position, length)
		self.position += length
	end
	return out
end

function Reader:varUInt()
	local result = 0
	local multiplier = 1
	for _ = 1, 8 do
		local byte = self:u8()
		result += (byte % 128) * multiplier
		if result > MAX_SAFE_INTEGER then
			error("NetStream varuint exceeds safe integer range", 0)
		end
		if byte < 128 then
			return result
		end
		multiplier *= 128
	end
	error("NetStream varuint overflow", 0)
end

function Reader:varInt()
	local value = self:varUInt()
	if value % 2 == 0 then
		return value / 2
	end
	return -((value + 1) / 2)
end


-- v2.1 continuous BitFrame writer/reader. All byte-shaped legacy values are
-- written through BufferUtil at the current bit position, so they no longer
-- force byte alignment between fields.
Internal.BitFrameScratch = buffer.create(8)
Internal.BitFrameWriter = {}
Internal.BitFrameWriter.__index = Internal.BitFrameWriter

function Internal.BitFrameWriter.new(initialBytes)
	local capacity = math.max(16, initialBytes or 256)
	return setmetatable({
		buffer = Internal.BufferUtil.new(capacity),
		capacity = capacity,
		bitPosition = 0,
		strings = {},
		stringToIndex = {},
	}, Internal.BitFrameWriter)
end

function Internal.BitFrameWriter:ensureBits(additionalBits)
	local neededBits = self.bitPosition + additionalBits
	local maxBits = Config.BitFrameMaxBytes * 8
	if neededBits > maxBits then error("NetStream BitFrame exceeds BitFrameMaxBytes", 0) end
	if neededBits <= self.capacity * 8 then return end
	local nextCapacity = self.capacity
	while nextCapacity * 8 < neededBits do nextCapacity *= 2 end
	nextCapacity = math.min(nextCapacity, Config.BitFrameMaxBytes)
	local nextBuffer = Internal.BufferUtil.new(nextCapacity)
	local usedBytes = math.ceil(self.bitPosition / 8)
	if usedBytes > 0 then buffer.copy(nextBuffer, 0, self.buffer, 0, usedBytes) end
	self.buffer = nextBuffer
	self.capacity = nextCapacity
end

function Internal.BitFrameWriter:ensure(bytes) self:ensureBits(bytes * 8) end
function Internal.BitFrameWriter:bits(value, count)
	self:ensureBits(count)
	Internal.BufferUtil.writeBits(self.buffer, self.bitPosition, count, value)
	self.bitPosition += count
end
function Internal.BitFrameWriter:adaptiveUInt(value)
	if value == 0 then self:bits(0, 1); return end
	if value <= 8 then self:bits(1, 2); self:bits(value - 1, 3); return end
	if value <= 40 then self:bits(3, 3); self:bits(value - 9, 5); return end
	self:bits(7, 3)
	repeat
		local byte = value % 128
		value = math.floor(value / 128)
		if value > 0 then byte += 128 end
		self:bits(byte, 8)
	until value == 0
end
function Internal.BitFrameWriter:u8(value) self:bits(value, 8) end
function Internal.BitFrameWriter:u16(value) self:bits(value, 16) end
function Internal.BitFrameWriter:i16(value) self:bits(if value < 0 then value + 65536 else value, 16) end
function Internal.BitFrameWriter:u32(value) self:bits(value, 32) end
function Internal.BitFrameWriter:i32(value) self:bits(if value < 0 then value + 4294967296 else value, 32) end
function Internal.BitFrameWriter:f32(value)
	buffer.writef32(Internal.BitFrameScratch, 0, value)
	self:bits(buffer.readu32(Internal.BitFrameScratch, 0), 32)
end
function Internal.BitFrameWriter:f64(value)
	buffer.writef64(Internal.BitFrameScratch, 0, value)
	self:bits(buffer.readu32(Internal.BitFrameScratch, 0), 32)
	self:bits(buffer.readu32(Internal.BitFrameScratch, 4), 32)
end
function Internal.BitFrameWriter:rawString(value)
	self:ensureBits(#value * 8)
	for i = 1, #value do self:bits(string.byte(value, i), 8) end
end
function Internal.BitFrameWriter:rawBuffer(value)
	local length = buffer.len(value)
	self:ensureBits(length * 8)
	for i = 0, length - 1 do self:bits(buffer.readu8(value, i), 8) end
end
function Internal.BitFrameWriter:varUInt(value)
	assert(value >= 0 and value <= MAX_SAFE_INTEGER and isInteger(value), "NetStream BitFrame varuint expects a non-negative safe integer")
	repeat
		local byte = value % 128
		value = math.floor(value / 128)
		if value > 0 then byte += 128 end
		self:bits(byte, 8)
	until value == 0
end
function Internal.BitFrameWriter:varInt(value)
	self:varUInt(if value >= 0 then value * 2 else -value * 2 - 1)
end
function Internal.BitFrameWriter:finish()
	return Internal.BufferUtil.cloneBits(self.buffer, self.bitPosition)
end

Internal.BitFrameReader = {}
Internal.BitFrameReader.__index = Internal.BitFrameReader

function Internal.BitFrameReader.new(data)
	return setmetatable({
		buffer = data,
		bitPosition = 0,
		bitLength = buffer.len(data) * 8,
		strings = {},
	}, Internal.BitFrameReader)
end
function Internal.BitFrameReader:needBits(count)
	if self.bitPosition + count > self.bitLength then error("NetStream BitFrame decode overflow", 0) end
end
function Internal.BitFrameReader:bits(count)
	self:needBits(count)
	local value = Internal.BufferUtil.readBits(self.buffer, self.bitPosition, count)
	self.bitPosition += count
	return value
end
function Internal.BitFrameReader:adaptiveUInt()
	if self:bits(1) == 0 then return 0 end
	if self:bits(1) == 0 then return self:bits(3) + 1 end
	if self:bits(1) == 0 then return self:bits(5) + 9 end
	local result, multiplier = 0, 1
	for _ = 1, 8 do
		local byte = self:bits(8)
		result += (byte % 128) * multiplier
		if result > MAX_SAFE_INTEGER then error("NetStream BitFrame adaptive UInt exceeds safe range", 0) end
		if byte < 128 then return result end
		multiplier *= 128
	end
	error("NetStream BitFrame adaptive UInt overflow", 0)
end
function Internal.BitFrameReader:u8() return self:bits(8) end
function Internal.BitFrameReader:u16() return self:bits(16) end
function Internal.BitFrameReader:i16()
	local value = self:bits(16)
	return if value >= 32768 then value - 65536 else value
end
function Internal.BitFrameReader:u32() return self:bits(32) end
function Internal.BitFrameReader:i32()
	local value = self:bits(32)
	return if value >= 2147483648 then value - 4294967296 else value
end
function Internal.BitFrameReader:f32()
	buffer.writeu32(Internal.BitFrameScratch, 0, self:bits(32))
	return buffer.readf32(Internal.BitFrameScratch, 0)
end
function Internal.BitFrameReader:f64()
	buffer.writeu32(Internal.BitFrameScratch, 0, self:bits(32))
	buffer.writeu32(Internal.BitFrameScratch, 4, self:bits(32))
	return buffer.readf64(Internal.BitFrameScratch, 0)
end
function Internal.BitFrameReader:rawString(length)
	if length > Config.MaxStringBytes then error("NetStream BitFrame string exceeds MaxStringBytes", 0) end
	self:needBits(length * 8)
	local chars = table.create(length)
	for i = 1, length do chars[i] = string.char(self:bits(8)) end
	return table.concat(chars)
end
function Internal.BitFrameReader:rawBuffer(length)
	if length > Config.MaxBufferBytes and length > Config.MaxIncomingPacketBytes then error("NetStream BitFrame buffer is too large", 0) end
	self:needBits(length * 8)
	local out = buffer.create(length)
	for i = 0, length - 1 do buffer.writeu8(out, i, self:bits(8)) end
	return out
end
function Internal.BitFrameReader:varUInt()
	local result, multiplier = 0, 1
	for _ = 1, 8 do
		local byte = self:bits(8)
		result += (byte % 128) * multiplier
		if result > MAX_SAFE_INTEGER then error("NetStream BitFrame varuint exceeds safe range", 0) end
		if byte < 128 then return result end
		multiplier *= 128
	end
	error("NetStream BitFrame varuint overflow", 0)
end
function Internal.BitFrameReader:varInt()
	local value = self:varUInt()
	return if value % 2 == 0 then value / 2 else -((value + 1) / 2)
end

local function writeMeta(writer, typeId, value)
	if value < 15 then
		writer:u8(typeId * 16 + value)
	else
		writer:u8(typeId * 16 + 15)
		writer:varUInt(value)
	end
end

local function readMeta(reader, descriptor)
	local meta = descriptor % 16
	if meta == 15 then
		return reader:varUInt()
	end
	return meta
end

function Internal.isArray(value)
	local count = 0
	local maxIndex = 0
	for key in pairs(value) do
		if type(key) ~= "number" or not isInteger(key) or key < 1 then
			return false, 0
		end
		count += 1
		if key > maxIndex then
			maxIndex = key
		end
	end
	return count == maxIndex, maxIndex
end

local function matrixToQuaternion(r00, r01, r02, r10, r11, r12, r20, r21, r22)
	local trace = r00 + r11 + r22
	local x, y, z, w
	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		w = 0.25 * s
		x = (r21 - r12) / s
		y = (r02 - r20) / s
		z = (r10 - r01) / s
	elseif r00 > r11 and r00 > r22 then
		local s = math.sqrt(1 + r00 - r11 - r22) * 2
		w = (r21 - r12) / s
		x = 0.25 * s
		y = (r01 + r10) / s
		z = (r02 + r20) / s
	elseif r11 > r22 then
		local s = math.sqrt(1 + r11 - r00 - r22) * 2
		w = (r02 - r20) / s
		x = (r01 + r10) / s
		y = 0.25 * s
		z = (r12 + r21) / s
	else
		local s = math.sqrt(1 + r22 - r00 - r11) * 2
		w = (r10 - r01) / s
		x = (r02 + r20) / s
		y = (r12 + r21) / s
		z = 0.25 * s
	end
	local magnitude = math.sqrt(x * x + y * y + z * z + w * w)
	if magnitude == 0 then
		return 0, 0, 0, 1
	end
	return x / magnitude, y / magnitude, z / magnitude, w / magnitude
end

local function quaternionToMatrix(x, y, z, w)
	local magnitude = math.sqrt(x * x + y * y + z * z + w * w)
	if magnitude == 0 then
		x, y, z, w = 0, 0, 0, 1
	else
		x, y, z, w = x / magnitude, y / magnitude, z / magnitude, w / magnitude
	end
	local xx = x * x
	local yy = y * y
	local zz = z * z
	local xy = x * y
	local xz = x * z
	local yz = y * z
	local wx = w * x
	local wy = w * y
	local wz = w * z
	return
		1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy),
		2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx),
		2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy)
end

local acquireArgsCount
local releaseMessage

function Internal.schemaFixedBytes(field)
	local kind = field.Kind
	if kind == SCHEMA_BOOL or kind == SCHEMA_U8 then return 1 end
	if kind == SCHEMA_U16 or kind == SCHEMA_I16 or kind == SCHEMA_EXT.BRICK_COLOR then return 2 end
	if kind == SCHEMA_U32 or kind == SCHEMA_I32 or kind == SCHEMA_F32 then return 4 end
	if kind == SCHEMA_F64 or kind == SCHEMA_EXT.DATETIME then return 8 end
	if kind == SCHEMA_COLOR3 then return 3 end
	if kind == SCHEMA_EXT.UDIM then return 12 end
	if kind == SCHEMA_EXT.NUMBER_RANGE then return 16 end
	if kind == SCHEMA_EXT.UDIM2 then return 24 end
	if kind == SCHEMA_EXT.RECT then return 32 end
	return nil
end

function Internal.compileSchema(spec, label)
	if spec == nil then
		return nil
	end
	local fields
	if type(spec) == "table" and spec._netstreamSchemaType == true then
		fields = { spec }
	else
		assert(type(spec) == "table", (label or "Schema") .. " must be a NetStream type or an array of NetStream types")
		fields = table.create(#spec)
		for i = 1, #spec do
			fields[i] = spec[i]
		end
	end
	local fixedBytes = 0
	local isFixed = true
	for i = 1, #fields do
		local field = fields[i]
		assert(type(field) == "table" and field._netstreamSchemaType == true, string.format("%s field %d is not a NetStream.Types value", label or "Schema", i))
		local fieldBytes = Internal.schemaFixedBytes(field)
		if fieldBytes then
			fixedBytes += fieldBytes
		else
			isFixed = false
		end
	end
	local signatureParts = table.create(#fields)
	for i = 1, #fields do
		local field = fields[i]
		signatureParts[i] = tostring(field.Kind) .. ":" .. tostring(field.Precision or "")
	end
	return {
		fields = fields,
		count = #fields,
		signature = table.concat(signatureParts, "|"),
		fixedBytes = if isFixed then fixedBytes else nil,
		isFixed = isFixed,
	}
end

function Internal.validateSchemaValue(field, value, level)
	local kind = field.Kind
	if kind == SCHEMA_BOOL then
		if type(value) ~= "boolean" then error(field.Name .. " expects boolean", level) end
	elseif kind == SCHEMA_U8 then
		if type(value) ~= "number" or not isInteger(value) or value < 0 or value > 255 then error("U8 expects integer 0..255", level) end
	elseif kind == SCHEMA_U16 then
		if type(value) ~= "number" or not isInteger(value) or value < 0 or value > 65535 then error("U16 expects integer 0..65535", level) end
	elseif kind == SCHEMA_I16 then
		if type(value) ~= "number" or not isInteger(value) or value < -32768 or value > 32767 then error("I16 expects integer -32768..32767", level) end
	elseif kind == SCHEMA_U32 then
		if type(value) ~= "number" or not isInteger(value) or value < 0 or value > 4294967295 then error("U32 expects integer 0..4294967295", level) end
	elseif kind == SCHEMA_I32 then
		if type(value) ~= "number" or not isInteger(value) or value < -2147483648 or value > 2147483647 then error("I32 expects signed 32-bit integer", level) end
	elseif kind == SCHEMA_VARUINT then
		if type(value) ~= "number" or not isInteger(value) or value < 0 or value > MAX_SAFE_INTEGER then error("VarUInt expects a non-negative safe integer", level) end
	elseif kind == SCHEMA_VARINT then
		if type(value) ~= "number" or not isInteger(value) or math.abs(value) > math.floor(MAX_SAFE_INTEGER / 2) then error("VarInt expects a safe signed integer", level) end
	elseif kind == SCHEMA_F32 then
		if not isFiniteNumber(value) or math.abs(value) > MAX_FLOAT32 then error("F32 expects a finite float32-range number", level) end
	elseif kind == SCHEMA_F64 then
		if not isFiniteNumber(value) then error("F64 expects a finite number", level) end
	elseif kind == SCHEMA_STRING then
		if type(value) ~= "string" then error("String expects string", level) end
		if #value > Config.MaxStringBytes then error("String exceeds MaxStringBytes", level) end
	elseif kind == SCHEMA_BUFFER then
		if typeof(value) ~= "buffer" then error("Buffer expects buffer", level) end
		if buffer.len(value) > Config.MaxBufferBytes then error("Buffer exceeds MaxBufferBytes", level) end
	elseif kind == SCHEMA_VECTOR3Q then
		if typeof(value) ~= "Vector3" then error("Vector3Q expects Vector3", level) end
		if not quantizedComponentIsSafe(value.X, field.Precision) or not quantizedComponentIsSafe(value.Y, field.Precision) or not quantizedComponentIsSafe(value.Z, field.Precision) then error("Vector3Q contains a non-finite or out-of-range component", level) end
	elseif kind == SCHEMA_VECTOR2Q then
		if typeof(value) ~= "Vector2" then error("Vector2Q expects Vector2", level) end
		if not quantizedComponentIsSafe(value.X, field.Precision) or not quantizedComponentIsSafe(value.Y, field.Precision) then error("Vector2Q contains a non-finite or out-of-range component", level) end
	elseif kind == SCHEMA_CFRAMEQ then
		if typeof(value) ~= "CFrame" then error("CFrameQ expects CFrame", level) end
		if not cframeIsFinite(value, field.Precision) then error("CFrameQ contains a non-finite or out-of-range component", level) end
	elseif kind == SCHEMA_COLOR3 then
		if typeof(value) ~= "Color3" then error("Color3 expects Color3", level) end
		if not isFiniteNumber(value.R) or not isFiniteNumber(value.G) or not isFiniteNumber(value.B) then error("Color3 contains a non-finite component", level) end
	elseif kind == SCHEMA_EXT.UDIM then
		if typeof(value) ~= "UDim" then error("UDim expects UDim", level) end
		if not isFiniteNumber(value.Scale) or not isInteger(value.Offset) or value.Offset < -2147483648 or value.Offset > 2147483647 then error("UDim contains an invalid component", level) end
	elseif kind == SCHEMA_EXT.UDIM2 then
		if typeof(value) ~= "UDim2" then error("UDim2 expects UDim2", level) end
		if not isFiniteNumber(value.X.Scale) or not isFiniteNumber(value.Y.Scale)
			or not isInteger(value.X.Offset) or value.X.Offset < -2147483648 or value.X.Offset > 2147483647
			or not isInteger(value.Y.Offset) or value.Y.Offset < -2147483648 or value.Y.Offset > 2147483647 then error("UDim2 contains an invalid component", level) end
	elseif kind == SCHEMA_EXT.RECT then
		if typeof(value) ~= "Rect" then error("Rect expects Rect", level) end
		if not isFiniteNumber(value.Min.X) or not isFiniteNumber(value.Min.Y) or not isFiniteNumber(value.Max.X) or not isFiniteNumber(value.Max.Y) then error("Rect contains a non-finite component", level) end
	elseif kind == SCHEMA_EXT.NUMBER_RANGE then
		if typeof(value) ~= "NumberRange" then error("NumberRange expects NumberRange", level) end
		if not isFiniteNumber(value.Min) or not isFiniteNumber(value.Max) then error("NumberRange contains a non-finite component", level) end
	elseif kind == SCHEMA_EXT.BRICK_COLOR then
		if typeof(value) ~= "BrickColor" then error("BrickColor expects BrickColor", level) end
	elseif kind == SCHEMA_EXT.DATETIME then
		if typeof(value) ~= "DateTime" then error("DateTime expects DateTime", level) end
		if not isFiniteNumber(value.UnixTimestampMillis) then error("DateTime contains an invalid timestamp", level) end
	else
		error("Unknown NetStream schema type", level)
	end
end

local function validateSchemaArgs(schema, args, trusted)
	if not schema then
		return false
	end
	if args.n ~= schema.count then
		error(string.format("NetStream schema expected %d arguments, got %d", schema.count, args.n), 4)
	end
	if not trusted then
		for i = 1, schema.count do
			Internal.validateSchemaValue(schema.fields[i], args[i], 5)
		end
	end
	return true
end

function Internal.writeSchemaString(writer, value)
	local index = writer.stringToIndex[value]
	if index ~= nil then
		writer:varUInt(index * 4 + 1)
		return
	end

	local rawMeta = #value * 4
	local rawCost = Internal.varUIntByteLength(rawMeta) + #value
	local compressed = nil
	local compressedCost = math.huge

	if Config.CompressionEnabled and #value >= Config.CompressionMinStringBytes then
		Stats.CompressionAttempts += 1
		local ok, packed = pcall(Compression.CompressString, value, Internal.compressionOptions())
		if ok and typeof(packed) == "buffer" then
			local packedLength = buffer.len(packed)
			local packedMeta = packedLength * 4 + 2
			compressedCost = Internal.varUIntByteLength(packedMeta) + packedLength
			if compressedCost + Config.CompressionMinSavingsBytes <= rawCost then
				compressed = packed
			else
				Stats.CompressionRejected += 1
				Stats.CompressionNoGain += 1
			end
		else
			Stats.CompressionRejected += 1
			Stats.CompressionErrors += 1
		end
	end

	if compressed then
		local packedLength = buffer.len(compressed)
		writer:varUInt(packedLength * 4 + 2)
		writer:rawBuffer(compressed)
		Stats.CompressionUsed += 1
		Stats.CompressedSchemaStrings += 1
		Stats.CompressionInputBytes += rawCost
		Stats.CompressionOutputBytes += compressedCost
		local saved = rawCost - compressedCost
		if saved > 0 then
			Stats.CompressionSavedBytes += saved
			Stats.SchemaStringBytesSaved += saved
		end
	else
		writer:varUInt(rawMeta)
		writer:rawString(value)
	end

	local nextIndex = #writer.strings
	writer.strings[nextIndex + 1] = value
	writer.stringToIndex[value] = nextIndex
end

function Internal.readSchemaString(reader)
	local meta = reader:varUInt()
	local mode = meta % 4
	local payload = math.floor(meta / 4)

	if mode == 1 then
		local value = reader.strings[payload + 1]
		if value == nil then
			error("NetStream invalid schema string reference", 0)
		end
		return value
	elseif mode == 2 then
		if payload > Config.MaxIncomingPacketBytes then
			error("NetStream incoming compressed schema string is too large", 0)
		end
		local packed = reader:rawBuffer(payload)
		local value = Compression.DecompressString(packed)
		if #value > Config.MaxStringBytes then
			error("NetStream incoming schema string exceeds MaxStringBytes", 0)
		end
		reader.strings[#reader.strings + 1] = value
		Stats.CompressionDecodeCount += 1
		return value
	elseif mode ~= 0 then
		error("NetStream invalid schema string mode", 0)
	end

	local length = payload
	if length > Config.MaxStringBytes then
		error("NetStream incoming schema string exceeds MaxStringBytes", 0)
	end
	local value = reader:rawString(length)
	reader.strings[#reader.strings + 1] = value
	return value
end

function Internal.writeSchemaBuffer(writer, value)
	local rawLength = buffer.len(value)
	local rawMeta = rawLength * 2
	local rawCost = Internal.varUIntByteLength(rawMeta) + rawLength
	local compressed = nil
	local compressedCost = math.huge

	if Config.CompressionEnabled and Config.CompressionCompressBuffers and rawLength >= Config.CompressionMinBufferBytes then
		Stats.CompressionAttempts += 1
		local ok, packed = pcall(Compression.CompressBuffer, value, Internal.compressionOptions())
		if ok and typeof(packed) == "buffer" then
			local packedLength = buffer.len(packed)
			local packedMeta = packedLength * 2 + 1
			compressedCost = Internal.varUIntByteLength(packedMeta) + packedLength
			if compressedCost + Config.CompressionMinSavingsBytes <= rawCost then
				compressed = packed
			else
				Stats.CompressionRejected += 1
				Stats.CompressionNoGain += 1
			end
		else
			Stats.CompressionRejected += 1
			Stats.CompressionErrors += 1
		end
	end

	if compressed then
		local packedLength = buffer.len(compressed)
		writer:varUInt(packedLength * 2 + 1)
		writer:rawBuffer(compressed)
		Stats.CompressionUsed += 1
		Stats.CompressedSchemaBuffers += 1
		Stats.CompressionInputBytes += rawCost
		Stats.CompressionOutputBytes += compressedCost
		local saved = rawCost - compressedCost
		if saved > 0 then
			Stats.CompressionSavedBytes += saved
			Stats.SchemaBufferBytesSaved += saved
		end
	else
		writer:varUInt(rawMeta)
		writer:rawBuffer(value)
	end
end

function Internal.readSchemaBuffer(reader)
	local meta = reader:varUInt()
	local compressed = meta % 2 == 1
	local payload = math.floor(meta / 2)
	if compressed then
		if payload > Config.MaxIncomingPacketBytes then error("NetStream incoming compressed schema buffer is too large", 0) end
		local packed = reader:rawBuffer(payload)
		local value = Compression.DecompressBuffer(packed)
		if buffer.len(value) > Config.MaxBufferBytes then error("NetStream incoming schema buffer exceeds MaxBufferBytes", 0) end
		Stats.CompressionDecodeCount += 1
		return value
	end
	if payload > Config.MaxBufferBytes then error("NetStream incoming schema buffer exceeds MaxBufferBytes", 0) end
	return reader:rawBuffer(payload)
end

local function writeSchemaValue(writer, field, value)
	local kind = field.Kind
	if kind == SCHEMA_BOOL then
		writer:u8(if value then 1 else 0)
	elseif kind == SCHEMA_U8 then
		writer:u8(value)
	elseif kind == SCHEMA_U16 then
		writer:u16(value)
	elseif kind == SCHEMA_I16 then
		writer:i16(value)
	elseif kind == SCHEMA_U32 then
		writer:u32(value)
	elseif kind == SCHEMA_I32 then
		writer:i32(value)
	elseif kind == SCHEMA_VARUINT then
		writer:varUInt(value)
	elseif kind == SCHEMA_VARINT then
		writer:varInt(value)
	elseif kind == SCHEMA_F32 then
		writer:f32(value)
	elseif kind == SCHEMA_F64 then
		writer:f64(value)
	elseif kind == SCHEMA_STRING then
		Internal.writeSchemaString(writer, value)
	elseif kind == SCHEMA_BUFFER then
		Internal.writeSchemaBuffer(writer, value)
	elseif kind == SCHEMA_VECTOR3Q then
		local precision = field.Precision
		writer:varInt(roundScaled(value.X, precision))
		writer:varInt(roundScaled(value.Y, precision))
		writer:varInt(roundScaled(value.Z, precision))
	elseif kind == SCHEMA_VECTOR2Q then
		local precision = field.Precision
		writer:varInt(roundScaled(value.X, precision))
		writer:varInt(roundScaled(value.Y, precision))
	elseif kind == SCHEMA_CFRAMEQ then
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()
		local precision = field.Precision
		writer:varInt(roundScaled(x, precision))
		writer:varInt(roundScaled(y, precision))
		writer:varInt(roundScaled(z, precision))
		local qx, qy, qz, qw = matrixToQuaternion(r00, r01, r02, r10, r11, r12, r20, r21, r22)
		writer:i16(clampInteger(roundScaled(qx, 32767), -32767, 32767))
		writer:i16(clampInteger(roundScaled(qy, 32767), -32767, 32767))
		writer:i16(clampInteger(roundScaled(qz, 32767), -32767, 32767))
		writer:i16(clampInteger(roundScaled(qw, 32767), -32767, 32767))
	elseif kind == SCHEMA_COLOR3 then
		writer:u8(clampInteger(math.floor(value.R * 255 + 0.5), 0, 255))
		writer:u8(clampInteger(math.floor(value.G * 255 + 0.5), 0, 255))
		writer:u8(clampInteger(math.floor(value.B * 255 + 0.5), 0, 255))
	elseif kind == SCHEMA_EXT.UDIM then
		writer:f64(value.Scale)
		writer:i32(value.Offset)
	elseif kind == SCHEMA_EXT.UDIM2 then
		writer:f64(value.X.Scale)
		writer:i32(value.X.Offset)
		writer:f64(value.Y.Scale)
		writer:i32(value.Y.Offset)
	elseif kind == SCHEMA_EXT.RECT then
		writer:f64(value.Min.X)
		writer:f64(value.Min.Y)
		writer:f64(value.Max.X)
		writer:f64(value.Max.Y)
	elseif kind == SCHEMA_EXT.NUMBER_RANGE then
		writer:f64(value.Min)
		writer:f64(value.Max)
	elseif kind == SCHEMA_EXT.BRICK_COLOR then
		writer:u16(value.Number)
	elseif kind == SCHEMA_EXT.DATETIME then
		writer:f64(value.UnixTimestampMillis)
	end
end

local function readSchemaValue(reader, field)
	local kind = field.Kind
	if kind == SCHEMA_BOOL then
		local value = reader:u8()
		if value > 1 then
			error("NetStream invalid schema boolean", 0)
		end
		return value == 1
	elseif kind == SCHEMA_U8 then
		return reader:u8()
	elseif kind == SCHEMA_U16 then
		return reader:u16()
	elseif kind == SCHEMA_I16 then
		return reader:i16()
	elseif kind == SCHEMA_U32 then
		return reader:u32()
	elseif kind == SCHEMA_I32 then
		return reader:i32()
	elseif kind == SCHEMA_VARUINT then
		return reader:varUInt()
	elseif kind == SCHEMA_VARINT then
		return reader:varInt()
	elseif kind == SCHEMA_F32 then
		local value = reader:f32()
		if not isFiniteNumber(value) or math.abs(value) > MAX_FLOAT32 then
			error("NetStream incoming F32 is not finite", 0)
		end
		return value
	elseif kind == SCHEMA_F64 then
		local value = reader:f64()
		if not isFiniteNumber(value) then
			error("NetStream incoming F64 is not finite", 0)
		end
		return value
	elseif kind == SCHEMA_STRING then
		return Internal.readSchemaString(reader)
	elseif kind == SCHEMA_BUFFER then
		return Internal.readSchemaBuffer(reader)
	elseif kind == SCHEMA_VECTOR3Q then
		local inv = 1 / field.Precision
		return Vector3.new(reader:varInt() * inv, reader:varInt() * inv, reader:varInt() * inv)
	elseif kind == SCHEMA_VECTOR2Q then
		local inv = 1 / field.Precision
		return Vector2.new(reader:varInt() * inv, reader:varInt() * inv)
	elseif kind == SCHEMA_CFRAMEQ then
		local inv = 1 / field.Precision
		local x = reader:varInt() * inv
		local y = reader:varInt() * inv
		local z = reader:varInt() * inv
		local qx = reader:i16() / 32767
		local qy = reader:i16() / 32767
		local qz = reader:i16() / 32767
		local qw = reader:i16() / 32767
		local r00, r01, r02, r10, r11, r12, r20, r21, r22 = quaternionToMatrix(qx, qy, qz, qw)
		return CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	elseif kind == SCHEMA_COLOR3 then
		return Color3.fromRGB(reader:u8(), reader:u8(), reader:u8())
	elseif kind == SCHEMA_EXT.UDIM then
		return UDim.new(reader:f64(), reader:i32())
	elseif kind == SCHEMA_EXT.UDIM2 then
		return UDim2.new(reader:f64(), reader:i32(), reader:f64(), reader:i32())
	elseif kind == SCHEMA_EXT.RECT then
		return Rect.new(reader:f64(), reader:f64(), reader:f64(), reader:f64())
	elseif kind == SCHEMA_EXT.NUMBER_RANGE then
		return NumberRange.new(reader:f64(), reader:f64())
	elseif kind == SCHEMA_EXT.BRICK_COLOR then
		return BrickColor.new(reader:u16())
	elseif kind == SCHEMA_EXT.DATETIME then
		local millis = reader:f64()
		if not isFiniteNumber(millis) then error("NetStream incoming DateTime timestamp is not finite", 0) end
		return DateTime.fromUnixTimestampMillis(millis)
	end
	error("Unknown NetStream schema type", 0)
end

function Internal.writeFixedSchemaPayload(data, position, schema, args)
	local fields = schema.fields
	local pos = position
	for i = 1, schema.count do
		local field = fields[i]
		local kind = field.Kind
		local value = args[i]
		if kind == SCHEMA_BOOL then
			buffer.writeu8(data, pos, if value then 1 else 0)
			pos += 1
		elseif kind == SCHEMA_U8 then
			buffer.writeu8(data, pos, value)
			pos += 1
		elseif kind == SCHEMA_U16 then
			buffer.writeu16(data, pos, value)
			pos += 2
		elseif kind == SCHEMA_I16 then
			buffer.writei16(data, pos, value)
			pos += 2
		elseif kind == SCHEMA_U32 then
			buffer.writeu32(data, pos, value)
			pos += 4
		elseif kind == SCHEMA_I32 then
			buffer.writei32(data, pos, value)
			pos += 4
		elseif kind == SCHEMA_F32 then
			buffer.writef32(data, pos, value)
			pos += 4
		elseif kind == SCHEMA_F64 then
			buffer.writef64(data, pos, value)
			pos += 8
		elseif kind == SCHEMA_COLOR3 then
			buffer.writeu8(data, pos, clampInteger(math.floor(value.R * 255 + 0.5), 0, 255))
			buffer.writeu8(data, pos + 1, clampInteger(math.floor(value.G * 255 + 0.5), 0, 255))
			buffer.writeu8(data, pos + 2, clampInteger(math.floor(value.B * 255 + 0.5), 0, 255))
			pos += 3
		elseif kind == SCHEMA_EXT.UDIM then
			buffer.writef64(data, pos, value.Scale)
			buffer.writei32(data, pos + 8, value.Offset)
			pos += 12
		elseif kind == SCHEMA_EXT.UDIM2 then
			buffer.writef64(data, pos, value.X.Scale)
			buffer.writei32(data, pos + 8, value.X.Offset)
			buffer.writef64(data, pos + 12, value.Y.Scale)
			buffer.writei32(data, pos + 20, value.Y.Offset)
			pos += 24
		elseif kind == SCHEMA_EXT.RECT then
			buffer.writef64(data, pos, value.Min.X)
			buffer.writef64(data, pos + 8, value.Min.Y)
			buffer.writef64(data, pos + 16, value.Max.X)
			buffer.writef64(data, pos + 24, value.Max.Y)
			pos += 32
		elseif kind == SCHEMA_EXT.NUMBER_RANGE then
			buffer.writef64(data, pos, value.Min)
			buffer.writef64(data, pos + 8, value.Max)
			pos += 16
		elseif kind == SCHEMA_EXT.BRICK_COLOR then
			buffer.writeu16(data, pos, value.Number)
			pos += 2
		elseif kind == SCHEMA_EXT.DATETIME then
			buffer.writef64(data, pos, value.UnixTimestampMillis)
			pos += 8
		else
			error("NetStream fixed schema contained a variable-width field", 0)
		end
	end
	return pos
end

function Internal.writeFixedSchemaFlatPayload(data, position, schema, values, base)
	local fields = schema.fields
	local pos = position
	for i = 1, schema.count do
		local field = fields[i]
		local kind = field.Kind
		local value = values[base + i]
		if kind == SCHEMA_BOOL then
			buffer.writeu8(data, pos, if value then 1 else 0)
			pos += 1
		elseif kind == SCHEMA_U8 then
			buffer.writeu8(data, pos, value)
			pos += 1
		elseif kind == SCHEMA_U16 then
			buffer.writeu16(data, pos, value)
			pos += 2
		elseif kind == SCHEMA_I16 then
			buffer.writei16(data, pos, value)
			pos += 2
		elseif kind == SCHEMA_U32 then
			buffer.writeu32(data, pos, value)
			pos += 4
		elseif kind == SCHEMA_I32 then
			buffer.writei32(data, pos, value)
			pos += 4
		elseif kind == SCHEMA_F32 then
			buffer.writef32(data, pos, value)
			pos += 4
		elseif kind == SCHEMA_F64 then
			buffer.writef64(data, pos, value)
			pos += 8
		elseif kind == SCHEMA_COLOR3 then
			buffer.writeu8(data, pos, clampInteger(math.floor(value.R * 255 + 0.5), 0, 255))
			buffer.writeu8(data, pos + 1, clampInteger(math.floor(value.G * 255 + 0.5), 0, 255))
			buffer.writeu8(data, pos + 2, clampInteger(math.floor(value.B * 255 + 0.5), 0, 255))
			pos += 3
		elseif kind == SCHEMA_EXT.UDIM then
			buffer.writef64(data, pos, value.Scale)
			buffer.writei32(data, pos + 8, value.Offset)
			pos += 12
		elseif kind == SCHEMA_EXT.UDIM2 then
			buffer.writef64(data, pos, value.X.Scale)
			buffer.writei32(data, pos + 8, value.X.Offset)
			buffer.writef64(data, pos + 12, value.Y.Scale)
			buffer.writei32(data, pos + 20, value.Y.Offset)
			pos += 24
		elseif kind == SCHEMA_EXT.RECT then
			buffer.writef64(data, pos, value.Min.X)
			buffer.writef64(data, pos + 8, value.Min.Y)
			buffer.writef64(data, pos + 16, value.Max.X)
			buffer.writef64(data, pos + 24, value.Max.Y)
			pos += 32
		elseif kind == SCHEMA_EXT.NUMBER_RANGE then
			buffer.writef64(data, pos, value.Min)
			buffer.writef64(data, pos + 8, value.Max)
			pos += 16
		elseif kind == SCHEMA_EXT.BRICK_COLOR then
			buffer.writeu16(data, pos, value.Number)
			pos += 2
		elseif kind == SCHEMA_EXT.DATETIME then
			buffer.writef64(data, pos, value.UnixTimestampMillis)
			pos += 8
		else
			error("NetStream packed schema run contained a variable-width field", 0)
		end
	end
	return pos
end

local function writeSchemaArgs(writer, schema, args)
	if schema.fixedBytes ~= nil then
		writer:ensure(schema.fixedBytes)
		writer.position = Internal.writeFixedSchemaPayload(writer.buffer, writer.position, schema, args)
		Stats.FixedSchemaFastWrites += 1
		return
	end
	for i = 1, schema.count do
		writeSchemaValue(writer, schema.fields[i], args[i])
	end
end

local function readFixedSchemaArgs(reader, schema)
	reader:need(schema.fixedBytes)
	local data = reader.buffer
	local pos = reader.position
	local args = acquireArgsCount(schema.count)
	for i = 1, schema.count do
		local kind = schema.fields[i].Kind
		local value
		if kind == SCHEMA_BOOL then
			local byte = buffer.readu8(data, pos)
			if byte > 1 then error("NetStream invalid schema boolean", 0) end
			value = byte == 1
			pos += 1
		elseif kind == SCHEMA_U8 then
			value = buffer.readu8(data, pos)
			pos += 1
		elseif kind == SCHEMA_U16 then
			value = buffer.readu16(data, pos)
			pos += 2
		elseif kind == SCHEMA_I16 then
			value = buffer.readi16(data, pos)
			pos += 2
		elseif kind == SCHEMA_U32 then
			value = buffer.readu32(data, pos)
			pos += 4
		elseif kind == SCHEMA_I32 then
			value = buffer.readi32(data, pos)
			pos += 4
		elseif kind == SCHEMA_F32 then
			value = buffer.readf32(data, pos)
			if not isFiniteNumber(value) or math.abs(value) > MAX_FLOAT32 then error("NetStream incoming F32 is not finite", 0) end
			pos += 4
		elseif kind == SCHEMA_F64 then
			value = buffer.readf64(data, pos)
			if not isFiniteNumber(value) then error("NetStream incoming F64 is not finite", 0) end
			pos += 8
		elseif kind == SCHEMA_COLOR3 then
			value = Color3.fromRGB(buffer.readu8(data, pos), buffer.readu8(data, pos + 1), buffer.readu8(data, pos + 2))
			pos += 3
		elseif kind == SCHEMA_EXT.UDIM then
			value = UDim.new(buffer.readf64(data, pos), buffer.readi32(data, pos + 8))
			pos += 12
		elseif kind == SCHEMA_EXT.UDIM2 then
			value = UDim2.new(buffer.readf64(data, pos), buffer.readi32(data, pos + 8), buffer.readf64(data, pos + 12), buffer.readi32(data, pos + 20))
			pos += 24
		elseif kind == SCHEMA_EXT.RECT then
			value = Rect.new(buffer.readf64(data, pos), buffer.readf64(data, pos + 8), buffer.readf64(data, pos + 16), buffer.readf64(data, pos + 24))
			pos += 32
		elseif kind == SCHEMA_EXT.NUMBER_RANGE then
			value = NumberRange.new(buffer.readf64(data, pos), buffer.readf64(data, pos + 8))
			pos += 16
		elseif kind == SCHEMA_EXT.BRICK_COLOR then
			value = BrickColor.new(buffer.readu16(data, pos))
			pos += 2
		elseif kind == SCHEMA_EXT.DATETIME then
			local millis = buffer.readf64(data, pos)
			if not isFiniteNumber(millis) then error("NetStream incoming DateTime timestamp is not finite", 0) end
			value = DateTime.fromUnixTimestampMillis(millis)
			pos += 8
		else
			error("NetStream fixed schema contained a variable-width field", 0)
		end
		args[i] = value
	end
	reader.position = pos
	args.n = schema.count
	Stats.FixedSchemaFastReads += 1
	return args
end

local function readSchemaArgs(reader, schema)
	if schema.count == 0 then
		return EMPTY_ARGS
	end
	if schema.count == 1 and schema.fields[1].Kind == SCHEMA_BOOL then
		local value = reader:u8()
		if value > 1 then
			error("NetStream invalid schema boolean", 0)
		end
		return if value == 1 then TRUE_ARGS else FALSE_ARGS
	end
	if schema.fixedBytes ~= nil then
		return readFixedSchemaArgs(reader, schema)
	end
	local args = acquireArgsCount(schema.count)
	for i = 1, schema.count do
		args[i] = readSchemaValue(reader, schema.fields[i])
	end
	args.n = schema.count
	return args
end


function Internal.bitFrameWriteSchemaArgs(writer, schema, args, base)
	local offset = base or 0
	for i = 1, schema.count do
		local field = schema.fields[i]
		local value = args[offset + i]
		if field.Kind == SCHEMA_BOOL then
			writer:bits(value and 1 or 0, 1)
		else
			writeSchemaValue(writer, field, value)
		end
	end
end

function Internal.bitFrameReadSchemaArgs(reader, schema)
	if schema.count == 0 then return EMPTY_ARGS end
	if schema.count == 1 and schema.fields[1].Kind == SCHEMA_BOOL then
		return if reader:bits(1) ~= 0 then TRUE_ARGS else FALSE_ARGS
	end
	local args = acquireArgsCount(schema.count)
	for i = 1, schema.count do
		local field = schema.fields[i]
		if field.Kind == SCHEMA_BOOL then
			args[i] = reader:bits(1) ~= 0
		else
			args[i] = readSchemaValue(reader, field)
		end
	end
	args.n = schema.count
	return args
end

local function validateValue(value, depth, seen)
	depth = depth or 0
	if depth > Config.MaxDepth then
		error("NetStream value exceeded MaxDepth", 4)
	end
	if value == nil then
		return
	end
	local luaType = type(value)
	local robloxType = typeof(value)
	if luaType == "boolean" or luaType == "number" then
		if luaType == "number" and (value ~= value or value == math.huge or value == -math.huge) then
			error("NetStream cannot encode NaN or infinity", 4)
		end
		return
	elseif luaType == "string" then
		if #value > Config.MaxStringBytes then
			error("NetStream string exceeds MaxStringBytes", 4)
		end
		return
	elseif robloxType == "Vector3" then
		if not quantizedComponentIsSafe(value.X, Config.VectorPrecision) or not quantizedComponentIsSafe(value.Y, Config.VectorPrecision) or not quantizedComponentIsSafe(value.Z, Config.VectorPrecision) then
			error("NetStream Vector3 contains a non-finite or out-of-range component", 4)
		end
		return
	elseif robloxType == "Vector2" then
		if not quantizedComponentIsSafe(value.X, Config.VectorPrecision) or not quantizedComponentIsSafe(value.Y, Config.VectorPrecision) then
			error("NetStream Vector2 contains a non-finite or out-of-range component", 4)
		end
		return
	elseif robloxType == "CFrame" then
		if not cframeIsFinite(value, Config.VectorPrecision) then
			error("NetStream CFrame contains a non-finite or out-of-range component", 4)
		end
		return
	elseif robloxType == "Color3" then
		if not isFiniteNumber(value.R) or not isFiniteNumber(value.G) or not isFiniteNumber(value.B) then
			error("NetStream Color3 contains a non-finite component", 4)
		end
		return
	elseif robloxType == "buffer" then
		if buffer.len(value) > Config.MaxBufferBytes then
			error("NetStream buffer exceeds MaxBufferBytes", 4)
		end
		return
	elseif robloxType == "UDim" then
		if not isFiniteNumber(value.Scale) or not isInteger(value.Offset) or value.Offset < -2147483648 or value.Offset > 2147483647 then error("NetStream UDim contains an invalid component", 4) end
		return
	elseif robloxType == "UDim2" then
		if not isFiniteNumber(value.X.Scale) or not isFiniteNumber(value.Y.Scale)
			or not isInteger(value.X.Offset) or value.X.Offset < -2147483648 or value.X.Offset > 2147483647
			or not isInteger(value.Y.Offset) or value.Y.Offset < -2147483648 or value.Y.Offset > 2147483647 then error("NetStream UDim2 contains an invalid component", 4) end
		return
	elseif robloxType == "Rect" then
		if not isFiniteNumber(value.Min.X) or not isFiniteNumber(value.Min.Y) or not isFiniteNumber(value.Max.X) or not isFiniteNumber(value.Max.Y) then error("NetStream Rect contains a non-finite component", 4) end
		return
	elseif robloxType == "NumberRange" then
		if not isFiniteNumber(value.Min) or not isFiniteNumber(value.Max) then error("NetStream NumberRange contains a non-finite component", 4) end
		return
	elseif robloxType == "BrickColor" then
		return
	elseif robloxType == "DateTime" then
		if not isFiniteNumber(value.UnixTimestampMillis) then error("NetStream DateTime contains an invalid timestamp", 4) end
		return
	elseif luaType == "table" then
		local mt = getmetatable(value)
		if mt == Float32Tag or mt == RawStringTag then
			return
		end
		seen = seen or {}
		if seen[value] then
			error("NetStream cannot encode circular tables", 4)
		end
		seen[value] = true
		local entries = 0
		for key, item in pairs(value) do
			entries += 1
			if entries > Config.MaxTableEntries then
				error("NetStream table exceeds MaxTableEntries", 4)
			end
			validateValue(key, depth + 1, seen)
			validateValue(item, depth + 1, seen)
		end
		seen[value] = nil
		return
	end
	error("NetStream unsupported value type: " .. robloxType, 4)
end

local writeValue
local readValue

writeValue = function(writer, value, depth, seen)
	depth = depth or 0
	if value == nil then
		writer:u8(TYPE_NIL * 16)
		return
	end
	local luaType = type(value)
	local robloxType = typeof(value)
	if luaType == "boolean" then
		writer:u8(TYPE_BOOL * 16 + (if value then 1 else 0))
	elseif luaType == "number" then
		local canVarInt = isInteger(value) and ((value >= 0 and value <= MAX_SAFE_INTEGER) or (value < 0 and -value <= math.floor(MAX_SAFE_INTEGER / 2)))
		if canVarInt then
			if value >= 0 then
				if value < 15 then
					writer:u8(TYPE_UINT * 16 + value)
				else
					writer:u8(TYPE_UINT * 16 + 15)
					writer:varUInt(value)
				end
			else
				local zigzag = -value * 2 - 1
				if zigzag < 15 then
					writer:u8(TYPE_SINT * 16 + zigzag)
				else
					writer:u8(TYPE_SINT * 16 + 15)
					writer:varUInt(zigzag)
				end
			end
		else
			writer:u8(TYPE_F64 * 16)
			writer:f64(value)
		end
	elseif luaType == "string" then
		local index = writer.stringToIndex[value]
		if index ~= nil then
			writeMeta(writer, TYPE_STRING_REF, index)
		else
			writeMeta(writer, TYPE_STRING, #value)
			writer:rawString(value)
			local nextIndex = #writer.strings
			writer.strings[nextIndex + 1] = value
			writer.stringToIndex[value] = nextIndex
		end
	elseif robloxType == "Vector3" then
		writer:u8(TYPE_VECTOR3 * 16)
		local precision = Config.VectorPrecision
		writer:varInt(roundScaled(value.X, precision))
		writer:varInt(roundScaled(value.Y, precision))
		writer:varInt(roundScaled(value.Z, precision))
	elseif robloxType == "Vector2" then
		writer:u8(TYPE_VECTOR2 * 16)
		local precision = Config.VectorPrecision
		writer:varInt(roundScaled(value.X, precision))
		writer:varInt(roundScaled(value.Y, precision))
	elseif robloxType == "Color3" then
		writer:u8(TYPE_COLOR3 * 16)
		writer:u8(clampInteger(math.floor(value.R * 255 + 0.5), 0, 255))
		writer:u8(clampInteger(math.floor(value.G * 255 + 0.5), 0, 255))
		writer:u8(clampInteger(math.floor(value.B * 255 + 0.5), 0, 255))
	elseif robloxType == "CFrame" then
		writer:u8(TYPE_CFRAME * 16)
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()
		local precision = Config.VectorPrecision
		writer:varInt(roundScaled(x, precision))
		writer:varInt(roundScaled(y, precision))
		writer:varInt(roundScaled(z, precision))
		local qx, qy, qz, qw = matrixToQuaternion(r00, r01, r02, r10, r11, r12, r20, r21, r22)
		writer:i16(clampInteger(roundScaled(qx, 32767), -32767, 32767))
		writer:i16(clampInteger(roundScaled(qy, 32767), -32767, 32767))
		writer:i16(clampInteger(roundScaled(qz, 32767), -32767, 32767))
		writer:i16(clampInteger(roundScaled(qw, 32767), -32767, 32767))
	elseif robloxType == "buffer" then
		local length = buffer.len(value)
		writeMeta(writer, TYPE_BUFFER, length)
		writer:rawBuffer(value)
	elseif robloxType == "UDim" then
		writer:u8(TYPE_EXTENDED * 16 + EXT.UDIM)
		writer:f64(value.Scale)
		writer:i32(value.Offset)
	elseif robloxType == "UDim2" then
		writer:u8(TYPE_EXTENDED * 16 + EXT.UDIM2)
		writer:f64(value.X.Scale)
		writer:i32(value.X.Offset)
		writer:f64(value.Y.Scale)
		writer:i32(value.Y.Offset)
	elseif robloxType == "Rect" then
		writer:u8(TYPE_EXTENDED * 16 + EXT.RECT)
		writer:f64(value.Min.X)
		writer:f64(value.Min.Y)
		writer:f64(value.Max.X)
		writer:f64(value.Max.Y)
	elseif robloxType == "NumberRange" then
		writer:u8(TYPE_EXTENDED * 16 + EXT.NUMBER_RANGE)
		writer:f64(value.Min)
		writer:f64(value.Max)
	elseif robloxType == "BrickColor" then
		writer:u8(TYPE_EXTENDED * 16 + EXT.BRICK_COLOR)
		writer:u16(value.Number)
	elseif robloxType == "DateTime" then
		writer:u8(TYPE_EXTENDED * 16 + EXT.DATETIME)
		writer:f64(value.UnixTimestampMillis)
	elseif luaType == "table" then
		local mt = getmetatable(value)
		if mt == Float32Tag then
			writer:u8(TYPE_F32 * 16)
			writer:f32(value[1])
			return
		elseif mt == RawStringTag then
			local raw = value[1]
			writer:u8(TYPE_EXTENDED * 16 + EXT.RAW_STRING)
			writer:varUInt(#raw)
			writer:rawString(raw)
			return
		end
		seen = seen or {}
		if seen[value] then
			error("NetStream cannot encode circular tables", 0)
		end
		seen[value] = true
		local arrayMode, length = Internal.isArray(value)
		if arrayMode then
			writeMeta(writer, TYPE_ARRAY, length)
			for i = 1, length do
				writeValue(writer, value[i], depth + 1, seen)
			end
		else
			local count = 0
			for _ in pairs(value) do
				count += 1
			end
			writeMeta(writer, TYPE_MAP, count)
			for key, item in pairs(value) do
				writeValue(writer, key, depth + 1, seen)
				writeValue(writer, item, depth + 1, seen)
			end
		end
		seen[value] = nil
	else
		error("NetStream unsupported value type: " .. robloxType, 0)
	end
end


-- Exact byte-cost estimator for the native dynamic codec. This mirrors writeValue
-- without touching a scratch buffer, so compression decisions no longer serialize
-- the same payload twice just to learn its native byte count.
Internal._nativeMeasurePool = {}

function Internal.nativeMetaByteLength(value)
	if value < 15 then
		return 1
	end
	return 1 + Internal.varUIntByteLength(value)
end

function Internal.nativeVarIntByteLength(value)
	local zigzag
	if value >= 0 then
		zigzag = value * 2
	else
		zigzag = -value * 2 - 1
	end
	return Internal.varUIntByteLength(zigzag)
end

function Internal.acquireNativeMeasureState(writer)
	local pool = Internal._nativeMeasurePool
	local state = pool[#pool]
	if state then
		pool[#pool] = nil
	else
		state = { strings = {}, seen = {}, nextStringIndex = 0 }
	end
	table.clear(state.strings)
	table.clear(state.seen)
	state.nextStringIndex = writer and #writer.strings or 0
	return state
end

function Internal.releaseNativeMeasureState(state)
	if not state then
		return
	end
	table.clear(state.strings)
	table.clear(state.seen)
	state.nextStringIndex = 0
	local pool = Internal._nativeMeasurePool
	if #pool < Config.MaxScratchWriterPoolSize then
		pool[#pool + 1] = state
	end
end

function Internal.nativeValueByteLength(writer, value, state)
	if value == nil then
		return 1
	end
	local luaType = type(value)
	local robloxType = typeof(value)
	if luaType == "boolean" then
		return 1
	elseif luaType == "number" then
		local canVarInt = isInteger(value)
			and ((value >= 0 and value <= MAX_SAFE_INTEGER)
				or (value < 0 and -value <= MAX_SAFE_VARINT_MAGNITUDE))
		if not canVarInt then
			return 9
		end
		if value >= 0 then
			if value < 15 then
				return 1
			end
			return 1 + Internal.varUIntByteLength(value)
		end
		local zigzag = -value * 2 - 1
		if zigzag < 15 then
			return 1
		end
		return 1 + Internal.varUIntByteLength(zigzag)
	elseif luaType == "string" then
		local index = writer and writer.stringToIndex[value] or nil
		if index == nil then
			index = state.strings[value]
		end
		if index ~= nil then
			return Internal.nativeMetaByteLength(index)
		end
		local length = #value
		state.strings[value] = state.nextStringIndex
		state.nextStringIndex += 1
		return Internal.nativeMetaByteLength(length) + length
	elseif robloxType == "Vector3" then
		local precision = Config.VectorPrecision
		return 1
			+ Internal.nativeVarIntByteLength(roundScaled(value.X, precision))
			+ Internal.nativeVarIntByteLength(roundScaled(value.Y, precision))
			+ Internal.nativeVarIntByteLength(roundScaled(value.Z, precision))
	elseif robloxType == "Vector2" then
		local precision = Config.VectorPrecision
		return 1
			+ Internal.nativeVarIntByteLength(roundScaled(value.X, precision))
			+ Internal.nativeVarIntByteLength(roundScaled(value.Y, precision))
	elseif robloxType == "Color3" then
		return 4
	elseif robloxType == "CFrame" then
		local position = value.Position
		local precision = Config.VectorPrecision
		return 9
			+ Internal.nativeVarIntByteLength(roundScaled(position.X, precision))
			+ Internal.nativeVarIntByteLength(roundScaled(position.Y, precision))
			+ Internal.nativeVarIntByteLength(roundScaled(position.Z, precision))
	elseif robloxType == "buffer" then
		local length = buffer.len(value)
		return Internal.nativeMetaByteLength(length) + length
	elseif robloxType == "UDim" then
		return 13
	elseif robloxType == "UDim2" then
		return 25
	elseif robloxType == "Rect" then
		return 33
	elseif robloxType == "NumberRange" then
		return 17
	elseif robloxType == "BrickColor" then
		return 3
	elseif robloxType == "DateTime" then
		return 9
	elseif luaType == "table" then
		local mt = getmetatable(value)
		if mt == Float32Tag then
			return 5
		elseif mt == RawStringTag then
			local raw = value[1]
			return 1 + Internal.varUIntByteLength(#raw) + #raw
		end
		if state.seen[value] then
			error("NetStream cannot estimate circular tables", 0)
		end
		state.seen[value] = true
		local count = 0
		local maxIndex = 0
		local arrayCandidate = true
		for key in pairs(value) do
			count += 1
			if type(key) ~= "number" or not isInteger(key) or key < 1 then
				arrayCandidate = false
			elseif key > maxIndex then
				maxIndex = key
			end
		end
		local bytes
		if arrayCandidate and count == maxIndex then
			bytes = Internal.nativeMetaByteLength(maxIndex)
			for i = 1, maxIndex do
				bytes += Internal.nativeValueByteLength(writer, value[i], state)
			end
		else
			bytes = Internal.nativeMetaByteLength(count)
			for key, item in pairs(value) do
				bytes += Internal.nativeValueByteLength(writer, key, state)
				bytes += Internal.nativeValueByteLength(writer, item, state)
			end
		end
		state.seen[value] = nil
		return bytes
	end
	error("NetStream unsupported value type during native size estimate: " .. robloxType, 0)
end

function Internal.nativeDynamicArgsByteLength(writer, args)
	local state = Internal.acquireNativeMeasureState(writer)
	local bytes = 0
	for i = 1, args.n do
		bytes += Internal.nativeValueByteLength(writer, args[i], state)
	end
	Internal.releaseNativeMeasureState(state)
	Stats.CompressionNativeSizeEstimates += 1
	Stats.CompressionNativeScratchAvoided += 1
	return bytes
end

function Internal.nativeSingleValueByteLength(value)
	local state = Internal.acquireNativeMeasureState(nil)
	local bytes = Internal.nativeValueByteLength(nil, value, state)
	Internal.releaseNativeMeasureState(state)
	Stats.CompressionNativeSizeEstimates += 1
	Stats.CompressionNativeScratchAvoided += 1
	return bytes
end

readValue = function(reader, depth)
	depth = depth or 0
	if depth > Config.MaxDepth then
		error("NetStream decode exceeded MaxDepth", 0)
	end
	local descriptor = reader:u8()
	local typeId = math.floor(descriptor / 16)
	local meta = descriptor % 16
	if typeId == TYPE_NIL then
		if meta ~= 0 then error("NetStream invalid nil descriptor", 0) end
		return nil
	elseif typeId == TYPE_BOOL then
		if meta > 1 then error("NetStream invalid boolean descriptor", 0) end
		return meta ~= 0
	elseif typeId == TYPE_UINT then
		if meta == 15 then
			return reader:varUInt()
		end
		return meta
	elseif typeId == TYPE_SINT then
		local zigzag = if meta == 15 then reader:varUInt() else meta
		if zigzag % 2 == 0 then
			return zigzag / 2
		end
		return -((zigzag + 1) / 2)
	elseif typeId == TYPE_F32 then
		local value = reader:f32()
		if not isFiniteNumber(value) or math.abs(value) > MAX_FLOAT32 then
			error("NetStream incoming float32 is not finite", 0)
		end
		return value
	elseif typeId == TYPE_F64 then
		local value = reader:f64()
		if not isFiniteNumber(value) then
			error("NetStream incoming float64 is not finite", 0)
		end
		return value
	elseif typeId == TYPE_STRING then
		local length = readMeta(reader, descriptor)
		if length > Config.MaxStringBytes then
			error("NetStream incoming string exceeds MaxStringBytes", 0)
		end
		local value = reader:rawString(length)
		reader.strings[#reader.strings + 1] = value
		return value
	elseif typeId == TYPE_STRING_REF then
		local index = readMeta(reader, descriptor)
		local value = reader.strings[index + 1]
		if value == nil then
			error("NetStream invalid string reference", 0)
		end
		return value
	elseif typeId == TYPE_VECTOR3 then
		local inv = 1 / Config.VectorPrecision
		return Vector3.new(reader:varInt() * inv, reader:varInt() * inv, reader:varInt() * inv)
	elseif typeId == TYPE_VECTOR2 then
		local inv = 1 / Config.VectorPrecision
		return Vector2.new(reader:varInt() * inv, reader:varInt() * inv)
	elseif typeId == TYPE_COLOR3 then
		return Color3.fromRGB(reader:u8(), reader:u8(), reader:u8())
	elseif typeId == TYPE_CFRAME then
		local inv = 1 / Config.VectorPrecision
		local x = reader:varInt() * inv
		local y = reader:varInt() * inv
		local z = reader:varInt() * inv
		local qx = reader:i16() / 32767
		local qy = reader:i16() / 32767
		local qz = reader:i16() / 32767
		local qw = reader:i16() / 32767
		local r00, r01, r02, r10, r11, r12, r20, r21, r22 = quaternionToMatrix(qx, qy, qz, qw)
		return CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	elseif typeId == TYPE_ARRAY then
		local length = readMeta(reader, descriptor)
		if length > Config.MaxTableEntries then
			error("NetStream incoming array exceeds MaxTableEntries", 0)
		end
		local value = table.create(length)
		for i = 1, length do
			value[i] = readValue(reader, depth + 1)
		end
		return value
	elseif typeId == TYPE_MAP then
		local count = readMeta(reader, descriptor)
		if count > Config.MaxTableEntries then
			error("NetStream incoming map exceeds MaxTableEntries", 0)
		end
		local value = {}
		for _ = 1, count do
			local key = readValue(reader, depth + 1)
			if key == nil then
				error("NetStream incoming map contains a nil key", 0)
			end
			local item = readValue(reader, depth + 1)
			value[key] = item
		end
		return value
	elseif typeId == TYPE_BUFFER then
		local length = readMeta(reader, descriptor)
		if length > Config.MaxBufferBytes then
			error("NetStream incoming buffer exceeds MaxBufferBytes", 0)
		end
		return reader:rawBuffer(length)
	elseif typeId == TYPE_EXTENDED then
		if meta == EXT.RAW_STRING then
			local length = reader:varUInt()
			if length > Config.MaxStringBytes then error("NetStream incoming raw string exceeds MaxStringBytes", 0) end
			return reader:rawString(length)
		elseif meta == EXT.UDIM then
			return UDim.new(reader:f64(), reader:i32())
		elseif meta == EXT.UDIM2 then
			return UDim2.new(reader:f64(), reader:i32(), reader:f64(), reader:i32())
		elseif meta == EXT.RECT then
			return Rect.new(reader:f64(), reader:f64(), reader:f64(), reader:f64())
		elseif meta == EXT.NUMBER_RANGE then
			return NumberRange.new(reader:f64(), reader:f64())
		elseif meta == EXT.BRICK_COLOR then
			return BrickColor.new(reader:u16())
		elseif meta == EXT.DATETIME then
			local millis = reader:f64()
			if not isFiniteNumber(millis) then error("NetStream incoming DateTime timestamp is not finite", 0) end
			return DateTime.fromUnixTimestampMillis(millis)
		end
		error("NetStream unknown extended type descriptor", 0)
	end
	error("NetStream unknown type descriptor", 0)
end

local peekTargetBucket

local function messageLogicalCount(item)
	if item and item.packedRun then
		return item.runCount or 1
	end
	return if item then 1 else 0
end

function Internal.newQueue()
	return { items = {}, head = 1, tail = 0, logicalCount = 0 }
end

local function queueCount(queue)
	return queue.tail - queue.head + 1
end

local function queueLogicalCount(queue)
	return queue.logicalCount or queueCount(queue)
end

local function queuePush(queue, item)
	queue.tail += 1
	queue.items[queue.tail] = item
	queue.logicalCount += messageLogicalCount(item)
end

local function queuePop(queue)
	if queue.head > queue.tail then
		return nil
	end
	local item = queue.items[queue.head]
	queue.items[queue.head] = nil
	queue.head += 1
	queue.logicalCount = math.max(0, queue.logicalCount - messageLogicalCount(item))
	if queue.head > queue.tail then
		queue.head = 1
		queue.tail = 0
		queue.logicalCount = 0
	end
	return item
end

function Internal.newBucket()
	return {
		reliable = Internal.newQueue(),
		unreliable = Internal.newQueue(),
		latestReliable = {},
		latestUnreliable = {},
		reliableNotBefore = 0,
		unreliableNotBefore = 0,
	}
end

local function bucketEmpty(bucket)
	return queueCount(bucket.reliable) <= 0
		and queueCount(bucket.unreliable) <= 0
		and next(bucket.latestReliable) == nil
		and next(bucket.latestUnreliable) == nil
end

function Internal.releaseQueue(queue)
	while queueCount(queue) > 0 do
		releaseMessage(queuePop(queue))
	end
end

function Internal.releaseLatest(latest)
	for _, message in pairs(latest) do
		releaseMessage(message)
	end
	table.clear(latest)
end

function Internal.releaseBucket(bucket)
	if not bucket then
		return
	end
	Internal.releaseQueue(bucket.reliable)
	Internal.releaseQueue(bucket.unreliable)
	Internal.releaseLatest(bucket.latestReliable)
	Internal.releaseLatest(bucket.latestUnreliable)
end

function Internal.queueRemoveRoute(queue, routeId, kind)
	if queueCount(queue) <= 0 then
		return 0
	end
	local removed = 0
	local remainingLogical = 0
	local writeIndex = queue.head
	for readIndex = queue.head, queue.tail do
		local message = queue.items[readIndex]
		queue.items[readIndex] = nil
		if message and message.id == routeId and message.kind == kind then
			local logical = messageLogicalCount(message)
			releaseMessage(message)
			removed += logical
		elseif message then
			queue.items[writeIndex] = message
			remainingLogical += messageLogicalCount(message)
			writeIndex += 1
		end
	end
	queue.logicalCount = remainingLogical
	if writeIndex == queue.head then
		queue.head = 1
		queue.tail = 0
	else
		queue.tail = writeIndex - 1
	end
	return removed
end

function Internal.cancelQueuedForRoute(target, routeId, kind)
	local bucket = peekTargetBucket and peekTargetBucket(target) or nil
	if not bucket then
		return 0
	end
	local removed = Internal.queueRemoveRoute(bucket.reliable, routeId, kind)
	removed += Internal.queueRemoveRoute(bucket.unreliable, routeId, kind)
	local key = routeId * 4 + kind
	local reliableLatest = bucket.latestReliable[key]
	if reliableLatest then
		bucket.latestReliable[key] = nil
		releaseMessage(reliableLatest)
		removed += 1
	end
	local unreliableLatest = bucket.latestUnreliable[key]
	if unreliableLatest then
		bucket.latestUnreliable[key] = nil
		releaseMessage(unreliableLatest)
		removed += 1
	end
	if removed > 0 then
		Stats.CancelledQueued += removed
	end
	if IS_SERVER and target ~= ALL and bucketEmpty(bucket) then
		targetBuckets[target] = nil
	end
	return removed
end

function Internal.mapCount(map)
	local count = 0
	for _ in pairs(map) do
		count += 1
	end
	return count
end

local function getTargetBucket(target)
	if IS_SERVER then
		if target == ALL then
			if not broadcastBucket then
				broadcastBucket = Internal.newBucket()
			end
			return broadcastBucket
		end
		assert(typeof(target) == "Instance" and target:IsA("Player"), "NetStream server target must be a Player")
		local bucket = targetBuckets[target]
		if not bucket then
			bucket = Internal.newBucket()
			targetBuckets[target] = bucket
			activeTargetTail += 1
			activeTargets[activeTargetTail] = target
		end
		return bucket
	end
	if not clientBucket then
		clientBucket = Internal.newBucket()
	end
	return clientBucket
end

acquireArgsCount = function(n)
	if n == 0 then
		return EMPTY_ARGS
	end
	local args = argsPool[#argsPool]
	if args then
		argsPool[#argsPool] = nil
		Stats.ArgsPoolHits += 1
	else
		args = {}
	end
	args.n = n
	return args
end

local function makeArgs(...)
	local n = select("#", ...)
	local args = acquireArgsCount(n)
	for i = 1, n do
		args[i] = select(i, ...)
	end
	return args
end


local function acquirePackedValues(capacity)
	local values = packedValuePool[#packedValuePool]
	if values then
		packedValuePool[#packedValuePool] = nil
		table.clear(values)
		Stats.PackedValuePoolHits += 1
		return values
	end
	return table.create(capacity or 8)
end

local function releasePackedValues(values)
	if not values then
		return
	end
	table.clear(values)
	if #packedValuePool < Config.MaxBatchPoolSize then
		packedValuePool[#packedValuePool + 1] = values
	end
end
local function releaseArgs(args)
	if not args or args == EMPTY_ARGS or args == TRUE_ARGS or args == FALSE_ARGS then
		return
	end
	local n = args.n or 0
	for i = 1, n do
		args[i] = nil
	end
	args.n = 0
	if n <= Config.MaxPooledArgs and #argsPool < Config.MaxPoolSize then
		argsPool[#argsPool + 1] = args
	end
end

local function validateArgs(args)
	for i = 1, args.n do
		validateValue(args[i], 0, nil)
	end
end

local function acquireMessage()
	local message = messagePool[#messagePool]
	if message then
		messagePool[#messagePool] = nil
		Stats.MessagePoolHits += 1
		return message
	end
	return {}
end

local function makeMessage(kind, id, request, args, schema, priority)
	local message = acquireMessage()
	message.kind = kind
	message.id = id
	message.request = request
	message.args = args
	message.n = args and args.n or 0
	message.schema = schema
	message.priority = priority
	message.latestKey = nil
	message.packedRun = false
	message.packedValues = nil
	message.runCount = nil
	message.runLimit = nil
	message.fieldCount = nil
	return message
end

local function makePackedRunMessage(route, valueCount, runLimit, ...)
	local message = acquireMessage()
	local values = acquirePackedValues(math.max(8, valueCount * math.min(Config.MaxBatchMessages, 512)))
	for i = 1, valueCount do
		values[i] = select(i, ...)
	end
	message.kind = KIND_EVENT
	message.id = route.Id
	message.request = 0
	message.args = nil
	message.n = valueCount
	message.schema = route._schema
	message.priority = route.Priority or "Normal"
	message.latestKey = nil
	message.packedRun = true
	message.packedValues = values
	message.runCount = 1
	message.runLimit = runLimit
	message.fieldCount = valueCount
	Stats.PackedSchemaRunItems += 1
	Stats.PackedSchemaRunMessages += 1
	return message
end

releaseMessage = function(message)
	if not message then
		return
	end
	releaseArgs(message.args)
	if message.packedValues then
		releasePackedValues(message.packedValues)
	end
	message.kind = nil
	message.id = nil
	message.request = nil
	message.args = nil
	message.n = nil
	message.schema = nil
	message.priority = nil
	message.latestKey = nil
	message.packedRun = nil
	message.packedValues = nil
	message.runCount = nil
	message.runLimit = nil
	message.fieldCount = nil
	if #messagePool < Config.MaxPoolSize then
		messagePool[#messagePool + 1] = message
	end
end

function Internal.messagePriority(message)
	if message.priority then
		return message.priority
	end
	if message.kind == KIND_RETURN then
		return "Critical"
	end
	local route
	if message.kind == KIND_EVENT then
		route = eventRoutes[message.id]
	elseif message.kind == KIND_CALL then
		route = functionRoutes[message.id]
	elseif message.kind == KIND_STATE then
		route = stateRoutes[message.id]
	end
	if route and route.Priority then
		return route.Priority
	end
	if message.kind == KIND_CALL then
		return "Critical"
	end
	return "Normal"
end

function Internal.transportWindow(priority)
	if not Config.TransportAdaptiveBatching or priority == "Critical" then
		return 0
	end
	if priority == "Realtime" then
		return Config.TransportRealtimeBatchWindowSeconds
	end
	return Config.TransportBatchWindowSeconds
end

local function enqueue(target, unreliable, message, latestKey)
	local bucket = getTargetBucket(target)
	message.latestKey = latestKey
	local priority = Internal.messagePriority(message)
	local queue = if unreliable then bucket.unreliable else bucket.reliable
	local latest = if unreliable then bucket.latestUnreliable else bucket.latestReliable
	local wasEmpty = queueCount(queue) <= 0 and next(latest) == nil
	local now = os.clock()
	local notBeforeKey = if unreliable then "unreliableNotBefore" else "reliableNotBefore"
	if wasEmpty then
		bucket[notBeforeKey] = now + Internal.transportWindow(priority)
	elseif priority == "Critical" then
		bucket[notBeforeKey] = now
	end
	Stats.TransportLogicalMessagesQueued += 1
	if priority == "Critical" then
		Stats.TransportCriticalMessagesQueued += 1
	elseif priority == "Realtime" then
		Stats.TransportRealtimeMessagesQueued += 1
	else
		Stats.TransportNormalMessagesQueued += 1
	end
	if latestKey ~= nil then
		local old = latest[latestKey]
		if old then
			releaseMessage(old)
			Stats.CoalescedLatest += 1
		end
		latest[latestKey] = message
		return true
	end
	local maxQueue = if unreliable then Config.MaxUnreliableQueue else Config.MaxReliableQueue
	if Config.BandwidthGovernorEnabled then
		local pressureLimit = if unreliable then Config.BandwidthMaxUnreliableQueue else Config.BandwidthMaxReliableQueue
		maxQueue = math.min(maxQueue, pressureLimit)
	end
	if queueLogicalCount(queue) >= maxQueue then
		if unreliable then
			local dropped = queuePop(queue)
			local droppedCount = messageLogicalCount(dropped)
			releaseMessage(dropped)
			Stats.DroppedUnreliable += droppedCount
			Stats.BandwidthQueuePressureDrops += droppedCount
		else
			Stats.RejectedReliable += 1
			releaseMessage(message)
			if not overflowWarned then
				overflowWarned = true
				warn(LOG_PREFIX, "Reliable queue is full; rejecting new messages. Use Coalesce/Latest for high-frequency state or increase the bandwidth queue limits deliberately.")
			end
			return false
		end
	end
	queuePush(queue, message)
	return true
end


local function packedRunMaxMessages(schema)
	local maxRun = Config.MaxBatchMessages
	if Config.BandwidthGovernorEnabled and schema and schema.fixedBytes and schema.fixedBytes > 0 then
		local payloadBudget = math.max(schema.fixedBytes, Config.BandwidthMaxPacketBytes - 24)
		maxRun = math.min(maxRun, math.max(1, math.floor(payloadBudget / schema.fixedBytes)))
	end
	return maxRun
end

function Internal.enqueuePackedEvent(target, unreliable, route, valueCount, ...)
	local bucket = getTargetBucket(target)
	local queue = if unreliable then bucket.unreliable else bucket.reliable
	local latest = if unreliable then bucket.latestUnreliable else bucket.latestReliable
	local priority = route.Priority or "Normal"
	local maxQueue = if unreliable then Config.MaxUnreliableQueue else Config.MaxReliableQueue
	if Config.BandwidthGovernorEnabled then
		local pressureLimit = if unreliable then Config.BandwidthMaxUnreliableQueue else Config.BandwidthMaxReliableQueue
		maxQueue = math.min(maxQueue, pressureLimit)
	end

	if queueLogicalCount(queue) >= maxQueue then
		if unreliable then
			local dropped = queuePop(queue)
			local droppedCount = messageLogicalCount(dropped)
			releaseMessage(dropped)
			Stats.DroppedUnreliable += droppedCount
			Stats.BandwidthQueuePressureDrops += droppedCount
		else
			Stats.RejectedReliable += 1
			if not overflowWarned then
				overflowWarned = true
				warn(LOG_PREFIX, "Reliable queue is full; rejecting new messages. Use Coalesce/Latest for high-frequency state or increase the bandwidth queue limits deliberately.")
			end
			return false
		end
	end

	local wasEmpty = queueCount(queue) <= 0 and next(latest) == nil
	local tail = if queue.tail >= queue.head then queue.items[queue.tail] else nil
	if tail and tail.packedRun and tail.kind == KIND_EVENT and tail.id == route.Id and tail.schema == route._schema
		and tail.priority == priority and tail.runCount < tail.runLimit then
		local base = tail.runCount * valueCount
		local values = tail.packedValues
		for i = 1, valueCount do
			values[base + i] = select(i, ...)
		end
		tail.runCount += 1
		queue.logicalCount += 1
		Stats.PackedSchemaRunMessages += 1
		Stats.PackedSchemaRunAppends += 1
	else
		queuePush(queue, makePackedRunMessage(route, valueCount, packedRunMaxMessages(route._schema), ...))
	end

	local notBeforeKey = if unreliable then "unreliableNotBefore" else "reliableNotBefore"
	if wasEmpty then
		bucket[notBeforeKey] = os.clock() + Internal.transportWindow(priority)
	elseif priority == "Critical" then
		bucket[notBeforeKey] = os.clock()
	end
	Stats.TransportLogicalMessagesQueued += 1
	if priority == "Critical" then
		Stats.TransportCriticalMessagesQueued += 1
	elseif priority == "Realtime" then
		Stats.TransportRealtimeMessagesQueued += 1
	else
		Stats.TransportNormalMessagesQueued += 1
	end
	return true
end
function Internal.routeForItem(item)
	if item.kind == KIND_EVENT then
		return eventRoutes[item.id]
	elseif item.kind == KIND_CALL then
		return functionRoutes[item.id]
	elseif item.kind == KIND_STATE then
		return stateRoutes[item.id]
	end
	return nil
end

function Internal.routeCompressionEnabled(item)
	if not Config.CompressionEnabled then
		return false
	end
	local route = Internal.routeForItem(item)
	if route and route.Compression == false then
		return false
	end
	if route and route.Compression == true then
		return true
	end
	return Internal.shouldAttemptCompression(item.args)
end

function Internal.compressionOptionsForRoute(route)
	local base = Internal.compressionOptions()
	if not Config.CompressionRouteStrategyCache or Config.CompressionTableStrategy ~= "Auto" or route == nil then
		return base, false
	end
	local strategy = route._compressionTableStrategy
	if strategy == nil then
		Stats.CompressionStrategyCacheMisses += 1
		return base, false
	end
	local remaining = route._compressionStrategyRemaining or 0
	if remaining <= 0 then
		Stats.CompressionStrategyCacheResamples += 1
		return base, false
	end
	route._compressionStrategyRemaining = remaining - 1
	local options = route._compressionStrategyOptions
	if options == nil or options.TableStrategy ~= strategy then
		options = table.clone(base)
		options.TableStrategy = strategy
		route._compressionStrategyOptions = options
	end
	Stats.CompressionStrategyCacheHits += 1
	return options, true
end

function Internal.observeCompressionStrategy(route, data, usedCachedStrategy)
	if not Config.CompressionRouteStrategyCache or Config.CompressionTableStrategy ~= "Auto" or route == nil then
		return
	end
	local selected = if Compression.IsCompactTable(data) then "Compact" else "Dynamic"
	local locked = route._compressionTableStrategy
	if locked ~= nil then
		if usedCachedStrategy then
			if selected ~= locked then
				route._compressionTableStrategy = nil
				route._compressionStrategyOptions = nil
				route._compressionStrategyCandidate = selected
				route._compressionStrategyCandidateCount = 1
				route._compressionStrategyRemaining = 0
				Stats.CompressionStrategyCacheResets += 1
			end
			return
		end
		if selected == locked then
			route._compressionStrategyRemaining = Config.CompressionRouteStrategyResample
			return
		end
		route._compressionTableStrategy = nil
		route._compressionStrategyOptions = nil
		route._compressionStrategyCandidate = selected
		route._compressionStrategyCandidateCount = 1
		route._compressionStrategyRemaining = 0
		Stats.CompressionStrategyCacheResets += 1
		return
	end
	if route._compressionStrategyCandidate == selected then
		route._compressionStrategyCandidateCount = (route._compressionStrategyCandidateCount or 0) + 1
	else
		route._compressionStrategyCandidate = selected
		route._compressionStrategyCandidateCount = 1
	end
	if route._compressionStrategyCandidateCount >= Config.CompressionRouteStrategyWarmup then
		route._compressionTableStrategy = selected
		route._compressionStrategyOptions = nil
		route._compressionStrategyRemaining = Config.CompressionRouteStrategyResample
		route._compressionStrategyCandidate = nil
		route._compressionStrategyCandidateCount = 0
		Stats.CompressionStrategyCacheLocks += 1
	end
end

function Internal.tryCompressDynamicArgs(writer, item, isTail)
	if not Internal.routeCompressionEnabled(item) then
		return nil, nil, false, false
	end

	Stats.CompressionAttempts += 1

	local rawPayloadBytes = Internal.nativeDynamicArgsByteLength(writer, item.args)
	local rawCountBytes = if item.n >= 30 then Internal.varUIntByteLength(item.n * 4) else 0
	local rawCost = rawCountBytes + rawPayloadBytes
	if not Internal.hybridCompressionAllowed(item, rawCost * 8) then return nil, nil, false, false end

	local source = item.args
	local mode = 1
	if item.n == 1 and typeof(item.args[1]) == "table" then
		source = item.args[1]
		mode = 2
	end

	local route = Internal.routeForItem(item)
	local compressionOptions, usedCachedStrategy = Internal.compressionOptionsForRoute(route)
	local ok, packet = pcall(Compression.Compress, source, compressionOptions)
	if not ok or type(packet) ~= "table" or typeof(packet.Data) ~= "buffer" then
		Stats.CompressionRejected += 1
		Stats.CompressionErrors += 1
		if not ok then
			Internal.debugWarn("Compression candidate rejected:", packet)
		end
		return nil, nil, false, false
	end

	local data = packet.Data
	Internal.observeCompressionStrategy(route, data, usedCachedStrategy)
	local dataBytes = buffer.len(data)
	local directSingle = mode == 2
	local control = if directSingle then nil else item.n * 4 + mode
	local omitLength = isTail == true
	local compressedCost = dataBytes
	if not omitLength then
		compressedCost += Internal.varUIntByteLength(dataBytes)
	end
	if control ~= nil then
		compressedCost += Internal.varUIntByteLength(control)
	end

	if compressedCost + Config.CompressionMinSavingsBytes <= rawCost then
		Stats.CompressionUsed += 1
		Stats.CompressionInputBytes += rawCost
		Stats.CompressionOutputBytes += compressedCost
		Internal.recordCompressionPacketBits(packet, rawCost, compressedCost)
		local saved = rawCost - compressedCost
		if saved > 0 then
			Stats.CompressionSavedBytes += saved
			Stats.CompressionEstimatedNetBytesSaved += saved
		end
		if Compression.IsCompactTable(data) then
			Stats.CompressionCompactTableUsed += 1
			local tableMode = Compression.TableMode(data)
			if string.find(tableMode, "Mapped", 1, true) ~= nil then Stats.CompressionMappedTableUsed += 1 end
		else
			Stats.CompressionDynamicTableUsed += 1
		end
		if directSingle then
			Stats.CompressionDirectTableUsed += 1
		end
		if omitLength then
			Stats.CompressionTailLengthElisions += 1
		end
		return data, control, directSingle, omitLength
	end

	Stats.CompressionRejected += 1
	Stats.CompressionNoGain += 1
	return nil, nil, false, false
end


-- v2.0: BufferUtil tiny-payload fast path.
function Internal.tryEncodeHybridSmallSingle(item)
	if not Config.HybridCodecEnabled or not Config.HybridSmallScalarEnabled or item.schema ~= nil then return nil end
	local route = Internal.routeForItem(item)
	if route and route.Compression == true then return nil end
	local scalarBits
	local rawPayloadBytes
	local nativeBytes
	local totalBits
	local out
	local bitPosition = 0
	if item.kind == KIND_EVENT or item.kind == KIND_STATE then
		if item.n ~= 1 then return nil end
		scalarBits = Internal.hybridScalarBitLength(item.args[1]); if scalarBits == nil then return nil end
		rawPayloadBytes = Internal.nativeDynamicArgsByteLength(nil, item.args)
		totalBits = 3 + 1 + Internal.packetAdaptiveUIntBitLength(item.id) + scalarBits
		nativeBytes = 2 + Internal.varUIntByteLength(item.id) + rawPayloadBytes
	elseif item.kind == KIND_CALL then
		if item.n ~= 1 then return nil end
		scalarBits = Internal.hybridScalarBitLength(item.args[1]); if scalarBits == nil then return nil end
		rawPayloadBytes = Internal.nativeDynamicArgsByteLength(nil, item.args)
		totalBits = 3 + Internal.packetAdaptiveUIntBitLength(item.id) + Internal.packetAdaptiveUIntBitLength(item.request) + scalarBits
		nativeBytes = 2 + Internal.varUIntByteLength(item.id) + Internal.varUIntByteLength(item.request) + rawPayloadBytes
	elseif item.kind == KIND_RETURN then
		if item.n ~= 2 or type(item.args[1]) ~= "boolean" then return nil end
		scalarBits = Internal.hybridScalarBitLength(item.args[2]); if scalarBits == nil then return nil end
		rawPayloadBytes = Internal.nativeDynamicArgsByteLength(nil, item.args)
		totalBits = 3 + Internal.packetAdaptiveUIntBitLength(item.request) + 1 + scalarBits
		nativeBytes = 2 + Internal.varUIntByteLength(item.request) + rawPayloadBytes
	else
		return nil
	end
	if totalBits > Config.HybridSmallPacketMaxBits then return nil end
	local totalBytes = math.ceil(totalBits / 8)
	if nativeBytes - totalBytes < Config.HybridMinPhysicalSavingsBytes then return nil end
	out = Internal.BufferUtil.new(totalBytes)
	if item.kind == KIND_EVENT or item.kind == KIND_STATE then
		bitPosition = Internal.packetWriteBits(out, bitPosition, Internal.HYBRID_EVENT_STATE_MARKER, 3)
		bitPosition = Internal.packetWriteBits(out, bitPosition, item.kind == KIND_STATE and 1 or 0, 1)
		bitPosition = Internal.packetWriteAdaptiveUInt(out, bitPosition, item.id)
		bitPosition = Internal.hybridWriteScalar(out, bitPosition, item.args[1])
	elseif item.kind == KIND_CALL then
		bitPosition = Internal.packetWriteBits(out, bitPosition, Internal.HYBRID_CALL_MARKER, 3)
		bitPosition = Internal.packetWriteAdaptiveUInt(out, bitPosition, item.id)
		bitPosition = Internal.packetWriteAdaptiveUInt(out, bitPosition, item.request)
		bitPosition = Internal.hybridWriteScalar(out, bitPosition, item.args[1])
	else
		bitPosition = Internal.packetWriteBits(out, bitPosition, Internal.HYBRID_RETURN_MARKER, 3)
		bitPosition = Internal.packetWriteAdaptiveUInt(out, bitPosition, item.request)
		bitPosition = Internal.packetWriteBits(out, bitPosition, item.args[1] and 1 or 0, 1)
		bitPosition = Internal.hybridWriteScalar(out, bitPosition, item.args[2])
	end
	Internal.recordHybridPacket(bitPosition, totalBytes, nativeBytes)
	Stats.SingleMessagePackets += 1
	Stats.DynamicMessages += 1
	return out
end

-- v1.8: packs a single dynamic Function call header at bit granularity.
-- Format (LSB-first):
--   3 bits marker (000)
--   adaptive UInt route id
--   adaptive UInt request id
--   compressed payload bytes shifted directly into the same bitstream
-- Only the final packet tail is byte-rounded.
function Internal.tryEncodeBitCallSingle(item)
	if not Config.BitPacketEnabled
		or not Config.BitPacketCompressedCalls
		or item.schema ~= nil
		or item.kind ~= KIND_CALL
		or item.n ~= 1
		or typeof(item.args[1]) ~= "table"
		or item.id <= 0
		or item.request <= 0
		or not Internal.routeCompressionEnabled(item)
	then
		return nil, false
	end

	Stats.CompressionAttempts += 1
	local rawPayloadBytes = Internal.nativeSingleValueByteLength(item.args[1])
	if not Internal.hybridCompressionAllowed(item, rawPayloadBytes * 8) then return nil, true end
	local route = Internal.routeForItem(item)
	local compressionOptions, usedCachedStrategy = Internal.compressionOptionsForRoute(route)
	local ok, packet = pcall(Compression.Compress, item.args[1], compressionOptions)
	if not ok or type(packet) ~= "table" or typeof(packet.Data) ~= "buffer" then
		Stats.CompressionRejected += 1
		Stats.CompressionErrors += 1
		if not ok then Internal.debugWarn("Bit-call compression rejected:", packet) end
		return nil, true
	end

	local data = packet.Data
	Internal.observeCompressionStrategy(route, data, usedCachedStrategy)
	local dataBytes = buffer.len(data)
	local headerBits = 3
		+ Internal.packetAdaptiveUIntBitLength(item.id)
		+ Internal.packetAdaptiveUIntBitLength(item.request)
	local totalBits = headerBits + dataBytes * 8
	local totalBytes = math.ceil(totalBits / 8)
	local nativePacketBytes = 2
		+ Internal.varUIntByteLength(item.id)
		+ Internal.varUIntByteLength(item.request)
		+ rawPayloadBytes
	local netSaved = nativePacketBytes - totalBytes

	if netSaved < Config.CompressionMinSavingsBytes then
		Stats.CompressionRejected += 1
		Stats.CompressionNoGain += 1
		return nil, true
	end

	local out = buffer.create(totalBytes)
	local bitPosition = 0
	bitPosition = Internal.packetWriteBits(out, bitPosition, Internal.BIT_CALL_MARKER, 3)
	bitPosition = Internal.packetWriteAdaptiveUInt(out, bitPosition, item.id)
	bitPosition = Internal.packetWriteAdaptiveUInt(out, bitPosition, item.request)
	bitPosition = Internal.packetAppendBufferBits(out, bitPosition, data)

	local paddingBits = totalBytes * 8 - bitPosition
	Stats.CompressionUsed += 1
	Stats.CompressionInputBytes += rawPayloadBytes
	Stats.CompressionOutputBytes += dataBytes
	Internal.recordCompressionPacketBits(packet, rawPayloadBytes, dataBytes)
	local payloadSaved = rawPayloadBytes - dataBytes
	if payloadSaved > 0 then Stats.CompressionSavedBytes += payloadSaved end
	Stats.CompressionEstimatedNetBytesSaved += netSaved
	Stats.BitPacketCallsSent += 1
	Stats.BitPacketHeaderBits += headerBits
	local oldHeaderBits = (2
		+ Internal.varUIntByteLength(item.id)
		+ Internal.varUIntByteLength(item.request)) * 8
	Stats.BitPacketHeaderBitsSaved += math.max(0, oldHeaderBits - headerBits)
	Stats.BitPacketPaddingBits += paddingBits
	Stats.SingleMessagePackets += 1
	Stats.CompressionDirectTableUsed += 1
	Stats.CompressionTailLengthElisions += 1
	if Compression.IsCompactTable(data) then
		Stats.CompressionCompactTableUsed += 1
		local tableMode = Compression.TableMode(data)
		if string.find(tableMode, "Mapped", 1, true) ~= nil then Stats.CompressionMappedTableUsed += 1 end
	else
		Stats.CompressionDynamicTableUsed += 1
	end

	return out, true
end

function Internal.tryEncodeCompactSingle(item)
	if item.schema ~= nil
		or item.n ~= 1
		or typeof(item.args[1]) ~= "table"
		or (item.kind ~= KIND_EVENT and item.kind ~= KIND_STATE)
		or item.id < 0
		or item.id > 63
		or not Internal.routeCompressionEnabled(item)
	then
		return nil, false
	end

	Stats.CompressionAttempts += 1

	local rawPayloadBytes = Internal.nativeSingleValueByteLength(item.args[1])
	if not Internal.hybridCompressionAllowed(item, rawPayloadBytes * 8) then return nil, true end
	local route = Internal.routeForItem(item)
	local compressionOptions, usedCachedStrategy = Internal.compressionOptionsForRoute(route)
	local ok, packet = pcall(Compression.Compress, item.args[1], compressionOptions)
	if not ok or type(packet) ~= "table" or typeof(packet.Data) ~= "buffer" then
		Stats.CompressionRejected += 1
		Stats.CompressionErrors += 1
		if not ok then
			Internal.debugWarn("Compact single compression rejected:", packet)
		end
		return nil, true
	end

	local data = packet.Data
	Internal.observeCompressionStrategy(route, data, usedCachedStrategy)
	local dataBytes = buffer.len(data)
	local nativePacketBytes = 1 + 1 + Internal.varUIntByteLength(item.id) + rawPayloadBytes
	local compactPacketBytes = 2 + dataBytes
	local netSaved = nativePacketBytes - compactPacketBytes

	if netSaved < Config.CompressionMinSavingsBytes then
		Stats.CompressionRejected += 1
		Stats.CompressionNoGain += 1
		return nil, true
	end

	local compactOut = buffer.create(compactPacketBytes)
	buffer.writeu8(compactOut, 0, Internal.LEGACY_PROTOCOL_COMPACT_TABLE)
	buffer.writeu8(compactOut, 1, item.id * 4 + item.kind)
	if dataBytes > 0 then
		buffer.copy(compactOut, 2, data, 0, dataBytes)
	end

	Stats.CompressionUsed += 1
	Stats.CompressionInputBytes += rawPayloadBytes
	Stats.CompressionOutputBytes += dataBytes
	Internal.recordCompressionPacketBits(packet, rawPayloadBytes, dataBytes)
	local payloadSaved = rawPayloadBytes - dataBytes
	if payloadSaved > 0 then
		Stats.CompressionSavedBytes += payloadSaved
	end
	Stats.CompressionEstimatedNetBytesSaved += netSaved
	Stats.CompressionCompactSingleSent += 1
	Stats.CompressionDirectTableUsed += 1
	Stats.CompressionTailLengthElisions += 1
	Stats.SingleMessagePackets += 1
	Stats.SingleMessageHeaderBytesSaved += 1
	Stats.CompressionFramingBytesSaved += math.max(0, netSaved - math.max(0, payloadSaved))
	if Compression.IsCompactTable(data) then
		Stats.CompressionCompactTableUsed += 1
		local tableMode = Compression.TableMode(data)
		if string.find(tableMode, "Mapped", 1, true) ~= nil then Stats.CompressionMappedTableUsed += 1 end
	else
		Stats.CompressionDynamicTableUsed += 1
	end

	return compactOut, true
end

local function writeMessage(writer, item, isTail, skipCompression)
	local argc = item.n
	local routeBearing = item.kind == KIND_EVENT or item.kind == KIND_CALL or item.kind == KIND_STATE
	local reuseRoute = false
	local compressedData = nil
	local compressedControl = nil
	local compressedDirect = false
	local compressedOmitLength = false

	if item.schema and routeBearing then
		if item.kind == KIND_EVENT then
			reuseRoute = writer.lastEventRoute == item.id
			writer.lastEventRoute = item.id
		elseif item.kind == KIND_CALL then
			reuseRoute = writer.lastCallRoute == item.id
			writer.lastCallRoute = item.id
		else
			reuseRoute = writer.lastStateRoute == item.id
			writer.lastStateRoute = item.id
		end
	end

	if item.schema then
		writer:u8(item.kind + 4 + (if reuseRoute then 8 else 0))
		Stats.SchemaMessages += 1
	else
		if not skipCompression then
			compressedData, compressedControl, compressedDirect, compressedOmitLength = Internal.tryCompressDynamicArgs(writer, item, isTail)
		end
		if compressedData then
			if compressedDirect then
				writer:u8(30 * 8 + item.kind)
			else
				writer:u8(31 * 8 + item.kind)
				writer:varUInt(compressedControl)
			end
		else
			local shortCount = if argc < 30 then argc else 31
			writer:u8(shortCount * 8 + item.kind)
			if argc >= 30 then
				writer:varUInt(argc * 4)
			end
		end
		Stats.DynamicMessages += 1
	end

	if routeBearing and not reuseRoute then
		writer:varUInt(item.id)
	end
	if item.kind == KIND_CALL or item.kind == KIND_RETURN then
		writer:varUInt(item.request)
	end

	if item.schema then
		writeSchemaArgs(writer, item.schema, item.args)
	elseif compressedData then
		if not compressedOmitLength then
			writer:varUInt(buffer.len(compressedData))
		end
		writer:rawBuffer(compressedData)
	else
		for i = 1, argc do
			writeValue(writer, item.args[i], 0, nil)
		end
	end
end

local function writePackedSchemaSingle(writer, item)
	local reuseRoute = writer.lastEventRoute == item.id
	writer.lastEventRoute = item.id
	writer:u8(KIND_EVENT + 4 + (if reuseRoute then 8 else 0))
	if not reuseRoute then
		writer:varUInt(item.id)
	end
	writer:ensure(item.schema.fixedBytes)
	writer.position = Internal.writeFixedSchemaFlatPayload(writer.buffer, writer.position, item.schema, item.packedValues, 0)
	Stats.SchemaMessages += 1
	Stats.FixedSchemaFastWrites += 1
end

local function writePackedSchemaRun(writer, item)
	local reuseRoute = writer.lastEventRoute == item.id
	writer.lastEventRoute = item.id
	writer:u8(KIND_EVENT + 4 + (if reuseRoute then 8 else 0) + 16)
	if not reuseRoute then
		writer:varUInt(item.id)
	end
	local runCount = item.runCount
	writer:varUInt(runCount)
	local schema = item.schema
	local values = item.packedValues
	if schema.count == 1 then
		local kind = schema.fields[1].Kind
		if kind == SCHEMA_BOOL then
			local bit = 0
			local packed = 0
			for index = 1, runCount do
				if values[index] then packed += bit32.lshift(1, bit) end
				bit += 1
				if bit == 8 then
					writer:u8(packed)
					bit = 0
					packed = 0
				end
			end
			if bit > 0 then writer:u8(packed) end
		elseif kind == SCHEMA_U8 then
			writer:ensure(runCount)
			local data = writer.buffer
			local pos = writer.position
			for index = 1, runCount do
				buffer.writeu8(data, pos, values[index])
				pos += 1
			end
			writer.position = pos
		elseif kind == SCHEMA_U16 then
			writer:ensure(runCount * 2)
			local data = writer.buffer
			local pos = writer.position
			for index = 1, runCount do
				buffer.writeu16(data, pos, values[index])
				pos += 2
			end
			writer.position = pos
		else
			writer:ensure(schema.fixedBytes * runCount)
			local pos = writer.position
			for index = 0, runCount - 1 do
				pos = Internal.writeFixedSchemaFlatPayload(writer.buffer, pos, schema, values, index)
			end
			writer.position = pos
		end
	else
		writer:ensure(schema.fixedBytes * runCount)
		local pos = writer.position
		local fieldCount = item.fieldCount
		for index = 0, runCount - 1 do
			pos = Internal.writeFixedSchemaFlatPayload(writer.buffer, pos, schema, values, index * fieldCount)
		end
		writer.position = pos
	end
	Stats.SchemaMessages += runCount
	Stats.FixedSchemaFastWrites += runCount
end

local function writeSchemaEventRun(writer, items, startIndex, runCount)
	local first = items[startIndex]
	local reuseRoute = writer.lastEventRoute == first.id
	writer.lastEventRoute = first.id
	writer:u8(KIND_EVENT + 4 + (if reuseRoute then 8 else 0) + 16)
	if not reuseRoute then
		writer:varUInt(first.id)
	end
	writer:varUInt(runCount)
	local schema = first.schema
	if schema.count == 0 then
		Stats.SchemaMessages += runCount
		return
	end
	if schema.count == 1 then
		local field = schema.fields[1]
		local kind = field.Kind
		if kind == SCHEMA_BOOL then
			local bit = 0
			local packed = 0
			for offset = 0, runCount - 1 do
				if items[startIndex + offset].args[1] then
					packed += bit32.lshift(1, bit)
				end
				bit += 1
				if bit == 8 then
					writer:u8(packed)
					bit = 0
					packed = 0
				end
			end
			if bit > 0 then
				writer:u8(packed)
			end
		elseif kind == SCHEMA_U8 then
			writer:ensure(runCount)
			local data = writer.buffer
			local pos = writer.position
			for offset = 0, runCount - 1 do
				buffer.writeu8(data, pos, items[startIndex + offset].args[1])
				pos += 1
			end
			writer.position = pos
			Stats.FixedSchemaFastWrites += runCount
		elseif kind == SCHEMA_U16 then
			writer:ensure(runCount * 2)
			local data = writer.buffer
			local pos = writer.position
			for offset = 0, runCount - 1 do
				buffer.writeu16(data, pos, items[startIndex + offset].args[1])
				pos += 2
			end
			writer.position = pos
			Stats.FixedSchemaFastWrites += runCount
		elseif kind == SCHEMA_VARUINT then
			for offset = 0, runCount - 1 do
				writer:varUInt(items[startIndex + offset].args[1])
			end
		elseif kind == SCHEMA_VARINT then
			for offset = 0, runCount - 1 do
				writer:varInt(items[startIndex + offset].args[1])
			end
		elseif kind == SCHEMA_VECTOR3Q then
			local precision = field.Precision
			for offset = 0, runCount - 1 do
				local value = items[startIndex + offset].args[1]
				writer:varInt(roundScaled(value.X, precision))
				writer:varInt(roundScaled(value.Y, precision))
				writer:varInt(roundScaled(value.Z, precision))
			end
		elseif schema.fixedBytes ~= nil then
			writer:ensure(schema.fixedBytes * runCount)
			for offset = 0, runCount - 1 do
				writer.position = Internal.writeFixedSchemaPayload(writer.buffer, writer.position, schema, items[startIndex + offset].args)
			end
			Stats.FixedSchemaFastWrites += runCount
		else
			for offset = 0, runCount - 1 do
				writeSchemaValue(writer, field, items[startIndex + offset].args[1])
			end
		end
	elseif schema.fixedBytes ~= nil then
		writer:ensure(schema.fixedBytes * runCount)
		for offset = 0, runCount - 1 do
			writer.position = Internal.writeFixedSchemaPayload(writer.buffer, writer.position, schema, items[startIndex + offset].args)
		end
		Stats.FixedSchemaFastWrites += runCount
	else
		for offset = 0, runCount - 1 do
			writeSchemaArgs(writer, schema, items[startIndex + offset].args)
		end
	end
	Stats.SchemaMessages += runCount
end

function Internal.tryEncodeFastSchemaSingle(item)
	if not Config.FastSchemaEnabled
		or item.schema == nil
		or item.schema.fixedBytes == nil
		or item.schema.fixedBytes > Config.FastSchemaMaxBytes
		or (item.kind ~= KIND_EVENT and item.kind ~= KIND_STATE)
	then
		return nil
	end

	local routeTag = item.id * 4 + item.kind
	local fastHeaderBytes = 1 + Internal.varUIntByteLength(routeTag)
	local regularHeaderBytes = 2 + Internal.varUIntByteLength(item.id)
	if not Config.FastSchemaAllowHeaderExpansion and fastHeaderBytes > regularHeaderBytes then
		return nil
	end

	local totalBytes = fastHeaderBytes + item.schema.fixedBytes
	if totalBytes > Config.MaxOutgoingBatchBytes then
		return nil
	end
	local out = buffer.create(totalBytes)
	buffer.writeu8(out, 0, Internal.LEGACY_PROTOCOL_FAST_SCHEMA)
	local pos = 1
	local value = routeTag
	repeat
		local byte = value % 128
		value = math.floor(value / 128)
		if value > 0 then byte += 128 end
		buffer.writeu8(out, pos, byte)
		pos += 1
	until value == 0
	pos = Internal.writeFixedSchemaPayload(out, pos, item.schema, item.args)
	if pos ~= totalBytes then
		error("NetStream fast schema encoder size mismatch", 0)
	end

	Stats.SchemaMessages += 1
	Stats.FastSchemaSent += 1
	Stats.FastSchemaBytes += totalBytes
	Stats.FastSchemaHeaderBytesSaved += math.max(0, regularHeaderBytes - fastHeaderBytes)
	Stats.FixedSchemaFastWrites += 1
	Stats.SingleMessagePackets += 1
	Stats.SingleMessageHeaderBytesSaved += math.max(0, regularHeaderBytes - fastHeaderBytes)
	return out
end

function Internal.tryEncodeFastPackedSingle(item)
	if not Config.FastSchemaEnabled or not item.packedRun or item.runCount ~= 1
		or item.schema == nil or item.schema.fixedBytes == nil or item.schema.fixedBytes > Config.FastSchemaMaxBytes then
		return nil
	end
	local routeTag = item.id * 4 + KIND_EVENT
	local fastHeaderBytes = 1 + Internal.varUIntByteLength(routeTag)
	local regularHeaderBytes = 2 + Internal.varUIntByteLength(item.id)
	if not Config.FastSchemaAllowHeaderExpansion and fastHeaderBytes > regularHeaderBytes then
		return nil
	end
	local totalBytes = fastHeaderBytes + item.schema.fixedBytes
	if totalBytes > Config.MaxOutgoingBatchBytes then return nil end
	local out = buffer.create(totalBytes)
	buffer.writeu8(out, 0, Internal.LEGACY_PROTOCOL_FAST_SCHEMA)
	local pos = 1
	local value = routeTag
	repeat
		local byte = value % 128
		value = math.floor(value / 128)
		if value > 0 then byte += 128 end
		buffer.writeu8(out, pos, byte)
		pos += 1
	until value == 0
	pos = Internal.writeFixedSchemaFlatPayload(out, pos, item.schema, item.packedValues, 0)
	if pos ~= totalBytes then error("NetStream packed fast schema encoder size mismatch", 0) end
	Stats.SchemaMessages += 1
	Stats.FastSchemaSent += 1
	Stats.FastSchemaBytes += totalBytes
	Stats.FastSchemaHeaderBytesSaved += math.max(0, regularHeaderBytes - fastHeaderBytes)
	Stats.FixedSchemaFastWrites += 1
	Stats.SingleMessagePackets += 1
	Stats.SingleMessageHeaderBytesSaved += math.max(0, regularHeaderBytes - fastHeaderBytes)
	return out
end

local function acquireWriter()
	local writer = writerPool[#writerPool]
	if writer then
		writerPool[#writerPool] = nil
		writer.maxBytes = Config.MaxOutgoingBatchBytes
		writer:reset()
		Stats.WriterPoolHits += 1
		return writer
	end
	return Writer.new(math.min(Config.InitialWriterBytes, Config.MaxOutgoingBatchBytes), Config.MaxOutgoingBatchBytes)
end

local function releaseWriter(writer)
	if writer.capacity <= Config.MaxPooledWriterBytes and #writerPool < Config.MaxWriterPoolSize then
		writerPool[#writerPool + 1] = writer
	end
end

local function batchLogicalCount(items)
	local total = 0
	for i = 1, #items do
		total += messageLogicalCount(items[i])
	end
	return total
end


-- v2.1 universal BitFrame transport.
-- No packet protocol byte and no batch-count field are emitted. The frame is:
--   1 bit message-present, message..., repeated, then a single 0 end bit.
-- Message kind is 2 bits; route/request ids use adaptive bit UInts. Route lookup
-- tells the receiver whether a schema is present, so schema packets need no codec id.
function Internal.bitFrameWriteDynamic(writer, item)
	local route = Internal.routeForItem(item)
	if item.kind == KIND_RETURN then
		local ok = item.args[1] == true
		writer:bits(ok and 1 or 0, 1)
		local resultCount = math.max(0, item.n - 1)
		writer:adaptiveUInt(resultCount)
		for i = 2, item.n do writeValue(writer, item.args[i], 0, nil) end
		Stats.BitFrameNativeValues += resultCount
		return
	end

	local forceCompression = route and route.Compression == true
	if Config.BitFrameTinyScalarEnabled and not forceCompression and item.n == 1 then
		local scalarBits = Internal.hybridScalarBitLength(item.args[1])
		if scalarBits ~= nil and scalarBits <= Config.HybridSmallPacketMaxBits then
			writer:bits(0, 2) -- tiny scalar
			writer:ensureBits(scalarBits)
			Internal.hybridWriteScalar(writer.buffer, writer.bitPosition, item.args[1])
			-- hybridWriteScalar operates on a raw buffer position; advance explicitly.
			writer.bitPosition += scalarBits
			Stats.BitFrameTinyValues += 1
			return
		end
	end

	local compressedData, _, compressedDirect = Internal.tryCompressDynamicArgs(nil, item, false)
	if compressedData then
		writer:bits(compressedDirect and 2 or 3, 2)
		writer:adaptiveUInt(buffer.len(compressedData))
		writer:rawBuffer(compressedData)
		Stats.BitFrameCompressedValues += 1
		return
	end

	writer:bits(1, 2) -- native dynamic
	writer:adaptiveUInt(item.n)
	for i = 1, item.n do writeValue(writer, item.args[i], 0, nil) end
	Stats.BitFrameNativeValues += item.n
end

function Internal.bitFrameWriteOne(writer, item)
	writer:bits(1, 1) -- another message follows
	writer:bits(item.kind, 2)
	if item.kind ~= KIND_RETURN then writer:adaptiveUInt(item.id) end
	if item.kind == KIND_CALL or item.kind == KIND_RETURN then writer:adaptiveUInt(item.request) end

	if item.schema then
		if item.kind == KIND_EVENT then
			local isRun = item.packedRun == true and item.runCount and item.runCount > 1
			writer:bits(isRun and 1 or 0, 1)
			if isRun then
				writer:adaptiveUInt(item.runCount)
				for index = 0, item.runCount - 1 do
					Internal.bitFrameWriteSchemaArgs(writer, item.schema, item.packedValues, index * item.fieldCount)
				end
				Stats.SchemaMessages += item.runCount
			else
				if item.packedRun then
					Internal.bitFrameWriteSchemaArgs(writer, item.schema, item.packedValues, 0)
				else
					Internal.bitFrameWriteSchemaArgs(writer, item.schema, item.args, 0)
				end
				Stats.SchemaMessages += 1
			end
		else
			Internal.bitFrameWriteSchemaArgs(writer, item.schema, item.args, 0)
			Stats.SchemaMessages += 1
		end
	else
		Internal.bitFrameWriteDynamic(writer, item)
		Stats.DynamicMessages += 1
	end
	Stats.BitFrameMessagesEncoded += messageLogicalCount(item)
end

function Internal.encodeBitFrame(items)
	local writer = Internal.BitFrameWriter.new(math.min(Config.InitialWriterBytes, Config.BitFrameMaxBytes))
	for i = 1, #items do Internal.bitFrameWriteOne(writer, items[i]) end
	writer:bits(0, 1) -- end-of-frame marker; remaining physical tail bits stay zero
	local usefulBits = writer.bitPosition
	local out = writer:finish()
	local physicalBits = buffer.len(out) * 8
	Internal._lastEncodedUsefulBits = usefulBits
	Internal._lastEncodedCodec = "BitFrame"
	Stats.BitFramePacketsEncoded += 1
	-- Every old v2 packet paid one protocol byte. Multi-message packets also paid
	-- at least one byte for logicalCount; BitFrame needs neither.
	Internal._lastEncodedProtocolBytesElided = 1
	local logicalCount = batchLogicalCount(items)
	Internal._lastEncodedBatchCountBytesElided = if logicalCount > 1 then Internal.varUIntByteLength(logicalCount) else 0
	return out
end

local function encodeBatch(items)
	if Config.BitFrameEnabled then
		return Internal.encodeBitFrame(items)
	end
	local logicalCount = batchLogicalCount(items)
	local compactAttempted = false
	if logicalCount == 1 and #items == 1 then
		if items[1].packedRun then
			local fastPacked = Internal.tryEncodeFastPackedSingle(items[1])
			if fastPacked then return fastPacked end
		else
			local fastSchema = Internal.tryEncodeFastSchemaSingle(items[1])
			if fastSchema then
				return fastSchema
			end
			local hybridSmall = Internal.tryEncodeHybridSmallSingle(items[1])
			if hybridSmall then return hybridSmall end
			local bitCall, bitAttempted = Internal.tryEncodeBitCallSingle(items[1])
			if bitCall then
				Stats.DynamicMessages += 1
				return bitCall
			end
			local compact, attempted = Internal.tryEncodeCompactSingle(items[1])
			compactAttempted = bitAttempted or attempted
			if compact then
				Stats.DynamicMessages += 1
				return compact
			end
		end
	end

	local writer = acquireWriter()
	local ok, result = pcall(function()
		if logicalCount == 1 then
			writer:u8(Internal.LEGACY_PROTOCOL_SINGLE)
			Stats.SingleMessagePackets += 1
			Stats.SingleMessageHeaderBytesSaved += 1
		else
			writer:u8(Internal.LEGACY_PROTOCOL)
			writer:varUInt(logicalCount)
		end
		local index = 1
		while index <= #items do
			local item = items[index]
			if item.packedRun then
				if item.runCount >= 2 then
					writePackedSchemaRun(writer, item)
				else
					writePackedSchemaSingle(writer, item)
				end
				index += 1
			elseif item.kind == KIND_EVENT and item.schema then
				local runCount = 1
				while index + runCount <= #items do
					local nextItem = items[index + runCount]
					if nextItem.packedRun or nextItem.kind ~= KIND_EVENT or nextItem.id ~= item.id or nextItem.schema ~= item.schema then
						break
					end
					runCount += 1
				end
				if runCount >= 2 then
					writeSchemaEventRun(writer, items, index, runCount)
					index += runCount
				else
					writeMessage(writer, item, index == #items, compactAttempted and logicalCount == 1)
					index += 1
				end
			else
				writeMessage(writer, item, index == #items, compactAttempted and logicalCount == 1)
				index += 1
			end
		end
		return writer:finish()
	end)
	releaseWriter(writer)
	if not ok then
		error(result, 0)
	end
	return result
end

function Internal.getBandwidthState(target)
	local key
	if IS_SERVER then
		key = target
	else
		key = "client"
	end
	local state = Internal.bandwidthStates[key]
	if not state then
		state = {
			nextByteAt = 0,
			nextPacketAt = 0,
			lastDelay = 0,
		}
		Internal.bandwidthStates[key] = state
	end
	return state
end

function Internal.bandwidthReady(target)
	if not Config.BandwidthGovernorEnabled then
		return true, 0
	end
	local now = os.clock()
	local waitUntil = 0
	if IS_SERVER and target == ALL then
		for _, player in ipairs(Players:GetPlayers()) do
			local state = Internal.getBandwidthState(player)
			waitUntil = math.max(waitUntil, state.nextByteAt, state.nextPacketAt)
		end
	else
		local state = Internal.getBandwidthState(target)
		waitUntil = math.max(state.nextByteAt, state.nextPacketAt)
	end
	if now + 1e-6 < waitUntil then
		return false, waitUntil - now
	end
	return true, 0
end

function Internal.commitBandwidth(target, bytes)
	if not Config.BandwidthGovernorEnabled then
		return
	end
	local now = os.clock()
	local chargedBytes = bytes + Config.TransportEstimatedPacketOverheadBytes
	local byteDelay = chargedBytes / Config.BandwidthLimitBytesPerSecond
	local packetDelay = 1 / Config.BandwidthMaxPacketsPerSecond
	local function commitState(state)
		state.nextByteAt = math.max(now, state.nextByteAt) + byteDelay
		state.nextPacketAt = math.max(now, state.nextPacketAt) + packetDelay
		state.lastDelay = math.max(byteDelay, packetDelay)
	end
	if IS_SERVER and target == ALL then
		for _, player in ipairs(Players:GetPlayers()) do
			commitState(Internal.getBandwidthState(player))
		end
	else
		commitState(Internal.getBandwidthState(target))
	end
	Stats.BandwidthGovernedBatches += 1
	Stats.BandwidthGovernedBytes += bytes
	Stats.TransportEstimatedOverheadBytes += Config.TransportEstimatedPacketOverheadBytes
	Stats.TransportEstimatedBytes += chargedBytes
	Internal.trafficWindowEstimatedTransportBytes += chargedBytes
end

function Internal.restoreDeferredItems(queue, latest, items, unreliable)
	local normal = table.create(#items)
	for i = 1, #items do
		local item = items[i]
		if item then
			if item.latestKey ~= nil then
				local old = latest[item.latestKey]
				if old and old ~= item then
					releaseMessage(old)
					Stats.CoalescedLatest += 1
				end
				latest[item.latestKey] = item
			elseif unreliable and Config.BandwidthDropUnreliableOnPressure then
				local droppedCount = messageLogicalCount(item)
				releaseMessage(item)
				Stats.BandwidthDroppedUnreliableMessages += droppedCount
			else
				normal[#normal + 1] = item
			end
		end
	end
	for i = #normal, 1, -1 do
		queue.head -= 1
		queue.items[queue.head] = normal[i]
		queue.logicalCount += messageLogicalCount(normal[i])
	end
end

local function fireRemote(remote, target, data)
	if IS_SERVER then
		if target == ALL then
			remote:FireAllClients(data)
		elseif target and target.Parent == Players then
			remote:FireClient(target, data)
		end
	else
		remote:FireServer(data)
	end
end


function Internal.clearLastSendStats()
	lastPacketBytes = 0
	local stats = Internal.LastSendStats
	stats.Bytes = 0
	stats.PhysicalBits = 0
	stats.UsefulBits = 0
	stats.PaddingBits = 0
	stats.Codec = "None"
end

function Internal.commitLastSendStats(bytes)
	local physicalBits = bytes * 8
	local usefulBits = Internal._lastEncodedUsefulBits
	if type(usefulBits) ~= "number" or usefulBits <= 0 or usefulBits > physicalBits then usefulBits = physicalBits end
	local stats = Internal.LastSendStats
	stats.Bytes = bytes
	stats.PhysicalBits = physicalBits
	stats.UsefulBits = usefulBits
	stats.PaddingBits = math.max(0, physicalBits - usefulBits)
	stats.Codec = Internal._lastEncodedCodec or "Unknown"
	lastPacketBytes = bytes
	if stats.Codec == "BitFrame" then
		Stats.BitFramePacketsSent += 1
		Stats.BitFrameUsefulBits += usefulBits
		Stats.BitFramePhysicalBits += physicalBits
		Stats.BitFramePaddingBits += stats.PaddingBits
		Stats.BitFrameProtocolBytesElided += Internal._lastEncodedProtocolBytesElided or 0
		Stats.BitFrameBatchCountBytesElided += Internal._lastEncodedBatchCountBytesElided or 0
	end
end

local function sendBatch(target, unreliable, data)
	Internal.clearLastSendStats()
	if IS_SERVER and target ~= ALL and (not target or target.Parent ~= Players) then
		return false, "invalid"
	end
	local bytes = buffer.len(data)
	local ready = Internal.bandwidthReady(target)
	if not ready then
		Stats.BandwidthDeferredBatches += 1
		Stats.BandwidthDeferredBytes += bytes
		Stats.BandwidthThrottleEvents += 1
		return false, "defer"
	end
	if Config.BandwidthGovernorEnabled and bytes > Config.BandwidthMaxPacketBytes then
		Stats.BandwidthOversizedPackets += 1
		if unreliable and Config.BandwidthDropUnreliableOnPressure then
			return false, "drop"
		end
	end
	local remote = reliableRemote
	if unreliable and unreliableRemote and bytes <= Config.UnreliableMaxBytes then
		remote = unreliableRemote
	elseif unreliable then
		Stats.FallbackReliable += 1
	end
	local ok, err = pcall(fireRemote, remote, target, data)
	if not ok and remote == unreliableRemote then
		Stats.FallbackReliable += 1
		ok, err = pcall(fireRemote, reliableRemote, target, data)
	end
	if not ok then
		warn(LOG_PREFIX, "send failed:", err)
		return false, "error"
	end
	Internal.commitBandwidth(target, bytes)
	Stats.SentBatches += 1
	Stats.SentBytes += bytes
	trafficWindowSentBatches += 1
	trafficWindowSentBytes += bytes
	Internal.commitLastSendStats(bytes)
	return true, "sent"
end

local function acquireBatch(limit)
	local items = batchPool[#batchPool]
	if items then
		batchPool[#batchPool] = nil
		table.clear(items)
		Stats.BatchPoolHits += 1
		return items
	end
	return table.create(limit)
end

local function releaseBatch(items)
	table.clear(items)
	if #batchPool < Config.MaxBatchPoolSize then
		batchPool[#batchPool + 1] = items
	end
end

local function collectBatch(queue, latest, limit)
	local items = acquireBatch(limit)
	local logical = 0
	while logical < limit and queueCount(queue) > 0 do
		local nextItem = queue.items[queue.head]
		local nextCount = messageLogicalCount(nextItem)
		if logical > 0 and logical + nextCount > limit then
			break
		end
		local item = queuePop(queue)
		if not item then
			break
		end
		items[#items + 1] = item
		logical += nextCount
	end
	if logical < limit and next(latest) ~= nil then
		for key, item in pairs(latest) do
			items[#items + 1] = item
			latest[key] = nil
			logical += 1
			if logical >= limit then
				break
			end
		end
	end
	return items
end

function Internal.encodeBandwidthSizedBatch(queue, latest, items, unreliable)
	local ok, data = pcall(encodeBatch, items)
	while ok and Config.BandwidthGovernorEnabled and #items > 1 and buffer.len(data) > Config.BandwidthMaxPacketBytes do
		local originalCount = #items
		local keepCount = math.max(1, math.floor(originalCount / 2))
		local deferred = acquireBatch(originalCount - keepCount)
		for i = keepCount + 1, originalCount do
			deferred[#deferred + 1] = items[i]
			items[i] = nil
		end
		Internal.restoreDeferredItems(queue, latest, deferred, unreliable)
		releaseBatch(deferred)
		Stats.BandwidthBatchSplits += 1
		ok, data = pcall(encodeBatch, items)
	end
	return ok, data
end

function Internal.sendIsolatedMessages(target, unreliable, items)
	for i = 1, #items do
		local item = items[i]
		local single = acquireBatch(1)
		single[1] = item
		local ok, data = pcall(encodeBatch, single)
		releaseBatch(single)
		if ok then
			local sent, reason = sendBatch(target, unreliable, data)
			if sent then
				local logical = messageLogicalCount(item)
				Stats.SentMessages += logical
				trafficWindowSentMessages += logical
				releaseMessage(item)
				items[i] = nil
			elseif reason == "defer" then
				return i
			else
				releaseMessage(item)
				items[i] = nil
			end
		else
			Stats.RejectedMessages += 1
			Internal.debugWarn("Dropped malformed message during batch recovery:", data)
			releaseMessage(item)
			items[i] = nil
		end
	end
	return nil
end

local function flushChannel(target, queue, latest, unreliable, deadline)
	for _ = 1, Config.MaxBatchesPerFlush do
		if os.clock() >= deadline then
			break
		end
		if queueCount(queue) <= 0 and next(latest) == nil then
			break
		end
		local ready = Internal.bandwidthReady(target)
		if not ready then
			Stats.BandwidthDeferredFlushes += 1
			break
		end
		local items = collectBatch(queue, latest, Config.MaxBatchMessages)
		if #items == 0 then
			releaseBatch(items)
			break
		end
		local ok, data = Internal.encodeBandwidthSizedBatch(queue, latest, items, unreliable)
		if not ok then
			Internal.debugWarn("Batch encode failed; retrying messages individually:", data)
			local deferredIndex = Internal.sendIsolatedMessages(target, unreliable, items)
			if deferredIndex then
				local pendingItems = acquireBatch(#items - deferredIndex + 1)
				for i = deferredIndex, #items do
					if items[i] then
						pendingItems[#pendingItems + 1] = items[i]
					end
				end
				Internal.restoreDeferredItems(queue, latest, pendingItems, unreliable)
				releaseBatch(pendingItems)
				releaseBatch(items)
				break
			end
			releaseBatch(items)
		else
			local sent, reason = sendBatch(target, unreliable, data)
			if sent then
				local logical = batchLogicalCount(items)
				Stats.SentMessages += logical
				trafficWindowSentMessages += logical
				for i = 1, #items do
					releaseMessage(items[i])
				end
			elseif reason == "defer" then
				Internal.restoreDeferredItems(queue, latest, items, unreliable)
				releaseBatch(items)
				break
			else
				for i = 1, #items do
					releaseMessage(items[i])
				end
			end
			releaseBatch(items)
		end
	end
end

local function flushBucket(target, bucket, deadline, force)
	local now = os.clock()
	local reliableCount = math.max(0, queueLogicalCount(bucket.reliable)) + Internal.mapCount(bucket.latestReliable)
	local reliablePending = reliableCount > 0
	if reliablePending then
		local targetReady = reliableCount >= Config.TransportTargetMessagesPerPacket
		if force or targetReady or now + 1e-6 >= bucket.reliableNotBefore then
			if targetReady and not force then
				Stats.TransportTargetFlushes += 1
			end
			flushChannel(target, bucket.reliable, bucket.latestReliable, false, deadline)
		else
			Stats.TransportBatchHolds += 1
		end
	end
	if queueCount(bucket.reliable) <= 0 and next(bucket.latestReliable) == nil then
		bucket.reliableNotBefore = 0
	end
	if os.clock() < deadline then
		now = os.clock()
		local unreliableCount = math.max(0, queueLogicalCount(bucket.unreliable)) + Internal.mapCount(bucket.latestUnreliable)
		local unreliablePending = unreliableCount > 0
		if unreliablePending then
			local targetReady = unreliableCount >= Config.TransportTargetMessagesPerPacket
			if force or targetReady or now + 1e-6 >= bucket.unreliableNotBefore then
				if targetReady and not force then
					Stats.TransportTargetFlushes += 1
				end
				flushChannel(target, bucket.unreliable, bucket.latestUnreliable, true, deadline)
			else
				Stats.TransportBatchHolds += 1
			end
		end
	end
	if queueCount(bucket.unreliable) <= 0 and next(bucket.latestUnreliable) == nil then
		bucket.unreliableNotBefore = 0
	end
end

function Internal.nextRequestId()
	for _ = 1, 2147483647 do
		requestId += 1
		if requestId > 2147483647 then
			requestId = 1
		end
		if pending[requestId] == nil then
			return requestId
		end
	end
	error("NetStream request id space exhausted", 0)
end

function Internal.failPendingForPlayer(player, reason)
	for id, entry in pairs(pending) do
		if entry.target == player then
			pending[id] = nil
			task.spawn(entry.thread, false, reason)
		end
	end
end

function Internal.checkTimeouts()
	local now = os.clock()
	for id, entry in pairs(pending) do
		if entry.deadline <= now then
			pending[id] = nil
			Stats.CallsTimedOut += 1
			task.spawn(entry.thread, false, "NetStream request timed out")
		end
	end
end

function Internal.getPeerState(player)
	local key = if IS_SERVER then player else "server"
	local state = peerStates[key]
	if not state then
		state = {}
		peerStates[key] = state
	end
	return state
end

function Internal.peekPeerState(player)
	local key = if IS_SERVER then player else "server"
	return peerStates[key]
end

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	local node = self._node
	local route = self._route
	if not node or not route then
		self._node = nil
		self._route = nil
		return false
	end
	if not node.connected then
		self._node = nil
		self._route = nil
		return false
	end
	node.connected = false
	if node.prev then
		node.prev.next = node.next
	else
		route._head = node.next
	end
	if node.next then
		node.next.prev = node.prev
	else
		route._tail = node.prev
	end
	route._listenerCount -= 1
	node.prev = nil
	node.next = nil
	node.callback = nil
	self._node = nil
	self._route = nil
	return true
end

function Connection:IsConnected()
	local node = self._node
	return node ~= nil and node.connected == true
end

local BaseRoute = {}
BaseRoute.__index = BaseRoute

function BaseRoute:Connect(callback)
	assert(not destroyed, "NetStream has been destroyed")
	assert(type(callback) == "function", "NetStream Connect expects a function")
	local node = {
		callback = callback,
		connected = true,
		once = false,
		prev = self._tail,
		next = nil,
	}
	if self._tail then
		self._tail.next = node
	else
		self._head = node
	end
	self._tail = node
	self._listenerCount += 1
	return setmetatable({ _node = node, _route = self }, Connection)
end

function BaseRoute:Once(callback)
	local connection = self:Connect(callback)
	connection._node.once = true
	return connection
end

function BaseRoute:DisconnectAll()
	local node = self._head
	while node do
		local nextNode = node.next
		node.connected = false
		node.callback = nil
		node.prev = nil
		node.next = nil
		node = nextNode
	end
	self._head = nil
	self._tail = nil
	self._listenerCount = 0
end

function BaseRoute:ListenerCount()
	return self._listenerCount
end

BaseRoute.GetListenerCount = BaseRoute.ListenerCount

function BaseRoute:HasListeners()
	return self._listenerCount > 0
end

function BaseRoute:IsCoalescing()
	return self.Coalesce == true
end

function BaseRoute:GetName()
	return self.Name
end

function BaseRoute:GetId()
	return self.Id
end

function BaseRoute:GetPriority()
	return self.Priority or "Normal"
end

function BaseRoute:GetOptimizationLevel()
	local schema = self._schema
	if not schema then return "Dynamic" end
	if schema.fixedBytes ~= nil then
		if Config.FastSchemaEnabled and schema.fixedBytes <= Config.FastSchemaMaxBytes then return "FastFixed" end
		return "Fixed"
	end
	return "Schema"
end

function BaseRoute:GetSchemaInfo()
	local schema = self._schema
	if not schema then return nil end
	return {
		Count = schema.count,
		Signature = schema.signature,
		FixedBytes = schema.fixedBytes,
		IsFixed = schema.isFixed,
		OptimizationLevel = self:GetOptimizationLevel(),
	}
end

function BaseRoute:Wait(timeout)
	local thread = coroutine.running()
	assert(thread, "NetStream Wait must be called from a yielding thread")
	local done = false
	local connection
	connection = self:Once(function(...)
		if done then
			return
		end
		done = true
		connection:Disconnect()
		task.spawn(thread, true, ...)
	end)
	if timeout and timeout > 0 then
		task.delay(timeout, function()
			if done then
				return
			end
			done = true
			connection:Disconnect()
			task.spawn(thread, false, "NetStream Wait timed out")
		end)
	end
	local result = table.pack(coroutine.yield())
	if not result[1] then
		return nil, result[2]
	end
	return table.unpack(result, 2, result.n)
end

function Internal.disconnectNode(route, node)
	if not node.connected then
		return
	end
	node.connected = false
	if node.prev then
		node.prev.next = node.next
	else
		route._head = node.next
	end
	if node.next then
		node.next.prev = node.prev
	else
		route._tail = node.prev
	end
	route._listenerCount -= 1
end

local function dispatchRoute(route, player, args)
	if not route then
		return
	end
	local node = route._head
	while node do
		local nextNode = node.next
		if node.connected then
			if node.once then
				Internal.disconnectNode(route, node)
			end
			local ok, err
			if IS_SERVER then
				ok, err = pcall(node.callback, player, table.unpack(args, 1, args.n))
			else
				ok, err = pcall(node.callback, table.unpack(args, 1, args.n))
			end
			if not ok then
				warn(LOG_PREFIX, "event callback error:", err)
			end
		end
		node = nextNode
	end
end

local function dispatchRouteScalar(route, player, value)
	if not route then
		return
	end
	local node = route._head
	while node do
		local nextNode = node.next
		if node.connected then
			if node.once then
				Internal.disconnectNode(route, node)
			end
			local ok, err
			if IS_SERVER then
				ok, err = pcall(node.callback, player, value)
			else
				ok, err = pcall(node.callback, value)
			end
			if not ok then
				warn(LOG_PREFIX, "event callback error:", err)
			end
		end
		node = nextNode
	end
end

local function runDispatch()
	local processed = 0
	local startedAt = os.clock()
	while dispatchHead <= dispatchCount and processed < Config.MaxDispatchPerCycle do
		local index = dispatchHead
		local route = dispatchRoutes[index]
		local player = dispatchPlayers[index]
		local args = dispatchArgs[index]
		local scalar = dispatchScalarFlags[index] == true
		local scalarValue = dispatchScalarValues[index]
		dispatchRoutes[index] = nil
		dispatchPlayers[index] = nil
		dispatchArgs[index] = nil
		dispatchScalarFlags[index] = nil
		dispatchScalarValues[index] = nil
		dispatchHead += 1
		processed += 1
		if scalar then
			dispatchRouteScalar(route, player, scalarValue)
		else
			dispatchRoute(route, player, args)
			releaseArgs(args)
		end
		if processed % 32 == 0 and os.clock() - startedAt >= Config.DispatchBudgetSeconds then
			break
		end
	end
	if dispatchHead > dispatchCount then
		dispatchCount = 0
		dispatchHead = 1
	end
end

local function enqueueDispatch(route, player, args)
	if not route or route._listenerCount == 0 then
		releaseArgs(args)
		return false
	end
	local backlog = if dispatchCount == 0 then 0 else math.max(0, dispatchCount - dispatchHead + 1)
	if backlog >= Config.MaxDispatchBacklog then
		Stats.DroppedDispatch += 1
		releaseArgs(args)
		return false
	end
	dispatchCount += 1
	dispatchRoutes[dispatchCount] = route
	dispatchPlayers[dispatchCount] = player
	dispatchArgs[dispatchCount] = args
	return true
end

local function enqueueDispatchScalar(route, player, value)
	if not route or route._listenerCount == 0 then
		return false
	end
	local backlog = if dispatchCount == 0 then 0 else math.max(0, dispatchCount - dispatchHead + 1)
	if backlog >= Config.MaxDispatchBacklog then
		Stats.DroppedDispatch += 1
		return false
	end
	dispatchCount += 1
	dispatchRoutes[dispatchCount] = route
	dispatchPlayers[dispatchCount] = player
	dispatchArgs[dispatchCount] = nil
	dispatchScalarFlags[dispatchCount] = true
	dispatchScalarValues[dispatchCount] = value
	Stats.ScalarDispatches += 1
	return true
end

local function enqueueReturn(player, id, ok, results)
	local args = acquireArgsCount(results.n + 1)
	args[1] = ok
	for i = 1, results.n do
		args[i + 1] = results[i]
	end
	args.n = results.n + 1
	enqueue(if IS_SERVER then player else nil, false, makeMessage(KIND_RETURN, 0, id, args, nil, "Critical"), nil)
end

function Internal.handleCall(player, routeId, id, args)
	local route = functionRoutes[routeId]
	local callback = route and route._callback or nil
	local usesFallback = false
	if not callback and fallbackCallHandler then
		callback = fallbackCallHandler
		usesFallback = true
	end
	if not callback then
		releaseArgs(args)
		enqueueReturn(player, id, false, table.pack("No NetStream callback registered for function route " .. tostring(routeId)))
		return
	end
	local packed
	local ok, err = xpcall(function()
		if usesFallback then
			if IS_SERVER then
				packed = table.pack(callback(player, routeId, table.unpack(args, 1, args.n)))
			else
				packed = table.pack(callback(routeId, table.unpack(args, 1, args.n)))
			end
		elseif IS_SERVER then
			packed = table.pack(callback(player, table.unpack(args, 1, args.n)))
		else
			packed = table.pack(callback(table.unpack(args, 1, args.n)))
		end
	end, debug.traceback)
	releaseArgs(args)
	if ok then
		local valid, validationError = pcall(function()
			for i = 1, packed.n do
				validateValue(packed[i], 0, nil)
			end
		end)
		if valid then
			enqueueReturn(player, id, true, packed)
		else
			enqueueReturn(player, id, false, table.pack("NetStream callback returned an unsupported value: " .. tostring(validationError)))
		end
	else
		enqueueReturn(player, id, false, table.pack(err))
	end
end

function Internal.processReturn(player, id, args)
	local entry = pending[id]
	if not entry then
		releaseArgs(args)
		return
	end
	if IS_SERVER and entry.target ~= player then
		Internal.debugWarn("Ignored RPC return from unexpected player")
		releaseArgs(args)
		return
	end
	pending[id] = nil
	local ok = args[1] == true
	if ok then
		task.spawn(entry.thread, true, table.unpack(args, 2, args.n))
	else
		task.spawn(entry.thread, false, tostring(args[2] or "Remote call failed"))
	end
	releaseArgs(args)
end

local function acquireReader(data)
	local reader = readerPool[#readerPool]
	if reader then
		readerPool[#readerPool] = nil
		reader:reset(data)
		Stats.ReaderPoolHits += 1
		return reader
	end
	return Reader.new(data)
end

local function releaseReader(reader)
	reader.buffer = nil
	reader.position = 0
	reader.length = 0
	if #reader.strings > Config.MaxPooledStrings then
		reader.strings = {}
	else
		table.clear(reader.strings)
	end
	if #readerPool < 32 then
		readerPool[#readerPool + 1] = reader
	end
end

local function getIncomingRate(player, now)
	local rate = incomingRates[player]
	if not rate then
		rate = { started = now, bytes = 0, messages = 0, calls = 0, batches = 0 }
		incomingRates[player] = rate
	elseif now - rate.started >= 1 then
		rate.started = now
		rate.bytes = 0
		rate.messages = 0
		rate.calls = 0
		rate.batches = 0
	end
	return rate
end

local function getGlobalIncomingRate(now)
	local rate = globalIncomingRate
	if not rate then
		rate = { started = now, bytes = 0, messages = 0, calls = 0, batches = 0 }
		globalIncomingRate = rate
	elseif now - rate.started >= 1 then
		rate.started = now
		rate.bytes = 0
		rate.messages = 0
		rate.calls = 0
		rate.batches = 0
	end
	return rate
end

local function chargeIncomingEnvelope(player, bytes)
	if not IS_SERVER or not player then
		return true
	end
	local now = os.clock()
	local rate = getIncomingRate(player, now)
	if rate.bytes + bytes > Config.MaxIncomingBytesPerSecond or rate.batches + 1 > Config.MaxIncomingBatchesPerSecond then
		return false
	end
	local globalRate = getGlobalIncomingRate(now)
	if globalRate.bytes + bytes > Config.MaxGlobalIncomingBytesPerSecond or globalRate.batches + 1 > Config.MaxGlobalIncomingBatchesPerSecond then
		Stats.GlobalRateLimitedBatches += 1
		return false
	end
	rate.bytes += bytes
	rate.batches += 1
	globalRate.bytes += bytes
	globalRate.batches += 1
	return true
end

local function canAcceptIncomingMessages(player, messages)
	if not IS_SERVER or not player then
		return true
	end
	local now = os.clock()
	local rate = getIncomingRate(player, now)
	if rate.messages + messages > Config.MaxIncomingMessagesPerSecond then
		return false
	end
	local globalRate = getGlobalIncomingRate(now)
	if globalRate.messages + messages > Config.MaxGlobalIncomingMessagesPerSecond then
		Stats.GlobalRateLimitedBatches += 1
		return false
	end
	return true
end

local function commitIncomingMessages(player, messages)
	if not IS_SERVER or not player then
		return
	end
	local now = os.clock()
	local rate = getIncomingRate(player, now)
	local globalRate = getGlobalIncomingRate(now)
	rate.messages += messages
	globalRate.messages += messages
end

function Internal.chargeIncomingCall(player)
	if not IS_SERVER or not player then
		return true
	end
	local now = os.clock()
	local rate = getIncomingRate(player, now)
	if rate.calls >= Config.MaxIncomingCallsPerSecond then
		Stats.RateLimitedCalls += 1
		return false
	end
	local globalRate = getGlobalIncomingRate(now)
	if globalRate.calls >= Config.MaxGlobalIncomingCallsPerSecond then
		Stats.GlobalRateLimitedCalls += 1
		return false
	end
	rate.calls += 1
	globalRate.calls += 1
	return true
end

local function consumeRouteAllowance(route, player, requested)
	if not IS_SERVER or not player or not route or not route._maxPerSecond then
		return requested
	end
	local now = os.clock()
	local rates = route._rateByPlayer
	local entry = rates[player]
	local burst = route._burst
	if not entry then
		entry = { tokens = burst, last = now }
		rates[player] = entry
	else
		local elapsed = now - entry.last
		if elapsed > 0 then
			entry.tokens = math.min(burst, entry.tokens + elapsed * route._maxPerSecond)
			entry.last = now
		end
	end
	local allowed = math.min(requested, math.floor(entry.tokens))
	if allowed > 0 then
		entry.tokens -= allowed
	end
	local rejected = requested - allowed
	if rejected > 0 then
		Stats.RouteRateLimited += rejected
	end
	return allowed
end

local function decodeSchemaEventRun(reader, schema, repeatCount, route, player, allowedCount)
	allowedCount = allowedCount or repeatCount
	if schema.count == 0 then
		for index = 1, repeatCount do
			if index <= allowedCount then
				enqueueDispatch(route, player, EMPTY_ARGS)
			end
		end
		return
	end
	if schema.count == 1 then
		local field = schema.fields[1]
		local kind = field.Kind
		if kind == SCHEMA_BOOL then
			local bit = 8
			local packed = 0
			for index = 1, repeatCount do
				if bit == 8 then
					packed = reader:u8()
					bit = 0
				end
				local value = bit32.band(packed, bit32.lshift(1, bit)) ~= 0
				bit += 1
				if index <= allowedCount then enqueueDispatchScalar(route, player, value) end
			end
			return
		elseif kind == SCHEMA_U8 then
			reader:need(repeatCount)
			local data = reader.buffer
			local pos = reader.position
			for index = 1, repeatCount do
				local value = buffer.readu8(data, pos)
				pos += 1
				if index <= allowedCount then enqueueDispatchScalar(route, player, value) end
			end
			reader.position = pos
			Stats.FixedSchemaFastReads += repeatCount
			return
		elseif kind == SCHEMA_U16 then
			reader:need(repeatCount * 2)
			local data = reader.buffer
			local pos = reader.position
			for index = 1, repeatCount do
				local value = buffer.readu16(data, pos)
				pos += 2
				if index <= allowedCount then enqueueDispatchScalar(route, player, value) end
			end
			reader.position = pos
			Stats.FixedSchemaFastReads += repeatCount
			return
		end
		for index = 1, repeatCount do
			local value = readSchemaValue(reader, field)
			if index <= allowedCount then enqueueDispatchScalar(route, player, value) end
		end
		return
	end
	for index = 1, repeatCount do
		local args = readSchemaArgs(reader, schema)
		if index <= allowedCount then
			enqueueDispatch(route, player, args)
		else
			releaseArgs(args)
		end
	end
end

function Internal.decodeFastSchemaSingle(player, data, reader)
	if not canAcceptIncomingMessages(player, 1) then
		Stats.RateLimitedBatches += 1
		Stats.ReceivedBatches += 1
		Stats.ReceivedBytes += buffer.len(data)
		return
	end

	local routeTag = reader:varUInt()
	local kind = routeTag % 4
	local routeId = math.floor(routeTag / 4)
	if kind ~= KIND_EVENT and kind ~= KIND_STATE then
		error("NetStream fast schema packet only supports Event or State", 0)
	end
	local route = if kind == KIND_EVENT then eventRoutes[routeId] else stateRoutes[routeId]
	if not route or not route._schema or route._schema.fixedBytes == nil then
		error("NetStream fast schema packet referenced an unknown or variable-width schema route", 0)
	end
	if reader.length - reader.position ~= route._schema.fixedBytes then
		error("NetStream fast schema payload size mismatch", 0)
	end

	local schema = route._schema
	if schema.count == 1 then
		local value = readSchemaValue(reader, schema.fields[1])
		Stats.FixedSchemaFastReads += 1
		if kind == KIND_EVENT then
			if consumeRouteAllowance(route, player, 1) > 0 then
				enqueueDispatchScalar(route, player, value)
			end
		else
			if consumeRouteAllowance(route, player, 1) > 0 then
				local state = Internal.getPeerState(player)
				state[routeId] = value
				enqueueDispatchScalar(route, player, value)
			end
		end
	else
		local args = readSchemaArgs(reader, schema)
		if kind == KIND_EVENT then
			if consumeRouteAllowance(route, player, 1) > 0 then
				enqueueDispatch(route, player, args)
			else
				releaseArgs(args)
			end
		else
			if consumeRouteAllowance(route, player, 1) > 0 then
				local state = Internal.getPeerState(player)
				state[routeId] = args[1]
				enqueueDispatch(route, player, args)
			else
				releaseArgs(args)
			end
		end
	end

	if reader.position ~= reader.length then
		error("NetStream fast schema packet contains trailing bytes", 0)
	end
	commitIncomingMessages(player, 1)
	local receivedBytes = buffer.len(data)
	Stats.FastSchemaReceived += 1
	Stats.ReceivedBatches += 1
	Stats.ReceivedBytes += receivedBytes
	Stats.ReceivedMessages += 1
	trafficWindowReceivedBatches += 1
	trafficWindowReceivedBytes += receivedBytes
	trafficWindowReceivedMessages += 1
end

function Internal.decodeCompactSingleTable(player, data, reader)
	if not canAcceptIncomingMessages(player, 1) then
		Stats.RateLimitedBatches += 1
		Stats.ReceivedBatches += 1
		Stats.ReceivedBytes += buffer.len(data)
		return
	end

	local packedRoute = reader:u8()
	local kind = packedRoute % 4
	local routeId = math.floor(packedRoute / 4)
	if kind ~= KIND_EVENT and kind ~= KIND_STATE then
		error("NetStream compact-table packet only supports Event or State", 0)
	end

	local route = if kind == KIND_EVENT then eventRoutes[routeId] else stateRoutes[routeId]
	if not route then
		error("NetStream compact-table packet referenced an unknown route", 0)
	end
	if route._schema then
		error("NetStream compact-table packet is not valid for a schema route", 0)
	end

	local compressedBytes = reader.length - reader.position
	if compressedBytes <= 0 or compressedBytes > Config.MaxIncomingPacketBytes then
		error("NetStream compact-table payload has an invalid size", 0)
	end
	local compressedData = reader:rawBuffer(compressedBytes)
	local decoded = Compression.Decode(compressedData, Internal.compressionOptions())
	if typeof(decoded) ~= "table" then
		error("NetStream compact-table payload did not decode to a table", 0)
	end
	validateValue(decoded, 0, nil)

	local args = acquireArgsCount(1)
	args[1] = decoded
	Stats.CompressionDecodeCount += 1
	Stats.CompressionCompactSingleReceived += 1

	if kind == KIND_EVENT then
		if consumeRouteAllowance(route, player, 1) > 0 then
			enqueueDispatch(route, player, args)
		else
			releaseArgs(args)
		end
	else
		if consumeRouteAllowance(route, player, 1) > 0 then
			local state = Internal.getPeerState(player)
			state[routeId] = decoded
			enqueueDispatch(route, player, args)
		else
			releaseArgs(args)
		end
	end

	if reader.position ~= reader.length then
		error("NetStream compact-table packet contains trailing bytes", 0)
	end
	commitIncomingMessages(player, 1)
	local receivedBytes = buffer.len(data)
	Stats.ReceivedBatches += 1
	Stats.ReceivedBytes += receivedBytes
	Stats.ReceivedMessages += 1
	trafficWindowReceivedBatches += 1
	trafficWindowReceivedBytes += receivedBytes
	trafficWindowReceivedMessages += 1
end


function Internal.validateHybridTail(data, bitPosition)
	local totalBits = buffer.len(data) * 8
	while bitPosition < totalBits do
		local bit; bit, bitPosition = Internal.packetReadBits(data, bitPosition, 1)
		if bit ~= 0 then error("NetStream hybrid packet has non-zero tail padding", 0) end
	end
end

function Internal.commitHybridReceive(player, data)
	commitIncomingMessages(player, 1)
	local bytes = buffer.len(data)
	Stats.HybridBufferUtilReceived += 1
	Stats.ReceivedBatches += 1; Stats.ReceivedBytes += bytes; Stats.ReceivedMessages += 1
	trafficWindowReceivedBatches += 1; trafficWindowReceivedBytes += bytes; trafficWindowReceivedMessages += 1
end

function Internal.decodeHybridSmallSingle(player, data, markerValue)
	if not canAcceptIncomingMessages(player, 1) then Stats.RateLimitedBatches += 1; Stats.ReceivedBatches += 1; Stats.ReceivedBytes += buffer.len(data); return end
	local bitPosition = 3
	if markerValue == Internal.HYBRID_EVENT_STATE_MARKER then
		local stateBit; stateBit, bitPosition = Internal.packetReadBits(data, bitPosition, 1)
		local routeId; routeId, bitPosition = Internal.packetReadAdaptiveUInt(data, bitPosition)
		local value; value, bitPosition = Internal.hybridReadScalar(data, bitPosition)
		Internal.validateHybridTail(data, bitPosition)
		local kind = if stateBit == 1 then KIND_STATE else KIND_EVENT
		local route = if kind == KIND_STATE then stateRoutes[routeId] else eventRoutes[routeId]
		if not route or route._schema then error("NetStream invalid hybrid route", 0) end
		if consumeRouteAllowance(route, player, 1) > 0 then
			if kind == KIND_STATE then local state = Internal.getPeerState(player); state[routeId] = value end
			enqueueDispatchScalar(route, player, value)
		end
	elseif markerValue == Internal.HYBRID_CALL_MARKER then
		local routeId; routeId, bitPosition = Internal.packetReadAdaptiveUInt(data, bitPosition)
		local requestId; requestId, bitPosition = Internal.packetReadAdaptiveUInt(data, bitPosition)
		local value; value, bitPosition = Internal.hybridReadScalar(data, bitPosition)
		Internal.validateHybridTail(data, bitPosition)
		local route = functionRoutes[routeId]
		if not route or route._schema then error("NetStream invalid hybrid call route", 0) end
		local args = acquireArgsCount(1); args[1] = value
		if Internal.chargeIncomingCall(player) then task.spawn(Internal.handleCall, player, routeId, requestId, args) else releaseArgs(args) end
	elseif markerValue == Internal.HYBRID_RETURN_MARKER then
		local requestId; requestId, bitPosition = Internal.packetReadAdaptiveUInt(data, bitPosition)
		local okBit; okBit, bitPosition = Internal.packetReadBits(data, bitPosition, 1)
		local value; value, bitPosition = Internal.hybridReadScalar(data, bitPosition)
		Internal.validateHybridTail(data, bitPosition)
		local args = acquireArgsCount(2); args[1] = okBit ~= 0; args[2] = value
		Internal.processReturn(player, requestId, args)
	else
		error("NetStream unknown hybrid marker", 0)
	end
	Internal.commitHybridReceive(player, data)
end

function Internal.decodeBitCallSingle(player, data)
	if not canAcceptIncomingMessages(player, 1) then
		Stats.RateLimitedBatches += 1
		Stats.ReceivedBatches += 1
		Stats.ReceivedBytes += buffer.len(data)
		return
	end

	local bitPosition = 0
	local marker
	marker, bitPosition = Internal.packetReadBits(data, bitPosition, 3)
	if marker ~= Internal.BIT_CALL_MARKER then
		error("NetStream invalid bit-call marker", 0)
	end

	local routeId
	routeId, bitPosition = Internal.packetReadAdaptiveUInt(data, bitPosition)
	local callId
	callId, bitPosition = Internal.packetReadAdaptiveUInt(data, bitPosition)

	local route = functionRoutes[routeId]
	if not route then error("NetStream bit-call packet referenced an unknown function route", 0) end
	if route._schema then error("NetStream bit-call packet is only valid for dynamic function routes", 0) end

	local totalBits = buffer.len(data) * 8
	local remainingBits = totalBits - bitPosition
	local compressedBytes = math.floor(remainingBits / 8)
	if compressedBytes <= 0 or compressedBytes > Config.MaxIncomingPacketBytes then
		error("NetStream bit-call payload has an invalid size", 0)
	end

	local compressedData
	compressedData, bitPosition = Internal.packetReadBufferBits(data, bitPosition, compressedBytes)

	-- Any tail bits exist only because the final Roblox buffer must be whole-byte sized.
	while bitPosition < totalBits do
		local tailBit
		tailBit, bitPosition = Internal.packetReadBits(data, bitPosition, 1)
		if tailBit ~= 0 then error("NetStream bit-call packet has non-zero tail padding", 0) end
	end

	local decoded = Compression.Decode(compressedData, Internal.compressionOptions())
	if typeof(decoded) ~= "table" then
		error("NetStream bit-call payload did not decode to a table", 0)
	end
	validateValue(decoded, 0, nil)

	local args = acquireArgsCount(1)
	args[1] = decoded
	Stats.CompressionDecodeCount += 1
	Stats.BitPacketCallsReceived += 1

	if Internal.chargeIncomingCall(player) then
		task.spawn(Internal.handleCall, player, routeId, callId, args)
	else
		releaseArgs(args)
	end

	commitIncomingMessages(player, 1)
	local receivedBytes = buffer.len(data)
	Stats.ReceivedBatches += 1
	Stats.ReceivedBytes += receivedBytes
	Stats.ReceivedMessages += 1
	trafficWindowReceivedBatches += 1
	trafficWindowReceivedBytes += receivedBytes
	trafficWindowReceivedMessages += 1
end


function Internal.bitFrameCommitReceive(player, data, logicalCount)
	commitIncomingMessages(player, logicalCount)
	local receivedBytes = buffer.len(data)
	Stats.BitFramePacketsReceived += 1
	Stats.BitFrameMessagesDecoded += logicalCount
	Stats.ReceivedBatches += 1
	Stats.ReceivedBytes += receivedBytes
	Stats.ReceivedMessages += logicalCount
	trafficWindowReceivedBatches += 1
	trafficWindowReceivedBytes += receivedBytes
	trafficWindowReceivedMessages += logicalCount
end

function Internal.bitFrameReadDynamic(reader, player, kind, routeId, requestId, route, allowMessage)
	if kind == KIND_RETURN then
		local ok = reader:bits(1) ~= 0
		local resultCount = reader:adaptiveUInt()
		if resultCount > Config.MaxTableEntries then error("NetStream BitFrame return result count too large", 0) end
		local args = acquireArgsCount(resultCount + 1)
		args[1] = ok
		for i = 1, resultCount do args[i + 1] = readValue(reader, 0) end
		args.n = resultCount + 1
		if allowMessage then Internal.processReturn(player, requestId, args) else releaseArgs(args) end
		return 1
	end

	local mode = reader:bits(2)
	local args
	if mode == 0 then
		local value
		value, reader.bitPosition = Internal.hybridReadScalar(reader.buffer, reader.bitPosition)
		args = acquireArgsCount(1); args[1] = value; args.n = 1
	elseif mode == 1 then
		local argc = reader:adaptiveUInt()
		if argc > Config.MaxTableEntries then error("NetStream BitFrame argument count too large", 0) end
		args = acquireArgsCount(argc)
		for i = 1, argc do args[i] = readValue(reader, 0) end
		args.n = argc
	else
		local compressedBytes = reader:adaptiveUInt()
		if compressedBytes <= 0 or compressedBytes > Config.MaxIncomingPacketBytes then error("NetStream BitFrame compressed payload size invalid", 0) end
		local compressedData = reader:rawBuffer(compressedBytes)
		local decoded = Compression.Decode(compressedData, Internal.compressionOptions())
		Stats.CompressionDecodeCount += 1
		if mode == 2 then
			if typeof(decoded) ~= "table" then error("NetStream BitFrame compressed single payload invalid", 0) end
			validateValue(decoded, 0, nil)
			args = acquireArgsCount(1); args[1] = decoded; args.n = 1
		elseif mode == 3 then
			if typeof(decoded) ~= "table" or type(decoded.n) ~= "number" or not isInteger(decoded.n) or decoded.n < 0 then error("NetStream BitFrame compressed args invalid", 0) end
			local argc = decoded.n
			if argc > Config.MaxTableEntries then error("NetStream BitFrame compressed argc too large", 0) end
			args = acquireArgsCount(argc)
			for i = 1, argc do
				validateValue(decoded[i], 0, nil)
				args[i] = decoded[i]
			end
			args.n = argc
		else
			error("NetStream BitFrame payload mode invalid", 0)
		end
	end

	if not allowMessage then
		releaseArgs(args)
	elseif kind == KIND_EVENT then
		if consumeRouteAllowance(route, player, 1) > 0 then enqueueDispatch(route, player, args) else releaseArgs(args) end
	elseif kind == KIND_CALL then
		if Internal.chargeIncomingCall(player) then task.spawn(Internal.handleCall, player, routeId, requestId, args) else releaseArgs(args) end
	elseif kind == KIND_STATE then
		local state = Internal.getPeerState(player)
		state[routeId] = args[1]
		if consumeRouteAllowance(route, player, 1) > 0 then enqueueDispatch(route, player, args) else releaseArgs(args) end
	else
		releaseArgs(args)
		error("NetStream BitFrame invalid message kind", 0)
	end
	return 1
end

function Internal.decodeBitFrame(player, data)
	local reader = Internal.BitFrameReader.new(data)
	local logicalCount = 0
	while true do
		local present = reader:bits(1)
		if present == 0 then break end
		local kind = reader:bits(2)
		local routeId = 0
		local requestId = 0
		local route = nil
		if kind ~= KIND_RETURN then
			routeId = reader:adaptiveUInt()
			if kind == KIND_EVENT then route = eventRoutes[routeId]
			elseif kind == KIND_CALL then route = functionRoutes[routeId]
			elseif kind == KIND_STATE then route = stateRoutes[routeId]
			else error("NetStream BitFrame invalid kind", 0) end
			if not route then error("NetStream BitFrame referenced unknown route " .. tostring(routeId), 0) end
		end
		if kind == KIND_CALL or kind == KIND_RETURN then requestId = reader:adaptiveUInt() end

		if route and route._schema then
			if kind == KIND_EVENT then
				local run = reader:bits(1) ~= 0
				local count = if run then reader:adaptiveUInt() else 1
				if count < 1 or count > Config.MaxIncomingMessages then error("NetStream BitFrame schema run count invalid", 0) end
				if not canAcceptIncomingMessages(player, logicalCount + count) then
					Stats.RateLimitedBatches += 1
					-- Decode to keep framing valid, but do not dispatch.
					for _ = 1, count do local dropped = Internal.bitFrameReadSchemaArgs(reader, route._schema); if dropped ~= EMPTY_ARGS and dropped ~= TRUE_ARGS and dropped ~= FALSE_ARGS then releaseArgs(dropped) end end
				else
					local allowance = consumeRouteAllowance(route, player, count)
					for index = 1, count do
						local args = Internal.bitFrameReadSchemaArgs(reader, route._schema)
						if index <= allowance then enqueueDispatch(route, player, args) elseif args ~= EMPTY_ARGS and args ~= TRUE_ARGS and args ~= FALSE_ARGS then releaseArgs(args) end
					end
				end
				logicalCount += count
			else
				local allowMessage = canAcceptIncomingMessages(player, logicalCount + 1)
				if not allowMessage then Stats.RateLimitedBatches += 1 end
				local args = Internal.bitFrameReadSchemaArgs(reader, route._schema)
				if not allowMessage then
					if args ~= EMPTY_ARGS and args ~= TRUE_ARGS and args ~= FALSE_ARGS then releaseArgs(args) end
				elseif kind == KIND_CALL then
					if Internal.chargeIncomingCall(player) then task.spawn(Internal.handleCall, player, routeId, requestId, args) elseif args ~= EMPTY_ARGS and args ~= TRUE_ARGS and args ~= FALSE_ARGS then releaseArgs(args) end
				elseif kind == KIND_STATE then
					local state = Internal.getPeerState(player); state[routeId] = args[1]
					if consumeRouteAllowance(route, player, 1) > 0 then enqueueDispatch(route, player, args) elseif args ~= EMPTY_ARGS and args ~= TRUE_ARGS and args ~= FALSE_ARGS then releaseArgs(args) end
				end
				logicalCount += 1
			end
		else
			local allowMessage = canAcceptIncomingMessages(player, logicalCount + 1)
			if not allowMessage then Stats.RateLimitedBatches += 1 end
			logicalCount += Internal.bitFrameReadDynamic(reader, player, kind, routeId, requestId, route, allowMessage)
		end
		if logicalCount > Config.MaxIncomingMessages then error("NetStream BitFrame exceeds MaxIncomingMessages", 0) end
	end

	-- All remaining bits are physical tail padding and must be zero.
	while reader.bitPosition < reader.bitLength do
		if reader:bits(1) ~= 0 then error("NetStream BitFrame has non-zero tail padding", 0) end
	end
	Internal.bitFrameCommitReceive(player, data, logicalCount)
end

local function decodeBatch(player, data, reader)
	if Config.BitFrameEnabled then
		Internal.decodeBitFrame(player, data)
		return
	end
	if buffer.len(data) > 0 then
		local lowMarker = bit32.band(buffer.readu8(data, 0), 7)
		if lowMarker == Internal.BIT_CALL_MARKER then Internal.decodeBitCallSingle(player, data); return end
		if lowMarker == Internal.HYBRID_EVENT_STATE_MARKER or lowMarker == Internal.HYBRID_CALL_MARKER or lowMarker == Internal.HYBRID_RETURN_MARKER then
			Internal.decodeHybridSmallSingle(player, data, lowMarker); return
		end
	end
	local packetProtocol = reader:u8()
	if packetProtocol == Internal.LEGACY_PROTOCOL_COMPACT_TABLE then
		Internal.decodeCompactSingleTable(player, data, reader)
		return
	elseif packetProtocol == Internal.LEGACY_PROTOCOL_FAST_SCHEMA then
		Internal.decodeFastSchemaSingle(player, data, reader)
		return
	end
	local count
	if packetProtocol == Internal.LEGACY_PROTOCOL_SINGLE then
		count = 1
	elseif packetProtocol == Internal.LEGACY_PROTOCOL then
		count = reader:varUInt()
	else
		error(string.format("%s protocol mismatch: received 0x%02X, expected 0x%02X, 0x%02X, 0x%02X, or 0x%02X. Make sure both peers use the same NetStream version (v2.1 BitFrameEnabled=false legacy fallback).", LOG_PREFIX, packetProtocol, Internal.LEGACY_PROTOCOL, Internal.LEGACY_PROTOCOL_SINGLE, Internal.LEGACY_PROTOCOL_COMPACT_TABLE, Internal.LEGACY_PROTOCOL_FAST_SCHEMA), 0)
	end
	if count > Config.MaxIncomingMessages then
		error("NetStream batch exceeds MaxIncomingMessages", 0)
	end
	if not canAcceptIncomingMessages(player, count) then
		Stats.RateLimitedBatches += 1
		Stats.ReceivedBatches += 1
		Stats.ReceivedBytes += buffer.len(data)
		return
	end
	local processed = 0
	while processed < count do
		local header = reader:u8()
		local kind = header % 4
		local schemaEncoded = math.floor(header / 4) % 2 == 1
		local reuseRoute = schemaEncoded and (math.floor(header / 8) % 2 == 1) or false
		local runEncoded = schemaEncoded and (math.floor(header / 16) % 2 == 1) or false
		local argc = 0
		local compressedDynamic = false
		local compressedSingle = false
		if not schemaEncoded then
			argc = math.floor(header / 8)
			if argc == 30 then
				compressedSingle = true
				argc = 1
			elseif argc == 31 then
				local control = reader:varUInt()
				local compressionMode = control % 4
				argc = math.floor(control / 4)
				if compressionMode == 1 then
					compressedDynamic = true
				elseif compressionMode == 2 then
					compressedSingle = true
				elseif compressionMode ~= 0 then
					error("NetStream invalid dynamic compression mode", 0)
				end
			end
			if argc > Config.MaxTableEntries then
				error("NetStream argument count is too large", 0)
			end
		elseif header >= 32 then
			error("NetStream reserved schema header bits are set", 0)
		end
		if runEncoded and kind ~= KIND_EVENT then
			error("NetStream schema runs are only valid for events", 0)
		end

		local routeId = nil
		local id = nil
		local route = nil
		if kind == KIND_EVENT or kind == KIND_CALL or kind == KIND_STATE then
			if reuseRoute then
				if kind == KIND_EVENT then
					routeId = reader.lastEventRoute
				elseif kind == KIND_CALL then
					routeId = reader.lastCallRoute
				else
					routeId = reader.lastStateRoute
				end
				if routeId == nil then
					error("NetStream route reuse appeared before a route id", 0)
				end
			else
				routeId = reader:varUInt()
				if kind == KIND_EVENT then
					reader.lastEventRoute = routeId
				elseif kind == KIND_CALL then
					reader.lastCallRoute = routeId
				else
					reader.lastStateRoute = routeId
				end
			end
			if kind == KIND_EVENT then
				route = eventRoutes[routeId]
			elseif kind == KIND_CALL then
				route = functionRoutes[routeId]
			else
				route = stateRoutes[routeId]
			end
		end
		if kind == KIND_CALL or kind == KIND_RETURN then
			id = reader:varUInt()
		end

		local schema = route and route._schema or nil
		if schemaEncoded then
			if kind == KIND_RETURN then
				error("NetStream schema encoding is not valid for return messages", 0)
			end
			if not schema then
				error("NetStream received schema packet for an unknown or dynamic route", 0)
			end
			argc = schema.count
		elseif schema then
			error("NetStream received dynamic packet for a schema route", 0)
		end

		local repeatCount = 1
		if runEncoded then
			repeatCount = reader:varUInt()
			if repeatCount < 2 or processed + repeatCount > count then
				error("NetStream invalid schema event run length", 0)
			end
		end

		if runEncoded then
			decodeSchemaEventRun(reader, schema, repeatCount, route, player, consumeRouteAllowance(route, player, repeatCount))
		else
			local args
			local scalarFast = false
			local scalarValue = nil
			if schemaEncoded and schema.count == 1 and (kind == KIND_EVENT or kind == KIND_STATE) then
				scalarValue = readSchemaValue(reader, schema.fields[1])
				scalarFast = true
				if schema.fixedBytes ~= nil then Stats.FixedSchemaFastReads += 1 end
			elseif schemaEncoded then
				args = readSchemaArgs(reader, schema)
			elseif compressedDynamic or compressedSingle then
				local isTail = processed + 1 == count
				local compressedBytes = if isTail then reader.length - reader.position else reader:varUInt()
				if compressedBytes <= 0 or compressedBytes > Config.MaxIncomingPacketBytes then
					error("NetStream compressed dynamic payload exceeds MaxIncomingPacketBytes", 0)
				end
				local compressedData = reader:rawBuffer(compressedBytes)
				local decoded = Compression.Decode(compressedData, Internal.compressionOptions())
				if compressedSingle then
					if argc ~= 1 or typeof(decoded) ~= "table" then
						error("NetStream direct compressed table payload is invalid", 0)
					end
					validateValue(decoded, 0, nil)
					args = acquireArgsCount(1)
					args[1] = decoded
				else
					if typeof(decoded) ~= "table" or type(decoded.n) ~= "number" or decoded.n ~= argc then
						error("NetStream compressed argument payload is invalid", 0)
					end
					args = acquireArgsCount(argc)
					for i = 1, argc do
						args[i] = decoded[i]
					end
					validateArgs(args)
				end
				Stats.CompressionDecodeCount += 1
			else
				args = acquireArgsCount(argc)
				for i = 1, argc do
					args[i] = readValue(reader, 0)
				end
			end

			if kind == KIND_EVENT then
				if consumeRouteAllowance(route, player, 1) > 0 then
					if scalarFast then enqueueDispatchScalar(route, player, scalarValue) else enqueueDispatch(route, player, args) end
				elseif not scalarFast then
					releaseArgs(args)
				end
			elseif kind == KIND_STATE then
				if route and consumeRouteAllowance(route, player, 1) > 0 then
					local state = Internal.getPeerState(player)
					state[routeId] = if scalarFast then scalarValue else args[1]
					if scalarFast then enqueueDispatchScalar(route, player, scalarValue) else enqueueDispatch(route, player, args) end
				elseif not scalarFast then
					releaseArgs(args)
				end
			elseif kind == KIND_CALL then
				if Internal.chargeIncomingCall(player) then
					task.spawn(Internal.handleCall, player, routeId, id, args)
				else
					releaseArgs(args)
				end
			elseif kind == KIND_RETURN then
				Internal.processReturn(player, id, args)
			else
				releaseArgs(args)
				error("NetStream unknown message kind", 0)
			end
		end

		processed += repeatCount
	end
	if reader.position ~= reader.length then
		error("NetStream packet contains trailing bytes", 0)
	end
	commitIncomingMessages(player, count)
	local receivedBytes = buffer.len(data)
	Stats.ReceivedBatches += 1
	Stats.ReceivedBytes += receivedBytes
	Stats.ReceivedMessages += count
	trafficWindowReceivedBatches += 1
	trafficWindowReceivedBytes += receivedBytes
	trafficWindowReceivedMessages += count
end

local function receive(player, data)
	local isBuffer = typeof(data) == "buffer"
	local bytes = if isBuffer then buffer.len(data) else 0
	if not chargeIncomingEnvelope(player, bytes) then
		Stats.RateLimitedBatches += 1
		Stats.ReceivedBatches += 1
		Stats.ReceivedBytes += bytes
		return
	end
	if isBuffer and bytes > Config.MaxIncomingPacketBytes then
		Stats.RejectedOversizedPackets += 1
		Stats.DecodeErrors += 1
		return
	end
	if not isBuffer then
		Stats.DecodeErrors += 1
		Stats.RejectedMalformedPackets += 1
		return
	end
	local reader = acquireReader(data)
	local ok, err = pcall(decodeBatch, player, data, reader)
	releaseReader(reader)
	if not ok then
		Stats.DecodeErrors += 1
		Stats.RejectedMalformedPackets += 1
		Internal.debugWarn("Decode rejected:", err)
	end
end

function Internal.makeRemoteFolder()
	local folderName = "__NetStream_" .. Config.Namespace
	local folder = ReplicatedStorage:FindFirstChild(folderName)
	if IS_SERVER then
		if folder and not folder:IsA("Folder") then
			folder:Destroy()
			folder = nil
		end
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = folderName
			folder.Parent = ReplicatedStorage
		end
		return folder
	end
	local folder = ReplicatedStorage:WaitForChild(folderName, Config.RemoteWaitTimeout)
	if not folder then
		error(string.format(
			LOG_PREFIX .. " Timed out after %.1fs waiting for ReplicatedStorage.%s. Make sure a server Script requires NetStream and calls NetStream.Start() (or creates a route) before the client starts.",
			Config.RemoteWaitTimeout,
			folderName
			), 0)
	end
	if not folder:IsA("Folder") then
		error(LOG_PREFIX .. " Remote container " .. folderName .. " is not a Folder", 0)
	end
	return folder
end

function Internal.ensureRemotes()
	local folder = Internal.makeRemoteFolder()
	if IS_SERVER then
		reliableRemote = folder:FindFirstChild("R")
		if reliableRemote and not reliableRemote:IsA("RemoteEvent") then
			reliableRemote:Destroy()
			reliableRemote = nil
		end
		if not reliableRemote then
			reliableRemote = Instance.new("RemoteEvent")
			reliableRemote.Name = "R"
			reliableRemote.Parent = folder
		end
		unreliableRemote = folder:FindFirstChild("U")
		if unreliableRemote and not unreliableRemote:IsA("UnreliableRemoteEvent") then
			unreliableRemote:Destroy()
			unreliableRemote = nil
		end
		if not unreliableRemote then
			local ok, remote = pcall(Instance.new, "UnreliableRemoteEvent")
			if ok and remote then
				unreliableRemote = remote
				unreliableRemote.Name = "U"
				unreliableRemote.Parent = folder
			end
		end
	else
		reliableRemote = folder:WaitForChild("R", Config.RemoteWaitTimeout)
		if not reliableRemote then
			error(string.format(
				LOG_PREFIX .. " Timed out after %.1fs waiting for reliable remote R. Make sure NetStream.Start() is running on the server.",
				Config.RemoteWaitTimeout
				), 0)
		end
		assert(reliableRemote:IsA("RemoteEvent"), "NetStream remote R is not a RemoteEvent")
		unreliableRemote = folder:FindFirstChild("U")
		if not unreliableRemote then
			unreliableRemote = folder:WaitForChild("U", 2)
		end
		if unreliableRemote and not unreliableRemote:IsA("UnreliableRemoteEvent") then
			unreliableRemote = nil
		end
	end
end

local function updateTrafficSnapshot()
	local now = os.clock()
	local elapsed = now - trafficWindowStarted
	if elapsed < 1 then
		return
	end
	trafficSnapshot.SentBytesPerSecond = trafficWindowSentBytes / elapsed
	trafficSnapshot.ReceivedBytesPerSecond = trafficWindowReceivedBytes / elapsed
	trafficSnapshot.SentMessagesPerSecond = trafficWindowSentMessages / elapsed
	trafficSnapshot.ReceivedMessagesPerSecond = trafficWindowReceivedMessages / elapsed
	trafficSnapshot.SentBatchesPerSecond = trafficWindowSentBatches / elapsed
	trafficSnapshot.ReceivedBatchesPerSecond = trafficWindowReceivedBatches / elapsed
	trafficSnapshot.BandwidthLimitBytesPerSecond = if Config.BandwidthGovernorEnabled then Config.BandwidthLimitBytesPerSecond else 0
	trafficSnapshot.EstimatedTransportBytesPerSecond = Internal.trafficWindowEstimatedTransportBytes / elapsed
	trafficSnapshot.BandwidthUtilization = if Config.BandwidthGovernorEnabled then trafficSnapshot.EstimatedTransportBytesPerSecond / Config.BandwidthLimitBytesPerSecond else 0
	trafficSnapshot.BandwidthHeadroomBytesPerSecond = if Config.BandwidthGovernorEnabled then math.max(0, Config.BandwidthLimitBytesPerSecond - trafficSnapshot.EstimatedTransportBytesPerSecond) else math.huge
	trafficSnapshot.EstimatedTransportUtilization = trafficSnapshot.BandwidthUtilization
	trafficSnapshot.EstimatedTransportHeadroomBytesPerSecond = trafficSnapshot.BandwidthHeadroomBytesPerSecond
	trafficWindowStarted = now
	trafficWindowSentBytes = 0
	trafficWindowReceivedBytes = 0
	trafficWindowSentMessages = 0
	trafficWindowReceivedMessages = 0
	trafficWindowSentBatches = 0
	trafficWindowReceivedBatches = 0
	Internal.trafficWindowEstimatedTransportBytes = 0
	Stats.TrafficSnapshots += 1
end

local function flushAll()
	if destroyed or not started then
		return
	end
	local deadline = os.clock() + Config.FlushBudgetSeconds
	if IS_SERVER then
		if broadcastBucket and not bucketEmpty(broadcastBucket) and os.clock() < deadline then
			flushBucket(ALL, broadcastBucket, deadline)
		end
		local processedTargets = 0
		while activeTargetHead <= activeTargetTail and processedTargets < Config.MaxTargetsPerFlush do
			if os.clock() >= deadline then
				break
			end
			local index = activeTargetHead
			local player = activeTargets[index]
			activeTargets[index] = nil
			activeTargetHead += 1
			local bucket = player and targetBuckets[player] or nil
			if bucket then
				processedTargets += 1
				if player.Parent ~= Players then
					Internal.releaseBucket(bucket)
					targetBuckets[player] = nil
				else
					if not bucketEmpty(bucket) then
						flushBucket(player, bucket, deadline)
					end
					if bucketEmpty(bucket) then
						targetBuckets[player] = nil
					else
						activeTargetTail += 1
						activeTargets[activeTargetTail] = player
					end
				end
			end
		end
		if activeTargetHead > activeTargetTail then
			activeTargetHead = 1
			activeTargetTail = 0
			table.clear(activeTargets)
		elseif activeTargetHead > 1024 and activeTargetHead > math.floor(activeTargetTail / 2) then
			local newTail = 0
			for index = activeTargetHead, activeTargetTail do
				local player = activeTargets[index]
				if player then
					newTail += 1
					activeTargets[newTail] = player
				end
				activeTargets[index] = nil
			end
			activeTargetHead = 1
			activeTargetTail = newTail
		end
	else
		if clientBucket and not bucketEmpty(clientBucket) and os.clock() < deadline then
			flushBucket(nil, clientBucket, deadline)
		end
	end
end

local function ensureStarted()
	if started then
		return
	end
	assert(not destroyed, "NetStream has been destroyed")
	Internal.ensureRemotes()
	started = true
	if IS_SERVER then
		receiveConnections[#receiveConnections + 1] = reliableRemote.OnServerEvent:Connect(function(player, data)
			receive(player, data)
		end)
		if unreliableRemote then
			receiveConnections[#receiveConnections + 1] = unreliableRemote.OnServerEvent:Connect(function(player, data)
				receive(player, data)
			end)
		end
		playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
			Internal.releaseBucket(targetBuckets[player])
			targetBuckets[player] = nil
			incomingRates[player] = nil
			Internal.bandwidthStates[player] = nil
			peerStates[player] = nil
			Internal.failPendingForPlayer(player, "Player left before NetStream call completed")
		end)
	else
		receiveConnections[#receiveConnections + 1] = reliableRemote.OnClientEvent:Connect(function(data)
			receive(nil, data)
		end)
		if unreliableRemote then
			receiveConnections[#receiveConnections + 1] = unreliableRemote.OnClientEvent:Connect(function(data)
				receive(nil, data)
			end)
		end
	end
	local interval = 1 / math.max(1, Config.FlushRate)
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		runDispatch()
		updateTrafficSnapshot()
		accumulator += dt
		timeoutAccumulator += dt
		if timeoutAccumulator >= Config.TimeoutSweepInterval then
			timeoutAccumulator %= Config.TimeoutSweepInterval
			Internal.checkTimeouts()
		end
		if accumulator >= interval then
			accumulator %= interval
			flushAll()
		end
	end)
end

peekTargetBucket = function(target)
	if IS_SERVER then
		if target == ALL then
			return broadcastBucket
		end
		return targetBuckets[target]
	end
	return clientBucket
end

function Internal.flushTargetNow(target)
	if destroyed or not started then
		return false
	end
	local bucket = peekTargetBucket(target)
	if not bucket or bucketEmpty(bucket) then
		return true
	end
	Stats.ImmediateFlushes += 1
	local deadline = os.clock() + Config.ImmediateFlushBudgetSeconds
	flushBucket(target, bucket, deadline, true)
	local empty = bucketEmpty(bucket)
	if not empty then
		Stats.TransportImmediateDeferred += 1
	end
	if IS_SERVER and target ~= ALL and empty then
		targetBuckets[target] = nil
	end
	return empty
end

function Internal.cancelLatestForRoute(target, key)
	local bucket = peekTargetBucket(target)
	if not bucket then
		return 0
	end
	local cancelled = 0
	local reliableMessage = bucket.latestReliable[key]
	if reliableMessage then
		bucket.latestReliable[key] = nil
		releaseMessage(reliableMessage)
		cancelled += 1
	end
	local unreliableMessage = bucket.latestUnreliable[key]
	if unreliableMessage then
		bucket.latestUnreliable[key] = nil
		releaseMessage(unreliableMessage)
		cancelled += 1
	end
	if cancelled > 0 then
		Stats.CancelledLatest += cancelled
	end
	if IS_SERVER and target ~= ALL and bucketEmpty(bucket) then
		targetBuckets[target] = nil
	end
	return cancelled
end

local EventRoute = setmetatable({}, BaseRoute)
EventRoute.__index = EventRoute

function EventRoute:_send(target, unreliable, latest, ...)
	ensureStarted()
	local args
	local schema = self._schema
	local argCount = select("#", ...)
	if self._packedEligible and not unreliable and not latest and argCount == schema.count then
		if not self._trusted then
			for i = 1, schema.count do
				Internal.validateSchemaValue(schema.fields[i], select(i, ...), 5)
			end
		end
		return Internal.enqueuePackedEvent(target, unreliable, self, schema.count, ...)
	end
	if schema and schema.count == 0 and argCount == 0 then
		args = EMPTY_ARGS
	elseif schema and schema.count == 1 and argCount == 1 and schema.fields[1].Kind == SCHEMA_BOOL then
		local value = select(1, ...)
		if type(value) == "boolean" then
			args = if value then TRUE_ARGS else FALSE_ARGS
		else
			args = makeArgs(...)
			validateSchemaArgs(schema, args, self._trusted)
		end
	else
		args = makeArgs(...)
		if schema then
			validateSchemaArgs(schema, args, self._trusted)
		else
			validateArgs(args)
		end
	end
	local message = makeMessage(KIND_EVENT, self.Id, 0, args, schema, self.Priority)
	return enqueue(target, unreliable, message, if latest then self.Id * 4 + KIND_EVENT else nil)
end

function EventRoute:FireServer(...)
	assert(not IS_SERVER, "FireServer can only be used on the client")
	local ok = self:_send(nil, self.Unreliable, self.Coalesce, ...)
	if ok and self.Immediate then Internal.flushTargetNow(nil) end
	return ok
end

function EventRoute:FireServerNow(...)
	assert(not IS_SERVER, "FireServerNow can only be used on the client")
	local ok = self:_send(nil, self.Unreliable, false, ...)
	if ok then Internal.flushTargetNow(nil) end
	return ok
end

EventRoute.FireServerImmediate = EventRoute.FireServerNow

function EventRoute:FireClient(player, ...)
	assert(IS_SERVER, "FireClient can only be used on the server")
	local ok = self:_send(player, self.Unreliable, self.Coalesce, ...)
	if ok and self.Immediate then Internal.flushTargetNow(player) end
	return ok
end

function EventRoute:FireClientNow(player, ...)
	assert(IS_SERVER, "FireClientNow can only be used on the server")
	local ok = self:_send(player, self.Unreliable, false, ...)
	if ok then Internal.flushTargetNow(player) end
	return ok
end

EventRoute.FireClientImmediate = EventRoute.FireClientNow

function EventRoute:FireAll(...)
	assert(IS_SERVER, "FireAll can only be used on the server")
	local ok = self:_send(ALL, self.Unreliable, self.Coalesce, ...)
	if ok and self.Immediate then Internal.flushTargetNow(ALL) end
	return ok
end

function EventRoute:FireAllNow(...)
	assert(IS_SERVER, "FireAllNow can only be used on the server")
	local ok = self:_send(ALL, self.Unreliable, false, ...)
	if ok then Internal.flushTargetNow(ALL) end
	return ok
end

EventRoute.FireAllImmediate = EventRoute.FireAllNow

function EventRoute:FireAllExcept(exceptPlayer, ...)
	assert(IS_SERVER, "FireAllExcept can only be used on the server")
	local ok = true
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= exceptPlayer then
			local sent = self:_send(player, self.Unreliable, self.Coalesce, ...)
			if sent and self.Immediate then Internal.flushTargetNow(player) end
			ok = sent and ok
		end
	end
	return ok
end

function EventRoute:FireAllExceptNow(exceptPlayer, ...)
	assert(IS_SERVER, "FireAllExceptNow can only be used on the server")
	local ok = true
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= exceptPlayer then
			local sent = self:_send(player, self.Unreliable, false, ...)
			if sent then Internal.flushTargetNow(player) end
			ok = sent and ok
		end
	end
	return ok
end

function EventRoute:FireUnreliableServer(...)
	assert(not IS_SERVER, "FireUnreliableServer can only be used on the client")
	local ok = self:_send(nil, true, self.Coalesce, ...)
	if ok and self.Immediate then Internal.flushTargetNow(nil) end
	return ok
end

function EventRoute:FireUnreliableClient(player, ...)
	assert(IS_SERVER, "FireUnreliableClient can only be used on the server")
	local ok = self:_send(player, true, self.Coalesce, ...)
	if ok and self.Immediate then Internal.flushTargetNow(player) end
	return ok
end

function EventRoute:FireUnreliableAll(...)
	assert(IS_SERVER, "FireUnreliableAll can only be used on the server")
	local ok = self:_send(ALL, true, self.Coalesce, ...)
	if ok and self.Immediate then Internal.flushTargetNow(ALL) end
	return ok
end

function EventRoute:LatestServer(...)
	assert(not IS_SERVER, "LatestServer can only be used on the client")
	return self:_send(nil, true, true, ...)
end

function EventRoute:LatestClient(player, ...)
	assert(IS_SERVER, "LatestClient can only be used on the server")
	return self:_send(player, true, true, ...)
end

function EventRoute:LatestAll(...)
	assert(IS_SERVER, "LatestAll can only be used on the server")
	return self:_send(ALL, true, true, ...)
end

function EventRoute:CancelLatestServer()
	assert(not IS_SERVER, "CancelLatestServer can only be used on the client")
	return Internal.cancelLatestForRoute(nil, self.Id * 4 + KIND_EVENT)
end

function EventRoute:CancelLatestClient(player)
	assert(IS_SERVER, "CancelLatestClient can only be used on the server")
	return Internal.cancelLatestForRoute(player, self.Id * 4 + KIND_EVENT)
end

function EventRoute:CancelLatestAll()
	assert(IS_SERVER, "CancelLatestAll can only be used on the server")
	return Internal.cancelLatestForRoute(ALL, self.Id * 4 + KIND_EVENT)
end

function EventRoute:CancelQueuedServer()
	assert(not IS_SERVER, "CancelQueuedServer can only be used on the client")
	return Internal.cancelQueuedForRoute(nil, self.Id, KIND_EVENT)
end

function EventRoute:CancelQueuedClient(player)
	assert(IS_SERVER, "CancelQueuedClient can only be used on the server")
	return Internal.cancelQueuedForRoute(player, self.Id, KIND_EVENT)
end

function EventRoute:CancelQueuedAll()
	assert(IS_SERVER, "CancelQueuedAll can only be used on the server")
	return Internal.cancelQueuedForRoute(ALL, self.Id, KIND_EVENT)
end

function EventRoute:Fire(...)
	if IS_SERVER then
		local args = table.pack(...)
		if args.n > 0 and typeof(args[1]) == "Instance" and args[1]:IsA("Player") then
			return self:FireClient(args[1], table.unpack(args, 2, args.n))
		end
		return self:FireAll(...)
	end
	return self:FireServer(...)
end

EventRoute.Send = EventRoute.Fire

local FunctionRoute = {}
FunctionRoute.__index = FunctionRoute

function FunctionRoute:GetPriority()
	return self.Priority or "Critical"
end

function FunctionRoute:GetOptimizationLevel()
	local schema = self._schema
	if not schema then return "Dynamic" end
	if schema.fixedBytes ~= nil then return "Fixed" end
	return "Schema"
end

function FunctionRoute:GetSchemaInfo()
	local schema = self._schema
	if not schema then return nil end
	return { Count = schema.count, Signature = schema.signature, FixedBytes = schema.fixedBytes, IsFixed = schema.isFixed, OptimizationLevel = self:GetOptimizationLevel() }
end

function FunctionRoute:SetCallback(callback)
	assert(type(callback) == "function" or callback == nil, "SetCallback expects a function or nil")
	ensureStarted()
	self._callback = callback
	return self
end

FunctionRoute.OnInvoke = FunctionRoute.SetCallback
FunctionRoute.Bind = FunctionRoute.SetCallback

function FunctionRoute:_invoke(target, immediate, ...)
	ensureStarted()
	local thread = coroutine.running()
	assert(thread, "NetStream Invoke must be called from a yielding thread")
	local args = makeArgs(...)
	if self._schema then
		validateSchemaArgs(self._schema, args, self._trusted)
	else
		validateArgs(args)
	end
	local id = Internal.nextRequestId()
	pending[id] = {
		thread = thread,
		target = if IS_SERVER then target else nil,
		deadline = os.clock() + Config.CallTimeout,
	}
	local message = makeMessage(KIND_CALL, self.Id, id, args, self._schema, self.Priority)
	local queued = enqueue(target, false, message, nil)
	if not queued then
		pending[id] = nil
		error("NetStream reliable queue is full", 3)
	end
	if immediate or self.Immediate then
		Internal.flushTargetNow(target)
	end
	local result = table.pack(coroutine.yield())
	if not result[1] then
		error(result[2] or "NetStream remote call failed", 3)
	end
	return table.unpack(result, 2, result.n)
end

function FunctionRoute:InvokeServer(...)
	assert(not IS_SERVER, "InvokeServer can only be used on the client")
	return self:_invoke(nil, false, ...)
end

function FunctionRoute:InvokeClient(player, ...)
	assert(IS_SERVER, "InvokeClient can only be used on the server")
	assert(typeof(player) == "Instance" and player:IsA("Player"), "InvokeClient expects a Player")
	return self:_invoke(player, false, ...)
end

function FunctionRoute:InvokeServerNow(...)
	assert(not IS_SERVER, "InvokeServerNow can only be used on the client")
	return self:_invoke(nil, true, ...)
end

FunctionRoute.InvokeServerImmediate = FunctionRoute.InvokeServerNow

function FunctionRoute:InvokeClientNow(player, ...)
	assert(IS_SERVER, "InvokeClientNow can only be used on the server")
	assert(typeof(player) == "Instance" and player:IsA("Player"), "InvokeClientNow expects a Player")
	return self:_invoke(player, true, ...)
end

FunctionRoute.InvokeClientImmediate = FunctionRoute.InvokeClientNow

function FunctionRoute:Invoke(...)
	if IS_SERVER then
		local args = table.pack(...)
		assert(args.n >= 1 and typeof(args[1]) == "Instance" and args[1]:IsA("Player"), "Server Invoke expects player as first argument")
		return self:InvokeClient(args[1], table.unpack(args, 2, args.n))
	end
	return self:InvokeServer(...)
end

local StateRoute = setmetatable({}, BaseRoute)
StateRoute.__index = StateRoute

function StateRoute:_send(target, value, unreliable, latest)
	ensureStarted()
	local schema = self._schema
	local args
	if schema and schema.count == 1 and schema.fields[1].Kind == SCHEMA_BOOL and type(value) == "boolean" then
		args = if value then TRUE_ARGS else FALSE_ARGS
	else
		args = makeArgs(value)
	end
	if schema then
		validateSchemaArgs(schema, args, self._trusted)
	else
		validateValue(value, 0, nil)
	end
	local message = makeMessage(KIND_STATE, self.Id, 0, args, schema, self.Priority)
	return enqueue(target, unreliable, message, if latest then self.Id * 4 + KIND_STATE else nil)
end

function StateRoute:SetServer(value, unreliable)
	assert(not IS_SERVER, "SetServer can only be used on the client")
	local ok = self:_send(nil, value, unreliable == true, self.Coalesce)
	if ok and self.Immediate then Internal.flushTargetNow(nil) end
	return ok
end

function StateRoute:SetServerNow(value, unreliable)
	assert(not IS_SERVER, "SetServerNow can only be used on the client")
	local ok = self:_send(nil, value, unreliable == true, false)
	if ok then Internal.flushTargetNow(nil) end
	return ok
end

StateRoute.SetServerImmediate = StateRoute.SetServerNow

function StateRoute:SetClient(player, value, unreliable)
	assert(IS_SERVER, "SetClient can only be used on the server")
	local ok = self:_send(player, value, unreliable == true, self.Coalesce)
	if ok and self.Immediate then Internal.flushTargetNow(player) end
	return ok
end

function StateRoute:SetClientNow(player, value, unreliable)
	assert(IS_SERVER, "SetClientNow can only be used on the server")
	local ok = self:_send(player, value, unreliable == true, false)
	if ok then Internal.flushTargetNow(player) end
	return ok
end

StateRoute.SetClientImmediate = StateRoute.SetClientNow

function StateRoute:SetAll(value, unreliable)
	assert(IS_SERVER, "SetAll can only be used on the server")
	local ok = self:_send(ALL, value, unreliable == true, self.Coalesce)
	if ok and self.Immediate then Internal.flushTargetNow(ALL) end
	return ok
end

function StateRoute:SetAllNow(value, unreliable)
	assert(IS_SERVER, "SetAllNow can only be used on the server")
	local ok = self:_send(ALL, value, unreliable == true, false)
	if ok then Internal.flushTargetNow(ALL) end
	return ok
end

StateRoute.SetAllImmediate = StateRoute.SetAllNow

function StateRoute:SetLatestServer(value)
	assert(not IS_SERVER, "SetLatestServer can only be used on the client")
	return self:_send(nil, value, true, true)
end

function StateRoute:SetLatestClient(player, value)
	assert(IS_SERVER, "SetLatestClient can only be used on the server")
	return self:_send(player, value, true, true)
end

function StateRoute:SetLatestAll(value)
	assert(IS_SERVER, "SetLatestAll can only be used on the server")
	return self:_send(ALL, value, true, true)
end

function StateRoute:CancelLatestServer()
	assert(not IS_SERVER, "CancelLatestServer can only be used on the client")
	return Internal.cancelLatestForRoute(nil, self.Id * 4 + KIND_STATE)
end

function StateRoute:CancelLatestClient(player)
	assert(IS_SERVER, "CancelLatestClient can only be used on the server")
	return Internal.cancelLatestForRoute(player, self.Id * 4 + KIND_STATE)
end

function StateRoute:CancelLatestAll()
	assert(IS_SERVER, "CancelLatestAll can only be used on the server")
	return Internal.cancelLatestForRoute(ALL, self.Id * 4 + KIND_STATE)
end

function StateRoute:CancelQueuedServer()
	assert(not IS_SERVER, "CancelQueuedServer can only be used on the client")
	return Internal.cancelQueuedForRoute(nil, self.Id, KIND_STATE)
end

function StateRoute:CancelQueuedClient(player)
	assert(IS_SERVER, "CancelQueuedClient can only be used on the server")
	return Internal.cancelQueuedForRoute(player, self.Id, KIND_STATE)
end

function StateRoute:CancelQueuedAll()
	assert(IS_SERVER, "CancelQueuedAll can only be used on the server")
	return Internal.cancelQueuedForRoute(ALL, self.Id, KIND_STATE)
end

function StateRoute:Set(...)
	if IS_SERVER then
		local args = table.pack(...)
		if args.n >= 2 and typeof(args[1]) == "Instance" and args[1]:IsA("Player") then
			return self:SetClient(args[1], args[2], args[3])
		end
		return self:SetAll(args[1], args[2])
	end
	return self:SetServer(...)
end

function StateRoute:Get(player)
	if IS_SERVER then
		if not player then
			return nil
		end
		assert(typeof(player) == "Instance" and player:IsA("Player"), "State:Get(player) expects a Player on the server")
		local state = Internal.peekPeerState(player)
		return state and state[self.Id] or nil
	end
	local state = Internal.peekPeerState(nil)
	return state and state[self.Id] or nil
end

local NetStream = {}
NetStream.Types = Types
NetStream.Version = VERSION
NetStream.Protocol = Internal.LEGACY_PROTOCOL
NetStream.ProtocolSingle = Internal.LEGACY_PROTOCOL_SINGLE
NetStream.ProtocolCompactTable = Internal.LEGACY_PROTOCOL_COMPACT_TABLE
NetStream.ProtocolFastSchema = Internal.LEGACY_PROTOCOL_FAST_SCHEMA
NetStream.BitCallMarker = Internal.BIT_CALL_MARKER
NetStream.RequiredCompressionVersion = "2.9.0"
NetStream.RequiredBufferUtilVersion = "1.1.0"
NetStream.BitFrameVersion = 1
NetStream.ProtocolHeaderBytes = 0
NetStream.HybridEventStateMarker = Internal.HYBRID_EVENT_STATE_MARKER
NetStream.HybridCallMarker = Internal.HYBRID_CALL_MARKER
NetStream.HybridReturnMarker = Internal.HYBRID_RETURN_MARKER

function Internal.validateConfig(config)
	assert(type(config.Namespace) == "string" and #config.Namespace > 0, "Namespace must be a non-empty string")
	assert(type(config.RemoteWaitTimeout) == "number" and isFiniteNumber(config.RemoteWaitTimeout) and config.RemoteWaitTimeout > 0, "RemoteWaitTimeout must be a finite number greater than 0")
	assert(type(config.FlushRate) == "number" and isFiniteNumber(config.FlushRate) and config.FlushRate > 0, "FlushRate must be a finite number greater than 0")
	assert(type(config.VectorPrecision) == "number" and isFiniteNumber(config.VectorPrecision) and config.VectorPrecision > 0, "VectorPrecision must be a finite number greater than 0")
	assert(type(config.MaxBatchMessages) == "number" and config.MaxBatchMessages >= 1, "MaxBatchMessages must be >= 1")
	assert(type(config.MaxOutgoingBatchBytes) == "number" and config.MaxOutgoingBatchBytes >= 1024, "MaxOutgoingBatchBytes must be >= 1024")
	assert(type(config.MaxIncomingPacketBytes) == "number" and config.MaxIncomingPacketBytes >= 1024, "MaxIncomingPacketBytes must be >= 1024")
	assert(type(config.MaxBatchesPerFlush) == "number" and config.MaxBatchesPerFlush >= 1, "MaxBatchesPerFlush must be >= 1")
	assert(type(config.MaxDispatchPerCycle) == "number" and config.MaxDispatchPerCycle >= 1, "MaxDispatchPerCycle must be >= 1")
	assert(type(config.MaxDispatchBacklog) == "number" and config.MaxDispatchBacklog >= config.MaxDispatchPerCycle, "MaxDispatchBacklog must be >= MaxDispatchPerCycle")
	assert(type(config.DispatchBudgetSeconds) == "number" and isFiniteNumber(config.DispatchBudgetSeconds) and config.DispatchBudgetSeconds > 0, "DispatchBudgetSeconds must be a finite number > 0")
	assert(type(config.FlushBudgetSeconds) == "number" and isFiniteNumber(config.FlushBudgetSeconds) and config.FlushBudgetSeconds > 0, "FlushBudgetSeconds must be a finite number > 0")
	assert(type(config.ImmediateFlushBudgetSeconds) == "number" and isFiniteNumber(config.ImmediateFlushBudgetSeconds) and config.ImmediateFlushBudgetSeconds > 0, "ImmediateFlushBudgetSeconds must be a finite number > 0")
	assert(type(config.TimeoutSweepInterval) == "number" and config.TimeoutSweepInterval > 0, "TimeoutSweepInterval must be > 0")
	assert(type(config.MaxPoolSize) == "number" and config.MaxPoolSize >= 0, "MaxPoolSize must be >= 0")
	assert(type(config.MaxPooledArgs) == "number" and config.MaxPooledArgs >= 0, "MaxPooledArgs must be >= 0")
	assert(type(config.MaxPooledWriterBytes) == "number" and config.MaxPooledWriterBytes >= 512, "MaxPooledWriterBytes must be >= 512")
	assert(type(config.MaxPooledStrings) == "number" and config.MaxPooledStrings >= 0, "MaxPooledStrings must be >= 0")
	assert(type(config.MaxBatchPoolSize) == "number" and config.MaxBatchPoolSize >= 0, "MaxBatchPoolSize must be >= 0")
	assert(type(config.MaxTargetsPerFlush) == "number" and config.MaxTargetsPerFlush >= 1, "MaxTargetsPerFlush must be >= 1")
	assert(type(config.MaxIncomingMessagesPerSecond) == "number" and config.MaxIncomingMessagesPerSecond >= 1, "MaxIncomingMessagesPerSecond must be >= 1")
	assert(type(config.MaxIncomingBytesPerSecond) == "number" and config.MaxIncomingBytesPerSecond >= 1, "MaxIncomingBytesPerSecond must be >= 1")
	assert(type(config.MaxIncomingBatchesPerSecond) == "number" and config.MaxIncomingBatchesPerSecond >= 1, "MaxIncomingBatchesPerSecond must be >= 1")
	assert(type(config.MaxGlobalIncomingMessagesPerSecond) == "number" and config.MaxGlobalIncomingMessagesPerSecond >= 1, "MaxGlobalIncomingMessagesPerSecond must be >= 1")
	assert(type(config.MaxGlobalIncomingBytesPerSecond) == "number" and config.MaxGlobalIncomingBytesPerSecond >= 1, "MaxGlobalIncomingBytesPerSecond must be >= 1")
	assert(type(config.MaxGlobalIncomingBatchesPerSecond) == "number" and config.MaxGlobalIncomingBatchesPerSecond >= 1, "MaxGlobalIncomingBatchesPerSecond must be >= 1")
	assert(type(config.MaxIncomingCallsPerSecond) == "number" and config.MaxIncomingCallsPerSecond >= 1, "MaxIncomingCallsPerSecond must be >= 1")
	assert(type(config.MaxGlobalIncomingCallsPerSecond) == "number" and config.MaxGlobalIncomingCallsPerSecond >= 1, "MaxGlobalIncomingCallsPerSecond must be >= 1")
	assert(type(config.MaxReliableQueue) == "number" and config.MaxReliableQueue >= 1, "MaxReliableQueue must be >= 1")
	assert(type(config.MaxUnreliableQueue) == "number" and config.MaxUnreliableQueue >= 1, "MaxUnreliableQueue must be >= 1")
	assert(type(config.UnreliableMaxBytes) == "number" and config.UnreliableMaxBytes >= 1, "UnreliableMaxBytes must be >= 1")
	assert(type(config.CallTimeout) == "number" and config.CallTimeout > 0, "CallTimeout must be > 0")
	assert(type(config.MaxIncomingMessages) == "number" and config.MaxIncomingMessages >= 1, "MaxIncomingMessages must be >= 1")
	assert(type(config.MaxStringBytes) == "number" and config.MaxStringBytes >= 0, "MaxStringBytes must be >= 0")
	assert(type(config.MaxBufferBytes) == "number" and config.MaxBufferBytes >= 0, "MaxBufferBytes must be >= 0")
	assert(type(config.MaxTableEntries) == "number" and config.MaxTableEntries >= 1, "MaxTableEntries must be >= 1")
	assert(type(config.MaxDepth) == "number" and config.MaxDepth >= 1, "MaxDepth must be >= 1")
	assert(type(config.CompressionEnabled) == "boolean", "CompressionEnabled must be a boolean")
	assert(type(config.CompressionMinSavingsBytes) == "number" and config.CompressionMinSavingsBytes >= 0, "CompressionMinSavingsBytes must be >= 0")
	assert(type(config.CompressionMinStringBytes) == "number" and config.CompressionMinStringBytes >= 0, "CompressionMinStringBytes must be >= 0")
	assert(
		config.CompressionStringStrategy == "Auto"
			or config.CompressionStringStrategy == "Raw"
			or config.CompressionStringStrategy == "LZ"
			or config.CompressionStringStrategy == "ASCII7"
			or config.CompressionStringStrategy == "LowASCII5"
			or config.CompressionStringStrategy == "Identifier6"
			or config.CompressionStringStrategy == "Numeric4",
		"CompressionStringStrategy must be Auto, Raw, LZ, ASCII7, LowASCII5, Identifier6, or Numeric4"
	)
	assert(type(config.CompressionUseStringDictionary) == "boolean", "CompressionUseStringDictionary must be a boolean")
	assert(type(config.CompressionTableCompression) == "boolean", "CompressionTableCompression must be a boolean")
	assert(
		config.CompressionTableStrategy == "Auto"
			or config.CompressionTableStrategy == "Compact"
			or config.CompressionTableStrategy == "Dynamic",
		"CompressionTableStrategy must be Auto, Compact, or Dynamic"
	)
	assert(type(config.CompressionHomogeneousArrays) == "boolean", "CompressionHomogeneousArrays must be a boolean")
	assert(type(config.CompressionDeltaArrays) == "boolean", "CompressionDeltaArrays must be a boolean")
	assert(type(config.CompressionRunLengthArrays) == "boolean", "CompressionRunLengthArrays must be a boolean")
	assert(type(config.CompressionCompactMapKeys) == "boolean", "CompressionCompactMapKeys must be a boolean")
	assert(type(config.CompressionTableKeyMapping) == "boolean", "CompressionTableKeyMapping must be a boolean")
	assert(type(config.CompressionMappedKeyMinUses) == "number" and isInteger(config.CompressionMappedKeyMinUses) and config.CompressionMappedKeyMinUses >= 2, "CompressionMappedKeyMinUses must be an integer >= 2")
	assert(type(config.CompressionMaxMappedKeys) == "number" and isInteger(config.CompressionMaxMappedKeys) and config.CompressionMaxMappedKeys >= 0 and config.CompressionMaxMappedKeys <= 4095, "CompressionMaxMappedKeys must be an integer from 0 to 4095")
	assert(type(config.CompressionCompressBuffers) == "boolean", "CompressionCompressBuffers must be a boolean")
	assert(type(config.CompressionMinBufferBytes) == "number" and isInteger(config.CompressionMinBufferBytes) and config.CompressionMinBufferBytes >= 0, "CompressionMinBufferBytes must be a non-negative integer")
	assert(config.CompressionBufferStrategy == "Auto" or config.CompressionBufferStrategy == "Raw" or config.CompressionBufferStrategy == "LZ" or config.CompressionBufferStrategy == "Sparse" or config.CompressionBufferStrategy == "Nibble", "CompressionBufferStrategy must be Auto, Raw, LZ, Sparse, or Nibble")
	assert(type(config.CompressionEntropyCoding) == "boolean", "CompressionEntropyCoding must be a boolean")
	assert(config.CompressionEntropyStrategy == "Auto" or config.CompressionEntropyStrategy == "Huffman" or config.CompressionEntropyStrategy == "None", "CompressionEntropyStrategy must be Auto, Huffman, or None")
	assert(type(config.CompressionHuffmanMinBytes) == "number" and isInteger(config.CompressionHuffmanMinBytes) and config.CompressionHuffmanMinBytes >= 1, "CompressionHuffmanMinBytes must be an integer >= 1")
	assert(type(config.CompressionHuffmanMinSavings) == "number" and isInteger(config.CompressionHuffmanMinSavings) and config.CompressionHuffmanMinSavings >= 0, "CompressionHuffmanMinSavings must be a non-negative integer")
	assert(type(config.CompressionHuffmanMaxCodeBits) == "number" and isInteger(config.CompressionHuffmanMaxCodeBits) and config.CompressionHuffmanMaxCodeBits >= 4 and config.CompressionHuffmanMaxCodeBits <= 32, "CompressionHuffmanMaxCodeBits must be an integer from 4 to 32")
	assert(type(config.CompressionRouteStrategyCache) == "boolean", "CompressionRouteStrategyCache must be a boolean")
	assert(type(config.CompressionRouteStrategyWarmup) == "number" and isInteger(config.CompressionRouteStrategyWarmup) and config.CompressionRouteStrategyWarmup >= 1 and config.CompressionRouteStrategyWarmup <= 16, "CompressionRouteStrategyWarmup must be an integer from 1 to 16")
	assert(type(config.CompressionRouteStrategyResample) == "number" and isInteger(config.CompressionRouteStrategyResample) and config.CompressionRouteStrategyResample >= 1 and config.CompressionRouteStrategyResample <= 4096, "CompressionRouteStrategyResample must be an integer from 1 to 4096")
	assert(type(config.CompressionAllowExpansion) == "boolean", "CompressionAllowExpansion must be a boolean")
	assert(type(config.BandwidthGovernorEnabled) == "boolean", "BandwidthGovernorEnabled must be a boolean")
	assert(type(config.BandwidthLimitBytesPerSecond) == "number" and isFiniteNumber(config.BandwidthLimitBytesPerSecond) and config.BandwidthLimitBytesPerSecond >= 64, "BandwidthLimitBytesPerSecond must be a finite number >= 64")
	assert(type(config.BandwidthMaxPacketBytes) == "number" and isFiniteNumber(config.BandwidthMaxPacketBytes) and config.BandwidthMaxPacketBytes >= 32 and config.BandwidthMaxPacketBytes <= config.BandwidthLimitBytesPerSecond, "BandwidthMaxPacketBytes must be >= 32 and <= BandwidthLimitBytesPerSecond")
	assert(type(config.BandwidthMaxPacketsPerSecond) == "number" and isFiniteNumber(config.BandwidthMaxPacketsPerSecond) and config.BandwidthMaxPacketsPerSecond >= 1, "BandwidthMaxPacketsPerSecond must be a finite number >= 1")
	assert(type(config.BandwidthMaxReliableQueue) == "number" and isInteger(config.BandwidthMaxReliableQueue) and config.BandwidthMaxReliableQueue >= 1, "BandwidthMaxReliableQueue must be an integer >= 1")
	assert(type(config.BandwidthMaxUnreliableQueue) == "number" and isInteger(config.BandwidthMaxUnreliableQueue) and config.BandwidthMaxUnreliableQueue >= 1, "BandwidthMaxUnreliableQueue must be an integer >= 1")
	assert(type(config.BandwidthDropUnreliableOnPressure) == "boolean", "BandwidthDropUnreliableOnPressure must be a boolean")
	assert(type(config.BandwidthWarnAtUtilization) == "number" and isFiniteNumber(config.BandwidthWarnAtUtilization) and config.BandwidthWarnAtUtilization > 0 and config.BandwidthWarnAtUtilization <= 1, "BandwidthWarnAtUtilization must be > 0 and <= 1")
	assert(type(config.TransportAdaptiveBatching) == "boolean", "TransportAdaptiveBatching must be a boolean")
	assert(type(config.TransportBatchWindowSeconds) == "number" and isFiniteNumber(config.TransportBatchWindowSeconds) and config.TransportBatchWindowSeconds >= 0 and config.TransportBatchWindowSeconds <= 1, "TransportBatchWindowSeconds must be from 0 to 1")
	assert(type(config.TransportRealtimeBatchWindowSeconds) == "number" and isFiniteNumber(config.TransportRealtimeBatchWindowSeconds) and config.TransportRealtimeBatchWindowSeconds >= 0 and config.TransportRealtimeBatchWindowSeconds <= 1, "TransportRealtimeBatchWindowSeconds must be from 0 to 1")
	assert(type(config.TransportEstimatedPacketOverheadBytes) == "number" and isFiniteNumber(config.TransportEstimatedPacketOverheadBytes) and config.TransportEstimatedPacketOverheadBytes >= 0, "TransportEstimatedPacketOverheadBytes must be >= 0")
	assert(type(config.TransportTargetMessagesPerPacket) == "number" and isInteger(config.TransportTargetMessagesPerPacket) and config.TransportTargetMessagesPerPacket >= 1, "TransportTargetMessagesPerPacket must be an integer >= 1")
	assert(type(config.MaxWriterPoolSize) == "number" and isInteger(config.MaxWriterPoolSize) and config.MaxWriterPoolSize >= 0, "MaxWriterPoolSize must be a non-negative integer")
	assert(type(config.MaxScratchWriterPoolSize) == "number" and isInteger(config.MaxScratchWriterPoolSize) and config.MaxScratchWriterPoolSize >= 0, "MaxScratchWriterPoolSize must be a non-negative integer")
	assert(type(config.InitialWriterBytes) == "number" and isInteger(config.InitialWriterBytes) and config.InitialWriterBytes >= 64, "InitialWriterBytes must be an integer >= 64")
	assert(type(config.FastSchemaEnabled) == "boolean", "FastSchemaEnabled must be a boolean")
	assert(type(config.FastSchemaMaxBytes) == "number" and isInteger(config.FastSchemaMaxBytes) and config.FastSchemaMaxBytes >= 0, "FastSchemaMaxBytes must be a non-negative integer")
	assert(type(config.FastSchemaAllowHeaderExpansion) == "boolean", "FastSchemaAllowHeaderExpansion must be a boolean")
	assert(type(config.PackedSchemaRunEnabled) == "boolean", "PackedSchemaRunEnabled must be a boolean")
	assert(type(config.PackedSchemaRunMaxFields) == "number" and isInteger(config.PackedSchemaRunMaxFields) and config.PackedSchemaRunMaxFields >= 1 and config.PackedSchemaRunMaxFields <= 32, "PackedSchemaRunMaxFields must be an integer from 1 to 32")
	assert(type(config.BitPacketEnabled) == "boolean", "BitPacketEnabled must be boolean")
	assert(type(config.BitPacketCompressedCalls) == "boolean", "BitPacketCompressedCalls must be boolean")
	assert(type(config.HybridCodecEnabled) == "boolean", "HybridCodecEnabled must be boolean")
	assert(type(config.HybridSmallScalarEnabled) == "boolean", "HybridSmallScalarEnabled must be boolean")
	assert(type(config.HybridSmallPacketMaxBits) == "number" and isInteger(config.HybridSmallPacketMaxBits) and config.HybridSmallPacketMaxBits >= 8, "HybridSmallPacketMaxBits must be integer >= 8")
	assert(type(config.HybridSmallStringMaxBytes) == "number" and isInteger(config.HybridSmallStringMaxBytes) and config.HybridSmallStringMaxBytes >= 0 and config.HybridSmallStringMaxBytes <= config.MaxStringBytes, "HybridSmallStringMaxBytes invalid")
	assert(type(config.HybridCompressionThresholdBits) == "number" and isInteger(config.HybridCompressionThresholdBits) and config.HybridCompressionThresholdBits >= 0, "HybridCompressionThresholdBits invalid")
	assert(type(config.HybridMinPhysicalSavingsBytes) == "number" and isInteger(config.HybridMinPhysicalSavingsBytes) and config.HybridMinPhysicalSavingsBytes >= 0, "HybridMinPhysicalSavingsBytes invalid")
	assert(type(config.BitFrameEnabled) == "boolean", "BitFrameEnabled must be boolean")
	assert(type(config.BitFrameMaxBytes) == "number" and isInteger(config.BitFrameMaxBytes) and config.BitFrameMaxBytes >= 16 and config.BitFrameMaxBytes <= config.MaxOutgoingBatchBytes, "BitFrameMaxBytes invalid")
	assert(type(config.BitFrameTinyScalarEnabled) == "boolean", "BitFrameTinyScalarEnabled must be boolean")
	assert(type(config.Debug) == "boolean", "Debug must be a boolean")
end

function NetStream.Configure(options, colonOptions)
	if options == NetStream then
		options = colonOptions
	end
	assert(not started, "NetStream.Configure must be called before the first route is created or Start() is called")
	assert(not destroyed, "NetStream has been destroyed")
	assert(type(options) == "table", "NetStream.Configure expects a table")
	local nextConfig = table.clone(Config)
	for key, value in pairs(options) do
		if DEFAULTS[key] == nil then
			error("Unknown NetStream option: " .. tostring(key), 2)
		end
		nextConfig[key] = value
	end
	Internal.validateConfig(nextConfig)
	Config = nextConfig
	Internal._compressionOptionsCache = nil
	return NetStream
end

function NetStream.Start()
	ensureStarted()
	return NetStream
end

function NetStream.GetConfig()
	return table.clone(Config)
end

function NetStream.IsStarted()
	return started and not destroyed
end

function NetStream.IsDestroyed()
	return destroyed
end

function Internal.newBaseRoute(id, name)
	return {
		Id = id,
		Name = name,
		_head = nil,
		_tail = nil,
		_listenerCount = 0,
	}
end

function Internal.assertCompatibleSchema(existingSchema, spec, label)
	if spec == nil then
		return
	end
	local incoming = Internal.compileSchema(spec, label)
	if not existingSchema or incoming.signature ~= existingSchema.signature then
		error(label .. " does not match the schema already registered for this route", 3)
	end
end

function Internal.applyRouteHandlingOptions(route, options, label)
	if not options then
		return route
	end
	local coalesce = options.Coalesce == true or options.Latest == true or options.Mode == "Latest" or options.Mode == "latest"
	if coalesce then
		route.Coalesce = true
	end
	if options.MaxPerSecond ~= nil then
		assert(type(options.MaxPerSecond) == "number" and isFiniteNumber(options.MaxPerSecond) and options.MaxPerSecond >= 1 and isInteger(options.MaxPerSecond), label .. " MaxPerSecond must be a positive integer")
		route._maxPerSecond = options.MaxPerSecond
		local burst = options.Burst or options.MaxPerSecond
		assert(type(burst) == "number" and isFiniteNumber(burst) and burst >= 1 and isInteger(burst), label .. " Burst must be a positive integer")
		route._burst = burst
		if not route._rateByPlayer then
			route._rateByPlayer = setmetatable({}, { __mode = "k" })
		end
	elseif options.Burst ~= nil then
		error(label .. " Burst requires MaxPerSecond", 3)
	end
	if options.Compression ~= nil then
		assert(type(options.Compression) == "boolean", label .. " Compression must be a boolean")
		route.Compression = options.Compression
	end
	if options.Priority ~= nil then
		assert(options.Priority == "Critical" or options.Priority == "Normal" or options.Priority == "Realtime", label .. " Priority must be Critical, Normal, or Realtime")
		route.Priority = options.Priority
	end
	return route
end

function NetStream.Event(nameOrId, options, colonOptions)
	if nameOrId == NetStream then
		nameOrId, options = options, colonOptions
	end
	ensureStarted()
	local id, name = Internal.resolveId(nameOrId, eventNames, "E:", options and options.Id)
	local route = eventRoutes[id]
	if route then
		if route.Name ~= name then
			if route.Name == tostring(id) and options and options.Id == id then
				route.Name = name
			else
				error(string.format("NetStream event id %d is already registered as %q", id, route.Name), 2)
			end
		end
		if options and options.Unreliable == true then
			route.Unreliable = true
		end
		Internal.assertCompatibleSchema(route._schema, options and options.Schema, "Event " .. name .. " Schema")
		if options and options.Trusted == true then
			route._trusted = true
		end
		if options and options.Immediate == true then
			route.Immediate = true
		end
		Internal.applyRouteHandlingOptions(route, options, "Event " .. name)
		return route
	end
	local base = Internal.newBaseRoute(id, name)
	base.Unreliable = options and options.Unreliable == true or false
	base.Immediate = options and options.Immediate == true or false
	base.Coalesce = false
	base.Compression = options and options.Compression
	base.Priority = options and options.Priority or "Normal"
	base._schema = Internal.compileSchema(options and options.Schema, "Event " .. name .. " Schema")
	base._trusted = options and options.Trusted == true or false
	base._packedEligible = Config.PackedSchemaRunEnabled and base._schema ~= nil and base._schema.fixedBytes ~= nil
		and base._schema.count > 0 and base._schema.count <= Config.PackedSchemaRunMaxFields
	route = setmetatable(base, EventRoute)
	Internal.applyRouteHandlingOptions(route, options, "Event " .. name)
	eventRoutes[id] = route
	return route
end

function NetStream.Unreliable(nameOrId, options, colonOptions)
	if nameOrId == NetStream then
		nameOrId, options = options, colonOptions
	end
	local resolved = if options then table.clone(options) else {}
	resolved.Unreliable = true
	return NetStream.Event(nameOrId, resolved)
end

function NetStream.Function(nameOrId, options, colonOptions)
	if nameOrId == NetStream then
		nameOrId, options = options, colonOptions
	end
	ensureStarted()
	local id, name = Internal.resolveId(nameOrId, functionNames, "F:", options and options.Id)
	if options and options.Priority ~= nil then
		assert(options.Priority == "Critical" or options.Priority == "Normal" or options.Priority == "Realtime", "Function " .. name .. " Priority must be Critical, Normal, or Realtime")
	end
	local route = functionRoutes[id]
	if route then
		if route.Name ~= name then
			if route.Name == tostring(id) and options and options.Id == id then
				route.Name = name
			else
				error(string.format("NetStream function id %d is already registered as %q", id, route.Name), 2)
			end
		end
		Internal.assertCompatibleSchema(route._schema, options and options.Schema, "Function " .. name .. " Schema")
		if options and options.Trusted == true then
			route._trusted = true
		end
		if options and options.Immediate == true then
			route.Immediate = true
		end
		if options and options.Compression ~= nil then
			assert(type(options.Compression) == "boolean", "Function " .. name .. " Compression must be a boolean")
			route.Compression = options.Compression
		end
		if options and options.Priority ~= nil then
			assert(options.Priority == "Critical" or options.Priority == "Normal" or options.Priority == "Realtime", "Function " .. name .. " Priority must be Critical, Normal, or Realtime")
			route.Priority = options.Priority
		end
		return route
	end
	route = setmetatable({
		Id = id,
		Name = name,
		Immediate = options and options.Immediate == true or false,
		Compression = options and options.Compression,
		Priority = options and options.Priority or "Critical",
		_callback = nil,
		_schema = Internal.compileSchema(options and options.Schema, "Function " .. name .. " Schema"),
		_trusted = options and options.Trusted == true or false,
	}, FunctionRoute)
	functionRoutes[id] = route
	return route
end

function NetStream.State(nameOrId, options, colonOptions)
	if nameOrId == NetStream then
		nameOrId, options = options, colonOptions
	end
	ensureStarted()
	local id, name = Internal.resolveId(nameOrId, stateNames, "S:", options and options.Id)
	local route = stateRoutes[id]
	if route then
		if route.Name ~= name then
			if route.Name == tostring(id) and options and options.Id == id then
				route.Name = name
			else
				error(string.format("NetStream state id %d is already registered as %q", id, route.Name), 2)
			end
		end
		Internal.assertCompatibleSchema(route._schema, options and options.Schema, "State " .. name .. " Schema")
		if options and options.Trusted == true then
			route._trusted = true
		end
		if options and options.Immediate == true then
			route.Immediate = true
		end
		Internal.applyRouteHandlingOptions(route, options, "State " .. name)
		return route
	end
	local base = Internal.newBaseRoute(id, name)
	base._schema = Internal.compileSchema(options and options.Schema, "State " .. name .. " Schema")
	if base._schema then
		assert(base._schema.count == 1, "NetStream State schema must contain exactly one type")
	end
	base._trusted = options and options.Trusted == true or false
	base.Immediate = options and options.Immediate == true or false
	base.Coalesce = false
	base.Compression = options and options.Compression
	base.Priority = options and options.Priority or "Normal"
	route = setmetatable(base, StateRoute)
	Internal.applyRouteHandlingOptions(route, options, "State " .. name)
	stateRoutes[id] = route
	return route
end


function NetStream.Define(schema, colonSchema)
	if schema == NetStream then
		schema = colonSchema
	end
	assert(type(schema) == "table", "NetStream.Define expects a table")
	local routes = {}
	for name, spec in pairs(schema) do
		if type(spec) == "number" then
			routes[name] = NetStream.Event(name, { Id = spec })
		elseif type(spec) == "string" then
			if spec == "Function" or spec == "function" then
				routes[name] = NetStream.Function(name)
			elseif spec == "State" or spec == "state" then
				routes[name] = NetStream.State(name)
			elseif spec == "Unreliable" or spec == "unreliable" then
				routes[name] = NetStream.Unreliable(name)
			else
				routes[name] = NetStream.Event(name)
			end
		elseif type(spec) == "table" then
			local kind = spec.Type or spec.Kind or "Event"
			if kind == "Function" or kind == "function" then
				routes[name] = NetStream.Function(name, { Id = spec.Id, Schema = spec.Schema, Trusted = spec.Trusted, Immediate = spec.Immediate, Compression = spec.Compression, Priority = spec.Priority })
			elseif kind == "State" or kind == "state" then
				routes[name] = NetStream.State(name, { Id = spec.Id, Schema = spec.Schema, Trusted = spec.Trusted, Immediate = spec.Immediate, Coalesce = spec.Coalesce, Latest = spec.Latest, Mode = spec.Mode, MaxPerSecond = spec.MaxPerSecond, Burst = spec.Burst, Compression = spec.Compression, Priority = spec.Priority })
			else
				routes[name] = NetStream.Event(name, { Id = spec.Id, Unreliable = spec.Unreliable == true or kind == "Unreliable" or kind == "unreliable", Schema = spec.Schema, Trusted = spec.Trusted, Immediate = spec.Immediate, Coalesce = spec.Coalesce, Latest = spec.Latest, Mode = spec.Mode, MaxPerSecond = spec.MaxPerSecond, Burst = spec.Burst, Compression = spec.Compression, Priority = spec.Priority })
			end
		else
			error("Invalid NetStream.Define entry for " .. tostring(name), 2)
		end
	end
	return routes
end

function Internal.compactKind(spec)
	if type(spec) == "string" then
		if spec == "Function" or spec == "function" then return "Function" end
		if spec == "State" or spec == "state" then return "State" end
		return "Event"
	elseif type(spec) == "table" then
		local kind = spec.Type or spec.Kind or "Event"
		if kind == "Function" or kind == "function" then return "Function" end
		if kind == "State" or kind == "state" then return "State" end
		return "Event"
	end
	return "Event"
end

function NetStream.DefineCompact(schema, colonSchema)
	if schema == NetStream then
		schema = colonSchema
	end
	assert(type(schema) == "table", "NetStream.DefineCompact expects a table")
	local prepared = {}
	local used = { Event = {}, Function = {}, State = {} }
	local pendingNames = { Event = {}, Function = {}, State = {} }
	for name, spec in pairs(schema) do
		assert(type(name) == "string", "NetStream.DefineCompact route names must be strings")
		if type(spec) == "number" then
			prepared[name] = spec
			used.Event[spec] = true
		else
			local kind = Internal.compactKind(spec)
			local copy
			if type(spec) == "table" then
				copy = table.clone(spec)
			elseif type(spec) == "string" then
				copy = { Type = spec }
			else
				error("Invalid NetStream.DefineCompact entry for " .. tostring(name), 2)
			end
			prepared[name] = copy
			if copy.Id ~= nil then
				used[kind][copy.Id] = true
			else
				pendingNames[kind][#pendingNames[kind] + 1] = name
			end
		end
	end
	for _, kind in ipairs({ "Event", "Function", "State" }) do
		table.sort(pendingNames[kind])
		local nextId = 1
		for _, name in ipairs(pendingNames[kind]) do
			while used[kind][nextId] do
				nextId += 1
			end
			prepared[name].Id = nextId
			used[kind][nextId] = true
			nextId += 1
		end
	end
	return NetStream.Define(prepared)
end

function NetStream.Id(name, kind)
	assert(type(name) == "string" and #name > 0, "NetStream.Id expects a non-empty string")
	local prefix = "E:"
	if kind == "Function" or kind == "function" then
		prefix = "F:"
	elseif kind == "State" or kind == "state" then
		prefix = "S:"
	end
	return Internal.hashName(prefix .. name)
end

function NetStream.Float32(value)
	assert(type(value) == "number", "NetStream.Float32 expects a number")
	assert(isFiniteNumber(value) and math.abs(value) <= MAX_FLOAT32, "NetStream.Float32 expects a finite float32-range number")
	return setmetatable({ value }, Float32Tag)
end

function NetStream.RawString(value)
	assert(type(value) == "string", "NetStream.RawString expects a string")
	assert(#value <= Config.MaxStringBytes, "NetStream.RawString exceeds MaxStringBytes")
	return setmetatable({ value }, RawStringTag)
end

function NetStream.Flush()
	ensureStarted()
	local beforeBytes = Stats.SentBytes
	local beforeBatches = Stats.SentBatches
	local beforeMessages = Stats.SentMessages
	Stats.ManualFlushes += 1
	flushAll()
	return Stats.SentBytes - beforeBytes, Stats.SentBatches - beforeBatches, Stats.SentMessages - beforeMessages
end

NetStream.FlushNow = NetStream.Flush

function NetStream.FlushTarget(player)
	ensureStarted()
	if IS_SERVER then
		if player == nil then
			return Internal.flushTargetNow(ALL)
		end
		assert(typeof(player) == "Instance" and player:IsA("Player"), "NetStream.FlushTarget expects a Player or nil for broadcast on the server")
		return Internal.flushTargetNow(player)
	end
	return Internal.flushTargetNow(nil)
end

function NetStream.GetVersion()
	return VERSION
end

function NetStream.GetState(player)
	if IS_SERVER then
		assert(player and player:IsA("Player"), "NetStream.GetState(player) requires a Player on the server")
		return Internal.getPeerState(player)
	end
	return Internal.getPeerState(nil)
end

function NetStream.GetStateSnapshot(player)
	if IS_SERVER then
		assert(player and player:IsA("Player"), "NetStream.GetStateSnapshot(player) requires a Player on the server")
		local state = Internal.peekPeerState(player)
		return if state then table.clone(state) else {}
	end
	local state = Internal.peekPeerState(nil)
	return if state then table.clone(state) else {}
end

function NetStream.GetLastPacketBytes()
	return lastPacketBytes
end

function NetStream.GetLastSendStats()
	return table.clone(Internal.LastSendStats)
end

function NetStream.ConsumeLastSendStats()
	local copy = table.clone(Internal.LastSendStats)
	Internal.clearLastSendStats()
	return copy
end

function NetStream.GetBitFrameStats()
	local physical = Stats.BitFramePhysicalBits
	return {
		PacketsEncoded = Stats.BitFramePacketsEncoded,
		PacketsSent = Stats.BitFramePacketsSent,
		PacketsReceived = Stats.BitFramePacketsReceived,
		MessagesEncoded = Stats.BitFrameMessagesEncoded,
		MessagesDecoded = Stats.BitFrameMessagesDecoded,
		UsefulBits = Stats.BitFrameUsefulBits,
		PhysicalBits = physical,
		PaddingBits = Stats.BitFramePaddingBits,
		ProtocolBytesElided = Stats.BitFrameProtocolBytesElided,
		BatchCountBytesElided = Stats.BitFrameBatchCountBytesElided,
		TinyValues = Stats.BitFrameTinyValues,
		NativeValues = Stats.BitFrameNativeValues,
		CompressedValues = Stats.BitFrameCompressedValues,
		EfficiencyPercent = if physical > 0 then Stats.BitFrameUsefulBits / physical * 100 else 100,
	}
end

function NetStream.ResetStats()
	for key in pairs(Stats) do
		Stats[key] = 0
	end
	overflowWarned = false
	Internal.clearLastSendStats()
	Internal._lastEncodedUsefulBits = 0
	Internal._lastEncodedCodec = "None"
	Internal._lastEncodedProtocolBytesElided = 0
	Internal._lastEncodedBatchCountBytesElided = 0
	trafficWindowStarted = os.clock()
	trafficWindowSentBytes = 0
	trafficWindowReceivedBytes = 0
	trafficWindowSentMessages = 0
	trafficWindowReceivedMessages = 0
	trafficWindowSentBatches = 0
	trafficWindowReceivedBatches = 0
	Internal.trafficWindowEstimatedTransportBytes = 0
	for key in pairs(trafficSnapshot) do
		trafficSnapshot[key] = 0
	end
	table.clear(Internal.bandwidthStates)
	return NetStream
end

function NetStream.GetStats()
	local copy = table.clone(Stats)
	local queuedReliable = 0
	local queuedUnreliable = 0
	if IS_SERVER then
		if broadcastBucket then
			queuedReliable += math.max(0, queueLogicalCount(broadcastBucket.reliable)) + Internal.mapCount(broadcastBucket.latestReliable)
			queuedUnreliable += math.max(0, queueLogicalCount(broadcastBucket.unreliable)) + Internal.mapCount(broadcastBucket.latestUnreliable)
		end
		for _, bucket in pairs(targetBuckets) do
			queuedReliable += math.max(0, queueLogicalCount(bucket.reliable)) + Internal.mapCount(bucket.latestReliable)
			queuedUnreliable += math.max(0, queueLogicalCount(bucket.unreliable)) + Internal.mapCount(bucket.latestUnreliable)
		end
	elseif clientBucket then
		queuedReliable = math.max(0, queueLogicalCount(clientBucket.reliable)) + Internal.mapCount(clientBucket.latestReliable)
		queuedUnreliable = math.max(0, queueLogicalCount(clientBucket.unreliable)) + Internal.mapCount(clientBucket.latestUnreliable)
	end
	copy.QueuedReliable = queuedReliable
	copy.QueuedUnreliable = queuedUnreliable
	copy.PendingCalls = 0
	for _ in pairs(pending) do
		copy.PendingCalls += 1
	end
	copy.DispatchBacklog = if dispatchCount == 0 then 0 else math.max(0, dispatchCount - dispatchHead + 1)
	copy.ActiveTargetBacklog = if IS_SERVER then math.max(0, activeTargetTail - activeTargetHead + 1) else 0
	copy.AverageBatchBytes = if copy.SentBatches > 0 then copy.SentBytes / copy.SentBatches else 0
	copy.AverageMessagesPerBatch = if copy.SentBatches > 0 then copy.SentMessages / copy.SentBatches else 0
	copy.EncodedSentBytes = copy.SentBytes
	copy.EncodedReceivedBytes = copy.ReceivedBytes
	updateTrafficSnapshot()
	for key, value in pairs(trafficSnapshot) do
		copy[key] = value
	end
	copy.MessagePoolSize = #messagePool
	copy.ArgsPoolSize = #argsPool
	copy.WriterPoolSize = #writerPool
	copy.ScratchWriterPoolSize = #scratchWriterPool
	copy.ReaderPoolSize = #readerPool
	copy.BatchPoolSize = #batchPool
	copy.PackedValuePoolSize = #packedValuePool
	copy.CompressionRatio = if copy.CompressionInputBytes > 0 then copy.CompressionOutputBytes / copy.CompressionInputBytes else 1
	copy.CompressionSavingsPercent = if copy.CompressionInputBytes > 0 then (copy.CompressionInputBytes - copy.CompressionOutputBytes) / copy.CompressionInputBytes * 100 else 0
	copy.CompressionBitSavingsPercent = if copy.CompressionInputBits > 0 then copy.CompressionUsefulBitsSaved / copy.CompressionInputBits * 100 else 0
	copy.CompressionPaddingPercent = if copy.CompressionPhysicalBits > 0 then copy.CompressionPaddingBits / copy.CompressionPhysicalBits * 100 else 0
	copy.CompressionVersion = Compression.Version()
	return copy
end

function NetStream.GetRateStats()
	updateTrafficSnapshot()
	return table.clone(trafficSnapshot)
end

function NetStream.GetPerformanceStats()
	local stats = NetStream.GetStats()
	return {
		Version = VERSION,
		FastSchemaEnabled = Config.FastSchemaEnabled,
		FastSchemaSent = stats.FastSchemaSent,
		FastSchemaReceived = stats.FastSchemaReceived,
		FastSchemaBytes = stats.FastSchemaBytes,
		FastSchemaHeaderBytesSaved = stats.FastSchemaHeaderBytesSaved,
		FixedSchemaFastWrites = stats.FixedSchemaFastWrites,
		FixedSchemaFastReads = stats.FixedSchemaFastReads,
		WriterPoolHits = stats.WriterPoolHits,
		ScratchWriterPoolHits = stats.ScratchWriterPoolHits,
		CompressionNativeSizeEstimates = stats.CompressionNativeSizeEstimates,
		CompressionNativeScratchAvoided = stats.CompressionNativeScratchAvoided,
		CompressionOptionsCacheHits = stats.CompressionOptionsCacheHits,
		CompressionStrategyCacheHits = stats.CompressionStrategyCacheHits,
		CompressionStrategyCacheMisses = stats.CompressionStrategyCacheMisses,
		CompressionStrategyCacheLocks = stats.CompressionStrategyCacheLocks,
		CompressionStrategyCacheResamples = stats.CompressionStrategyCacheResamples,
		CompressionStrategyCacheResets = stats.CompressionStrategyCacheResets,
		ReaderPoolHits = stats.ReaderPoolHits,
		ArgsPoolHits = stats.ArgsPoolHits,
		MessagePoolHits = stats.MessagePoolHits,
		PackedSchemaRunEnabled = Config.PackedSchemaRunEnabled,
		BitPacketEnabled = Config.BitPacketEnabled,
		BitPacketCompressedCalls = Config.BitPacketCompressedCalls,
		PackedSchemaRunItems = stats.PackedSchemaRunItems,
		PackedSchemaRunMessages = stats.PackedSchemaRunMessages,
		PackedSchemaRunAppends = stats.PackedSchemaRunAppends,
		PackedValuePoolHits = stats.PackedValuePoolHits,
		ScalarDispatches = stats.ScalarDispatches,
		AverageMessagesPerBatch = stats.AverageMessagesPerBatch,
		AverageBatchBytes = stats.AverageBatchBytes,
	}
end

function NetStream.GetBandwidthStats()
	local rates = NetStream.GetRateStats()
	return {
		Enabled = Config.BandwidthGovernorEnabled,
		LimitBytesPerSecond = Config.BandwidthLimitBytesPerSecond,
		MaxPacketBytes = Config.BandwidthMaxPacketBytes,
		MaxPacketsPerSecond = Config.BandwidthMaxPacketsPerSecond,
		SentBytesPerSecond = rates.SentBytesPerSecond,
		ReceivedBytesPerSecond = rates.ReceivedBytesPerSecond,
		EstimatedTransportBytesPerSecond = rates.EstimatedTransportBytesPerSecond,
		EstimatedPacketOverheadBytes = Config.TransportEstimatedPacketOverheadBytes,
		Utilization = rates.BandwidthUtilization,
		HeadroomBytesPerSecond = rates.BandwidthHeadroomBytesPerSecond,
		DeferredFlushes = Stats.BandwidthDeferredFlushes,
		DeferredBatches = Stats.BandwidthDeferredBatches,
		DeferredBytes = Stats.BandwidthDeferredBytes,
		DroppedUnreliableMessages = Stats.BandwidthDroppedUnreliableMessages,
		QueuePressureDrops = Stats.BandwidthQueuePressureDrops,
		OversizedPackets = Stats.BandwidthOversizedPackets,
		BatchSplits = Stats.BandwidthBatchSplits,
		ThrottleEvents = Stats.BandwidthThrottleEvents,
	}
end

function NetStream.GetTransportStats()
	local rates = NetStream.GetRateStats()
	local sentBatches = Stats.SentBatches
	return {
		AdaptiveBatching = Config.TransportAdaptiveBatching,
		BatchWindowSeconds = Config.TransportBatchWindowSeconds,
		RealtimeBatchWindowSeconds = Config.TransportRealtimeBatchWindowSeconds,
		EstimatedPacketOverheadBytes = Config.TransportEstimatedPacketOverheadBytes,
		TargetMessagesPerPacket = Config.TransportTargetMessagesPerPacket,
		LogicalMessagesQueued = Stats.TransportLogicalMessagesQueued,
		LogicalMessagesSent = Stats.SentMessages,
		TransportPackets = Stats.SentBatches,
		MessagesPerTransportPacket = if sentBatches > 0 then Stats.SentMessages / sentBatches else 0,
		EncodedBytesPerSecond = rates.SentBytesPerSecond,
		EstimatedTransportBytesPerSecond = rates.EstimatedTransportBytesPerSecond,
		PacketRatePerSecond = rates.SentBatchesPerSecond,
		EstimatedUtilization = rates.EstimatedTransportUtilization,
		EstimatedHeadroomBytesPerSecond = rates.EstimatedTransportHeadroomBytesPerSecond,
		BatchHolds = Stats.TransportBatchHolds,
		TargetFlushes = Stats.TransportTargetFlushes,
		ImmediateDeferred = Stats.TransportImmediateDeferred,
		CriticalQueued = Stats.TransportCriticalMessagesQueued,
		NormalQueued = Stats.TransportNormalMessagesQueued,
		RealtimeQueued = Stats.TransportRealtimeMessagesQueued,
		EstimatedOverheadBytes = Stats.TransportEstimatedOverheadBytes,
		EstimatedTransportBytes = Stats.TransportEstimatedBytes,
		CoalescedMessages = Stats.CoalescedLatest,
		DroppedUnreliableMessages = Stats.BandwidthDroppedUnreliableMessages + Stats.DroppedUnreliable,
		DeferredBatches = Stats.BandwidthDeferredBatches,
		BatchSplits = Stats.BandwidthBatchSplits,
		FastSchemaSent = Stats.FastSchemaSent,
		FastSchemaReceived = Stats.FastSchemaReceived,
		FastSchemaHeaderBytesSaved = Stats.FastSchemaHeaderBytesSaved,
		FixedSchemaFastWrites = Stats.FixedSchemaFastWrites,
		FixedSchemaFastReads = Stats.FixedSchemaFastReads,
	}
end

function NetStream.GetHealth()
	local stats = NetStream.GetStats()
	local queued = stats.QueuedReliable + stats.QueuedUnreliable
	local backlog = stats.DispatchBacklog
	local status = "Healthy"
	local queueLimit = if Config.BandwidthGovernorEnabled then Config.BandwidthMaxReliableQueue + Config.BandwidthMaxUnreliableQueue else Config.MaxReliableQueue + Config.MaxUnreliableQueue
	if backlog >= Config.MaxDispatchBacklog * 0.8 or queued >= queueLimit * 0.8 then
		status = "Overloaded"
	elseif backlog >= Config.MaxDispatchBacklog * 0.4 or queued >= queueLimit * 0.4 then
		status = "Congested"
	elseif backlog > 0 or queued > Config.MaxBatchMessages then
		status = "Busy"
	end
	local rates = NetStream.GetRateStats()
	if Config.BandwidthGovernorEnabled and rates.BandwidthUtilization >= Config.BandwidthWarnAtUtilization and status == "Healthy" then
		status = "Busy"
	end
	return {
		Status = status,
		QueuedMessages = queued,
		DispatchBacklog = backlog,
		ActiveTargetBacklog = stats.ActiveTargetBacklog,
		SentBytesPerSecond = rates.SentBytesPerSecond,
		ReceivedBytesPerSecond = rates.ReceivedBytesPerSecond,
		SentMessagesPerSecond = rates.SentMessagesPerSecond,
		ReceivedMessagesPerSecond = rates.ReceivedMessagesPerSecond,
		BandwidthLimitBytesPerSecond = rates.BandwidthLimitBytesPerSecond,
		BandwidthUtilization = rates.BandwidthUtilization,
		BandwidthHeadroomBytesPerSecond = rates.BandwidthHeadroomBytesPerSecond,
		EstimatedTransportBytesPerSecond = rates.EstimatedTransportBytesPerSecond,
		TransportPacketRatePerSecond = rates.SentBatchesPerSecond,
	}
end

function NetStream.GetCompressionStats()
	local stats = NetStream.GetStats()
	return {
		Version = Compression.Version(),
		Enabled = Config.CompressionEnabled,
		Attempts = stats.CompressionAttempts,
		Used = stats.CompressionUsed,
		Rejected = stats.CompressionRejected,
		Errors = stats.CompressionErrors,
		NoGain = stats.CompressionNoGain,
		AcceptancePercent = if stats.CompressionAttempts > 0 then stats.CompressionUsed / stats.CompressionAttempts * 100 else 0,
		Decoded = stats.CompressionDecodeCount,
		InputBytes = stats.CompressionInputBytes,
		OutputBytes = stats.CompressionOutputBytes,
		SavedBytes = stats.CompressionSavedBytes,
		AverageSavedBytes = if stats.CompressionUsed > 0 then stats.CompressionSavedBytes / stats.CompressionUsed else 0,
		SavingsPercent = stats.CompressionSavingsPercent,
		Ratio = stats.CompressionRatio,
		InputBits = stats.CompressionInputBits,
		UsefulBits = stats.CompressionUsefulBits,
		PhysicalBits = stats.CompressionPhysicalBits,
		PaddingBits = stats.CompressionPaddingBits,
		UsefulBitsSaved = stats.CompressionUsefulBitsSaved,
		BitSavingsPercent = stats.CompressionBitSavingsPercent,
		PaddingPercent = stats.CompressionPaddingPercent,
		BitPackedPackets = stats.CompressionBitPackedPackets,
		EntropyCoding = Config.CompressionEntropyCoding,
		EntropyStrategy = Config.CompressionEntropyStrategy,
		HuffmanMinBytes = Config.CompressionHuffmanMinBytes,
		HuffmanMinSavings = Config.CompressionHuffmanMinSavings,
		HuffmanMaxCodeBits = Config.CompressionHuffmanMaxCodeBits,
		RouteStrategyCache = Config.CompressionRouteStrategyCache,
		RouteStrategyWarmup = Config.CompressionRouteStrategyWarmup,
		RouteStrategyResample = Config.CompressionRouteStrategyResample,
		NativeSizeEstimates = stats.CompressionNativeSizeEstimates,
		NativeScratchAvoided = stats.CompressionNativeScratchAvoided,
		OptionsCacheHits = stats.CompressionOptionsCacheHits,
		StrategyCacheHits = stats.CompressionStrategyCacheHits,
		StrategyCacheMisses = stats.CompressionStrategyCacheMisses,
		StrategyCacheLocks = stats.CompressionStrategyCacheLocks,
		StrategyCacheResamples = stats.CompressionStrategyCacheResamples,
		StrategyCacheResets = stats.CompressionStrategyCacheResets,
		AllowExpansion = Config.CompressionAllowExpansion,
		StringStrategy = Config.CompressionStringStrategy,
		BufferStrategy = Config.CompressionBufferStrategy,
		TableStrategy = Config.CompressionTableStrategy,
		TableKeyMapping = Config.CompressionTableKeyMapping,
		CompactTablesUsed = stats.CompressionCompactTableUsed,
		MappedTablesUsed = stats.CompressionMappedTableUsed,
		DynamicTablesUsed = stats.CompressionDynamicTableUsed,
		DirectTablesUsed = stats.CompressionDirectTableUsed,
		TailLengthElisions = stats.CompressionTailLengthElisions,
		CompactSingleSent = stats.CompressionCompactSingleSent,
		CompactSingleReceived = stats.CompressionCompactSingleReceived,
		FramingBytesSaved = stats.CompressionFramingBytesSaved,
		EstimatedNetBytesSaved = stats.CompressionEstimatedNetBytesSaved,
		SingleMessagePackets = stats.SingleMessagePackets,
		SingleMessageHeaderBytesSaved = stats.SingleMessageHeaderBytesSaved,
		CompressedSchemaStrings = stats.CompressedSchemaStrings,
		SchemaStringBytesSaved = stats.SchemaStringBytesSaved,
		CompressedSchemaBuffers = stats.CompressedSchemaBuffers,
		SchemaBufferBytesSaved = stats.SchemaBufferBytesSaved,
		BitPacketCallsSent = stats.BitPacketCallsSent,
		BitPacketCallsReceived = stats.BitPacketCallsReceived,
		BitPacketHeaderBits = stats.BitPacketHeaderBits,
		BitPacketHeaderBitsSaved = stats.BitPacketHeaderBitsSaved,
		BitPacketPaddingBits = stats.BitPacketPaddingBits,
	}
end

function NetStream.GetCompressionBitStats()
	local stats = NetStream.GetStats()
	return {
		InputBits = stats.CompressionInputBits,
		UsefulBits = stats.CompressionUsefulBits,
		PhysicalBits = stats.CompressionPhysicalBits,
		PaddingBits = stats.CompressionPaddingBits,
		UsefulBitsSaved = stats.CompressionUsefulBitsSaved,
		SavingsPercent = stats.CompressionBitSavingsPercent,
		PaddingPercent = stats.CompressionPaddingPercent,
		BitPackedPackets = stats.CompressionBitPackedPackets,
		PacketHeaderBits = stats.BitPacketHeaderBits,
		PacketHeaderBitsSaved = stats.BitPacketHeaderBitsSaved,
		PacketPaddingBits = stats.BitPacketPaddingBits,
		BitPacketCalls = stats.BitPacketCallsSent,
	}
end

function NetStream.UIntBitLength(value)
	return Compression.UIntBitLength(value)
end

function NetStream.IntBitLength(value)
	return Compression.IntBitLength(value)
end

function NetStream.GetCompressionOptions()
	return table.clone(Internal.compressionOptions())
end

function NetStream.GetSupportedTypes()
	return {
		"nil",
		"boolean",
		"number",
		"string",
		"buffer",
		"table",
		"Vector2",
		"Vector3",
		"Color3",
		"CFrame",
		"UDim",
		"UDim2",
		"Rect",
		"NumberRange",
		"BrickColor",
		"DateTime",
	}
end

function NetStream.GetCompatibilityInfo()
	return {
		Version = VERSION,
		CompressionVersion = Compression.Version(),
		BufferUtilVersion = Internal.BufferUtil.VERSION,
		BitFrameEnabled = Config.BitFrameEnabled,
		BitFrameVersion = 1,
		ProtocolHeaderBytes = if Config.BitFrameEnabled then 0 else 1,
		Protocol = Internal.LEGACY_PROTOCOL,
		ProtocolSingle = Internal.LEGACY_PROTOCOL_SINGLE,
		ProtocolCompactTable = Internal.LEGACY_PROTOCOL_COMPACT_TABLE,
		ProtocolFastSchema = Internal.LEGACY_PROTOCOL_FAST_SCHEMA,
		FastSchemaEnabled = Config.FastSchemaEnabled,
		PackedSchemaRunEnabled = Config.PackedSchemaRunEnabled,
		CompressionBitFirst = true,
		CompressionEntropyCoding = Config.CompressionEntropyCoding,
		CompressionFormat = "v2.9-bit-first",
		PacketFormat = if Config.BitFrameEnabled then "v2.1-protocolless-bitframe" else "v2.1-legacy-byte-fallback",
		HybridCodec = "BufferUtil-BitFrame-small/Native-bitstream-medium/Compression-large",
		HybridSmallPacketMaxBits = Config.HybridSmallPacketMaxBits,
		HybridCompressionThresholdBits = Config.HybridCompressionThresholdBits,
		FastDynamicEstimator = true,
		RouteCompressionStrategyCache = Config.CompressionRouteStrategyCache,
		SupportedTypes = 16,
	}
end

function NetStream.AnalyzeCompression(value, options)
	return Compression.Analyze(value, options or Internal.compressionOptions())
end

NetStream.AnalyzeBits = NetStream.AnalyzeCompression

function NetStream.GetHybridCodecStats()
	local physicalBits = Stats.HybridBufferUtilPhysicalBits
	return {
		BufferUtilVersion = Internal.BufferUtil.VERSION,
		Enabled = Config.HybridCodecEnabled,
		BufferUtilSent = Stats.HybridBufferUtilSent,
		BufferUtilReceived = Stats.HybridBufferUtilReceived,
		UsefulBits = Stats.HybridBufferUtilUsefulBits,
		PhysicalBits = physicalBits,
		PaddingBits = Stats.HybridBufferUtilPaddingBits,
		BytesSavedVsNative = Stats.HybridBufferUtilBytesSaved,
		CompressionThresholdSkips = Stats.HybridCompressionThresholdSkips,
		CompressionThresholdAttempts = Stats.HybridCompressionThresholdAttempts,
		BitEfficiencyPercent = if physicalBits > 0 then Stats.HybridBufferUtilUsefulBits / physicalBits * 100 else 0,
	}
end

function NetStream.FormatBytes(bytes)
	assert(type(bytes) == "number" and bytes >= 0, "NetStream.FormatBytes expects a non-negative number")
	local units = { "B", "KB", "MB", "GB" }
	local value = bytes
	local index = 1
	while value >= 1024 and index < #units do
		value /= 1024
		index += 1
	end
	if index == 1 then
		return string.format("%d %s", math.floor(value + 0.5), units[index])
	end
	return string.format("%.2f %s", value, units[index])
end

function NetStream.Destroy()
	if destroyed then
		return
	end
	destroyed = true
	started = false
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	for _, connection in ipairs(receiveConnections) do
		connection:Disconnect()
	end
	table.clear(receiveConnections)
	for id, entry in pairs(pending) do
		pending[id] = nil
		task.spawn(entry.thread, false, "NetStream destroyed")
	end
	for index = dispatchHead, dispatchCount do
		if dispatchScalarFlags[index] ~= true then
			releaseArgs(dispatchArgs[index])
		end
	end
	table.clear(dispatchRoutes)
	table.clear(dispatchPlayers)
	table.clear(dispatchArgs)
	table.clear(dispatchScalarFlags)
	table.clear(dispatchScalarValues)
	dispatchCount = 0
	dispatchHead = 1

	Internal.releaseBucket(clientBucket)
	Internal.releaseBucket(broadcastBucket)
	for _, bucket in pairs(targetBuckets) do
		Internal.releaseBucket(bucket)
	end
	table.clear(targetBuckets)
	table.clear(Internal.bandwidthStates)
	Internal.trafficWindowEstimatedTransportBytes = 0
	clientBucket = nil
	broadcastBucket = nil

	for _, route in pairs(eventRoutes) do
		route:DisconnectAll()
	end
	for _, route in pairs(stateRoutes) do
		route:DisconnectAll()
	end
	for _, route in pairs(functionRoutes) do
		route._callback = nil
	end
	table.clear(eventRoutes)
	table.clear(functionRoutes)
	table.clear(stateRoutes)
	table.clear(eventNames)
	table.clear(functionNames)
	table.clear(stateNames)
	fallbackCallHandler = nil

	table.clear(activeTargets)
	activeTargetHead = 1
	activeTargetTail = 0
	table.clear(incomingRates)
	table.clear(peerStates)
	table.clear(messagePool)
	table.clear(argsPool)
	table.clear(writerPool)
	table.clear(scratchWriterPool)
	table.clear(Internal._nativeMeasurePool)
	Internal._compressionOptionsCache = nil
	table.clear(readerPool)
	table.clear(batchPool)
	table.clear(packedValuePool)
	globalIncomingRate = nil
	trafficWindowStarted = os.clock()
	trafficWindowSentBytes = 0
	trafficWindowReceivedBytes = 0
	trafficWindowSentMessages = 0
	trafficWindowReceivedMessages = 0
	trafficWindowSentBatches = 0
	trafficWindowReceivedBatches = 0
	for key in pairs(trafficSnapshot) do
		trafficSnapshot[key] = 0
	end
	reliableRemote = nil
	unreliableRemote = nil
	accumulator = 0
	timeoutAccumulator = 0
	lastPacketBytes = 0
end

local Codec = {}

function Codec.Encode(...)
	local args = table.pack(...)
	validateArgs(args)
	local packet = Compression.Compress(args, Internal.compressionOptions())
	return packet.Data
end

function Codec.Decode(data)
	assert(typeof(data) == "buffer", "NetStream.Codec.Decode expects a buffer")
	local args = Compression.Decode(data, Internal.compressionOptions())
	assert(typeof(args) == "table" and type(args.n) == "number", "NetStream.Codec.Decode received an invalid Compression payload")
	validateArgs(args)
	return table.unpack(args, 1, args.n)
end

function Codec.TryEncode(...)
	local args = table.pack(...)
	local ok, dataOrError = pcall(function()
		validateArgs(args)
		local packet = Compression.Compress(args, Internal.compressionOptions())
		return packet.Data
	end)
	if ok then return true, dataOrError, nil end
	return false, nil, tostring(dataOrError)
end

function Codec.TryDecode(data)
	local ok, valuesOrError = pcall(function()
		assert(typeof(data) == "buffer", "NetStream.Codec.TryDecode expects a buffer")
		local args = Compression.Decode(data, Internal.compressionOptions())
		assert(typeof(args) == "table" and type(args.n) == "number", "NetStream.Codec.TryDecode received an invalid Compression payload")
		validateArgs(args)
		return args
	end)
	if not ok then return false, nil, tostring(valuesOrError) end
	return true, valuesOrError, nil
end

function Codec.ByteLength(...)
	return buffer.len(Codec.Encode(...))
end

function Codec.Analyze(...)
	local args = table.pack(...)
	validateArgs(args)
	return Compression.Analyze(args, Internal.compressionOptions())
end

NetStream.Codec = Codec
NetStream.Compression = Compression
NetStream.BufferUtil = Internal.BufferUtil
NetStream.CompressionVersion = Compression.Version()


local LegacyBus = {}

function LegacyBus:Connect(id, callback)
	return NetStream.Event(id):Connect(callback)
end

function LegacyBus:Once(id, callback)
	return NetStream.Event(id):Once(callback)
end

function LegacyBus:Fire(id, ...)
	return NetStream.Event(id):Fire(...)
end

function LegacyBus:FireAll(id, ...)
	return NetStream.Event(id):FireAll(...)
end

function LegacyBus:FireToPlayer(player, id, ...)
	return NetStream.Event(id):FireClient(player, ...)
end

function LegacyBus:Call(id, ...)
	return NetStream.Function(id):InvokeServer(...)
end

function LegacyBus:CallToPlayer(player, id, ...)
	return NetStream.Function(id):InvokeClient(player, ...)
end

function LegacyBus:OnCall(callback)
	return NetStream.OnCall(callback)
end

function LegacyBus:StateUpdate(player, id, value)
	return NetStream.State(id):SetClient(player, value, true)
end

function LegacyBus:Move(player, x, y, z)
	return NetStream.Move(player, x, y, z)
end

function LegacyBus:MoveVec(player, value)
	return NetStream.Move(player, value)
end

function NetStream.ReliableEvent()
	ensureStarted()
	return LegacyBus
end

function NetStream.ReliableFunction()
	ensureStarted()
	return LegacyBus
end

function NetStream.Connect(id, callback)
	return NetStream.Event(id):Connect(callback)
end

function NetStream.Once(id, callback)
	return NetStream.Event(id):Once(callback)
end

function NetStream.Fire(id, ...)
	return NetStream.Event(id):Fire(...)
end

function NetStream.FireAll(id, ...)
	return NetStream.Event(id):FireAll(...)
end

function NetStream.FireToPlayer(player, id, ...)
	return NetStream.Event(id):FireClient(player, ...)
end

function NetStream.Call(id, ...)
	return NetStream.Function(id):InvokeServer(...)
end

function NetStream.CallToPlayer(player, id, ...)
	return NetStream.Function(id):InvokeClient(player, ...)
end

function NetStream.OnCall(callback)
	assert(type(callback) == "function" or callback == nil, "NetStream.OnCall expects a function or nil")
	fallbackCallHandler = callback
	ensureStarted()
end

function NetStream.StateUpdate(playerOrId, idOrValue, value)
	if IS_SERVER then
		return NetStream.State(idOrValue):SetClient(playerOrId, value, true)
	end
	return NetStream.State(playerOrId):SetServer(idOrValue, true)
end

function NetStream.SetLatest(playerOrId, idOrValue, value)
	if IS_SERVER then
		return NetStream.State(idOrValue):SetLatestClient(playerOrId, value)
	end
	return NetStream.State(playerOrId):SetLatestServer(idOrValue)
end

local positionState = nil

function NetStream.Move(playerOrPosition, x, y, z)
	if not positionState then
		positionState = NetStream.State("__position")
	end
	if IS_SERVER then
		local player = playerOrPosition
		local position
		if typeof(x) == "Vector3" then
			position = x
		else
			position = Vector3.new(x, y, z)
		end
		return positionState:SetLatestClient(player, position)
	end
	local position
	if typeof(playerOrPosition) == "Vector3" then
		position = playerOrPosition
	else
		position = Vector3.new(playerOrPosition, x, y)
	end
	return positionState:SetLatestServer(position)
end

function NetStream.GetPlayerState(player)
	return NetStream.GetState(player)
end

return NetStream
