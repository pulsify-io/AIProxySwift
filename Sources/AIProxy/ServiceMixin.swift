//
//  ServiceMixin.swift
//  AIProxy
//
//  Created by Lou Zell on 4/24/25.
//

import Foundation
import AsyncHTTPClient
import NIOHTTP1

protocol ServiceMixin {
    var urlSession: URLSession { get }
    var httpClient: HTTPClient? { get }
}

extension ServiceMixin {
    var httpClient: HTTPClient? {
        nil
    }
}

extension ServiceMixin {
    func makeRequestAndDeserializeResponse<T: Decodable>(_ request: URLRequest) async throws -> T {
        if AIProxy.printRequestBodies {
            printRequestBody(request)
        }
        if let httpClient {
            let (request, timeoutInterval) = request.httpClientRequest
            let response = try await httpClient.execute(request, timeout: .seconds(Int64(timeoutInterval)))
            let data = try await response.body.reduce(into: Data()) { partialResult, byteBuffer in
                partialResult += Data(buffer: byteBuffer)
            }
            return try T.deserialize(from: data)
        } else {
            let (data, _) = try await BackgroundNetworker.makeRequestAndWaitForData(
                self.urlSession,
                request
            )
            if AIProxy.printResponseBodies {
                printBufferedResponseBody(data)
            }
            return try T.deserialize(from: data)
        }
    }

    func makeRequestAndDeserializeStreamingChunks<T: Decodable>(_ request: URLRequest) async throws -> AsyncThrowingStream<T, Error> {
        if AIProxy.printRequestBodies {
            printRequestBody(request)
        }
        
        if let httpClient {
            let (request, timeoutInterval) = request.httpClientRequest
            let response = try await httpClient.execute(request, timeout: .seconds(Int64(timeoutInterval)))
            
            return AsyncThrowingStream<T, Error> { continuation in
                Task(priority: .userInitiated) {
                    do {
                        for try await buffer in response.body {
                            String(buffer: buffer)
                                .components(separatedBy: "data: ")
                                .filter { $0.isEmpty == false && $0 != "data: " }
                                .forEach { value in
                                    let dataPrepended = "data: " + value.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if let object = T.deserialize(fromLine: dataPrepended) {
                                        continuation.yield(object)
                                    }
                                }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        } else {
            let (asyncBytes, _) = try await BackgroundNetworker.makeRequestAndWaitForAsyncBytes(
                self.urlSession,
                request
            )
            
            return AsyncThrowingStream<T, Error> { continuation in
                Task(priority: .userInitiated) {
                    do {
                        for try await line in asyncBytes.lines {
                            if let object = T.deserialize(fromLine: line) {
                                continuation.yield(object)
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
}

private extension URLRequest {
    var readableURL: String {
        return self.url?.absoluteString ?? ""
    }

    var readableBody: String {
        guard let body = self.httpBody else {
            return "None"
        }

        return String(data: body, encoding: .utf8) ?? "None"
    }
}

private func printRequestBody(_ request: URLRequest) {
    logIf(.debug)?.debug(
        """
        Making a request to \(request.readableURL)
        with request body:
        \(request.readableBody)
        """
    )
}

private func printBufferedResponseBody(_ data: Data) {
    logIf(.debug)?.debug(
        """
        Received response body:
        \(String(data: data, encoding: .utf8) ?? "")
        """
    )
}

private func printStreamingResponseChunk(_ chunk: String) {
    logIf(.debug)?.debug(
        """
        Received streaming response chunk:
        \(chunk)
        """
    )
}

private extension URLRequest {
    var httpClientRequest: (request: HTTPClientRequest, timeoutInterval: TimeInterval) {
        var request = HTTPClientRequest(url: self.url!.absoluteString)
        request.method = .init(rawValue: self.httpMethod!)
        if let body = self.httpBody {
            request.body = .bytes(.init(data: body))
        }
        
        let headerFields = self.allHTTPHeaderFields?.reduce(into: HTTPHeaders()) { partialResult, next in
            partialResult.add(name: next.key, value: next.value)
        }
        request.headers = headerFields ?? .init()
        
        return (request, timeoutInterval)
    }
}
