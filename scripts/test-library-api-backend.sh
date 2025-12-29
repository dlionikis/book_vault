#!/bin/bash
# Phase 8 Backend API Testing Script
# Tests all library-related API endpoints

set -e

API_BASE="http://localhost:3000/api"
TEST_USER_EMAIL="test@example.com"
TEST_USER_PASSWORD="password123"
TOKEN=""
BOOK_ID=""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🧪 Phase 8: Backend Library API Testing"
echo "========================================"
echo ""

# Function to check if jq is installed
check_jq() {
    if ! command -v jq &> /dev/null; then
        echo "❌ jq is required but not installed. Install with: brew install jq"
        exit 1
    fi
}

# Function to login and get token
login() {
    echo "🔐 Logging in as $TEST_USER_EMAIL..."
    local response=$(curl -s -X POST "$API_BASE/auth/mobile/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$TEST_USER_EMAIL\",\"password\":\"$TEST_USER_PASSWORD\"}")

    TOKEN=$(echo "$response" | jq -r '.accessToken // .token // .access_token // ""')

    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo -e "${RED}❌ Login failed${NC}"
        echo "Response: $response"
        exit 1
    fi

    echo -e "${GREEN}✅ Login successful${NC}"
    echo "   Token: ${TOKEN:0:20}..."
    echo ""
}

# Function to get a book ID from catalog
get_book_id() {
    echo "📚 Fetching a book from catalog..."
    local response=$(curl -s -X GET "$API_BASE/books?limit=1" \
        -H "Authorization: Bearer $TOKEN")

    BOOK_ID=$(echo "$response" | jq -r '.books[0].id // .data[0].id // ""')

    if [ -z "$BOOK_ID" ] || [ "$BOOK_ID" = "null" ]; then
        echo -e "${RED}❌ No books found in catalog${NC}"
        echo "Response: $response"
        exit 1
    fi

    echo -e "${GREEN}✅ Book ID obtained: $BOOK_ID${NC}"
    echo ""
}

# Test 1: GET /api/library (empty state)
test_library_empty() {
    echo "Test 1: GET /api/library (empty state)"
    echo "---------------------------------------"

    local response=$(curl -s -w "\n%{http_code}" -X GET "$API_BASE/library" \
        -H "Authorization: Bearer $TOKEN")

    local body=$(echo "$response" | sed '$d')
    local status=$(echo "$response" | tail -n 1)

    if [ "$status" = "200" ]; then
        local count=$(echo "$body" | jq '.books | length')
        echo -e "${GREEN}✅ Status: $status${NC}"
        echo "   Library books count: $count"
        echo "   Response preview: $(echo "$body" | jq -c '{total, bookCount: (.books | length)}')"
    else
        echo -e "${RED}❌ Status: $status (expected 200)${NC}"
        echo "   Response: $body"
        return 1
    fi
    echo ""
}

# Test 2: POST /api/library (add book)
test_add_to_library() {
    echo "Test 2: POST /api/library (add book)"
    echo "-------------------------------------"

    local response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/library" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"bookId\":\"$BOOK_ID\"}")

    local body=$(echo "$response" | sed '$d')
    local status=$(echo "$response" | tail -n 1)

    if [ "$status" = "200" ] || [ "$status" = "201" ]; then
        echo -e "${GREEN}✅ Status: $status${NC}"
        echo "   Book added successfully"
        echo "   Response: $body"
    else
        echo -e "${RED}❌ Status: $status (expected 200/201)${NC}"
        echo "   Response: $body"
        return 1
    fi
    echo ""
}

# Test 3: GET /api/library (with book)
test_library_with_book() {
    echo "Test 3: GET /api/library (with book)"
    echo "-------------------------------------"

    local response=$(curl -s -w "\n%{http_code}" -X GET "$API_BASE/library" \
        -H "Authorization: Bearer $TOKEN")

    local body=$(echo "$response" | sed '$d')
    local status=$(echo "$response" | tail -n 1)

    if [ "$status" = "200" ]; then
        local count=$(echo "$body" | jq '. | length')
        local has_book=$(echo "$body" | jq --arg id "$BOOK_ID" 'any(.[]; .id == $id or .bookId == $id)')

        echo -e "${GREEN}✅ Status: $status${NC}"
        echo "   Library books count: $count"
        echo "   Contains added book: $has_book"

        if [ "$has_book" = "true" ]; then
            echo -e "${GREEN}   ✅ Book found in library${NC}"
        else
            echo -e "${RED}   ❌ Book NOT found in library${NC}"
            echo "   Response: $body"
            return 1
        fi
    else
        echo -e "${RED}❌ Status: $status (expected 200)${NC}"
        echo "   Response: $body"
        return 1
    fi
    echo ""
}

