//
//  PhotoStorageService.swift
//  Regimen
//

import UIKit
import Supabase

/// Uploads/reads progress photo JPEGs in the private `progress-photos`
/// Supabase Storage bucket. The bucket is private (not public) because
/// these are personal photos — access always goes through short-lived
/// signed URLs rather than a permanently guessable public link. Storage
/// policies (see `supabase/schema.sql`) scope each user to a folder named
/// after their own auth UID, so one user can never read or overwrite
/// another's files even with a crafted path.
enum PhotoStorageService {
    private static var bucket: String { "progress-photos" }
    private static let signedURLLifetime = 3600

    static func upload(image: UIImage, userID: UUID) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw PhotoStorageError.encodingFailed
        }
        let path = "\(userID.uuidString)/\(UUID().uuidString).jpg"
        try await SupabaseManager.client.storage
            .from(bucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        return path
    }

    /// Signs every given path in parallel and returns whatever succeeded,
    /// keyed by storage path. A path that fails to sign (e.g. deleted out
    /// from under us) is silently dropped rather than failing the whole
    /// batch — the UI just shows a placeholder for that one photo.
    static func signedURLs(for paths: [String]) async -> [String: URL] {
        guard !paths.isEmpty else { return [:] }
        let results = try? await SupabaseManager.client.storage
            .from(bucket)
            .createSignedURLs(paths: paths, expiresIn: signedURLLifetime)

        var mapping: [String: URL] = [:]
        for result in results ?? [] {
            if case let .success(path, signedURL) = result {
                mapping[path] = signedURL
            }
        }
        return mapping
    }

    static func delete(path: String) async throws {
        _ = try await SupabaseManager.client.storage
            .from(bucket)
            .remove(paths: [path])
    }
}

enum PhotoStorageError: Error {
    case encodingFailed
}
