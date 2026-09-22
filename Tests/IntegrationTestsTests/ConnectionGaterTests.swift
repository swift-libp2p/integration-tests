//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-libp2p open source project
//
// Copyright (c) 2022-2026 swift-libp2p project authors
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

    @Suite("ConnectionGater Tests", .timeLimit(.minutes(1)))
    struct ConnectionGaterTests {

        @Test func anAllowAllGaterLetsTheConnectionThrough() async throws {
            try await withPeers(connectionType: BaseConnection.self) { host, client in
                host.connectionManager.use(connectionGater: AllowAllConnectionGater())
                client.connectionManager.use(connectionGater: AllowAllConnectionGater())

                let message = Data("gated hello".utf8)
                let echoed = try await client.echo(message, to: host.dialableAddress)
                #expect(echoed == message)

                // Both sides hold the (single) live connection the request rode over.
                #expect(try await host.liveConnectionCount() == 1)
                #expect(try await client.liveConnectionCount() == 1)
            }
        }

        @Test func aSecuredHookDenialClosesTheConnection() async throws {
            try await withPeers(connectionType: BaseConnection.self) { host, client in
                // Install a ConnectionGater that rejects the client's PeerID
                host.connectionManager.use(
                    connectionGater: DenyPeerConnectionGater(denying: client.peerID)
                )

                let addr = try host.dialableAddress
                // The host closes the channel mid-upgrade, so the request can never complete.
                await #expect(throws: (any Error).self) {
                    try await client.echo(Data("banned".utf8), to: addr, timeout: .seconds(3), attempts: 1)
                }

                // The denial closed the connection on both sides (teardown is asynchronous, so poll).
                #expect(await waitUntil { (try? await host.liveConnectionCount()) == 0 })
                #expect(await waitUntil { (try? await client.liveConnectionCount()) == 0 })
            }
        }

        /// A gater that refuses inbound connections at the raw-accept hook must close the channel
        /// before any handshake runs: the connection is never registered with the host's manager and
        /// the secured hook — which requires an authenticated peer — is never consulted.
        @Test func anAcceptHookDenialRefusesInboundBeforeTheHandshake() async throws {
            try await withPeers(connectionType: BaseConnection.self) { host, client in
                let gater = DenyInboundConnectionGater()
                host.connectionManager.use(connectionGater: gater)

                let addr = try host.dialableAddress
                await #expect(throws: (any Error).self) {
                    try await client.echo(Data("refused".utf8), to: addr, timeout: .seconds(3), attempts: 1)
                }

                // The accept hook fired, and the denial happened before the security handshake could
                // authenticate anyone, so the secured hook was never reached.
                #expect(await gater.acceptConsultations == 1)
                #expect(await gater.securedConsultations == 0)

                // The host never held the connection at all, and the client's channel
                // (closed by the host) gets cleaned up asynchronously.
                #expect(try await host.liveConnectionCount() == 0)
                #expect(await waitUntil { (try? await client.liveConnectionCount()) == 0 })
            }
        }
    }
}

// MARK: - Test helpers

/// A `ConnectionGater` that allows everything except one banned `PeerID`, which it denies at the
/// secured hook, once the security handshake has proven who the remote peer actually is.
actor DenyPeerConnectionGater: ConnectionGater {
    private let denied: PeerID

    init(denying denied: PeerID) {
        self.denied = denied
    }

    func shouldAllowSecuredConnection(_ context: SecuredConnectionGateContext) async -> ConnectionGateDecision {
        context.remotePeer.b58String == self.denied.b58String
            ? .deny(reason: "peer \(self.denied.b58String) is banned on this node")
            : .allow
    }
}

/// A `ConnectionGater` that refuses every inbound connection at the raw-accept hook, and records
/// its consultations so a test can prove the secured hook is never reached after an accept denial.
actor DenyInboundConnectionGater: ConnectionGater {
    private(set) var acceptConsultations = 0
    private(set) var securedConsultations = 0

    func shouldAcceptRawConnection(_ context: RawConnectionGateContext) async -> ConnectionGateDecision {
        self.acceptConsultations += 1
        return .deny(reason: "inbound connections are refused on this node")
    }

    func shouldAllowSecuredConnection(_ context: SecuredConnectionGateContext) async -> ConnectionGateDecision {
        self.securedConsultations += 1
        return .allow
    }
}
