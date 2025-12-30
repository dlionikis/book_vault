//
//  MockData.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//  Shared mock data for Xcode Previews
//

import Foundation

// MARK: - Book Mock Data

extension Book {
    /// Standard audiobook example
    static let mockStandard = Book(
        id: UUID(),
        asin: "B08G9PRS1K",
        title: "Project Hail Mary",
        description: """
        **#1 NEW YORK TIMES BESTSELLER • From the author of *The Martian*, a lone astronaut must save the earth from disaster in this "propulsive" (Entertainment Weekly), cinematic thriller full of suspense, humor, and fascinating science—in development as a major motion picture starring Ryan Gosling.

        "If you loved *The Martian*, you'll go crazy for Weir's latest."—*The Washington Post*
        """,
        runtimeMinutes: 967,
        releaseDate: Date(timeIntervalSince1970: 1_620_000_000), // May 2021
        publisher: "Audible Studios",
        coverUrl: "https://m.media-amazon.com/images/I/91vS2wAT8jL._SL1500_.jpg",
        audioUrl: "https://example.com/audio/project-hail-mary.mp3",
        authors: [
            Author(id: UUID(), name: "Andy Weir", asin: "B00G0WYW92")
        ],
        narrators: [
            Narrator(id: UUID(), name: "Ray Porter", asin: "B001PJTOQE")
        ],
        series: nil,
        categories: [
            Category(id: UUID(), name: "Science Fiction"),
            Category(id: UUID(), name: "Space Opera")
        ]
    )

    /// Book with long title (tests text wrapping)
    static let mockLongTitle = Book(
        id: UUID(),
        asin: "B002V1A0WE",
        title: "The Way of Kings: Book One of the Stormlight Archive",
        description: "Epic fantasy from Brandon Sanderson.",
        runtimeMinutes: 2735,
        releaseDate: Date(timeIntervalSince1970: 1_283_299_200), // Sept 2010
        publisher: "Macmillan Audio",
        coverUrl: "https://m.media-amazon.com/images/I/91jW9GZ8aTL._SL1500_.jpg",
        audioUrl: "https://example.com/audio/way-of-kings.mp3",
        authors: [
            Author(id: UUID(), name: "Brandon Sanderson", asin: "B001IGFHW6")
        ],
        narrators: [
            Narrator(id: UUID(), name: "Kate Reading", asin: "B001LBFQSO"),
            Narrator(id: UUID(), name: "Michael Kramer", asin: "B001LBFQTI")
        ],
        series: [
            SeriesInfo(id: UUID(), title: "The Stormlight Archive", sequence: "1", asin: "B006K1M4YI")
        ],
        categories: [
            Category(id: UUID(), name: "Epic Fantasy")
        ]
    )

    /// Book without optional fields
    static let mockMinimal = Book(
        id: UUID(),
        asin: "B001234567",
        title: "Short Book",
        description: nil,
        runtimeMinutes: 120,
        releaseDate: nil,
        publisher: nil,
        coverUrl: "https://via.placeholder.com/300x450",
        audioUrl: "https://example.com/audio/short.mp3",
        authors: [
            Author(id: UUID(), name: "Unknown Author", asin: nil)
        ],
        narrators: nil,
        series: nil,
        categories: nil
    )

    /// Book with multiple authors
    static let mockMultipleAuthors = Book(
        id: UUID(),
        asin: "B07D23CFGR",
        title: "Good Omens",
        description: "The classic collaboration from the internationally bestselling authors Neil Gaiman and Terry Pratchett.",
        runtimeMinutes: 744,
        releaseDate: Date(timeIntervalSince1970: 642_643_200), // May 1990
        publisher: "Random House Audio",
        coverUrl: "https://m.media-amazon.com/images/I/81u7S+aEQyL._SL1500_.jpg",
        audioUrl: "https://example.com/audio/good-omens.mp3",
        authors: [
            Author(id: UUID(), name: "Neil Gaiman", asin: "B000AQ01G2"),
            Author(id: UUID(), name: "Terry Pratchett", asin: "B000AQ0VQU")
        ],
        narrators: [
            Narrator(id: UUID(), name: "Martin Jarvis", asin: "B001PJQX9E")
        ],
        series: nil,
        categories: [
            Category(id: UUID(), name: "Fantasy"),
            Category(id: UUID(), name: "Humor")
        ]
    )
}

