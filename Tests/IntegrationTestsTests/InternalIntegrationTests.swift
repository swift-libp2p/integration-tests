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

@Suite("Internal Integration Tests", .serialized, .timeLimit(.minutes(5)))
struct InternalIntegrationTests {

    enum Muxer: CaseIterable {
        case yamux
        case mplex

        var provider: Application.MuxerUpgraders.Provider {
            switch self {
            case .yamux: .yamux
            case .mplex: .mplex
            }
        }
    }

    enum Security: CaseIterable {
        case noise
        case plaintext

        var provider: Application.SecurityUpgraders.Provider {
            switch self {
            case .noise: .noise
            case .plaintext: .plaintextV2
            }
        }
    }

    @Test(arguments: Muxer.allCases, Security.allCases)
    func testLibP2PInternalPingMultiaddr(muxer: Muxer, security: Security) async throws {
        let app1 = try await makeClient(port: 10_000, muxer: muxer.provider, security: security.provider)
        let app2 = try await makeClient(port: 10_001, muxer: muxer.provider, security: security.provider)

        try await app1.startup()
        try await app2.startup()

        let ma = try app2.listenAddresses.first!.encapsulate(proto: .p2p, address: app2.peerID.b58String)

        let ping = try await app1.identify.ping(addr: ma)
        print("Latency: \(ping.nanoseconds) ns")
        #expect(ping.nanoseconds >= 0)

        try await app1.asyncShutdown()
        try await app2.asyncShutdown()
    }

    @Test(arguments: Muxer.allCases, Security.allCases)
    func testLibP2PInternalPingPeer(muxer: Muxer, security: Security) async throws {
        let app1 = try await makeClient(port: 10_000, muxer: muxer.provider, security: security.provider)
        let app2 = try await makeClient(port: 10_001, muxer: muxer.provider, security: security.provider)

        try await app1.startup()
        try await app2.startup()

        do {
            try await app1.peers.add(peerInfo: app2.peerInfo)

            let ping = try await app1.identify.ping(peer: app2.peerID)
            print("Latency: \(ping.nanoseconds) ns")
            #expect(ping.nanoseconds >= 0)
        } catch {
            Issue.record(error)
        }

        try await app1.asyncShutdown()
        try await app2.asyncShutdown()
    }

    @Test(arguments: Muxer.allCases, Security.allCases)
    func testLibP2PInternalPingPeerCascadeMultipleInflightPings(muxer: Muxer, security: Security) async throws {
        let app1 = try await makeClient(port: 10_000, muxer: muxer.provider, security: security.provider)
        let app2 = try await makeClient(port: 10_001, muxer: muxer.provider, security: security.provider)

        try await app1.startup()
        try await app2.startup()

        do {
            try await app1.peers.add(peerInfo: app2.peerInfo)

            // Note: These pings happen concurrently
            async let latency1 = app1.identify.ping(peer: app2.peerID)
            async let latency2 = app1.identify.ping(peer: app2.peerID)
            async let latency3 = app1.identify.ping(peer: app2.peerID)

            // Even when we await them like this here...
            let ping1 = try await latency1
            let ping2 = try await latency2
            let ping3 = try await latency3

            let connectionCount = try await app1.connectionManager.getTotalConnectionCount().get()
            let streamCount = try await app1.connectionManager.getTotalStreamCount().get()

            print("Connection Count: \(connectionCount)")
            print("Stream Count: \(streamCount)")

            #expect(connectionCount == 1)
            // 2 streams for ID protocol and 1 stream for all three pings
            #expect(streamCount == 3)

            // All of the pings should be indentical because all three calls where cascaded into one
            #expect(ping1 == ping2)
            #expect(ping2 == ping3)
        } catch {
            Issue.record(error)
        }

        try await app1.asyncShutdown()
        try await app2.asyncShutdown()
    }

    @Test(arguments: Muxer.allCases, Security.allCases)
    func testLibP2PInternalPingPeerSequentialPingsUseSameConnection(muxer: Muxer, security: Security) async throws {
        let app1 = try await makeClient(port: 10_000, muxer: muxer.provider, security: security.provider)
        let app2 = try await makeClient(port: 10_001, muxer: muxer.provider, security: security.provider)

        try await app1.startup()
        try await app2.startup()

        do {
            try await app1.peers.add(peerInfo: app2.peerInfo)

            // Note: These pings happen sequentially
            let ping1 = try await app1.identify.ping(peer: app2.peerID)
            let ping2 = try await app1.identify.ping(peer: app2.peerID)
            let ping3 = try await app1.identify.ping(peer: app2.peerID)

            let connectionCount = try await app1.connectionManager.getTotalConnectionCount().get()
            let streamCount = try await app1.connectionManager.getTotalStreamCount().get()

            print("Connection Count: \(connectionCount)")
            print("Stream Count: \(streamCount)")

            #expect(connectionCount == 1)
            // 2 streams for ID protocol and 1 stream for each of the 3 pings
            #expect(streamCount == 5)

            // All three pings should be different because they happened sequentially
            #expect(ping1 != ping2)
            #expect(ping2 != ping3)
        } catch {
            Issue.record(error)
        }

        try await app1.asyncShutdown()
        try await app2.asyncShutdown()
    }

