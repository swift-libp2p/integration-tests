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

import LibP2PMPLEX
import LibP2PNoise
import LibP2PPlaintext
import LibP2PYAMUX
import Testing

@testable import LibP2P

extension IntegrationTestSuites {
    /// Reaches out to real public IPFS nodes. Marked intermittent because reality
    @Suite("External Integration Tests", .serialized, .timeLimit(.minutes(5)))
    struct ExternalIntegrationTests {

        @Test func testExternalPingMultiaddr() async throws {
            await withKnownIssue("Sometimes we cant reach the external node...", isIntermittent: true) {
                try await withNode(muxer: .yamux, security: .noise) { app in
                    let ma = try Multiaddr(
                        "/ip4/104.131.131.82/tcp/4001/p2p/QmaCpDMGvV2BGHeYERUEnRQAwe3N8SzbUtfsmvsqQLuvuJ"
                    )

                    let ping = try await app.identify.ping(addr: ma)
                    print("Latency: \(ping.nanoseconds) ns")
                    #expect(ping.nanoseconds >= 0)

                    let peerInfo = try await app.peers.getPeerInfo(byAddress: ma, on: nil).get()
                    #expect(peerInfo.peer.b58String == "QmaCpDMGvV2BGHeYERUEnRQAwe3N8SzbUtfsmvsqQLuvuJ")
                    #expect(peerInfo.addresses.contains(where: { $0 == ma }))
                }
            }
        }

        @Test func testExternalPingMultiaddrFromDNS() async throws {
            await withKnownIssue("Sometimes we cant reach the external node...", isIntermittent: true) {
                try await withNode(muxer: .yamux, security: .noise) { app in
                    let ma = try Multiaddr(
                        "/dns/sv15.bootstrap.libp2p.io/tcp/4001/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
                    )

                    let ping = try await app.identify.ping(addr: ma)
                    print("Latency: \(ping.nanoseconds) ns")
                    #expect(ping.nanoseconds >= 0)

                    let peerInfo = try await app.peers.getPeerInfo(
                        byID: "QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
                        on: nil
                    ).get()
                    #expect(peerInfo.peer.b58String == "QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN")
                    #expect(!peerInfo.addresses.isEmpty)
                }
            }
        }
    }
}
