import Foundation

public struct JSONRPCRequest<Parameters: Encodable>: Encodable {
    public let jsonrpc = "2.0"
    public let id: UUID
    public let method: String
    public let params: Parameters

    public init(id: UUID = UUID(), method: String, params: Parameters) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse<Result: Decodable>: Decodable {
    public struct Failure: Decodable, Error {
        public let code: Int
        public let message: String
    }

    public let jsonrpc: String
    public let id: UUID
    public let result: Result?
    public let error: Failure?
}

public enum PluginProcessError: LocalizedError {
    case invalidResponse
    case remote(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "插件返回了无效响应"
        case .remote(let code, let message): "插件错误 \(code)：\(message)"
        }
    }
}
