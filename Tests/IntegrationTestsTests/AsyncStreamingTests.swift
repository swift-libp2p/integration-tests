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
import LibP2PTesting
import NIOConcurrencyHelpers
import NIOCore
import Testing

@testable import LibP2P

extension IntegrationTestSuites {

    /// The async streaming surface over production muxers and security transports.
    @Suite("Async Streaming Tests", .timeLimit(.minutes(2)))
    struct AsyncStreamingTests {

        static let openTimeout: TimeAmount = .seconds(15).ciScaled

        /// Registers `/async-echo/1.0.0` as a streaming route that echoes every frame back, for as
        /// long as the remote keeps talking.
        static func installStreamingEcho(
            _ app: Application,
            inboundBufferSize: Int = LibP2PStream.defaultInboundBufferSize
        ) {
            app.routes.group("async-echo", handlers: [.varIntLengthPrefixed]) { group in
                group.on(["1.0.0"], inboundBufferSize: inboundBufferSize) { (stream: LibP2PStream) in
                    for try await frame in stream.inbound {
                        try await stream.write(frame)
                    }
                }
            }
        }

        /// A full conversation, many messages each way over a single stream, across the whole
        /// muxer × security matrix. The in-tree equivalent runs over the mock muxer, this proves the
        /// out-of-band write path and the inbound pump survive real muxer framing.
        @Test(arguments: TestMuxer.allCases, TestSecurity.allCases)
        func pingPongOverOneStream(muxer: TestMuxer, security: TestSecurity) async throws {
            let exchanges = 8

            try await withPeers(
                installEchoOnHost: false,
                configure: testStack(muxer: muxer, security: security) { Self.installStreamingEcho($0) }
            ) { host, client in
                let replies = try await client.withStream(
                    to: host.dialableAddress,
                    forProtocol: "/async-echo/1.0.0",
                    withHandlers: .handlers([.varIntLengthPrefixed]),
                    openTimeout: Self.openTimeout
                ) { stream -> [String] in
                    var replies: [String] = []
                    var inbound = stream.inbound.makeAsyncIterator()

                    // Strict alternation, so a reply arriving out of order fails the test.
                    for i in 0..<exchanges {
                        try await stream.write(ByteBuffer(string: "msg-\(i)"))
                        guard let reply = try await inbound.next() else { break }
                        replies.append(String(buffer: reply))
                    }
                    return replies
                }

                #expect(replies == (0..<exchanges).map { "msg-\($0)" })

                // One stream, one connection, the async API reuses connections like `newRequest`.
                let total = try await client.connectionManager.getTotalConnectionCount()
                #expect(total == 1)
            }
        }

        /// Two async conversations running at the same time must be multiplexed onto one connection,
        /// not serialized and not one-connection-each.
        ///
        /// Each side waits for the *other* stream to have received a reply before finishing, so the
        /// two streams are provably open simultaneously. If the muxer serialized them, the wait
        /// fails rather than stalling.
        @Test(arguments: TestMuxer.allCases)
        func concurrentStreamsShareOneConnection(muxer: TestMuxer) async throws {
            try await withPeers(
                installEchoOnHost: false,
                configure: testStack(muxer: muxer) { Self.installStreamingEcho($0) }
            ) { host, client in
                let addr = try host.dialableAddress
                let replied = (a: NIOLockedValueBox(false), b: NIOLockedValueBox(false))

                @Sendable func converse(
                    label: String,
                    mine: NIOLockedValueBox<Bool>,
                    theirs: NIOLockedValueBox<Bool>
                ) async throws -> String {
                    try await client.withStream(
                        to: addr,
                        forProtocol: "/async-echo/1.0.0",
                        withHandlers: .handlers([.varIntLengthPrefixed]),
                        openTimeout: Self.openTimeout
                    ) { stream -> String in
                        var inbound = stream.inbound.makeAsyncIterator()
                        try await stream.write(ByteBuffer(string: label))
                        let reply = try await inbound.next().map { String(buffer: $0) } ?? ""
                        mine.withLockedValue { $0 = true }

                        // Hold this stream open until the other one has also spoken.
                        let bothOpen = await waitUntil { theirs.withLockedValue { $0 } }
                        #expect(bothOpen, "\(label) never saw the other stream get a reply")
                        return reply
                    }
                }

                async let first = converse(label: "stream-a", mine: replied.a, theirs: replied.b)
                async let second = converse(label: "stream-b", mine: replied.b, theirs: replied.a)
                let (a, b) = try await (first, second)

                #expect(a == "stream-a")
                #expect(b == "stream-b")

                let total = try await client.connectionManager.getTotalConnectionCount()
                #expect(total == 1, "concurrent streams must be multiplexed, not dialed separately")
            }
        }

