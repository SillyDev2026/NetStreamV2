# NetStreamV2 v4.1.1 — Binary Packet-Size Audit

**Scope:** BitFrame v1, bundled Compression 2.4.2 (codec 230). This report is grounded in `Internal.bitFrameWriteOne`, `finishBitFrameBatch`, `BitFrameWriter:adaptiveUInt` and successful `sendBatch` in `Netstream.lua`. It reports **encoded buffers**, not packet profiler's complete remote-call estimates, internet packets, TLS, or Roblox engine replication. This is an audit of source layout; actual performance still requires a Roblox Studio run.

## Framing grammar

Every BitFrame packet is a chain of messages followed by a single end marker. Per item:
- `PresenceBits`: one bit that says an item follows.
- `KindBits`: two bits encoding Event, State, Call or Return.
- `RouteIdBits`: adaptive unsigned integer for all except Return. For IDs 0–127, 8 bits; 128–16,383, 16 bits.
- `RequestIdBits`: adaptive unsigned integer for calls and returns only.
- `RunMarkerBits`: one bit for schema Event; it says whether consecutive same-route events were packed.
- `RunCountBits`: adaptive unsigned integer only when schema Event has a packed run of two or more.
- `PayloadBits`: actual bits written for schema fields or a dynamic payload, including its mode/data framing; this audit doesn't decompose internal dynamic-payload subfields.
- `EndBits`: one final zero bit per packet.
- `PaddingBits`: zero bits added to complete the final byte.

No separate protocol byte, global message-count field, fixed-size route header or per-message byte alignment appears in BitFrame v1.

## Exact source-derived sizes

For schema Events, if route ID = 1001, adaptive route ID length = 16 bits.

| Sample | Bit formula | Useful bits | Encoded bytes |
|---|---|---:|---:|
| 1 U32 at route 1001 | 1 present + 2 kind + 16 ID + 1 run flag + 32 data + 1 end | 53 | 7 |
| 1 U16 at route 1002 | 1 + 2 + 16 + 1 + 16 + 1 | 37 | 5 |
| 1 U16 at route 1 | 1 + 2 + 8 + 1 + 16 + 1 | 29 | 4 |
| 8 U16 packed, route 1002 | 1 + 2 + 16 + 1 + 8 run count + (8 × 16) + 1 | 157 | 20 |
| 27 U32 packed, route 1001 | 1 + 2 + 16 + 1 + 8 run count + (27 × 32) + 1 | 893 | 112 |
| 27 U16 packed, route 1001 | 1 + 2 + 16 + 1 + 8 run count + (27 × 16) + 1 | 461 | 58 |

Byte lengths round each *complete packet*, not every message, up to a whole byte. Packed-run savings require adjacent schema Events using the same route, appropriate configuration, and actual batching. The eight-message example's aggregate metadata is 29 bits (1+2+16+1+8+1), data 128 bits and padding 3 bits.

## User's measured benchmark context

The supplied stress run was 9,998 U32 logical pings, 369 outgoing batches, 41,468 NetStream encoded outgoing bytes, with 9,998 echoed responses, RTT average 74.861 ms and P95 91.130 ms. Dividing gives ~4.15 encoded bytes per message. The 112-byte example for 27 U32 values is consistent with this aggregate but **does not prove every packet contained exactly 27 messages**. The Packet Profiler screenshot displayed a **14-byte buffer** and an **estimated 28-byte RemoteEvent call**; those are two different accounting scopes. Without a full packet decode, the 14-byte buffer's exact field breakdown remains unknown.

## Instrument the actual game

```luau
local NetStream = require(game:GetService("ReplicatedStorage"):WaitForChild("NetStream"))
NetStream.Configure({PacketSizeAuditEnabled = true}) -- before defining any routes
-- Define routes and run the workload.
local result = NetStream.GetPacketSizeAudit()
print("Last encoded buffer:", result.LastPacket.PhysicalBytes, "bytes")
print("Sent encoded total:", result.Totals.PhysicalBytes, "bytes")
print("Useful:", result.Totals.UsefulBits, "Padding:", result.Totals.PaddingBits)
print("Route IDs:", result.Totals.RouteIdBits, "Payload:", result.Totals.PayloadBits)
```

`GetPacketSizeAudit()` reports `Enabled`, `Codec`, `Scope`, `LastPacket`, and `Totals`. All breakdown fields count **successfully sent** NetStream BitFrame data (not attempts). The toggle defaults to false, avoiding audit allocations and additional calculations during normal gameplay. Audit mode incurs extra CPU/allocations and must be disabled when comparing encoder throughput.

## Correctness and optimization decisions

1. **Keep payload small:** A U16 sequence field saves 16 bits per logical value compared with U32, if 65,535 unique IDs are sufficient between wraparounds.
2. **Compact route identifiers:** Using IDs below 128 saves 8 ID bits *per message or packed run* compared with ID 1001. It doesn't save 8 bits for each value within one run.
3. **Batch repeated schema events:** Repeated U16 pings become one run with a single header. Batching increases queue delay; always measure P95/P99.
4. **Do not squeeze absolute network rate by dropping required actions:** ACK sampling and server-driven autoclick change workload semantics; measure them as separate applications, never as equivalent serialization wins.
5. **Keep Roblox profiler scope separate:** Buffer byte length is exact for NetStream output; remote-call total includes other accounted overhead that this module cannot directly remove.

Use the paired `PacketSizeAuditRegression` tests to check these exact encoded-byte examples in Studio, and then compare the real stress test with audit off/on under a matched workload.
