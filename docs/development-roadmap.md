# Development Roadmap

**Last Updated**: December 29, 2025
**Current Phase**: Production-Ready (Web + iOS Complete)

> **TL;DR**: Web app and iOS app complete. Next priorities: AWS Deployment → User Lists (post-launch).

---

## 🎯 Current Focus (Next 2 Weeks)

### 1. Deployment Preparation 🚀

**Priority**: HIGH - Required before production launch
**Status**: Backend mobile-ready, infrastructure planning needed

**Checklist**:

- [ ] S3 upload script for audio files and images
- [ ] CloudFront CDN configuration for asset delivery
- [ ] Production environment variables setup
- [ ] Monitoring and error tracking (Sentry/CloudWatch)
- [ ] Performance testing and optimization
- [ ] Database query optimization review
- [ ] Caching strategy implementation (Redis/Memory)

**See**: [roadmap/aws-deployment.md](roadmap/aws-deployment.md) for infrastructure details

---

---

## 📅 Upcoming (Next Month)

### 2. AWS Deployment

**Infrastructure**:

- **Database**: RDS PostgreSQL
- **Storage**: S3 (audio + images) with CloudFront CDN
- **Hosting**: ECS or Lambda
- **Domain**: Route 53 + Certificate Manager (SSL)

**Timeline**: 1-2 weeks after lists feature complete

**See**: [roadmap/aws-deployment.md](roadmap/aws-deployment.md)

---

### ~~3. iOS Native App~~ ✅ COMPLETE (December 2025)

**Status**: All 8 phases implemented
**Technology**: Native Swift + SwiftUI

**Completed Phases**:

1. ✅ Auth & Browsing
2. ✅ Audio Playback (Basic)
3. ✅ Background Audio & Lock Screen
4. ✅ Progress Sync
5. ✅ Chapter Navigation
6. ✅ Search & Browse
7. ✅ Offline Downloads
8. ✅ Offline Mode (library caching, offline progress queue)

**Deferred**: User Lists (requires backend API development first)

**See**: [mobile-ios-plan.md](mobile-ios-plan.md) for maintenance docs and common commands

---

## 🔮 Future Ideas (Post-Launch)

### User Lists Feature 📚

**Priority**: Post-launch enhancement
**Status**: Deferred - nice to have, not essential for launch

Allow users to organize books into custom collections:

- "Want to Listen", "Favorites", "Currently Listening"
- Custom user-created lists
- Drag-to-reorder books within lists

**API endpoints needed**:

- `POST /api/lists` - Create list
- `GET /api/lists` - Get user's lists
- `POST /api/lists/[id]/books` - Add book to list
- `DELETE /api/lists/[id]/books/[bookId]` - Remove book from list
- `PUT /api/lists/[id]/reorder` - Reorder books

**See**: [roadmap/user-lists.md](roadmap/user-lists.md) for detailed implementation plan

---

### Enhanced Search

- Filters (category, narrator, series, date range, duration)
- Advanced search syntax
- Saved searches

### Performance Optimization

- Loading states and skeleton loaders
- Error boundaries
- Next.js Image optimization
- Caching headers on API responses

### Mobile Web Optimization

- Touch target improvements
- Mobile-specific layouts
- iOS/Android browser testing
- Gesture navigation

### Analytics & Insights

- Listening statistics
- Most played books/authors
- Listening streaks
- Personal recommendations

---

## ✅ Completed Milestones

### Phase 4: Enhancement & Features (Dec 2025)

- ✅ Audio Player with seeking, volume, speed control
- ✅ Chapter navigation with real-time highlighting
- ✅ Dark mode with system preference support
- ✅ User authentication (NextAuth.js)
- ✅ Progress tracking with auto-save
- ✅ Continue listening carousel
- ✅ Media Session API (lock screen controls)
- ✅ Storybook integration (184 tests passing)
- ✅ Mobile API backend support (S3 streaming, range requests)
- ✅ OpenAPI drift prevention (CI validates spec, checks stale types, runs contract tests)

### Phase 3: Core Features (Dec 2025)

- ✅ Search across books, authors, narrators, series
- ✅ Browse pages for all entity types
- ✅ Series detail pages with proper ordering
- ✅ Sort functionality (title, author, narrator, series)
- ✅ Customer reviews display
- ✅ Clickable category navigation
- ✅ Pagination UI controls

### Phase 2: Backend Core (Dec 2025)

- ✅ All API endpoints functional
- ✅ Database schema with 14 models
- ✅ Import script tested with 11+ books
- ✅ Prisma ORM integration

### Phase 1: Project Setup (Dec 2025)

- ✅ Next.js 14 app initialized
- ✅ PostgreSQL in Docker (port 5433)
- ✅ TypeScript strict mode
- ✅ Tailwind CSS configured
- ✅ Git repository with documentation

**See**: [STATUS.md](STATUS.md) for recent PRs and detailed completion status

---

## 📊 Success Metrics

### Current Achievement 🎉

- **Books imported**: 11+ with full metadata
- **API endpoints**: All functional and tested
- **Test coverage**: All tests passing
- **Features**: Browse, search, auth, progress, dark mode
- **Performance**: <2s page loads, <1s audio start
- **Mobile-ready**: Backend API supports iOS app development

### Next Milestones

- 🎯 Deployed to AWS production
- ~~🎯 iOS app complete~~ ✅ All 8 phases done
- 🎯 50+ books imported
- 🎯 User lists functional (post-launch)

---

## 📁 Related Documentation

| What                 | Where                                                |
| -------------------- | ---------------------------------------------------- |
| **iOS Maintenance**  | [mobile-ios-plan.md](mobile-ios-plan.md)             |
| **API Reference**    | [api-quick-ref.md](api-quick-ref.md)                 |
| **Architecture**     | [architecture.md](architecture.md)                   |
| **Historical Plans** | [archive/completed-plans/](archive/completed-plans/) |

---

## ❓ Questions?

**Not sure what to work on next?** Check "Current Focus" section above.

**Recent work?** See [STATUS.md](STATUS.md) for latest PRs.
