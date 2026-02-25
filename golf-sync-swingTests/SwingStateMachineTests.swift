//
//  SwingStateMachineTests.swift
//  golf-sync-swingTests
//

import Testing
@testable import golf_sync_swing

struct SwingStateMachineTests {

    @Test("Starts in idle state")
    func startsIdle() {
        let machine = SwingStateMachine()
        #expect(machine.currentState == .idle)
    }

    @Test("Transitions to swingDetected on swing event")
    func detectsSwing() {
        let machine = SwingStateMachine()
        let event = SwingEvent.swingDetected(confidence: 0.8, timestamp: 1.5)
        let result = machine.handle(event: event)

        #expect(machine.currentState == .swingDetected)
        #expect(result != nil)
        #expect(result?.confidence == 0.8)
        #expect(result?.detectionTimestamp == 1.5)
    }

    @Test("Ignores swings during cooldown")
    func cooldownPreventsRetrigger() {
        let machine = SwingStateMachine(cooldownDuration: 2.0)
        _ = machine.handle(event: .swingDetected(confidence: 0.8, timestamp: 1.0))
        machine.transitionToReplay(impactTime: 1.0, startTime: 0.5, endTime: 2.0)

        let result = machine.handle(event: .swingDetected(confidence: 0.9, timestamp: 2.5))
        #expect(result == nil)
        #expect(machine.currentState == .cooldown)
    }

    @Test("Returns to idle after cooldown expires")
    func cooldownExpires() {
        let machine = SwingStateMachine(cooldownDuration: 2.0)
        _ = machine.handle(event: .swingDetected(confidence: 0.8, timestamp: 1.0))
        machine.transitionToReplay(impactTime: 1.0, startTime: 0.5, endTime: 2.0)

        let result = machine.handle(event: .swingDetected(confidence: 0.9, timestamp: 5.0))
        #expect(result != nil)
        #expect(machine.currentState == .swingDetected)
    }

    @Test("noSwing event does not change idle state")
    func noSwingStaysIdle() {
        let machine = SwingStateMachine()
        let result = machine.handle(event: .noSwing)
        #expect(result == nil)
        #expect(machine.currentState == .idle)
    }
}
