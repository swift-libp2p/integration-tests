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
import Testing

@testable import LibP2P

/// Verifies that a real connection driven end-to-end over a socket publishes the full connection /
/// stream lifecycle on the `Application`'s `EventBus`.
///
/// The `LibP2PTests` unit suite can only cover these as post→subscriber contract tests, because the
/// `connected` / `upgraded` / `openedStream` / `closedStream` events are posted deep inside the
/// secure→mux→negotiate flow that can't be driven off-network. Here they fire for real.
extension IntegrationTestSuites {

    @Suite("Event Notification Tests", .timeLimit(.minutes(2)))
    struct EventNotificationTests {

        @Test(arguments: TestMuxer.allCases, TestSecurity.allCases)
        func fullConnectionLifecycleIsPublished(muxer: TestMuxer, security: TestSecurity) async throws {
            try await withPeers(muxer: muxer.provider, security: security.provider) { host, client in
                let recorder = EventRecorder()
                recorder.subscribe(to: client)

                let message = Data("events".utf8)
                #expect(try await client.echo(message, to: host.dialableAddress) == message)

                // The core connection-establishment events must all fire on the dialer.
                #expect(await waitUntil { recorder.contains("remotePeer") })
                #expect(await waitUntil { recorder.contains("connected") })
                #expect(await waitUntil { recorder.contains("upgraded") })
                // A real muxed sub-stream was opened for the echo request and then closed.
                #expect(await waitUntil { recorder.contains("openedStream") })
                #expect(await waitUntil { recorder.contains("closedStream") })
                // Identify runs automatically on upgrade and reports the identified peer.
                #expect(await waitUntil { recorder.contains("identifiedPeer") })

                // Tearing the connection down publishes `disconnected` (while the app is still running).
                _ = try await client.connections.closeConnectionsToPeer(peer: host.peerID, on: nil).get()
                #expect(await waitUntil { recorder.contains("disconnected") })
            }
        }

        /// The listener side of the very same exchange must observe the mirror-image lifecycle for its
        /// inbound connection.
        @Test(arguments: TestMuxer.allCases)
        func listenerObservesInboundConnectionLifecycle(muxer: TestMuxer) async throws {
            try await withPeers(muxer: muxer.provider, security: TestSecurity.noise.provider) { host, client in
                let hostRecorder = EventRecorder()
                hostRecorder.subscribe(to: host)

                _ = try await client.echo(Data("inbound".utf8), to: host.dialableAddress)

                // The core connection-establishment events must all fire on the host.
                #expect(await waitUntil { hostRecorder.contains("remotePeer") })
                #expect(await waitUntil { hostRecorder.contains("connected") })
                #expect(await waitUntil { hostRecorder.contains("upgraded") })
                // A real muxed sub-stream was opened for the echo request and then closed.
                #expect(await waitUntil { hostRecorder.contains("openedStream") })
                #expect(await waitUntil { hostRecorder.contains("closedStream") })
                // Identify runs automatically on upgrade and reports the identified peer.
                #expect(await waitUntil { hostRecorder.contains("identifiedPeer") })
                // Tearing the connection down publishes `disconnected` (while the app is still running).
                #expect(await waitUntil { hostRecorder.contains("disconnected") })
            }
        }
    }

}
