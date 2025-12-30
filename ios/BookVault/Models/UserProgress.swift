//
//  UserProgress.swift
//  BookVault
//
//  Created by Claude Code on 12/27/25.
//  Phase 4: Progress Sync
//

import Foundation

// MARK: - UserProgress

/// User progress for a book
struct UserProgress: Codable {
    let positionSeconds: Double
    let completed: Bool
    let lastPlayed: Date?

    enum CodingKeys: String, CodingKey {
        case positionSeconds
        case completed
        case lastPlayed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        positionSeconds = try container.decode(Double.self, forKey: .positionSeconds)
        completed = try container.decode(Bool.self, forKey: .completed)

        // lastPlayed can be null in the API response
        if let lastPlayedString = try container.decodeIfPresent(String.self, forKey: .lastPlayed) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            lastPlayed = formatter.date(from: lastPlayedString)
        } else {
            lastPlayed = nil
        }
    }

    init(positionSeconds: Double, completed: Bool, lastPlayed: Date?) {
        self.positionSeconds = positionSeconds
        self.completed = completed
        self.lastPlayed = lastPlayed
    }
}

// MARK: - SaveProgressRequest

/// Request body for saving progress
struct SaveProgressRequest: Codable {
    let bookId: String
    let positionSeconds: Double
    let timestamp: String?

    init(bookId: String, positionSeconds: Double, timestamp: Date? = nil) {
        self.bookId = bookId
        self.positionSeconds = positionSeconds

        if let timestamp {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.timestamp = formatter.string(from: timestamp)
        } else {
            self.timestamp = nil
        }
    }
}

// MARK: - SaveProgressResponse

/// Response from saving progress
struct SaveProgressResponse: Codable {
    let positionSeconds: Double
    let completed: Bool
    let lastPlayed: String?
    let updated: Bool
}
