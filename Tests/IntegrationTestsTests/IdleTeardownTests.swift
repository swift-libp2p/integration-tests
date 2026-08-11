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
import NIOCore
import Testing

@testable import LibP2P

/// Verifies idle teardown: once a connection's muxed sub-streams have all closed (idle *stream*
/// teardown), the now-empty connection reaps itself after its idle timeout (idle *connection*
/// teardown).
///
/// The default `ARCConnection` self-closes ~250ms after its last stream closes; the connection
/// manager's automatic-stream-counting path is a second, configurable option for the same condition.
extension IntegrationTestSuites {

    @Suite("Idle Teardown Tests", .timeLimit(.minutes(2)))
    struct IdleTeardownTests {

        @Test(arguments: TestMuxer.allCases, TestSecurity.allCases)
        func idleConnectionAndStreamsTearThemselvesDown(muxer: TestMuxer, security: TestSecurity) async throws {
            try await withPeers(muxer: muxer.provider, security: security.provider) { host, client in
                let recorder = EventRecorder()
                recorder.subscribe(to: client)

                _ = try await client.echo(Data("idle".utf8), to: host.dialableAddress)

                // Exactly one connection was opened for the request.
                let opened = try await client.connectionManager.getTotalConnectionCount().get()
                #expect(opened == 1)

                // Idle stream teardown: the request's sub-stream closes.
                #expect(await waitUntil { recorder.contains("closedStream") })
                // Idle connection teardown: with no streams left, the connection self-closes.
                #expect(await waitUntil { recorder.contains("disconnected") })
                #expect(await waitUntil { (try? await client.liveConnectionCount()) == 0 })
            }
        }

        /// The connection manager's automatic-stream-counting also closes idle connections; drive
        /// it explicitly with a short idle timeout.
        @Test(arguments: TestMuxer.allCases)
        func idleConnectionTearsDownWithAutomaticStreamCounting(muxer: TestMuxer) async throws {
            try await withPeers(
                muxer: muxer.provider,
                security: TestSecurity.noise.provider,
                enableAutomaticStreamCounting: true
            ) { host, client in
                client.connectionManager.setIdleTimeout(.milliseconds(500))

                _ = try await client.echo(Data("idle-asc".utf8), to: host.dialableAddress)

                #expect(await waitUntil { (try? await client.liveConnectionCount()) == 0 })
            }
        }
    }

}
