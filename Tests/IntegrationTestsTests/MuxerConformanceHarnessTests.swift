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

extension IntegrationTestSuites {
    /// Validates the `MuxerConformanceHarness` (shipped in `LibP2PTesting`) against the production muxers.
    ///
    /// All checks (including stream reset, event propagation, idempotency, and malformed-input crash-safety) run
    /// under the defaults now that both muxers are conformant
    @Suite("Muxer Conformance Harness", .serialized)
    struct MuxerConformanceHarnessTests {
        
        @Test("yamux is conformant")
        func yamuxIsConformant() async throws {
            let report = try await runMuxerConformance(
                muxer: .yamux,
                expectedCodec: "/yamux/1.0.0"
            )
            #expect(report.passed, "\(report)")
            // Ensure our write promises are succeeded, and only once the bytes land on the socket (not before)
            #expect(!report.warnings.contains { $0.contains("premature") }, "unexpected write-promise advisory; \(report)")
            #expect(
                !report.warnings.contains { $0.contains("never completed") },
                "unexpected write-promise advisory; \(report)"
            )
            // Malformed input must not crash the node, and the node must stay serviceable afterwards.
            #expect(
                !report.warnings.contains { $0.contains("follow-up echo") },
                "node not serviceable after malformed input; \(report)"
            )
        }
        
        @Test("yamux is conformant over noise")
        func yamuxIsConformantOverNoise() async throws {
            let report = try await runMuxerConformance(
                muxer: .yamux,
                expectedCodec: "/yamux/1.0.0",
                security: .noise
            )
            #expect(report.passed, "\(report)")
            // Ensure our write promises are succeeded, and only once the bytes land on the socket (not before)
            #expect(!report.warnings.contains { $0.contains("premature") }, "unexpected write-promise advisory; \(report)")
            #expect(
                !report.warnings.contains { $0.contains("never completed") },
                "unexpected write-promise advisory; \(report)"
            )
            // Malformed input must not crash the node, and the node must stay serviceable afterwards.
            #expect(
                !report.warnings.contains { $0.contains("follow-up echo") },
                "node not serviceable after malformed input; \(report)"
            )
        }
        
        @Test("mplex is conformant")
        func mplexIsConformant() async throws {
            let report = try await runMuxerConformance(
                muxer: .mplex,
                expectedCodec: "/mplex/6.7.0"
            )
            #expect(report.passed, "\(report)")
            // Ensure our write promises are succeeded, and only once the bytes land on the socket (not before)
            #expect(!report.warnings.contains { $0.contains("premature") }, "unexpected write-promise advisory; \(report)")
            #expect(
                !report.warnings.contains { $0.contains("never completed") },
                "unexpected write-promise advisory; \(report)"
            )
            // Malformed input must not crash the node, and the node must stay serviceable afterwards.
            #expect(
                !report.warnings.contains { $0.contains("follow-up echo") },
                "node not serviceable after malformed input; \(report)"
            )
        }
        
        @Test("mplex is conformant over noise")
        func mplexIsConformantOverNoise() async throws {
            let report = try await runMuxerConformance(
                muxer: .mplex,
                expectedCodec: "/mplex/6.7.0",
                security: .noise,
            )
            #expect(report.passed, "\(report)")
            // Ensure our write promises are succeeded, and only once the bytes land on the socket (not before)
            #expect(!report.warnings.contains { $0.contains("premature") }, "unexpected write-promise advisory; \(report)")
            #expect(
                !report.warnings.contains { $0.contains("never completed") },
                "unexpected write-promise advisory; \(report)"
            )
            // Malformed input must not crash the node, and the node must stay serviceable afterwards.
            #expect(
                !report.warnings.contains { $0.contains("follow-up echo") },
                "node not serviceable after malformed input; \(report)"
            )
        }
    }
}
