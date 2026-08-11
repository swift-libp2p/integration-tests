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
import LibP2PCore
import LibP2PMPLEX
import LibP2PNoise
import LibP2PPlaintext
// `LibP2PTesting` re-exports `LibP2P` + `LibP2PTestUtils`, giving us the `withApp` lifecycle
// helper, the in-memory `TestingApplicationTester`, the `MockMuxer`/`MockSecurity` doubles and
// the `ByteBuffer.string` convenience. These integration helpers mirror the `withApp` idiom for
// nodes that need a *real* transport / muxer / security stack stood up over a loopback socket.
import LibP2PTesting
import LibP2PYAMUX
import NIOConcurrencyHelpers
import NIOCore

@testable import LibP2P

// MARK: - Transport matrix

/// The muxers exercised across the parameterized integration suites.
enum TestMuxer: CaseIterable, Sendable {
    case yamux
    case mplex

    var provider: Application.MuxerUpgraders.Provider {
        switch self {
        case .yamux: .yamux
        case .mplex: .mplex
        }
    }
}

/// The security transports exercised across the parameterized integration suites.
enum TestSecurity: CaseIterable, Sendable {
    case noise
    case plaintext

    var provider: Application.SecurityUpgraders.Provider {
        switch self {
        case .noise: .noise
        case .plaintext: .plaintextV2
        }
    }
}

enum IntegrationTestError: Error {
    case noListenAddress
}

// MARK: - Node construction

/// Builds a fully configured (but not yet started) node.
///
/// - Note: `port` defaults to `0`, which asks the OS to pick a free ephemeral port. Combined with
///   ``Application/dialableAddress`` this means the suites never hard-code ports (so they can run
///   in parallel without colliding) and exercise automatic port-picking as a side effect.
func makeNode(
    port: Int = 0,
    peerID: PeerID? = nil,
    muxer: Application.MuxerUpgraders.Provider = .yamux,
    security: Application.SecurityUpgraders.Provider = .noise,
    enableAutomaticStreamCounting: Bool = false,
    logLevel: Logger.Level = .error
) async throws -> Application {
    let app: Application
    if let peerID {
        app = try await Application.make(
            .testing,
            peerID: peerID,
            enableAutomaticStreamCounting: enableAutomaticStreamCounting
        )
    } else {
        app = try await Application.make(
            .testing,
            peerID: .ephemeral(type: .Ed25519),
            enableAutomaticStreamCounting: enableAutomaticStreamCounting
        )
    }
    app.security.use(security)
    app.muxers.use(muxer)
    app.servers.use(.tcp(host: "127.0.0.1", port: port))
    app.logger.logLevel = logLevel
    return app
}

