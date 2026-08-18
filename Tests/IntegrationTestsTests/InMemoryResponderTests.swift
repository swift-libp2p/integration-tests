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

// `LibP2PTesting` re-exports the in-memory `TestingApplicationTester` and the `ByteBuffer.string`
// convenience from `LibP2PTestUtils`.
import LibP2PTesting
import NIOCore
import Testing

@testable import LibP2P

extension IntegrationTestSuites {
    /// Exercises the `LibP2PTestUtils` in-memory tester: a route can be driven through the responder
    /// (ready → data → closed) without standing up any transport, muxer or security. Complements the
    /// networked suites with a fast, socket-free check of route wiring.
    @Suite("In-Memory Responder Tests", .serialized)
    struct InMemoryResponderTests {
        
        @Test func echoRouteRespondsInMemory() async throws {
            let configuration: ((Application) async throws -> Void) = { app in installEchoRoute(app) }
            try await withApp(configure: configuration) { app in
                let ma = try Multiaddr("/ip4/127.0.0.1/tcp/1234")
                let payload = ByteBuffer(string: "Hello In-Memory")
                
                try await app.testing().test(ma, protocol: "/echo/1.0.0", payload: payload) { response in
                    // `ByteBuffer.string` comes from LibP2PTestUtils.
                    #expect(response.payload.string == "Hello In-Memory")
                }
            }
        }
    }
}
