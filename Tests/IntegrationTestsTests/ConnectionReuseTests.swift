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

        /// Desired end-state: several requests dialed *simultaneously from cold* to the same peer should
        /// coalesce onto a single connection.
        ///
        /// - Note: This is currently a **known gap** — address-based dialing has no in-flight dial
        ///   coalescing, so each concurrent cold `newRequest` opens its own connection. The test is
        ///   wrapped in `withKnownIssue` so the suite stays green while recording the deviation; if dial
        ///   coalescing is ever implemented, this will start passing and flag that the guard can be
        ///   removed. Kept intentionally small to limit the connection burst.
        @Test func concurrentColdDialsToSamePeerShouldCoalesce() async throws {
            try await withPeers { host, client in
                let addr = try host.dialableAddress
                let message = Data("cold".utf8)

                await withKnownIssue(
                    "Address-based dialing does not yet coalesce concurrent in-flight dials",
                    isIntermittent: true
                ) {
                    try await withThrowingTaskGroup(of: Data.self) { group in
                        for _ in 0..<4 {
                            group.addTask { try await client.echo(message, to: addr) }
                        }
                        for try await _ in group {}
                    }
                    let total = try await client.connectionManager.getTotalConnectionCount().get()
                    #expect(total == 1)
                }
            }
        }
    }

}
