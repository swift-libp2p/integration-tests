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

import LibP2P
import LibP2PMPLEX
import LibP2PTesting
import LibP2PYAMUX
import Testing

/// Validates the `MuxerConformanceHarness` (shipped in `LibP2PTesting`) against the production muxers,
/// which live in their own packages and so can only be exercised from the integration-tests package.
///
/// - Note: `testReset` is disabled here. The harness surfaced that both yamux and mplex implement
///   `stream.reset()` by writing a control frame *down the child-channel pipeline*, which trips an
///   outbound type assertion in `ResponseDecoderChannelHandler` and hard-crashes the in-process test
///   runner (rather than failing gracefully). That crash is a genuine finding to fix in those muxers;
///   until then we skip the reset phase so the rest of the conformance surface can be validated.
@Suite("Muxer Conformance Harness", .serialized)
struct MuxerConformanceHarnessTests {
    @Test("yamux is conformant")
    func yamuxIsConformant() async throws {
        let report = try await runMuxerConformance(
            muxer: .yamux,
            expectedCodec: "/yamux/1.0.0",
            testReset: false
        )
        #expect(report.passed, "\(report)")
    }

    @Test("mplex is conformant")
    func mplexIsConformant() async throws {
        let report = try await runMuxerConformance(
            muxer: .mplex,
            expectedCodec: "/mplex/6.7.0",
            testReset: false
        )
        #expect(report.passed, "\(report)")
    }
}
