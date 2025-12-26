# Development Roadmap

**Last Updated**: December 25, 2025
**Current Phase**: Phase 4 - Enhancement & Features Complete

> **TL;DR**: Core app complete with auth, progress tracking, dark mode. Next priorities: User Lists → AWS Deployment → iOS App.

---

## 🎯 Current Focus (Next 2 Weeks)

### 1. User Lists Feature 📚

**Priority**: HIGH - Next major feature
**Status**: Not started

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

### 2. Deployment Preparation 🚀

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

## 📅 Upcoming (Next Month)

### 3. AWS Deployment

**Infrastructure**:

- **Database**: RDS PostgreSQL
- **Storage**: S3 (audio + images) with CloudFront CDN
- **Hosting**: ECS or Lambda
- **Domain**: Route 53 + Certificate Manager (SSL)

**Timeline**: 1-2 weeks after lists feature complete

**See**: [roadmap/aws-deployment.md](roadmap/aws-deployment.md)

---

### 4. iOS Native App 📱

**Status**: Planning complete, implementation post-deployment
**Technology**: Native Swift + SwiftUI
**Timeline**: Start after AWS deployment

**Implementation**: 8 phased rollout

1. Auth & Browsing
2. Audio Playback (Basic)
3. Background Audio & Lock Screen
4. Progress Sync
5. Chapter Navigation
6. Search & Browse
7. User Lists Sync
8. Offline Downloads

**Backend is ready**: JWT auth, RESTful JSON API, S3 streaming with range requests

**See**: [mobile-ios-plan.md](mobile-ios-plan.md) for complete implementation guide

---

## 🔮 Future Ideas (Backlog)

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
- **Test coverage**: 184 tests passing
- **Features**: Browse, search, auth, progress, dark mode
- **Performance**: <2s page loads, <1s audio start
- **Mobile-ready**: Backend API supports iOS app development

### Next Milestones

- 🎯 User lists functional
- 🎯 Deployed to AWS production
- 🎯 iOS app Phase 1 complete (auth & browsing)
- 🎯 50+ books imported

---

## 📁 Detailed Planning Docs

For implementation details, see `docs/roadmap/`:

| File                                             | Purpose                                            |
| ------------------------------------------------ | -------------------------------------------------- |
| [user-lists.md](roadmap/user-lists.md)           | User lists feature spec (to be created)            |
| [aws-deployment.md](roadmap/aws-deployment.md)   | AWS infrastructure guide (to be created)           |
| [enhanced-search.md](roadmap/enhanced-search.md) | Search filters & advanced features (to be created) |

For mobile development, see:

- [mobile-ios-plan.md](mobile-ios-plan.md) - Complete iOS implementation plan
- [api-mobile.md](api-mobile.md) - Mobile API quick reference

---

## 🔄 Maintenance

**Review frequency**: Update roadmap weekly during active development

**Archive policy**: Move completed items to [STATUS.md](STATUS.md) and archive detailed plans to `archive/completed-plans/`

---

## ❓ Questions?

**Not sure what to work on next?** Check "Current Focus" section above.

**Need implementation details?** See linked files in `roadmap/` folder.

**Historical context?** Check archived plans in `docs/archive/completed-plans/`

**Recent work?** See [STATUS.md](STATUS.md) for latest PRs and features.
