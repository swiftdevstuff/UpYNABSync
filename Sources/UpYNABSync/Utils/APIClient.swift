import Foundation

class APIClient {
    static let shared = APIClient()
    private init() {}
    
    private let session = URLSession.shared
    private let logger = Logger.shared
    
    enum HTTPMethod: String {
        case GET = "GET"
        case POST = "POST"
        case PUT = "PUT"
        case DELETE = "DELETE"
    }
    
    enum APIError: Error, LocalizedError {
        case invalidURL
        case noData
        case requestFailed(Int, String?)
        case decodingError(Error)
        case encodingError(Error)
        case networkError(Error)
        case rateLimited(retryAfter: Int?)
        case unauthorized
        case forbidden
        case notFound
        case serverError(Int)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .noData:
                return "No data received"
            case .requestFailed(let statusCode, let message):
                return "Request failed with status \(statusCode): \(message ?? "Unknown error")"
            case .decodingError(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            case .encodingError(let error):
                return "Failed to encode request: \(error.localizedDescription)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .rateLimited(let retryAfter):
                if let retryAfter = retryAfter {
                    return "Rate limited. Retry after \(retryAfter) seconds."
                }
                return "Rate limited. Please try again later."
            case .unauthorized:
                return "Unauthorized. Please check your API token."
            case .forbidden:
                return "Forbidden. Your API token may not have the required permissions."
            case .notFound:
                return "Resource not found"
            case .serverError(let statusCode):
                return "Server error: \(statusCode)"
            }
        }
    }
    
    private struct APIResponse<T: Codable>: Codable {
        let data: T?
        let error: String?
        let errors: [String]?
    }
    
    func request<T: Codable>(
        url: URL,
        method: HTTPMethod = .GET,
        headers: [String: String] = [:],
        body: Data? = nil,
        responseType: T.Type,
        serviceName: String = "Unknown"
    ) async throws -> T {
        
        let startTime = Date()
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        
        // Set default headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add custom headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        logger.logAPICall(service: serviceName, endpoint: url.path, method: method.rawValue)
        
        do {
            let (data, response) = try await session.data(for: request)
            let responseTime = Date().timeIntervalSince(startTime)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError(URLError(.badServerResponse))
            }
            
            logger.logAPIResponse(service: serviceName, statusCode: httpResponse.statusCode, responseTime: responseTime)
            
            // Handle different HTTP status codes
            switch httpResponse.statusCode {
            case 200...299:
                // Success
                break
            case 401:
                throw APIError.unauthorized
            case 403:
                throw APIError.forbidden
            case 404:
                throw APIError.notFound
            case 429:
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                throw APIError.rateLimited(retryAfter: retryAfter)
            case 500...599:
                throw APIError.serverError(httpResponse.statusCode)
            default:
                let errorMessage = String(data: data, encoding: .utf8)
                throw APIError.requestFailed(httpResponse.statusCode, errorMessage)
            }
            
            guard !data.isEmpty else {
                throw APIError.noData
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                // Try to decode as the expected type first
                if let result = try? decoder.decode(T.self, from: data) {
                    return result
                }
                
                // If that fails, try to decode as a wrapped response
                if let wrappedResponse = try? decoder.decode(APIResponse<T>.self, from: data) {
                    if let result = wrappedResponse.data {
                        return result
                    } else if let error = wrappedResponse.error {
                        throw APIError.requestFailed(httpResponse.statusCode, error)
                    } else if let errors = wrappedResponse.errors, !errors.isEmpty {
                        throw APIError.requestFailed(httpResponse.statusCode, errors.joined(separator: ", "))
                    }
                }
                
                // If all else fails, try to decode as the raw type again and let the error propagate
                return try decoder.decode(T.self, from: data)
                
            } catch {
                logger.error("Failed to decode API response: \(error)")
                throw APIError.decodingError(error)
            }
            
        } catch let error as APIError {
            throw error
        } catch {
            logger.error("Network error: \(error)")
            throw APIError.networkError(error)
        }
    }
    
    func get<T: Codable>(
        url: URL,
        headers: [String: String] = [:],
        responseType: T.Type,
        serviceName: String = "Unknown"
    ) async throws -> T {
        return try await request(
            url: url,
            method: .GET,
            headers: headers,
            responseType: responseType,
            serviceName: serviceName
        )
    }
    
    func post<T: Codable, U: Codable>(
        url: URL,
        headers: [String: String] = [:],
        body: T,
        responseType: U.Type,
        serviceName: String = "Unknown"
    ) async throws -> U {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let bodyData: Data
        do {
            bodyData = try encoder.encode(body)
        } catch {
            throw APIError.encodingError(error)
        }
        
        return try await request(
            url: url,
            method: .POST,
            headers: headers,
            body: bodyData,
            responseType: responseType,
            serviceName: serviceName
        )
    }
    
    func withRetry<T>(
        operation: () async throws -> T,
        maxRetries: Int = 1,
        delay: TimeInterval = 2.0
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch let error as APIError {
                lastError = error
                
                // Don't retry on certain errors
                switch error {
                case .unauthorized, .forbidden, .notFound, .invalidURL, .decodingError, .encodingError:
                    throw error
                case .rateLimited(let retryAfter):
                    if attempt < maxRetries {
                        let sleepTime = retryAfter.map(TimeInterval.init) ?? delay
                        logger.warning("Rate limited, retrying in \(sleepTime) seconds...")
                        try await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
                    }
                default:
                    if attempt < maxRetries {
                        logger.warning("Request failed, retrying in \(delay) seconds... (attempt \(attempt + 1)/\(maxRetries + 1))")
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }
            } catch {
                lastError = error
                if attempt < maxRetries {
                    logger.warning("Request failed, retrying in \(delay) seconds... (attempt \(attempt + 1)/\(maxRetries + 1))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? APIError.networkError(URLError(.unknown))
    }
}

extension APIClient {
    func testConnectivity(url: URL, headers: [String: String], serviceName: String) async -> Bool {
        do {
            struct PingResponse: Codable {
                let success: Bool?
                let message: String?
            }
            
            _ = try await get(
                url: url,
                headers: headers,
                responseType: PingResponse.self,
                serviceName: serviceName
            )
            return true
        } catch {
            logger.error("Connectivity test failed for \(serviceName): \(error)")
            return false
        }
    }
}