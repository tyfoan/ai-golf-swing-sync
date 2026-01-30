# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added
- **Video Import**: PHPicker integration for importing videos from photo library
- **Video Playback**: Single video player with play/pause, speed controls, and timeline scrubbing
- **Side-by-Side Comparison**: ComparisonView with synchronized dual video playback
- **Manual Swing Marking**: Three-handle slider for marking swing start (green), ball contact (orange), and swing end (green)
- **Swing Editor Sheet**: Full UI for adding, editing, and deleting swing markers
- **History Tab**: List of all recordings with swing counts, tap to view/edit swings
- **Video Export**: Side-by-side video composition export to Photos library
- **Data Models**: SwingVideo, SwingMarker, ComparisonSession with SwiftData persistence
- **Services**: VideoStorageService, ThumbnailService, VideoExportService
- **Tab Navigation**: MainTabView with Compare and Recordings tabs
- Photo Library usage descriptions in project settings

### Changed
- Replaced Xcode template ContentView/Item with custom app architecture
- Updated SwiftData schema to use SwingVideo, SwingMarker, ComparisonSession

---

## [0.1.0] - 2026-01-30

### Added
- CLAUDE.md with project overview, build commands, and architecture guidance
- Code principles: Sandi Metz rules (adapted for Swift), atomic architecture, service extraction
- Monetization principles: Adam Lyttle onboarding/paywall patterns
- Documentation structure: project_spec.md, architecture.md, changelog.md, project_status.md
- Complete project specification with PRD and engineering design
- Initial Xcode project scaffolding
- SwiftData model setup