# Test 4: GET /api/library/check?bookId={id}
test_check_in_library() {
    echo "Test 4: GET /api/library/check?bookId=$BOOK_ID"
    echo "------------------------------------------------"

    local response=$(curl -s -w "\n%{http_code}" -X GET "$API_BASE/library/check?bookId=$BOOK_ID" \
        -H "Authorization: Bearer $TOKEN")

    local body=$(echo "$response" | sed '$d')
    local status=$(echo "$response" | tail -n 1)

    if [ "$status" = "200" ]; then
        local in_library=$(echo "$body" | jq -r '.inLibrary')

        echo -e "${GREEN}✅ Status: $status${NC}"
        echo "   In library: $in_library"

        if [ "$in_library" = "true" ]; then
            echo -e "${GREEN}   ✅ Check endpoint confirms book is in library${NC}"
        else
            echo -e "${RED}   ❌ Check endpoint says book is NOT in library${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ Status: $status (expected 200)${NC}"
        echo "   Response: $body"
        return 1
    fi
    echo ""
}

# Test 5: DELETE /api/library/{bookId}
test_remove_from_library() {
    echo "Test 5: DELETE /api/library/$BOOK_ID"
    echo "-------------------------------------"

    local response=$(curl -s -w "\n%{http_code}" -X DELETE "$API_BASE/library/$BOOK_ID" \
        -H "Authorization: Bearer $TOKEN")

    local body=$(echo "$response" | sed '$d')
    local status=$(echo "$response" | tail -n 1)

    if [ "$status" = "200" ] || [ "$status" = "204" ]; then
        echo -e "${GREEN}✅ Status: $status${NC}"
        echo "   Book removed successfully"
        echo "   Response: $body"
    else
        echo -e "${RED}❌ Status: $status (expected 200/204)${NC}"
        echo "   Response: $body"
        return 1
    fi
    echo ""
}

# Test 6: Verify book removed
test_library_after_removal() {
    echo "Test 6: GET /api/library (verify removal)"
    echo "------------------------------------------"

    local response=$(curl -s -w "\n%{http_code}" -X GET "$API_BASE/library" \
        -H "Authorization: Bearer $TOKEN")

    local body=$(echo "$response" | sed '$d')
    local status=$(echo "$response" | tail -n 1)

    if [ "$status" = "200" ]; then
        local count=$(echo "$body" | jq '. | length')
        local has_book=$(echo "$body" | jq --arg id "$BOOK_ID" 'any(.[]; .id == $id or .bookId == $id)')

        echo -e "${GREEN}✅ Status: $status${NC}"
        echo "   Library books count: $count"
        echo "   Contains removed book: $has_book"

        if [ "$has_book" = "false" ]; then
            echo -e "${GREEN}   ✅ Book successfully removed from library${NC}"
        else
            echo -e "${RED}   ❌ Book still in library after removal${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ Status: $status (expected 200)${NC}"
        echo "   Response: $body"
        return 1
    fi
    echo ""
}

# Test 7: Check endpoint after removal
test_check_after_removal() {
    echo "Test 7: GET /api/library/check (after removal)"
    echo "-----------------------------------------------"

    local response=$(curl -s -w "\n%{http_code}" -X GET "$API_BASE/library/check?bookId=$BOOK_ID" \
        -H "Authorization: Bearer $TOKEN")

    local body=$(echo "$response" | sed '$d')
    local status=$(echo "$response" | tail -n 1)

    if [ "$status" = "200" ]; then
        local in_library=$(echo "$body" | jq -r '.inLibrary')

        echo -e "${GREEN}✅ Status: $status${NC}"
        echo "   In library: $in_library"

        if [ "$in_library" = "false" ]; then
            echo -e "${GREEN}   ✅ Check endpoint confirms book is NOT in library${NC}"
        else
            echo -e "${RED}   ❌ Check endpoint says book IS in library${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ Status: $status (expected 200)${NC}"
        echo "   Response: $body"
        return 1
    fi
    echo ""
}

# Main execution
main() {
    check_jq

    # Check if server is running
    if ! curl -s "$API_BASE/health" > /dev/null 2>&1; then
        echo -e "${RED}❌ Backend server is not running${NC}"
        echo "   Start with: npm run dev"
        exit 1
    fi

    echo -e "${GREEN}✅ Backend server is running${NC}"
    echo ""

    # Run all tests
    login
    get_book_id

    echo "🧪 Running Test Suite"
    echo "===================="
    echo ""

    PASSED=0
    FAILED=0

    # Run tests and track results
    if test_library_empty; then ((PASSED++)); else ((FAILED++)); fi
    if test_add_to_library; then ((PASSED++)); else ((FAILED++)); fi
    if test_library_with_book; then ((PASSED++)); else ((FAILED++)); fi
    if test_check_in_library; then ((PASSED++)); else ((FAILED++)); fi
    if test_remove_from_library; then ((PASSED++)); else ((FAILED++)); fi
    if test_library_after_removal; then ((PASSED++)); else ((FAILED++)); fi
    if test_check_after_removal; then ((PASSED++)); else ((FAILED++)); fi

    # Summary
    echo "📊 Test Summary"
    echo "==============="
    echo -e "   ${GREEN}Passed: $PASSED${NC}"
    echo -e "   ${RED}Failed: $FAILED${NC}"
    echo -e "   Total: $((PASSED + FAILED))"
    echo ""

    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}✅ All backend API tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some tests failed${NC}"
        exit 1
    fi
}

main
