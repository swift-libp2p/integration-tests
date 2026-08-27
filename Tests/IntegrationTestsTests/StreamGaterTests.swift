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

extension IntegrationTestSuites {

    @Suite("StreamGater Tests", .timeLimit(.minutes(1)))
    struct StreamGaterTests {

        /// A `StreamGater` that refuses the echo protocol must actually stop the request, and must do so
        /// without taking the whole connection down with it. This is the end-to-end proof that the stream gater's
        /// approved protocol list is what multistream-select gets configured with on the real inbound path.
        @Test func aRejectingGaterBlocksTheProtocolButKeepsTheConnection() async throws {
            try await withPeers(connectionType: BaseConnection.self) { host, client in
                host.logger.logLevel = .debug
                // Gate the *host*: it's the side that receives the inbound `/echo/1.0.0` stream.
                host.connectionManager.use(streamGater: DenyProtocolStreamGater(denying: "/echo/1.0.0"))

                let addr = try host.dialableAddress
                // `/echo/1.0.0` is never offered to mss, so negotiation fails and the request gets no
                // response.
                await #expect(throws: (any Error).self) {
                    try await client.echo(Data("blocked".utf8), to: addr, timeout: .seconds(3), attempts: 1)
                }

                // The rejection was scoped to the stream: the connection itself is still up.
                #expect(try await client.connectionManager.getTotalConnectionCount().get() == 1)
            }
        }
    }
}

// MARK: - Test helpers

/// A `StreamGater` that carries inbound streams for everything except one specific protocol, which it
/// strikes off the list multistream-select is allowed to negotiate.
actor DenyProtocolStreamGater: StreamGater {
    private let denied: String

    init(denying denied: String) {
        self.denied = denied
    }

    func shouldAcceptInboundStream(_ context: InboundStreamGateContext) async -> InboundStreamGateDecision {
        .acceptFor(protocols: context.supportedProtocols.filter { $0 != self.denied })
    }

    func shouldAllowOutboundStream(_ context: OutboundStreamGateContext) async -> OutboundStreamGateDecision {
        context.protocolCodec == self.denied
            ? .reject(reason: "`\(self.denied)` is not accepted on this node")
            : .accept
    }
}
