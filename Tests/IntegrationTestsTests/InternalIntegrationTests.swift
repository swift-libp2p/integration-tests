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
import LibP2PMPLEX
import LibP2PNoise
import LibP2PPlaintext
import LibP2PYAMUX
import Testing

@testable import LibP2P

/// End-to-end ping / echo interop between two real `Application` nodes over a loopback TCP socket,
/// swept across every muxer × security combination.
///
/// Lifecycle (make → configure → startup → shutdown) is delegated to the shared ``withPeers``
/// helper (the networked analogue of `LibP2PTesting.withApp`), so nodes are always torn down — even
/// when an assertion path throws — and ports are auto-picked (`/tcp/0`) so the suite never collides.
extension IntegrationTestSuites {

    @Suite("Internal Integration Tests", .timeLimit(.minutes(5)))
    struct InternalIntegrationTests {

        @Test(arguments: TestMuxer.allCases, TestSecurity.allCases)
        func testLibP2PInternalPingMultiaddr(muxer: TestMuxer, security: TestSecurity) async throws {
            try await withPeers(muxer: muxer.provider, security: security.provider, installEchoOnHost: false) {
                host,
                client in
                let ping = try await client.identify.ping(addr: host.dialableAddress)
                print("Latency: \(ping.nanoseconds) ns")
                #expect(ping.nanoseconds >= 0)
            }
        }

        @Test(arguments: TestMuxer.allCases, TestSecurity.allCases)
        func testLibP2PInternalPingPeer(muxer: TestMuxer, security: TestSecurity) async throws {
            try await withPeers(muxer: muxer.provider, security: security.provider, installEchoOnHost: false) {
                host,
                client in
                try await client.peers.add(peerInfo: host.peerInfo)

                let ping = try await client.identify.ping(peer: host.peerID)
                print("Latency: \(ping.nanoseconds) ns")
                #expect(ping.nanoseconds >= 0)
            }
        }

        @Test(arguments: TestMuxer.allCases, TestSecurity.allCases)
        func testLibP2PInternalPingPeerCascadeMultipleInflightPings(
            muxer: TestMuxer,
            security: TestSecurity
        ) async throws {
            try await withPeers(muxer: muxer.provider, security: security.provider, installEchoOnHost: false) {
                host,
                client in
                try await client.peers.add(peerInfo: host.peerInfo)

                // Note: These pings happen concurrently
                async let latency1 = client.identify.ping(peer: host.peerID)
                async let latency2 = client.identify.ping(peer: host.peerID)
                async let latency3 = client.identify.ping(peer: host.peerID)

                // Even when we await them like this here...
                let ping1 = try await latency1
                let ping2 = try await latency2
                let ping3 = try await latency3

                let connectionCount = try await client.connectionManager.getTotalConnectionCount().get()
                let streamCount = try await client.connectionManager.getTotalStreamCount().get()

                print("Connection Count: \(connectionCount)")
                print("Stream Count: \(streamCount)")

                #expect(connectionCount == 1)
                // 2 streams for ID protocol and 1 stream for all three pings
                #expect(streamCount == 3)

                // All of the pings should be indentical because all three calls where cascaded into one
                #expect(ping1 == ping2)
                #expect(ping2 == ping3)
            }
        }

        @Test(arguments: TestMuxer.allCases, TestSecurity.allCases)
        func testLibP2PInternalPingPeerSequentialPingsUseSameConnection(
            muxer: TestMuxer,
            security: TestSecurity
        ) async throws {
            try await withPeers(muxer: muxer.provider, security: security.provider, installEchoOnHost: false) {
                host,
                client in
                try await client.peers.add(peerInfo: host.peerInfo)

                // Note: These pings happen sequentially
                let ping1 = try await client.identify.ping(peer: host.peerID)
                let ping2 = try await client.identify.ping(peer: host.peerID)
                let ping3 = try await client.identify.ping(peer: host.peerID)

                let connectionCount = try await client.connectionManager.getTotalConnectionCount().get()
                let streamCount = try await client.connectionManager.getTotalStreamCount().get()

                print("Connection Count: \(connectionCount)")
                print("Stream Count: \(streamCount)")

                #expect(connectionCount == 1)
                // 2 streams for ID protocol and 1 stream for each of the 3 pings
                #expect(streamCount == 5)

                // All three pings should be different because they happened sequentially
                #expect(ping1 != ping2)
                #expect(ping2 != ping3)
            }
        }

