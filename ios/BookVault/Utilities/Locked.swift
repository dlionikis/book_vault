//
//  Locked.swift
//  BookVault
//
//  A minimal lock-protected box for values that are genuinely shared across
//  actors.
//

import Foundation

/// A lock-protected box for a value read and written from more than one actor.
///
/// This exists because a plain `var` on a non-isolated class is rejected under
/// the Swift 6 language mode — correctly, since concurrent access to one really
/// is a data race. The alternatives were considered and rejected:
///
/// - **`@MainActor` on the holder**: would force every call site onto the main
///   actor, including request paths that deliberately run off it.
/// - **`actor`**: makes every access `await`, which turns simple synchronous
///   property reads (`if let token = accessToken`) into suspension points and
///   ripples through the call graph.
/// - **`nonisolated(unsafe)`**: silences the checker without fixing anything.
///
/// A lock keeps access synchronous and the semantics unchanged, which is what
/// makes this a safe refactor of existing code rather than a redesign.
///
/// Matches the `NSLock` + `@unchecked Sendable` approach already used by
/// `DebugLogger`'s verbose flag and `FileExtensionStorage` in `DownloadManager`.
///
/// `@unchecked` is sound here: `storage` is only ever touched while holding
/// `lock`, and `Value` is constrained to `Sendable` so what crosses the
/// boundary is safe to share.
final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ initial: Value) {
        storage = initial
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage = newValue
        }
    }

    /// Read-modify-write under a single lock acquisition.
    ///
    /// Prefer this over `value = f(value)`, which takes the lock twice and lets
    /// another writer interleave between the read and the write.
    @discardableResult
    func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&storage)
    }
}

/// Carries a **non-`Sendable`** value across an isolation boundary.
///
/// Unlike `Locked`, this provides no synchronization and makes no safety claim
/// of its own — it exists for values the compiler cannot prove safe but the
/// surrounding contract does. Every use must justify itself.
///
/// The motivating case is a system completion handler: the framework hands over
/// a plain (non-`Sendable`) closure, we must invoke it after hopping to another
/// actor, and the framework guarantees a single delivery. There is no shared
/// mutable state, so there is nothing to lock — only a type-system gap to cross.
///
/// Use `Locked` instead whenever the value is genuinely shared.
struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
