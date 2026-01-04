# Development Roadmap

**Last Updated**: January 4, 2026
**Current Phase**: ✅ DEPLOYED TO PRODUCTION

> **TL;DR**: Web app, iOS app, and AWS deployment complete. Live at https://bookvault.lionikis.com. Next priority: User Lists (post-launch).

---

## 🎯 Current Status

### ✅ AWS Deployment - COMPLETE (December 31, 2025)

**Live URL**: https://bookvault.lionikis.com

**Infrastructure**:

- **Database**: RDS PostgreSQL
- **Storage**: S3 (514 GB, 691 books) with presigned URLs
- **Hosting**: ECS Fargate with Application Load Balancer
- **Domain**: Custom domain + ACM SSL certificate

**Completed**:

- [x] S3 media upload (2,781 files)
- [x] RDS PostgreSQL with migrations
- [x] ECS Fargate deployment
- [x] SSL/HTTPS with custom domain
- [x] Presigned S3 URLs for secure media access
- [x] IAM task role support for ECS credentials

**Optional/Deferred**:

- [ ] CloudFront CDN (not required, presigned URLs work well)
- [ ] Monitoring/alerting (CloudWatch logs enabled)

**See**: [aws-deployment-plan.md](aws-deployment-plan.md) for complete deployment reference

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

**Post-launch enhancement**: ✅ Background Downloads (Jan 2026) - Downloads continue when app backgrounded

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

### Phase 5: AWS Deployment (Dec 31, 2025)

- ✅ S3 media storage (514 GB, 691 books)
- ✅ RDS PostgreSQL database
- ✅ ECS Fargate container hosting
- ✅ Application Load Balancer + SSL
- ✅ Custom domain (bookvault.lionikis.com)
- ✅ Presigned S3 URLs for secure media access
- ✅ IAM task role support for ECS credentials

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

- ~~🎯 Deployed to AWS production~~ ✅ Live at bookvault.lionikis.com
- ~~🎯 iOS app complete~~ ✅ All 8 phases done
- ~~🎯 50+ books imported~~ ✅ 691 books in production
- 🎯 User lists functional (post-launch)

---

## 📁 Related Documentation

| What                 | Where                                                |
| -------------------- | ---------------------------------------------------- |
| **AWS Deployment**   | [aws-deployment-plan.md](aws-deployment-plan.md)     |
| **iOS Maintenance**  | [mobile-ios-plan.md](mobile-ios-plan.md)             |
| **API Reference**    | [api-quick-ref.md](api-quick-ref.md)                 |
| **Architecture**     | [architecture.md](architecture.md)                   |
| **Historical Plans** | [archive/completed-plans/](archive/completed-plans/) |

---

## ❓ Questions?

**Not sure what to work on next?** Check "Current Focus" section above.

**Recent work?** See [STATUS.md](STATUS.md) for latest PRs.
