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
import LibP2PNoise
import LibP2PPlaintext
import LibP2PTesting
import Testing

extension IntegrationTestSuites {
    /// Validates the `SecurityConformanceHarness` (shipped in `LibP2PTesting`) against the production security modules.
    @Suite("Security Conformance Harness", .serialized)
    struct SecurityConformanceHarnessTests {
        
        @Test("noise is conformant and encrypts the wire")
        func noiseIsConformant() async throws {
            let report = try await runSecurityConformance(
                security: .noise,
                expectedCodec: "/noise"
            )
            #expect(report.passed, "\(report)")
            // Ensure that the `in the clear` flag is NOT present
            #expect(!report.warnings.contains { $0.contains("in the clear") }, "noise unexpectedly in the clear: \(report)")
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
        
        /// plaintextV2 (local checkout, with the write-promise fix applied) now threads its stream-write promise
        /// through to the socket write, so it PASSES the strict default. It is, by design, in the clear.
        @Test("plaintext v2 is conformant (and is, by design, in the clear)")
        func plaintextV2IsConformant() async throws {
            let report = try await runSecurityConformance(security: .plaintextV2, expectedCodec: "/plaintext/2.0.0")
            #expect(report.passed, "\(report)")
            // Ensure that the `in the clear` flag IS present
            #expect(
                report.warnings.contains { $0.contains("in the clear") },
                "expected plaintext-on-wire advisory; \(report)"
            )
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