    @Test(arguments: Muxer.allCases, Security.allCases)
    func testInternalInterop(muxer: Muxer, security: Security) async throws {
        let host = try await makeEchoHost(port: 10000, muxer: muxer.provider, security: security.provider)
        let client = try await makeClient(port: 10001, muxer: muxer.provider, security: security.provider)

        try await host.startup()
        try await client.startup()

        do {
            let message: Data = "Hello Swift LibP2P".data(using: .utf8)!

            /// Fire off an echo request
            let response = try await client.newRequest(
                to: host.listenAddresses.first!.encapsulate(proto: .p2p, address: host.peerID.b58String),
                forProtocol: "/echo/1.0.0",
                withRequest: message,
                withHandlers: .handlers([.newLineDelimited])
            ).get()

            #expect(response == message)

            try await Task.sleep(for: .milliseconds(10))
        } catch {
            Issue.record(error)
        }

        try await host.asyncShutdown()
        try await client.asyncShutdown()
    }

    @Test(.timeLimit(.minutes(2)), arguments: Muxer.allCases, Security.allCases)
    func testInternalInteropMultipleRequests_Sequentially(muxer: Muxer, security: Security) async throws {
        let host = try await makeEchoHost(port: 10000, muxer: muxer.provider, security: security.provider)
        let client = try await makeClient(port: 10001, muxer: muxer.provider, security: security.provider)

        try await host.startup()
        try await client.startup()

        let numberOfRequests = 500

        do {
            // Yamux handles 10_000 requests in ~40 seconds
            for _ in 0..<numberOfRequests {
                /// Fire off an echo request
                let response = try await client.newRequest(
                    to: host.listenAddresses.first!.encapsulate(proto: .p2p, address: host.peerID.b58String),
                    forProtocol: "/echo/1.0.0",
                    withRequest: "Hello Swift LibP2P".data(using: .utf8)!,
                    withHandlers: .handlers([.newLineDelimited])
                ).get()

                #expect(response == "Hello Swift LibP2P".data(using: .utf8)!)
            }

            try await Task.sleep(for: .milliseconds(10))

            let connections = try await host.connectionManager.getTotalConnectionCount().get()
            let streams = try await host.connectionManager.getTotalStreamCount().get()

            #expect(connections == 1)
            #expect(streams == numberOfRequests + 2)
        } catch {
            Issue.record(error)
        }

        try await host.asyncShutdown()
        try await client.asyncShutdown()
    }

    @Test(.timeLimit(.minutes(2)), arguments: Muxer.allCases, Security.allCases)
    func testInternalInteropMultipleBidirectionalRequests_Sequentially(muxer: Muxer, security: Security) async throws {
        let peer1 = try await makeEchoHost(port: 10000, muxer: muxer.provider, security: security.provider)
        let peer2 = try await makeEchoHost(port: 10001, muxer: muxer.provider, security: security.provider)

        try await peer1.startup()
        try await peer2.startup()

        let numberOfRequests = 500

        do {
            let peer1Address = try peer1.listenAddresses.first!.encapsulate(
                proto: .p2p,
                address: peer1.peerID.b58String
            )
            let peer2Address = try peer2.listenAddresses.first!.encapsulate(
                proto: .p2p,
                address: peer2.peerID.b58String
            )

            // Yamux handles 10_000 requests in ~40 seconds
            for _ in 0..<numberOfRequests {
                /// Fire off an echo request
                async let p1ToP2 = try peer1.newRequest(
                    to: peer2Address,
                    forProtocol: "/echo/1.0.0",
                    withRequest: "Hello from peer1".data(using: .utf8)!,
                    withHandlers: .handlers([.newLineDelimited])
                ).get()

                /// Fire off an echo request
                async let p2ToP1 = try peer2.newRequest(
                    to: peer1Address,
                    forProtocol: "/echo/1.0.0",
                    withRequest: "Hello from peer2".data(using: .utf8)!,
                    withHandlers: .handlers([.newLineDelimited])
                ).get()

                let repsonses = try await [p1ToP2, p2ToP1]
                #expect(repsonses.first == "Hello from peer1".data(using: .utf8)!)
                #expect(repsonses.last == "Hello from peer2".data(using: .utf8)!)
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
        } catch {
            Issue.record(error)
        }

        try await peer1.asyncShutdown()
        try await peer2.asyncShutdown()
    }
}

extension InternalIntegrationTests {
    fileprivate func makeEchoHost(
        port: Int,
        peerID: PeerID? = nil,
        logLevel: Logger.Level = .notice,
        muxer: Application.MuxerUpgraders.Provider,
        security: Application.SecurityUpgraders.Provider
    ) async throws -> Application {
        let lib = try await makeClient(port: port, peerID: peerID, logLevel: logLevel, muxer: muxer, security: security)

        lib.routes.group("echo", handlers: [.newLineDelimited]) { echo in
            echo.on("1.0.0") { req -> Response<ByteBuffer> in
                switch req.event {
                case .ready: return .stayOpen
                case .data(let data): return .respondThenClose(data)
                case .closed: return .close
                case .error(let error):
                    req.logger.error("\(error)")
                    return .close
                }
            }
        }

        return lib
    }

    fileprivate func makeClient(
        port: Int,
        peerID: PeerID? = nil,
        logLevel: Logger.Level = .notice,
        muxer: Application.MuxerUpgraders.Provider,
        security: Application.SecurityUpgraders.Provider
    ) async throws -> Application {
        let lib: Application
        if let peerID {
            lib = try await Application.make(.testing, peerID: peerID)
        } else {
            lib = try await Application.make(.testing, peerID: .ephemeral(type: .Ed25519))
        }
        lib.security.use(security)
        lib.muxers.use(muxer)
        lib.servers.use(.tcp(host: "127.0.0.1", port: port))

        lib.logger.logLevel = logLevel

        return lib
    }
}
