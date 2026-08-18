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

import Foundation
import LibP2P
import LibP2PTesting
import Testing

extension IntegrationTestSuites {
    /// Regression coverage for the `SingleBufferingRequest` promise leak and the connection-teardown drain that
    /// makes a failed dial fail fast.
    ///
    /// A dial whose security handshake fails (here: an authenticated dial to the host's transport address but
    /// with the WRONG expected peer ID) never establishes a stream, so the request's stream-event closure never
    /// fires on its own. Two things must hold:
    ///  1. The request must still settle (it must not wait forever) — previously the `[weak self]` timeout no-op'd after
    ///     the request was deallocated, leaking the promise forever.
    ///  2. It must settle quickly — when the connection is torn down mid-handshake, Connections are expected to deliver
    ///     an error to every queued stream request, so callers fail fast instead of waiting out their request timeout.
    ///
    /// The `.timeLimit` is a coarse safety net; the `elapsed` assertion is the real fail-fast check (a large
    /// request timeout is used so that a regression to slow-fail would blow past the `elapsed` bound).
    @Suite("newRequest failure handling", .serialized)
    struct NewRequestFailureTests {
        @Test("Dial to a mismatched peer ID rejects quickly (does not wait the timeout)", .timeLimit(.minutes(1)))
        func mismatchedPeerIDDialRejectsFast() async throws {
            try await withPeers(muxer: .yamux, security: .noise) { host, client in
                guard let base = host.listenAddresses.first else {
                    Issue.record("host announced no listen address")
                    return
                }
                // Encapsulate the host's real ip/tcp address with the WRONG peer ID (the client's own), so the
                // security handshake yields a peer that doesn't match what we expected.
                let bogusAddr = try base.encapsulate(proto: .p2p, address: client.peerID.b58String)

                let start = Date()
                do {
                    _ = try await client.newRequest(
                        to: bogusAddr,
                        forProtocol: "/echo/1.0.0",
                        withRequest: Data("hello".utf8),
                        withHandlers: .handlers([.newLineDelimited]),
                        // Deliberately generous: the teardown drain should reject well before this fires. If the
                        // drain regresses, the request would only settle at this timeout and trigger the `elapsed`
                        // assertion below.
                        withTimeout: .seconds(10)
                    ).get()
                    Issue.record("newRequest to a mismatched peer ID unexpectedly succeeded")
                } catch {
                    let elapsed = Date().timeIntervalSince(start)
                    #expect(
                        elapsed < 3,
                        "expected fast rejection via the connection-teardown drain, but it took \(elapsed)s (looks like it waited for the request timeout instead)"
                    )
                }
            }
        }
    }
}
