//
//  SwingValidationRule.swift
//  golf-sync-swing
//
//  Protocol for polymorphic swing validation rules.
//  Each rule checks one aspect of a SwingNet analysis result.
//

import Foundation

enum ValidationResult {
    case pass
    case fail(reason: String)
}

protocol SwingValidationRule {
    var name: String { get }
    func validate(_ analysis: SwingNetAnalysis) -> ValidationResult
}