        @Test(arguments: TestMuxer.allCases, TestSecurity.allCases)
        func testInternalInterop(muxer: TestMuxer, security: TestSecurity) async throws {
            try await withPeers(muxer: muxer.provider, security: security.provider) { host, client in
                let message = Data("Hello Swift LibP2P".utf8)

                /// Fire off an echo request
                let response = try await client.newRequest(
                    to: host.dialableAddress,
                    forProtocol: "/echo/1.0.0",
                    withRequest: message,
                    withHandlers: .handlers([.newLineDelimited])
                ).get()

                #expect(response == message)

                try await Task.sleep(for: .milliseconds(10))
            }
        }

        @Test(.timeLimit(.minutes(2)), arguments: TestMuxer.allCases, TestSecurity.allCases)
        func testInternalInteropMultipleRequests_Sequentially(muxer: TestMuxer, security: TestSecurity) async throws {
            await withKnownIssue("Sometimes these tests timeout", isIntermittent: true) {
                try await withPeers(muxer: muxer.provider, security: security.provider) { host, client in
                    let addr = try host.dialableAddress
                    let message = Data("Hello Swift LibP2P".utf8)
                    let numberOfRequests = 500

                    // Yamux handles 10_000 requests in ~40 seconds
                    for _ in 0..<numberOfRequests {
                        /// Fire off an echo request
                        let response = try await client.newRequest(
                            to: addr,
                            forProtocol: "/echo/1.0.0",
                            withRequest: message,
                            withHandlers: .handlers([.newLineDelimited])
                        ).get()

                        #expect(response == message)
                    }

                    try await Task.sleep(for: .milliseconds(10))

                    let connections = try await host.connectionManager.getTotalConnectionCount().get()
                    let streams = try await host.connectionManager.getTotalStreamCount().get()

                    #expect(connections == 1)
                    #expect(streams == numberOfRequests + 2)
                }
            }
        }

        @Test(.timeLimit(.minutes(2)), arguments: TestMuxer.allCases, TestSecurity.allCases)
        func testInternalInteropMultipleBidirectionalRequests_Sequentially(
            muxer: TestMuxer,
            security: TestSecurity
        ) async throws {
            await withKnownIssue("Sometimes these tests timeout", isIntermittent: true) {
                try await withPeers(
                    muxer: muxer.provider,
                    security: security.provider,
                    installEchoOnHost: true,
                    installEchoOnClient: true
                ) { peer1, peer2 in
                    let peer1Address = try peer1.dialableAddress
                    let peer2Address = try peer2.dialableAddress
                    let numberOfRequests = 500

                    // Yamux handles 10_000 requests in ~40 seconds
                    for _ in 0..<numberOfRequests {
                        /// Fire off an echo request
                        async let p1ToP2 = peer1.newRequest(
                            to: peer2Address,
                            forProtocol: "/echo/1.0.0",
                            withRequest: Data("Hello from peer1".utf8),
                            withHandlers: .handlers([.newLineDelimited])
                        ).get()

                        /// Fire off an echo request
                        async let p2ToP1 = peer2.newRequest(
                            to: peer1Address,
                            forProtocol: "/echo/1.0.0",
                            withRequest: Data("Hello from peer2".utf8),
                            withHandlers: .handlers([.newLineDelimited])
                        ).get()

                        let responses = try await [p1ToP2, p2ToP1]
                        #expect(responses.first == Data("Hello from peer1".utf8))
                        #expect(responses.last == Data("Hello from peer2".utf8))
                    }

                    try await Task.sleep(for: .milliseconds(10))

                    let connectionsP1 = try await peer1.connectionManager.getTotalConnectionCount().get()
                    let streamsP1 = try await peer1.connectionManager.getTotalStreamCount().get()

                    #expect(connectionsP1 == 2)
                    #expect(streamsP1 == (numberOfRequests + 2) * 2)

                    let connectionsP2 = try await peer2.connectionManager.getTotalConnectionCount().get()
                    let streamsP2 = try await peer2.connectionManager.getTotalStreamCount().get()

                    #expect(connectionsP2 == 2)
                    #expect(streamsP2 == (numberOfRequests + 2) * 2)
                }
            }
        }
    }

}
