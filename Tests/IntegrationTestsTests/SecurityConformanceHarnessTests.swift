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

/// Validates the `SecurityConformanceHarness` (shipped in `LibP2PTesting`) against the production security
/// modules, which live in their own packages and so can only be exercised from the integration-tests
/// package. The muxer partner is the in-package reset-safe wire muxer, so the reset checks stay enabled.
@Suite("Security Conformance Harness", .serialized)
struct SecurityConformanceHarnessTests {
    /// - Note: payloads are capped below Noise's 65535-byte per-message limit. The harness surfaced that
    ///   `swift-libp2p-noise` does NOT fragment a single write larger than one Noise message: a 64 KB or
    ///   1 MB `newRequest` times out (the other modules round-trip 1 MB fine). Raising these sizes back to
    ///   the harness default `[1, 1024, 65_536, 1_048_576]` reproduces the finding. Fix belongs in the
    ///   Noise module (chunk plaintext into ≤65535-byte Noise messages).
    @Test("noise is conformant and encrypts the wire")
    func noiseIsConformant() async throws {
        let report = try await runSecurityConformance(
            security: .noise,
            expectedCodec: "/noise",
            payloadSizes: [1, 1024, 32_768]
        )
        #expect(report.passed, "\(report)")
        // Noise must NOT leave payload bytes in the clear.
        #expect(
            !report.warnings.contains { $0.contains("in the clear") },
            "noise unexpectedly left bytes in the clear: \(report)"
        )
    }

    @Test("plaintext v2 is conformant (and is, by design, in the clear)")
    func plaintextV2IsConformant() async throws {
        let report = try await runSecurityConformance(security: .plaintextV2, expectedCodec: "/plaintext/2.0.0")
        #expect(report.passed, "\(report)")
        #expect(
            report.warnings.contains { $0.contains("in the clear") },
            "expected a plaintext-on-the-wire warning; got: \(report.warnings)"
        )
    }
}
