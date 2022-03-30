//
// MMMObservables. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

import XCTest
@testable import MMMObservables

public final class SimpleEventGroupObserverTestCase: XCTestCase {
    
    public func testBasics() {
        
        let event1 = SimpleEvent()
        let event2 = SimpleEvent()
        let event3 = LazySimpleEvent()
        
        let expectation = XCTestExpectation()
        expectation.assertForOverFulfill = true
        
        let observer = SimpleEventGroupObserver(events: event1, event2, event3) { _ in
            expectation.fulfill()
        }
        
        XCTAssertNotNil(observer)
        
        // Trigger all events, we only want a single callback.
        event1.trigger()
        event2.trigger()
        event3.trigger()
        
        wait(for: [expectation], timeout: 1)
    }
    
    public func testSimpleDebounce() {
        
        let event1 = SimpleEvent()
        let event2 = SimpleEvent()
        let event3 = LazySimpleEvent()
        
        let expectation = XCTestExpectation()
        expectation.assertForOverFulfill = true
        
        let startDate = Date()
        var triggerDate = Date()
        
        let observer = SimpleEventGroupObserver(
            events: event1, event2, event3,
            debounceTimeout: 0.1,
            debouncePolicy: .default
        ) { _ in
            
            triggerDate = Date()
            expectation.fulfill()
        }
        
        XCTAssertNotNil(observer)
        
        // Trigger all events, we only want a single callback.
        event1.trigger()
        event2.trigger()
        event3.trigger()
        
        wait(for: [expectation], timeout: 1)
        
        // Since we triggered all 3 events at the same time, we expect
        // the date difference to be around 0.1 seconds (as defined in
        // the debounceTimeout), with a little headroom.
        XCTAssert(triggerDate.timeIntervalSince(startDate) >= 0.1)
    }
    
    public func testDebounce() {
        
        let event1 = SimpleEvent()
        let event2 = SimpleEvent()
        let event3 = LazySimpleEvent()
        
        let expectation = XCTestExpectation()
        expectation.assertForOverFulfill = true
        
        let observer = SimpleEventGroupObserver(
            events: event1, event2, event3,
            debounceTimeout: 0.1,
            debouncePolicy: .default
        ) { _ in
            expectation.fulfill()
        }
        
        XCTAssertNotNil(observer)
        
        // Trigger all events, 0.05s after each other.
        let startDate = Date()
        
        event1.trigger()
        
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
            event2.trigger()
            
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
                event3.trigger()
            }
        }
        
        wait(for: [expectation], timeout: 1)
        
        // Since we triggered all 3 events with 0.05s between them, we expect
        // the date difference to be around 0.2 seconds (0.1 as defined in
        // the debounceTimeout, + 0.05 and 0.05), with a little headroom.
        XCTAssert(-startDate.timeIntervalSinceNow >= 0.2)
    }
    
    public func testLeadingDebounce() {
        
        let event1 = SimpleEvent()
        let event2 = SimpleEvent()
        let event3 = LazySimpleEvent()
        
        let expectation = XCTestExpectation()
        expectation.assertForOverFulfill = true
        
        let observer = SimpleEventGroupObserver(
            events: event1, event2, event3,
            debounceTimeout: 0.1,
            debouncePolicy: .debounceLeading
        ) { _ in
            
            expectation.fulfill()
        }
        
        XCTAssertNotNil(observer)
        
        let startDate = Date()
        
        // Trigger all events, 0.05s after each other.
        event1.trigger()
        
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
            event2.trigger()
            
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
                event3.trigger()
            }
        }
        
        wait(for: [expectation], timeout: 1)
        
        // Since we triggered all 3 events with 0.05s between them, we expect
        // the date difference to be almost 0, and no events after that; the assertForOverFulfill
        // handles this case.
        XCTAssert(-startDate.timeIntervalSinceNow >= 0)
    }
    
    public func testThrottle() {
        
        let event1 = SimpleEvent()
        let event2 = SimpleEvent()
        let event3 = LazySimpleEvent()
        
        let expectation = XCTestExpectation()
        expectation.assertForOverFulfill = true
        
        // We send one after 0.05s, that should be ignored, and one after 0.15s that should trigger.
        expectation.expectedFulfillmentCount = 2
        
        let observer = SimpleEventGroupObserver(
            events: event1, event2, event3,
            debounceTimeout: 0.1,
            debouncePolicy: .throttle
        ) { _ in
            expectation.fulfill()
        }
        
        XCTAssertNotNil(observer)
        
        // Trigger all events, 0.05s after each other.
        let startDate = Date()
        event1.trigger()
        
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
            event2.trigger()
            
            Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                event3.trigger()
            }
        }
        
        wait(for: [expectation], timeout: 1)
        
        // Since we triggered the last event after 0.2s, we expect it to have taken 0.3s for the
        // fulfilment of 2 triggers to have lasted.
        XCTAssert(-startDate.timeIntervalSinceNow >= 0.3)
    }
}
