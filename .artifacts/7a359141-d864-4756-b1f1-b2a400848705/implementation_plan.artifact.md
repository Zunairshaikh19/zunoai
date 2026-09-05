# Implementation Plan - Dashboard Cache Functionality

Implement a complete caching layer for the dashboard to provide an "Offline First" experience and faster load times.

## Proposed Changes

### [Models]

#### [MODIFY] [image_prompt.dart](file:///D:/zunoai/lib/models/image_prompt.dart)
- Add `toMap()` and `fromJson()` methods for serialization. (Already done in previous step)

### [Services]

#### [NEW] [local_cache_service.dart](file:///D:/zunoai/lib/services/local_cache_service.dart)
- Implement `LocalCacheService` using `shared_preferences`.
- Functions: `savePrompts`, `getCachedPrompts`.

### [Providers & Logic]

#### [MODIFY] [dashboard_screen.dart](file:///D:/zunoai/lib/features/dashboard/presentation/dashboard_screen.dart)
- Update `promptsProvider` to an `AsyncNotifierProvider`.
- Implement cache-first, then network update logic.
- Add `RefreshIndicator` for manual updates.

## Verification Plan

### Manual Verification
- Open the app with internet: Verify data loads and is saved to cache.
- Close the app and turn off internet: Verify dashboard still shows purana data from cache.
- Turn on internet and pull to refresh: Verify data updates from Firebase.
