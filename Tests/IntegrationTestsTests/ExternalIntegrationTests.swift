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

@Suite("External Integration Tests", .serialized, .timeLimit(.minutes(5)))
struct ExternalIntegrationTests {

    @Test func testExternalPingMultiaddr() async throws {
        await withKnownIssue("Sometimes we cant reach the external node...", isIntermittent: true) {
            let app1 = try await makeClient(port: 10_003)

            try await app1.startup()

            let ma = try Multiaddr("/ip4/104.131.131.82/tcp/4001/p2p/QmaCpDMGvV2BGHeYERUEnRQAwe3N8SzbUtfsmvsqQLuvuJ")

            let ping = try await app1.identify.ping(addr: ma)
            print("Latency: \(ping.nanoseconds) ns")
            #expect(ping.nanoseconds >= 0)

            try await app1.asyncShutdown()
        }
    }
}

extension ExternalIntegrationTests {
    fileprivate func makeClient(
        port: Int,
        logLevel: Logger.Level = .notice
    ) async throws -> Application {
        let lib = try await Application.make(.testing, peerID: .ephemeral(type: .Ed25519))

        lib.security.use(.noise)
        lib.muxers.use(.yamux, .mplex)
        lib.servers.use(.tcp(host: "127.0.0.1", port: port))

        lib.logger.logLevel = logLevel

        return lib
    }
}
