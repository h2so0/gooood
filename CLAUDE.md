# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GoodDeal (굿딜) is a Korean shopping deal aggregation and price tracking app. It collects deals from multiple sources (Naver Shopping, 11번가, G마켓, 옥션), tracks price changes, and sends push notifications for price drops. Flutter frontend with Firebase backend (Firestore + Cloud Functions).

## Common Commands

### Flutter (run from project root `gooood/`)
```bash
flutter pub get          # Install dependencies
flutter run              # Run app (dev mode)
flutter analyze          # Static analysis (uses flutter_lints)
flutter test             # Run all tests
flutter test test/widget_test.dart  # Run a single test
flutter build apk        # Build Android release
flutter build ipa        # Build iOS release
flutter build web        # Build web release
```

### Cloud Functions (run from `functions/`)
```bash
npm install              # Install dependencies
npm run build            # Compile TypeScript (tsc)
npm run serve            # Build + run local emulator
npm run deploy           # Deploy functions to Firebase (runs tsc as predeploy)
```

### Firebase
```bash
firebase deploy --only firestore:rules    # Deploy Firestore rules
firebase deploy --only firestore:indexes  # Deploy Firestore indexes
firebase deploy --only hosting            # Deploy hosting
```

## Architecture

### Frontend (`lib/`)

Layered architecture with Riverpod for state management:

- **`screens/`** — UI pages. `main_screen.dart` is the tab-based root navigator. Sub-folders: `home/`, `detail/`, `wishlist/`, `settings/`.
- **`providers/`** — Riverpod providers. Uses `StateNotifierProvider` for mutable state (e.g., `HotProductsNotifier` with infinite scroll pagination). Uses `.autoDispose.family` for parameterized providers (e.g., `categoryProductsProvider`).
- **`services/`** — Business logic. `naver_shopping_api.dart` is the API client. `keyword_price_tracker.dart` and `keyword_price_analyzer.dart` handle price monitoring. `notification_service.dart` manages FCM.
- **`models/`** — Data classes: `Product`, `KeywordWishItem`, `KeywordPriceData`, `TrendData`.
- **`widgets/`** — Reusable components: product cards, deal badges, charts, skeletons.
- **`theme/`** — `app_theme.dart` defines dark (default) and light themes with semantic colors (`drop` for discounts, `rankUp`/`rankDown`, `star`).
- **`utils/`** — Formatters, URL helpers, keyword extraction.
- **`constants/`** — Cache keys, Hive box names, sub-category mappings.

### Backend (`functions/src/`)

TypeScript Cloud Functions on Node.js 22:

- **`index.ts`** — Entry point. Exports scheduled and HTTP functions.
- **`feed.ts`** — `syncDeals` runs every 15 min, fetching deals from all sources and writing to Firestore.
- **`fetchers/naver.ts`** — Naver Shopping API (today's deals, best 100, shopping live, promotions).
- **`fetchers/external.ts`** — 11번가, G마켓, 옥션 scrapers.
- **`notifications.ts`** — FCM push notification logic with quiet hours support.
- **`classify.ts`** — Gemini AI-based sub-category classification.
- **`config.ts`** — Category definitions, rate limits, timing constants.

### Data Flow

1. Cloud Functions (`syncDeals`) fetch deals from multiple sources on a schedule
2. Products are written to Firestore with `feedOrder`/`categoryFeedOrder` for pagination
3. Flutter app reads from Firestore using cursor-based pagination with wrap-around
4. Local storage: Hive for notification history (up to 100), SharedPreferences for settings

### Key Patterns

- **Product ID prefixes** indicate source: `deal_*` (today's deal), `best_*` (best 100), `live_*` (shopping live), `promo_*` (promotions), `11st_*`, `gmkt_*`, `auction_*` (external retailers)
- **Deep linking** via `https://gooddeal-app.web.app/product/{productId}` with native app fallbacks (Naver, 11번가, etc.)
- **Keyword wishlist** allows users to track up to 20 keywords with target price alerts and daily price snapshots
- **In-memory caching** (`MemoryCache`) for API responses in the Flutter app
