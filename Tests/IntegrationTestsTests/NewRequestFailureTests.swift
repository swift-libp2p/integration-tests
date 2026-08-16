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

/// Regression coverage for the `SingleBufferingRequest` promise leak.
///
/// A dial whose security handshake fails (here: an authenticated dial to the host's transport address but
/// with the WRONG expected peer ID) never establishes a stream, so the request's stream-event closure never
/// fires. The request's scheduled timeout must still settle the promise. Previously the timeout captured
/// `[weak self]`, and because the request was only retained by that (now-released) stream closure, it was
/// deallocated and the timeout no-op'd — leaking the promise
///
/// The `.timeLimit` is a safety net: with the fix this rejects within the request timeout (a few seconds);
/// if the leak regresses this fails at the limit instead of freezing the whole test run indefinitely.
@Suite("newRequest failure handling", .serialized)
struct NewRequestFailureTests {
    @Test("Dial to a mismatched peer ID rejects (does not hang)", .timeLimit(.minutes(1)))
    func mismatchedPeerIDDialRejects() async throws {
        try await withPeers(muxer: .yamux, security: .noise) { host, client in
            guard let base = host.listenAddresses.first else {
                Issue.record("host announced no listen address")
                return
            }
            // Encapsulate the host's real ip/tcp address with the WRONG peer ID (the client's own), so the
            // security handshake will yield a peer that doesn't match what we expected.
            let bogusAddr = try base.encapsulate(proto: .p2p, address: client.peerID.b58String)

            do {
                _ = try await client.newRequest(
                    to: bogusAddr,
                    forProtocol: "/echo/1.0.0",
                    withRequest: Data("hello".utf8),
                    withHandlers: .handlers([.newLineDelimited]),
                    withTimeout: .seconds(3)
                ).get()
                Issue.record("newRequest to a mismatched peer ID unexpectedly succeeded")
            } catch {
                // Expected: the request is rejected (times out / fails) rather than hanging forever.
            }
        }
    }
}
