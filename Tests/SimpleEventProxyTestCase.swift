//
// MMMObservables. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

import XCTest
@testable import MMMObservables

public final class SimpleEventProxyTestCase: XCTestCase {
	
	public func testBasics() {
		
		let event1 = SimpleEvent()
		let event2 = SimpleEvent()
		let event3 = LazySimpleEvent()
		
		let proxy = SimpleEventProxy(events: event1, event2, event3)
		
		let expectation = XCTestExpectation()
		expectation.assertForOverFulfill = true
		
		var token = proxy.addObserver { _ in
			expectation.fulfill()
		}
		
		XCTAssertNotNil(token)
		
		// Trigger both events, we only want a single callback.
		event1.trigger()
		event2.trigger()
		
		wait(for: [expectation], timeout: 1)
		
		// We want the proxy itself to being able to trigger as well.
		let expectation2 = XCTestExpectation()
		
		token = proxy.addObserver { _ in
			expectation2.fulfill()
		}
		
		proxy.trigger()
		
		XCTAssertNotNil(token)
		
		wait(for: [expectation2], timeout: 1)
		
		// Even if we do all at the same time, we only want a single trigger.
		let expectation3 = XCTestExpectation()
		
		token = proxy.addObserver { _ in
			expectation3.fulfill()
		}
		
		event1.trigger()
		event2.trigger()
		event3.trigger()
		proxy.trigger()
		
		XCTAssertNotNil(token)
		
		wait(for: [expectation3], timeout: 1)
	}
}
