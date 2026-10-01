import Foundation
import Network

enum LoopbackCallbackListenerError: Error, Equatable {
    case cancelled
    case alreadyWaiting
    case invalidRequest
    case unableToBind
}

final class LoopbackCallbackListener: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.trainorrest.chatgpt-loopback")
    private let lock = NSLock()
    private var listener: NWListener?
    private var port: UInt16?
    private var callbackURL: URL?
    private var terminalError: Error?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var startContinuation: CheckedContinuation<UInt16, Error>?

    func start() async throws -> UInt16 {
        var lastError: Error = LoopbackCallbackListenerError.unableToBind
        for _ in 0..<3 {
            do {
                let port = try await startAttempt()
                return port
            } catch {
                lastError = error
                cancelListener()
            }
        }
        throw lastError
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }

            if let callbackURL {
                continuation.resume(returning: callbackURL)
            } else if let terminalError {
                continuation.resume(throwing: terminalError)
            } else if callbackContinuation != nil {
                continuation.resume(throwing: LoopbackCallbackListenerError.alreadyWaiting)
            } else {
                callbackContinuation = continuation
            }
        }
    }

    func cancel() {
        stop(with: LoopbackCallbackListenerError.cancelled)
    }

    private func stop(with error: Error) {
        let continuation: CheckedContinuation<URL, Error>?
        let listener: NWListener?

        lock.lock()
        if callbackURL == nil, terminalError == nil {
            terminalError = error
        }
        continuation = callbackContinuation
        callbackContinuation = nil
        listener = self.listener
        self.listener = nil
        lock.unlock()

        listener?.cancel()
        continuation?.resume(throwing: error)
    }

    static func callbackURL(fromRequestHeaders headers: Data, port: UInt16) -> URL? {
        guard let request = String(data: headers, encoding: .utf8),
              let requestLine = request.components(separatedBy: "\r\n").first else {
            return nil
        }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[0] == "GET", parts[2].hasPrefix("HTTP/") else {
            return nil
        }

        let target = String(parts[1])
        guard let components = URLComponents(string: target),
              components.scheme == nil,
              components.host == nil,
              components.path == ChatGPTAuthConfiguration.callbackPath else {
            return nil
        }

        var callback = URLComponents()
        callback.scheme = "http"
        callback.host = "127.0.0.1"
        callback.port = Int(port)
        callback.path = components.path
        callback.percentEncodedQuery = components.percentEncodedQuery
        return callback.url
    }

    private func startAttempt() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters, on: .any)

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            startContinuation = continuation
            lock.unlock()
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener else { return }
                switch state {
                case .ready:
                    let port = listener.port?.rawValue
                    self.lock.lock()
                    let pending = self.startContinuation
                    self.startContinuation = nil
                    if pending != nil, let port {
                        self.listener = listener
                        self.port = port
                    }
                    self.lock.unlock()
                    if let port {
                        pending?.resume(returning: port)
                    } else {
                        pending?.resume(throwing: LoopbackCallbackListenerError.unableToBind)
                    }
                case .failed(let error):
                    self.lock.lock()
                    let pending = self.startContinuation
                    self.startContinuation = nil
                    self.lock.unlock()
                    // Before ready this fails the start; after ready it ends the pending callback wait.
                    if let pending {
                        pending.resume(throwing: error)
                    } else {
                        self.stop(with: error)
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.receiveHeaders(from: connection, data: Data())
            }
            listener.start(queue: queue)
        }
    }

    private func receiveHeaders(from connection: NWConnection, data: Data) {
        connection.start(queue: queue)
        receiveMoreHeaders(from: connection, data: data)
    }

    private func receiveMoreHeaders(from connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var accumulated = data
            if let content {
                accumulated.append(content)
            }

            let headerTerminator = Data("\r\n\r\n".utf8)
            if let range = accumulated.range(of: headerTerminator) {
                let headers = accumulated.subdata(in: accumulated.startIndex..<range.upperBound)
                self.handle(headers: headers, connection: connection)
            } else if error != nil || isComplete || accumulated.count > 32_768 {
                self.reply(status: "400 Bad Request", connection: connection)
            } else {
                self.receiveMoreHeaders(from: connection, data: accumulated)
            }
        }
    }

    private func handle(headers: Data, connection: NWConnection) {
        lock.lock()
        let port = self.port
        lock.unlock()

        guard let port,
              let callbackURL = Self.callbackURL(fromRequestHeaders: headers, port: port) else {
            reply(status: "404 Not Found", connection: connection)
            return
        }

        reply(status: "302 Found", location: ChatGPTAuthConfiguration.completionURL.absoluteString, connection: connection)
        complete(with: callbackURL)
    }

    private func reply(status: String, location: String? = nil, connection: NWConnection) {
        var response = "HTTP/1.1 \(status)\r\n"
        if let location {
            response += "Location: \(location)\r\n"
        }
        response += "Content-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func complete(with callbackURL: URL) {
        let continuation: CheckedContinuation<URL, Error>?
        let listener: NWListener?

        lock.lock()
        guard self.callbackURL == nil, terminalError == nil else {
            lock.unlock()
            return
        }
        self.callbackURL = callbackURL
        continuation = callbackContinuation
        callbackContinuation = nil
        listener = self.listener
        self.listener = nil
        lock.unlock()

        listener?.cancel()
        continuation?.resume(returning: callbackURL)
    }

    private func cancelListener() {
        lock.lock()
        let listener = self.listener
        self.listener = nil
        lock.unlock()
        listener?.cancel()
    }
}
