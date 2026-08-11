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
import LibP2PCore
import NIOConcurrencyHelpers
import Testing

@testable import LibP2P

/// Verifies the `Topology` registration surface: a notifiee registered for a protocol is told when a
/// connected peer that supports that protocol is discovered (via Identify) and when it disconnects.
extension IntegrationTestSuites {

    @Suite("Topology Tests", .timeLimit(.minutes(2)))
    struct TopologyTests {

        @Test(arguments: TestMuxer.allCases, TestSecurity.allCases)
        func topologyNotifiesOnConnectAndDisconnect(muxer: TestMuxer, security: TestSecurity) async throws {
            try await withPeers(muxer: muxer.provider, security: security.provider) { host, client in
                let connectedPeer = NIOLockedValueBox<String?>(nil)
                let disconnectedPeer = NIOLockedValueBox<String?>(nil)

                // The client watches for peers that support the host's `/echo/1.0.0` protocol.
                client.topology.register(
                    TopologyRegistration(
                        protocol: "/echo/1.0.0",
                        handler: TopologyHandler(
                            onConnect: { peer, _ in connectedPeer.withLockedValue { $0 = peer.b58String } },
                            onDisconnect: { peer in disconnectedPeer.withLockedValue { $0 = peer.b58String } }
                        )
                    )
                )

                _ = try await client.echo(Data("topology".utf8), to: host.dialableAddress)

                // Once Identify tells the client the host speaks `/echo/1.0.0`, onConnect must fire with it.
                #expect(await waitUntil { connectedPeer.withLockedValue { $0 } == host.peerID.b58String })

                // Closing the connection fires onDisconnect for the same peer.
                _ = try await client.connections.closeConnectionsToPeer(peer: host.peerID, on: nil).get()
                #expect(await waitUntil { disconnectedPeer.withLockedValue { $0 } == host.peerID.b58String })
            }
        }

        /// A topology registered for a protocol nobody advertises must never be notified.
        @Test func topologyIsNotNotifiedForUnsupportedProtocol() async throws {
            try await withPeers { host, client in
                let notified = NIOLockedValueBox<Bool>(false)
                client.topology.register(
                    TopologyRegistration(
                        protocol: "/no-such-protocol/9.9.9",
                        handler: TopologyHandler(onConnect: { _, _ in notified.withLockedValue { $0 = true } })
                    )
                )

                _ = try await client.echo(Data("topology".utf8), to: host.dialableAddress)

                // Give Identify a generous window; the handler must never fire for an unsupported protocol.
                let fired = await waitUntil(attempts: 50) { notified.withLockedValue { $0 } }
                #expect(fired == false)
            }
        }
    }

}
