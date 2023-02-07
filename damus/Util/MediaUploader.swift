//
//  MediaUploader.swift
//  damus
//
//  Created by Shinichiro Oba on 2023/02/07.
//

import Foundation
import Combine

class MediaUploader {
    
    static var shared = MediaUploader()
    
    @MainActor
    @Published var isUploading = false
    
    func upload(mimeType: String, fileExtension: String, data: Data) async throws -> URL {
        defer {
            Task { @MainActor in
                isUploading = false
            }
        }
        
        await Task { @MainActor in
            isUploading = true
        }.value
        
        let url = URL(string: "https://nostr.build/upload.php")!
        let boundary = UUID().uuidString
        let paramName = "fileToUpload"
        let fileName = "file." + fileExtension
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var bodyData = Data()
        bodyData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"\(paramName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        bodyData.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        bodyData.append(data)
        bodyData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        let response = try await URLSession.shared.upload(for: urlRequest, from: bodyData)
        guard let htmlString = String(data: response.0, encoding: .utf8) else { throw Error.invalidEncoding }
        
        let regex = /https:\/\/nostr\.build\/(?:i|av)\/nostr\.build_[a-z0-9]{64}\.[a-z0-9]+/
        guard let match = htmlString.firstMatch(of: regex) else { throw Error.notFoundUrl }
        guard let url = URL(string: String(match.0)) else { throw Error.invalidUrl }
        
        return url
    }
}

extension MediaUploader {
    enum Error: Swift.Error {
        case invalidEncoding
        case notFoundUrl
        case invalidUrl
    }
}
