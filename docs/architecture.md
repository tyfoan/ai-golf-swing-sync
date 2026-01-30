# Architecture

> System design and data flow for Golf Sync Swing

## System Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         CLIENT                               │
│                    SwiftUI Views Layer                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      VIEW MODELS                             │
│              State Management & Business Logic               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        SERVICES                              │
│    SwingDetector │ VideoSyncEngine │ VideoExporter           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      DATA LAYER                              │
│              SwiftData │ AVFoundation │ Vision               │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. [Component Name]
**Purpose**: [What this component does]
**Key Files**: `src/path/to/file.ts`

## Data Flow

[Describe key data flows]

## Related Documents
- [Project Spec](../project_spec.md)
- [Changelog](./changelog.md)
- [Project Status](./project_status.md)