        /// Backpressure over a real muxer, a handler that isn't reading yet stops the stream from
        /// reading the network, and every frame is still delivered, in order, once it starts.
        ///
        /// - Note: yamux has flow control and can throttle the remote, mplex has none and
        ///   parks the frames in its child channel instead. Neither should lose / drop frames.
        @Test(arguments: TestMuxer.allCases)
        func aSlowHandlerStallsTheProducerWithoutLosingFrames(muxer: TestMuxer) async throws {
            let sent = (0..<8).map { "frame-\($0)" }
            let received = NIOLockedValueBox<[String]?>(nil)
            // Holds the handler off its `inbound` until the test says every frame has been written.
            let gate = AsyncStream.makeStream(of: Void.self)

            try await withPeers(
                installEchoOnHost: false,
                configure: testStack(muxer: muxer) { app in
                    app.routes.group("slow", handlers: [.varIntLengthPrefixed]) { group in
                        group.on(["1.0.0"], inboundBufferSize: 1) { (stream: LibP2PStream) in
                            for await _ in gate.stream { break }
                            var drained: [String] = []
                            for try await frame in stream.inbound {
                                drained.append(String(buffer: frame))
                            }
                            received.withLockedValue { $0 = drained }
                        }
                    }
                }
            ) { host, client in
                // Release the handler from outside the conversation. Doing it after `withStream`
                // returns would stall the muxer with a half-closure, the handler can't finish
                // until it's released, and it's what the client's own close is waiting on.
                let release = Task {
                    try? await Task.sleep(for: .milliseconds(500 * ciTimeoutMultiplier))
                    gate.continuation.yield()
                    gate.continuation.finish()
                }

                try await client.withStream(
                    to: host.dialableAddress,
                    forProtocol: "/slow/1.0.0",
                    withHandlers: .handlers([.varIntLengthPrefixed]),
                    openTimeout: Self.openTimeout
                ) { stream in
                    for message in sent {
                        try await stream.write(ByteBuffer(string: message))
                    }
                }

                await release.value

                let arrived = await waitUntil { received.withLockedValue { $0 } != nil }
                #expect(arrived, "the streaming handler never finished draining")
                #expect(received.withLockedValue { $0 } == sent)
            }
        }

        /// Frames large enough to matter to a muxer's flow control (yamux's default window is 256KB)
        /// must survive the round trip byte-for-byte. Exercises windowing / frame splitting
        /// underneath the async API, which loopback-sized payloads never reach.
        @Test(arguments: TestMuxer.allCases)
        func largeFramesRoundTripIntact(muxer: TestMuxer) async throws {
            let frames = (0..<3).map { _ in
                ByteBuffer(bytes: (0..<131_072).map { _ in UInt8.random(in: .min ... .max) })
            }

            try await withPeers(
                installEchoOnHost: false,
                configure: testStack(muxer: muxer) { Self.installStreamingEcho($0) }
            ) { host, client in
                let echoed = try await client.withStream(
                    to: host.dialableAddress,
                    forProtocol: "/async-echo/1.0.0",
                    withHandlers: .handlers([.varIntLengthPrefixed]),
                    openTimeout: Self.openTimeout
                ) { stream -> [ByteBuffer] in
                    var echoed: [ByteBuffer] = []
                    var inbound = stream.inbound.makeAsyncIterator()
                    for frame in frames {
                        try await stream.write(frame)
                        guard let reply = try await inbound.next() else { break }
                        echoed.append(reply)
                    }
                    return echoed
                }

                #expect(echoed.count == frames.count)
                #expect(echoed == frames, "large frames must round trip byte-for-byte")
            }
        }
    }
}
