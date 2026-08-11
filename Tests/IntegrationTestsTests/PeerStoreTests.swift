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
import Testing

@testable import LibP2P

/// Verifies that dialing a peer and letting Identify run populates the dialer's `PeerStore` with the
/// remote peer's key, addresses and advertised protocols.
extension IntegrationTestSuites {

    @Suite("PeerStore Tests", .timeLimit(.minutes(2)))
    struct PeerStoreTests {

        @Test(arguments: TestMuxer.allCases, TestSecurity.allCases)
        func identifyPopulatesTheDialersPeerStore(muxer: TestMuxer, security: TestSecurity) async throws {
            try await withPeers(muxer: muxer.provider, security: security.provider) { host, client in
                // A single echo request establishes the connection and triggers Identify.
                _ = try await client.echo(Data("peerstore".utf8), to: host.dialableAddress)

                // Identify updates the peerstore asynchronously, so poll until the protocols land.
                let learnedProtocols = await waitUntil {
                    let protos = (try? await client.peers.getProtocols(forPeer: host.peerID).get()) ?? []
                    return !protos.isEmpty
                }
                #expect(learnedProtocols)

                let protocols = try await client.peers.getProtocols(forPeer: host.peerID).get()
                #expect(!protocols.isEmpty)
                // The host advertises its registered echo route via Identify.
                #expect(protocols.contains { $0.stringValue.contains("/echo/1.0.0") })

                // The remote peer's key is retrievable and matches.
                let key = try await client.peers.getKey(forPeer: host.peerID.b58String).get()
                #expect(key == host.peerID)

                // ...as are the addresses Identify shared.
                let addresses = try await client.peers.getAddresses(forPeer: host.peerID).get()
                #expect(!addresses.isEmpty)

                // And the reverse index resolves the host by the echo protocol it supports.
                let supporting = try await client.peers.getPeers(supportingProtocol: SemVerProtocol("/echo/1.0.0")!)
                    .get()
                #expect(supporting.contains(host.peerID.b58String))
            }
        }

        @Test func manuallyAddedPeerInfoIsStored() async throws {
            try await withPeers(installEchoOnHost: false) { host, client in
                try await client.peers.add(peerInfo: host.peerInfo)

                let key = try await client.peers.getKey(forPeer: host.peerID.b58String).get()
                #expect(key == host.peerID)

                let addresses = try await client.peers.getAddresses(forPeer: host.peerID).get()
                #expect(!addresses.isEmpty)
            }
        }
    }

}