// MARK: - Chapter Mock Data

extension Chapter {
    /// Standard chapter
    static let mockChapter1 = Chapter(
        id: UUID(),
        title: "Chapter 1: A Place for Demons",
        startTime: 0,
        endTime: 1806.5,
        duration: 1806.5,
        index: 1
    )

    static let mockChapter2 = Chapter(
        id: UUID(),
        title: "Chapter 2: The Beginning of the End",
        startTime: 1806.5,
        endTime: 3612.0,
        duration: 1805.5,
        index: 2
    )

    static let mockChapter3 = Chapter(
        id: UUID(),
        title: "Chapter 3: A Very Long Chapter Title That Should Wrap to Multiple Lines to Test Layout",
        startTime: 3612.0,
        endTime: 5418.0,
        duration: 1806.0,
        index: 3
    )

    /// Array of chapters for testing lists
    static let mockChapters = [
        mockChapter1,
        mockChapter2,
        mockChapter3,
        Chapter(
            id: UUID(),
            title: "Chapter 4: Discovery",
            startTime: 5418.0,
            endTime: 7224.0,
            duration: 1806.0,
            index: 4
        ),
        Chapter(
            id: UUID(),
            title: "Chapter 5: The Journey Begins",
            startTime: 7224.0,
            endTime: 9030.0,
            duration: 1806.0,
            index: 5
        )
    ]
}

// MARK: - UserProgress Mock Data

// periphery:ignore - Mock data for SwiftUI Previews and testing
extension UserProgress {
    /// Just started
    static let mockStarted = UserProgress(
        positionSeconds: 125.5,
        completed: false,
        lastPlayed: Date()
    )

    /// Halfway through
    static let mockHalfway = UserProgress(
        positionSeconds: 14500.0,
        completed: false,
        lastPlayed: Date()
    )

    /// Nearly complete
    static let mockNearlyComplete = UserProgress(
        positionSeconds: 28500.0,
        completed: false,
        lastPlayed: Date()
    )

    /// Completed
    static let mockCompleted = UserProgress(
        positionSeconds: 29020.0,
        completed: true,
        lastPlayed: Date(timeIntervalSinceNow: -86400) // Yesterday
    )

    /// Not started
    static let mockNotStarted = UserProgress(
        positionSeconds: 0,
        completed: false,
        lastPlayed: nil
    )
}

// MARK: - Supporting Types Mock Data

// periphery:ignore - Mock data for SwiftUI Previews and testing
extension Author {
    static let mockAndyWeir = Author(
        id: UUID(),
        name: "Andy Weir",
        asin: "B00G0WYW92"
    )

    static let mockBrandonSanderson = Author(
        id: UUID(),
        name: "Brandon Sanderson",
        asin: "B001IGFHW6"
    )
}

// periphery:ignore - Mock data for SwiftUI Previews and testing
extension Narrator {
    static let mockRayPorter = Narrator(
        id: UUID(),
        name: "Ray Porter",
        asin: "B001PJTOQE"
    )

    static let mockKateReading = Narrator(
        id: UUID(),
        name: "Kate Reading",
        asin: "B001LBFQSO"
    )
}

// periphery:ignore - Mock data for SwiftUI Previews and testing
extension Category {
    static let mockSciFi = Category(
        id: UUID(),
        name: "Science Fiction"
    )

    static let mockFantasy = Category(
        id: UUID(),
        name: "Fantasy"
    )
}

// periphery:ignore - Mock data for SwiftUI Previews and testing
extension SeriesInfo {
    static let mockStormlightArchive = SeriesInfo(
        id: UUID(),
        title: "The Stormlight Archive",
        sequence: "1",
        asin: "B006K1M4YI"
    )
}
