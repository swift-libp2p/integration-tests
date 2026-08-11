//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-libp2p open source project
//
// Copyright (c) 2022-2025 swift-libp2p project authors
// Licensed under MIT
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of swift-libp2p project authors
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

import Testing

/// Parent suite that owns every suite which stands up *real* nodes over a loopback socket.
///
/// The `.serialized` trait runs the whole tree one test at a time. This is deliberate: each nested
/// suite spins up two libp2p nodes doing real security + muxer handshakes, and letting a dozen of
/// them race in parallel starves the loopback path badly enough that the slowest transport combos
/// (notably mplex + plaintext) intermittently exceed their request timeouts. Serializing keeps the
/// integration run deterministic — and mirrors the original single-serialized-suite design.
///
/// The non-networked ``InMemoryResponderTests`` and the deliberately-isolated
/// ``ExternalIntegrationTests`` are intentionally left outside this tree.
@Suite("swift-libp2p Integration Tests", .serialized)
enum IntegrationTestSuites {}
