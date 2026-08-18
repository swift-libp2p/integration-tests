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

/// Verifies connection re-use: repeated requests to the same peer over the same transport ride a
/// single connection rather than opening one per request.
///
/// `getTotalConnectionCount()` is a monotonic counter of every connection ever opened, so asserting
/// it stays `1` is immune to the idle-teardown timing that a live count would be subject to.
extension IntegrationTestSuites {

    @Suite("Connection Reuse Tests", .timeLimit(.minutes(2)))
    struct ConnectionReuseTests {

        @Test(arguments: TestMuxer.allCases, TestSecurity.allCases)
        func sequentialRequestsReuseASingleConnection(muxer: TestMuxer, security: TestSecurity) async throws {
            try await withPeers(muxer: muxer.provider, security: security.provider) { host, client in
                let addr = try host.dialableAddress
                let message = Data("reuse".utf8)

                // Fire back-to-back so the warm connection is reused before any idle reaping.
                for _ in 0..<10 {
                    #expect(try await client.echo(message, to: addr) == message)
                }

                let total = try await client.connectionManager.getTotalConnectionCount().get()
                #expect(total == 1)
            }
        }

        /// Concurrent requests issued while a connection is already established must ride the existing
        /// connection rather than each dialing a new one.
        @Test(arguments: TestMuxer.allCases, TestSecurity.allCases)
        func concurrentRequestsReuseAnEstablishedConnection(muxer: TestMuxer, security: TestSecurity) async throws {
            try await withPeers(muxer: muxer.provider, security: security.provider) { host, client in
                let addr = try host.dialableAddress
                let message = Data("warm".utf8)

                // Establish (and warm) a single connection first.
                #expect(try await client.echo(message, to: addr) == message)

                // Now fan out concurrent requests onto the established connection.
                try await withThrowingTaskGroup(of: Data.self) { group in
                    for _ in 0..<10 {
                        group.addTask { try await client.echo(message, to: addr) }
                    }
                    for try await response in group {
                        #expect(response == message)
                    }
                }

                let total = try await client.connectionManager.getTotalConnectionCount().get()
                #expect(total == 1)
            }
        }

        /// Several requests dialed simultaneously from cold to the same multiaddr must coalesce onto a
        /// single connection: the first dial establishes the connection and the rest ride it once it
        /// upgrades, rather than each opening its own.
        @Test func concurrentColdDialsToSamePeerShouldCoalesce() async throws {
            try await withPeers { host, client in
                let addr = try host.dialableAddress
                let message = Data("cold".utf8)

                try await withThrowingTaskGroup(of: Data.self) { group in
                    for _ in 0..<8 {
                        group.addTask { try await client.echo(message, to: addr) }
                    }
                    // Every coalesced request still gets its own correct echo back.
                    for try await response in group {
                        #expect(response == message)
                    }
                }

                let total = try await client.connectionManager.getTotalConnectionCount().get()
                #expect(total == 1)
            }
        }

        /// Coalescing keys on the dialed multiaddr, so concurrent cold dials to two different peers must
        /// stay independent — one connection per peer, never collapsed together.
        @Test func concurrentColdDialsToDifferentPeersStayIndependent() async throws {
            try await withPeers { hostA, client in
                try await withNode(installEcho: true) { hostB in
                    let addrA = try hostA.dialableAddress
                    let addrB = try hostB.dialableAddress
                    let message = Data("independent".utf8)

                    try await withThrowingTaskGroup(of: Data.self) { group in
                        for _ in 0..<4 {
                            group.addTask { try await client.echo(message, to: addrA) }
                            group.addTask { try await client.echo(message, to: addrB) }
                        }
                        for try await response in group {
                            #expect(response == message)
                        }
                    }

                    // One connection to each distinct peer — the two dial targets did not coalesce.
                    let total = try await client.connectionManager.getTotalConnectionCount().get()
                    #expect(total == 2)
                }
            }
        }

        /// When the underlying connection a batch of coalesced cold dials is riding fails to upgrade,
        /// every queued request must fail (fast) rather than waiting on a connection that will never
        /// be upgraded.
        @Test func concurrentColdDialsThatFailToUpgradeFailAllCallers() async throws {
            // Instantiate two nodes with different security protocols
            let host = try await makeNode(security: .plaintextV2)
            installEchoRoute(host)
            let client = try await makeNode(security: .noise)
            try await host.startup()
            try await client.startup()

            do {
                let addr = try host.dialableAddress
                let message = Data("doomed".utf8)

                // The following connection will fail due to no common sec protocol
                let failures = try await withThrowingTaskGroup(of: Bool.self) { group -> Int in
                    for _ in 0..<4 {
                        group.addTask {
                            do {
                                _ = try await client.echo(message, to: addr, timeout: .seconds(10))
                                return false
                            } catch {
                                return true
                            }
                        }
                    }
                    var count = 0
                    for try await didFail in group where didFail { count += 1 }
                    return count
                }

                // Every coalesced request surfaced the failed upgrade.
                #expect(failures == 4)
            } catch {
                try? await client.asyncShutdown()
                try? await host.asyncShutdown()
                throw error
            }

            try await client.asyncShutdown()
            try await host.asyncShutdown()
        }
    }

}
