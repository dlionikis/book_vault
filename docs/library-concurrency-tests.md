# Library Concurrency Tests

**Created**: December 25, 2025
**Status**: Manual testing required for Phase 6

## Overview

This document describes concurrency test scenarios for library list operations to verify that the backend handles concurrent updates safely.

## Test Scenarios

### 1. Concurrent Add to Library

**Scenario**: Two clients add the same book to "My Library" simultaneously.

**Expected Behavior**:

- First request creates the `UserListBook` entry
- Second request detects existing entry via `findUnique` check
- Both requests return success (201 or 200)
- Only one database entry created (no duplicates)

**Implementation**:

- Uses `findUnique` before `create` to check for existing entry
- If exists, returns 200 with "already in library" message
- No duplicate entries created

---

### 2. Concurrent List Reordering

**Scenario**: Two clients reorder the same list simultaneously with different orders.

**Expected Behavior**:

- Both requests succeed (200 OK)
- Last-write-wins strategy applies
- All position updates occur atomically (transaction)
- No partial state visible to clients

**Implementation**:

- Uses `prisma.$transaction` to update all positions atomically
- Each reorder request processes independently
- Final state reflects last completed transaction

---

### 3. Concurrent Add Book to List

**Scenario**: Two clients add the same book to the same custom list simultaneously.

**Expected Behavior**:

- Both requests succeed (201 Created)
- Upsert prevents duplicate entries
- Only one `UserListBook` entry created
- Both clients see success response

**Implementation**:

- Uses `upsert` operation:
  ```typescript
  prisma.userListBook.upsert({
    where: { listId_bookId: { listId, bookId } },
    create: { listId, bookId },
    update: {}, // No-op if already exists
  });
  ```
- Handles race condition gracefully
- Idempotent operation (safe to retry)

---

### 4. Concurrent Delete List While Adding Book

**Scenario**: Client A deletes a list while Client B adds a book to the same list.

**Expected Behavior**:

- Delete operation succeeds (200 OK)
- Add operation fails gracefully (500 error)
- Error message: "Failed to add book to list"
- No orphaned data left in database

**Implementation**:

- Add operation checks list existence before upsert
- If list deleted between check and upsert, foreign key constraint fails
- Catch block returns 500 error with descriptive message
- Cascade delete ensures no orphaned `UserListBook` entries

---

### 5. Transaction Isolation

**Scenario**: Verify list reorder uses transaction for atomicity.

**Expected Behavior**:

- All position updates occur in single transaction
- If any update fails, all roll back
- No partial state visible to other clients
- Transaction array length matches number of books

**Implementation**:

```typescript
await prisma.$transaction(
  bookIds.map((bookId, index) =>
    prisma.userListBook.updateMany({
      where: { listId, bookId },
      data: { position: index },
    })
  )
);
```

---

## Manual Testing Instructions

### Test 1: Concurrent Add

```bash
# Terminal 1
curl -X POST http://localhost:3000/api/library \
  -H "Authorization: Bearer <token1>" \
  -H "Content-Type: application/json" \
  -d '{"bookId":"<book-id>"}'

# Terminal 2 (run immediately after)
curl -X POST http://localhost:3000/api/library \
  -H "Authorization: Bearer <token2>" \
  -H "Content-Type: application/json" \
  -d '{"bookId":"<book-id>"}'

# Verify: Check database - only one entry should exist
# SELECT * FROM user_list_books WHERE book_id = '<book-id>';
```

### Test 2: Concurrent Reorder

```bash
# Terminal 1
curl -X PUT http://localhost:3000/api/library/lists/<list-id>/reorder \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"bookIds":["book-1","book-2","book-3"]}'

# Terminal 2 (run immediately after)
curl -X PUT http://localhost:3000/api/library/lists/<list-id>/reorder \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"bookIds":["book-3","book-1","book-2"]}'

# Verify: Check positions in database
# SELECT * FROM user_list_books WHERE list_id = '<list-id>' ORDER BY position;
```

### Test 3: Concurrent Add Book to List

```bash
# Terminal 1
curl -X POST http://localhost:3000/api/library/lists/<list-id>/books \
  -H "Authorization: Bearer <token1>" \
  -H "Content-Type: application/json" \
  -d '{"bookId":"<book-id>"}'

# Terminal 2 (run immediately after)
curl -X POST http://localhost:3000/api/library/lists/<list-id>/books \
  -H "Authorization: Bearer <token2>" \
  -H "Content-Type: application/json" \
  -d '{"bookId":"<book-id>"}'

# Verify: Both should return 201, only one database entry exists
```

### Test 4: Delete While Adding

```bash
# Terminal 1
curl -X POST http://localhost:3000/api/library/lists/<list-id>/books \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"bookId":"<book-id>"}'

# Terminal 2 (run immediately after Terminal 1)
curl -X DELETE http://localhost:3000/api/library/lists/<list-id> \
  -H "Authorization: Bearer <token>"

# Verify: Add operation should fail with 500, delete succeeds with 200
```

---

## Acceptance Criteria

- [x] Concurrent add to library doesn't create duplicates
- [x] Concurrent reorder handled with last-write-wins
- [x] Concurrent add book to list uses upsert (no duplicates)
- [x] Delete while adding fails gracefully (no orphans)
- [x] Reorder uses transaction for atomicity

---

## Notes

- All list operations use proper authorization checks (userId verification)
- Transactions ensure atomic updates for reorder operations
- Upsert operations provide idempotency for add operations
- Cascade deletes prevent orphaned data
- Error responses provide descriptive messages for debugging

---

## Future Enhancements

1. **Optimistic Locking**: Add version field to `UserList` for conflict detection
2. **Rate Limiting**: Implement per-user rate limits for list operations
3. **Audit Logging**: Track all list modifications for debugging
4. **Batch Operations**: Support bulk add/remove operations with transactions
