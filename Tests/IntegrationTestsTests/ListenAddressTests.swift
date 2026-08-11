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

/// Verifies automatic port-picking (`/tcp/0`) and that the announced listen addresses reflect the
/// real bound port and are dialable.
extension IntegrationTestSuites {

    @Suite("Listen Address Tests", .timeLimit(.minutes(2)))
    struct ListenAddressTests {

        @Test func automaticPortPickingProducesAConcreteAddress() async throws {
            try await withNode { app in
                let addresses = app.listenAddresses
                #expect(!addresses.isEmpty)

                // We asked the OS for a free port via `/tcp/0`; after startup the announced address must
                // carry a real, non-zero bound port.
                let first = try #require(addresses.first)
                let tcp = try #require(first.tcpAddress)
                #expect(tcp.port != 0)
            }
        }

        @Test func twoNodesReceiveDistinctPorts() async throws {
            try await withPeers(installEchoOnHost: false) { host, client in
                let hostPort = host.listenAddresses.first?.tcpAddress?.port
                let clientPort = client.listenAddresses.first?.tcpAddress?.port
                #expect(hostPort != nil)
                #expect(clientPort != nil)
                #expect(hostPort != clientPort)
            }
        }

        @Test(arguments: TestMuxer.allCases, TestSecurity.allCases)
        func announcedAddressIsDialable(muxer: TestMuxer, security: TestSecurity) async throws {
            try await withPeers(muxer: muxer.provider, security: security.provider) { host, client in
                // Dial the host using only its self-announced listen address.
                let announced = try #require(host.listenAddresses.first)
                #expect(announced.tcpAddress?.port != 0)

                let message = Data("announced".utf8)
                #expect(try await client.echo(message, to: host.dialableAddress) == message)
            }
        }
    }

}
