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

import LibP2P
import LibP2PMPLEX
import LibP2PNoise
import LibP2PPlaintext
import LibP2PTesting
import LibP2PYAMUX

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

// MARK: - Node configuration

/// Builds the `configure` closure that `LibP2PTesting`'s node helpers take, installing this suite's
/// transport stack plus the settings every integration test wants.
///
/// ```swift
/// try await withPeers(configure: testStack(muxer: muxer, security: security)) { host, client in … }
/// ```
///
/// - Parameters:
///   - idleTimeout: Defaults to 500ms, well under the library default. Several suites depend on idle
///     teardown happening inside a test's lifetime, and it's cheap for the rest, so it's the default
///     here rather than something each call site has to remember.
///   - logLevel: `.error` keeps the connection-teardown diagnostics the suite is occasionally read
///     for. Applied here rather than through the helpers' own `logLevel:` because `configure` runs
///     last and would otherwise be overridden by it.
///   - extra: Runs after the stack is installed, for per-test routes and configuration.
func testStack(
    muxer: TestMuxer = .yamux,
    security: TestSecurity = .noise,
    connectionType: AppConnection.Type? = nil,
    enableAutomaticStreamCounting: Bool = false,
    idleTimeout: TimeAmount? = .milliseconds(500),
    logLevel: Logger.Level = .error,
    then extra: @escaping (Application) async throws -> Void = { _ in }
) -> (Application) async throws -> Void {
    { app in
        app.security.use(security.provider)
        app.muxers.use(muxer.provider)
        if let connectionType { app.connectionManager.use(connectionType: connectionType) }
        if let idleTimeout { app.connectionManager.setIdleTimeout(idleTimeout) }
        app.logger.logLevel = logLevel
        try await extra(app)
    }
}