/// Registers a simple line-delimited `/echo/1.0.0` route that echoes any payload back and closes.
func installEchoRoute(_ app: Application) {
    app.routes.group("echo", handlers: [.newLineDelimited]) { echo in
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
}

// MARK: - Scoped lifecycle (the `withApp` idiom, for networked nodes)

/// Stands up a single node, runs `body`, and guarantees the node is shut down afterwards — even if
/// `body` throws. Mirrors `LibP2PTesting.withApp`, but for a node with a live transport stack.
@discardableResult
func withNode<T>(
    muxer: Application.MuxerUpgraders.Provider = .yamux,
    security: Application.SecurityUpgraders.Provider = .noise,
    enableAutomaticStreamCounting: Bool = false,
    installEcho: Bool = false,
    _ body: (Application) async throws -> T
) async throws -> T {
    let app = try await makeNode(
        muxer: muxer,
        security: security,
        enableAutomaticStreamCounting: enableAutomaticStreamCounting
    )
    if installEcho { installEchoRoute(app) }
    do {
        try await app.startup()
        let result = try await body(app)
        try await app.asyncShutdown()
        return result
    } catch {
        try? await app.asyncShutdown()
        throw error
    }
}

/// Stands up a `host` and a `client` node (both started), runs `body`, and guarantees both are shut
/// down afterwards — even if `body` throws. The `host` gets the `/echo/1.0.0` route by default.
@discardableResult
func withPeers<T>(
    muxer: Application.MuxerUpgraders.Provider = .yamux,
    security: Application.SecurityUpgraders.Provider = .noise,
    enableAutomaticStreamCounting: Bool = false,
    installEchoOnHost: Bool = true,
    installEchoOnClient: Bool = false,
    _ body: (_ host: Application, _ client: Application) async throws -> T
) async throws -> T {
    let host = try await makeNode(
        muxer: muxer,
        security: security,
        enableAutomaticStreamCounting: enableAutomaticStreamCounting
    )
    let client = try await makeNode(
        muxer: muxer,
        security: security,
        enableAutomaticStreamCounting: enableAutomaticStreamCounting
    )
    if installEchoOnHost { installEchoRoute(host) }
    if installEchoOnClient { installEchoRoute(client) }
    do {
        try await host.startup()
        try await client.startup()
        let result = try await body(host, client)
        try await client.asyncShutdown()
        try await host.asyncShutdown()
        return result
    } catch {
        try? await client.asyncShutdown()
        try? await host.asyncShutdown()
        throw error
    }
}

// MARK: - Convenience

extension Application {
    /// The first announced listen address, encapsulated with this node's `PeerID` — ready to dial.
    ///
    /// After `startup()` this reflects the *actual* bound port (never `/tcp/0`), so it doubles as the
    /// canonical way to verify automatic port-picking produced a concrete, dialable address.
    var dialableAddress: Multiaddr {
        get throws {
            guard let addr = self.listenAddresses.first else { throw IntegrationTestError.noListenAddress }
            return try addr.encapsulate(proto: .p2p, address: self.peerID.b58String)
        }
    }

    /// The number of connections currently held open by the connection manager.
    func liveConnectionCount() async throws -> Int {
        try await self.connections.getConnections(on: nil).get().count
    }

    /// Fires a single line-delimited `/echo/1.0.0` request and returns the echoed payload.
    ///
    /// Uses a generous request timeout because these suites run in parallel — a burst of nodes all
    /// doing real handshakes at once can push an individual round-trip well past the 3s default.
    @discardableResult
    func echo(_ message: Data, to address: Multiaddr, timeout: TimeAmount = .seconds(15)) async throws -> Data {
        try await self.newRequest(
            to: address,
            forProtocol: "/echo/1.0.0",
            withRequest: message,
            withHandlers: .handlers([.newLineDelimited]),
            withTimeout: timeout
        ).get()
    }
}

// MARK: - Polling

/// Polls `predicate` until it returns `true` or the attempts are exhausted, returning the final
/// value. Used because event delivery / connection teardown happen asynchronously off the calling
/// task, so assertions can't read state synchronously right after triggering an action.
@discardableResult
func waitUntil(
    attempts: Int = 250,
    every: Duration = .milliseconds(20),
    _ predicate: @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if await predicate() { return true }
        try? await Task.sleep(for: every)
    }
    return await predicate()
}

// MARK: - Event recording

/// Subscribes to every connection-lifecycle event on an `Application` and records the order in which
/// they arrive, so tests can assert on emitted notifications. The bus keys subscriptions off object
/// identity and holds no strong reference, so a single recorder instance can own all subscriptions.
final class EventRecorder: @unchecked Sendable {
    private let events = NIOLockedValueBox<[String]>([])

    var recorded: [String] { self.events.withLockedValue { $0 } }
    func count(of kind: String) -> Int { self.events.withLockedValue { $0.filter { $0 == kind }.count } }
    func contains(_ kind: String) -> Bool { self.events.withLockedValue { $0.contains(kind) } }
    private func record(_ kind: String) { self.events.withLockedValue { $0.append(kind) } }

    /// Subscribes to the full connection-lifecycle event set on `app`.
    func subscribe(to app: Application) {
        app.events.on(self, event: .connected { [weak self] _ in self?.record("connected") })
        app.events.on(self, event: .upgraded { [weak self] _ in self?.record("upgraded") })
        app.events.on(self, event: .remotePeer { [weak self] _ in self?.record("remotePeer") })
        app.events.on(self, event: .openedStream { [weak self] _ in self?.record("openedStream") })
        app.events.on(self, event: .closedStream { [weak self] _ in self?.record("closedStream") })
        app.events.on(self, event: .identifiedPeer { [weak self] _ in self?.record("identifiedPeer") })
        app.events.on(self, event: .disconnected { [weak self] _, _ in self?.record("disconnected") })
    }
}
