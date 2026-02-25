//
//  SchemaVersioning.swift
//  golf-sync-swing
//
//  SwiftData schema versioning and migration plan.
//

import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [SwingVideo.self, SwingMarker.self, ComparisonSession.self]
    }
}

enum SwingDataMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
