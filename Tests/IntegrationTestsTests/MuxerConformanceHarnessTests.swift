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
import LibP2PNoise
import LibP2PTesting
import LibP2PYAMUX
import Testing

/// Validates the `MuxerConformanceHarness` (shipped in `LibP2PTesting`) against the production muxers.
///
/// - Note: `testReset: false` — both muxers' `stream.reset()` write a control frame down the child-channel
///   pipeline, crashing the in-process runner (a separate finding).
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
        // Ensure our write promises are succeeded, and only once the bytes land on the socket (not before)
        #expect(!report.warnings.contains { $0.contains("premature") }, "unexpected write-promise advisory; \(report)")
        #expect(
            !report.warnings.contains { $0.contains("never completed") },
            "unexpected write-promise advisory; \(report)"
        )
    }

    @Test("yamux is conformant over noise")
    func yamuxIsConformantOverNoise() async throws {
        let report = try await runMuxerConformance(
            muxer: .yamux,
            expectedCodec: "/yamux/1.0.0",
            security: .noise,
            testReset: false
        )
        #expect(report.passed, "\(report)")
        // Ensure our write promises are succeeded, and only once the bytes land on the socket (not before)
        #expect(!report.warnings.contains { $0.contains("premature") }, "unexpected write-promise advisory; \(report)")
        #expect(
            !report.warnings.contains { $0.contains("never completed") },
            "unexpected write-promise advisory; \(report)"
        )
    }

    @Test("mplex is conformant (write-promise opt-out)")
    func mplexIsConformant() async throws {
        let report = try await runMuxerConformance(
            muxer: .mplex,
            expectedCodec: "/mplex/6.7.0",
            testReset: false,
            strictWritePromise: false
        )
        #expect(report.passed, "\(report)")
        // mplex (0.2.0) prematurely fires write promises, so we should see the `premature` warning
        #expect(report.warnings.contains { $0.contains("premature") }, "expected write-promise advisory; \(report)")
    }

    @Test("mplex (0.2.0) fails the write-promise contract under the strict default")
    func mplexFailsWritePromiseUnderStrict() async throws {
        let report = try await runMuxerConformance(
            muxer: .mplex,
            expectedCodec: "/mplex/6.7.0",
            testReset: false
        )
        #expect(!report.passed, "expected a strict write-promise failure; \(report)")
    }
}
