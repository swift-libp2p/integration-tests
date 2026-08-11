# LibP2P Integration Tests

[![](https://img.shields.io/badge/made%20by-Breth-blue.svg?style=flat-square)](https://breth.app)
[![](https://img.shields.io/badge/project-libp2p-yellow.svg?style=flat-square)](http://libp2p.io/)
[![Swift Package Manager compatible](https://img.shields.io/badge/SPM-compatible-blue.svg?style=flat-square)](https://github.com/apple/swift-package-manager)
![Build & Test (macos and linux)](https://github.com/swift-libp2p/integration-tests/actions/workflows/build+test.yml/badge.svg)

> Integration tests for swift-libp2p

## Table of Contents

- [Overview](#overview)
- [Test Suites](#test-suites)
- [Shared Helpers](#shared-helpers)
- [Running the Tests](#running-the-tests)
- [Known Gaps](#known-gaps)
- [Contributing](#contributing)
- [Credits](#credits)
- [License](#license)

## Overview

End-to-end integration tests for [swift-libp2p](https://github.com/swift-libp2p/swift-libp2p.git). Unlike the unit tests in the `swift-libp2p` package (which drive components in isolation, often over `EmbeddedChannel`), these tests stand up **real `Application` nodes** and exercise the full stack over a loopback TCP socket — security handshakes, muxer negotiation, protocol multistream-select, Identify, the peerstore, the connection manager and the event bus.

Most suites are parameterized over the full **transport matrix**:

| Muxer | Security |
| --- | --- |
| yamux | noise |
| mplex | plaintext (v2) |

The tests pull in the real conformers as dependencies — `swift-libp2p-{yamux,mplex,noise,plaintext}` — so a green run means those implementations interoperate against the current `swift-libp2p` working copy.

#### Note:
- For more information check out the [LibP2P Spec](https://github.com/libp2p/specs)

## Test Suites

Every suite that stands up real nodes is nested under a single parent suite, `IntegrationTestSuites`, which carries the `.serialized` trait so the whole networked tree runs **one test at a time**. This is deliberate: letting a dozen node pairs race in parallel starves the loopback path badly enough that the slowest transport combinations intermittently exceed their request timeouts.

| Suite | What it verifies |
| --- | --- |
| `InternalIntegrationTests` | Ping (by multiaddr and by peer) and echo interop between two nodes, connection/stream reuse counts, and high-volume sequential + bidirectional echo throughput. |
| `EventNotificationTests` | The full connection/stream lifecycle (`connected`, `upgraded`, `remotePeer`, `openedStream`, `closedStream`, `identifiedPeer`, `disconnected`) is published on the event bus for both the dialer and the listener. |
| `PeerStoreTests` | Identify populates the dialer's peerstore with the remote peer's protocols, key and addresses; the reverse protocol index resolves; and manually-added `PeerInfo` is stored. |
| `TopologyTests` | A topology notifiee registered for a protocol is told when a supporting peer connects and disconnects — and is *not* notified for an unsupported protocol. |
| `IdleTeardownTests` | Once a connection's muxed streams close, the idle connection reaps itself (the default `ARCConnection` self-close, and the connection manager's automatic-stream-counting reaper with a custom idle timeout). |
| `ConnectionReuseTests` | Sequential requests reuse a single connection; concurrent requests over an established connection reuse it; and (see [Known Gaps](#known-gaps)) concurrent *cold* dials to the same peer. |
| `ListenAddressTests` | Automatic port-picking (`/tcp/0`) yields a concrete, non-zero, dialable announced address, and two nodes receive distinct ports. |
| `InMemoryResponderTests` | Drives a route through the responder in-memory (no transport) via the `LibP2PTestUtils` `TestingApplicationTester`. Not networked, so it lives outside the serialized tree. |
| `ExternalIntegrationTests` | Pings a real public IPFS node. Marked intermittent (`withKnownIssue`) — the remote is fickle, so use sparingly. Left outside the serialized tree. |

## Shared Helpers

`Tests/IntegrationTestsTests/TestHelpers.swift` provides a small `withApp`-style toolkit shared by every suite (`LibP2PTesting` re-exports `LibP2P` + `LibP2PTestUtils`, so its `withApp`, in-memory tester and
`ByteBuffer.string` conveniences are available):

- `TestMuxer` / `TestSecurity` — `CaseIterable` enums used to drive the parameterized matrix.
- `makeNode(...)` — builds a configured (not yet started) node; binds `/tcp/0` by default.
- `withNode { app in ... }` / `withPeers { host, client in ... }` — scoped lifecycle that **guarantees
  `asyncShutdown` even when the body throws**.
- `installEchoRoute(_:)` — registers a line-delimited `/echo/1.0.0` route.
- `Application.dialableAddress` — the announced listen address encapsulated with the node's `PeerID`.
- `Application.echo(_:to:timeout:)` — fires an echo request with a generous timeout.
- `waitUntil(...)` — polls for asynchronously-delivered state (events, teardown).
- `EventRecorder` — subscribes to the whole connection-lifecycle event set and records what arrives.

## Running the Tests

This package is primarily intended to run in GitHub CI workflows against
[swift-libp2p](https://github.com/swift-libp2p/swift-libp2p.git), but it can be run locally too:

```sh
# Everything (includes the public-node External test and the high-volume interop tests)
swift test

# A single suite
swift test --filter EventNotificationTests

# A single test
swift test --filter PeerStoreTests/identifyPopulatesTheDialersPeerStore
```

Notes:
- The `ExternalIntegrationTests` suite reaches out to a public IPFS node and is intermittent by design; skip it (or expect the occasional known failure) when offline.
- The high-volume `InternalIntegrationTests` interop tests fire hundreds of requests and can take a little longer.

## Known Gaps

- **Concurrent cold-dial coalescing.** Several requests dialed *simultaneously from cold* to the same peer via `newRequest(to: Multiaddr)` currently open one connection each rather than coalescing onto a single connection (address-based dialing has no in-flight dial de-duplication). The desired end-state is captured by `ConnectionReuseTests/concurrentColdDialsToSamePeerShouldCoalesce`, wrapped in `withKnownIssue` so the suite stays green while recording the deviation — it will start failing (and thereby flag that the guard can be removed) once dial coalescing is implemented. Note that concurrent *pings* to the same peer, and concurrent requests over an *already-established* connection, both already reuse a single connection.

## Contributing

Contributions are welcomed! This code is very much a proof of concept. I can guarantee you there's a better / safer way to accomplish the same results. Any suggestions, improvements, or even just critiques, are welcome!

Let's make this code better together! 🤝


## Credits

- [LibP2P Spec](https://github.com/libp2p/specs)

## License

[MIT](LICENSE) © 2026 Breth Inc.
