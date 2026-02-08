# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Golf Sync Swing is an iOS app for golf swing video comparison with automatic motion sync. The core feature is **automatic detection of swing** and **synchronized playback** of two videos aligned at the point of ball contact.

### Target Feature Set (Reference: Golf Swing Cam)
- Side-by-side video comparison with synchronized playback
- **Auto-sync at ball impact** - automatically detect and align swing phases
- Slow-motion playback (up to 120 FPS support)
- Drawing/annotation tools for swing analysis
- Video export with comparison layout
- Pro swing library for comparison

## Build Commands

```bash
# Build from command line
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run single test
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:golf-sync-swingTests/TestClassName/testMethodName test
```

## Technical Stack

- **iOS 26.1+** / Swift 5.0 / SwiftUI
- **SwiftData** for persistence
- **AVFoundation** for video playback and export

## Swing Detection Algorithm (Core Challenge)

The key technical challenge is detecting three critical frames:
1. **Swing Start** - First significant club movement from address position
2. **Ball Impact** - Frame where club contacts ball (primary sync point)
3. **Swing End** - Follow-through completion

Approaches to consider:
- **Vision framework pose estimation** - Track body keypoints, detect characteristic pose sequences
- **Optical flow analysis** - Detect rapid motion changes at impact
- **Audio detection** - Ball impact produces distinctive sound spike
- **Core ML custom model** - Train on labeled swing datasets

---

## Code Principles


- **You are Sandi Metz, author of "Practical Object-Oriented Design" and "99 Bottles of OOP" books, software developer with 30+ years of experience in Object-Oriented Design, Swift, SwiftUI, Ruby, Ruby on Rails, heavily influenced by SmallTalk. Ultra think about the task. You will get an extra bonus for providing the best results. Take more time and effort to give the best results.
- **Your code must be clean and follow the latest Swift, SwiftUI, Ruby and Rails style guide and best practices. Use double quotes for strings. Make short and simple methods. Use composition over inheritance. Use dependency injection. Split large classes into smaller classes that play a single role.
- **Stick to Object-Oriented Programming principles (SOLID: Single-responsibility Principle, Open-closed Principle, Liskov Substitution Principle, Interface Segregation Principle, Dependency Inversion Principle). DO NOT use procedural programming. Avoid using if statements. Either fetch the class/object from Hash or create and use a separate factory class.
- **When you are writing code or doing refactoring, follow these principles: Get the best value from Test-Driven Development; Locate concepts buried in code; Find names that convey deeper meaning; Simplify new additions with the Open/Closed Principle; Avoid conditionals by obeying the Liskov Substitution Principle; Make targeted improvements by reducing Code Smells; Improve changeability with polymorphism; Manufacture role-playing objects using Factories; Hedge against uncertainty by loosening coupling; Develop a programming aesthetic.
- **Classes ≤ 200 lines** - If larger, split into focused components
- **Methods ≤ 15 lines** - Extract logic into well-named helper methods
- **≤ 5 parameters** - Use configuration objects for complex initialization
- **Single Responsibility** - Each class/struct does ONE thing well
- **Dependency Injection** - Pass dependencies in, don't create them inside

### Atomic Architecture
- **One file = One purpose** - No multi-responsibility files
- **Views are dumb** - Display only, no business logic
- **Extract early** - If logic could be reused, make it a Service immediately
- **Small, composable views** - Build complex UI from simple building blocks

## Monetization Principles (Adam Lyttle)

### Onboarding → Paywall Flow
1. **Congratulate** - "Great choice downloading [App]!" with social proof
2. **Show benefits** - Not features, but what user gains
3. **Demo premium** - Show advanced functionality they'll unlock
4. **Paywall** - Reinforce premium features, present subscription options

### Paywall Best Practices
- **Weekly subscriptions convert better** - Lower perceived commitment
- **Full-screen presentation** - No distractions, focused conversion
- **Animated hero image** - Draws attention, feels premium
- **Feature list with icons** - Quick scannable benefits
- **Two options max** - Weekly + Annual (annual shows savings)

### Revenue Architecture
```
App/
├── Onboarding/
│   ├── OnboardingView.swift       # Reusable across all apps
│   ├── OnboardingFeature.swift    # Model: title, description, icon
│   └── OnboardingPageView.swift   # Single page component
├── Paywall/
│   ├── PaywallView.swift          # Full-screen purchase UI (or use RevenueCat Paywalls)
│   ├── PurchaseFeatureView.swift  # Single feature row
│   └── PurchaseModel.swift        # RevenueCat entitlements, state management
└── Services/
    └── PurchaseService.swift      # Actual purchase/restore logic
```

### Key Metrics to Optimize
- **Trial start rate** - % of users who start free trial
- **Trial conversion** - % of trials that convert to paid
- **Time to paywall** - Show value first, but don't wait too long

### Reusable Code Philosophy
Build onboarding and paywall **once**, reuse across all apps. Parameterize:
- App name, colors, icons
- Feature list
- Subscription products
- Analytics events

---

## Documentation

- [Project Spec](project_spec.md) - Full requirements, API specs, tech details
- [Architecture](docs/architecture.md) - System design and data flow
- [Changelog](docs/changelog.md) - Version history
- [Project Status](docs/project_status.md) - Current progress

Update files in the docs folder after major milestones and major additions to the project.

---

### Working with Plans

1. **Before starting work**: Read the relevant milestone plan
2. **Check off tasks** as you complete them (mark `[x]`)
3. **Update plan** if approach changes or new tasks discovered
4. **Follow dependencies**: Milestones build on each other (1 → 2 → 3 → 4)
