//
// MMMObservables. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

import XCTest
@testable import MMMObservables

protocol TestObserverProtocol {
	func didChange(object: AnyObject)
}

class ObserverHubTestCase: XCTestCase {

	private var hub: ObserverHub<TestObserverProtocol>!

    override func setUp() {
    	super.setUp()
    	hub = ObserverHub<TestObserverProtocol>()
    }

    func notifyDidChange() {
    	hub.forEach { $0.didChange(object: hub) }
    }

    override func tearDown() {
    }

    private func shouldAssert(_ callback: @autoclosure () -> Void, _ message: String) {
    	// Currently there is no support for checking if the given method asserts, so commented this out for now.
    	//! callback();
    }

	func testCannotUseValues() {

		struct TestObserverStruct: TestObserverProtocol {
			func didChange(object: AnyObject) {
			}
		}

		shouldAssert(hub.add(TestObserverStruct()), "Should assert because we are trying to pass a value type")
	}

	func testCannotAddTwice() {

		let a = TestObserver()
		hub.add(a)

		shouldAssert(hub.add(a), "Should assert when the same observer is added again")
	}

	class TestObserver: TestObserverProtocol {

		var callback: ((TestObserverProtocol) -> Void)?

		var counter: Int = 0

		func didChange(object: AnyObject) {
			counter += 1
			if let callback = callback {
				callback(self)
			}
		}
	}

    func testBasics() {

    	let a = TestObserver()
    	let b = TestObserver()

    	XCTAssert(a.counter == 0 && b.counter == 0)

    	XCTAssert(hub.isEmpty)

    	hub.add(a)
    	notifyDidChange()
    	XCTAssert(a.counter == 1 && b.counter == 0)
    	XCTAssert(!hub.isEmpty)

    	hub.add(b)
    	notifyDidChange()
    	XCTAssert(a.counter == 2 && b.counter == 1)
    	XCTAssert(!hub.isEmpty)

    	hub.remove(a)
    	notifyDidChange()
    	XCTAssert(a.counter == 2 && b.counter == 2)
    	XCTAssert(!hub.isEmpty)

    	hub.remove(b)
    	notifyDidChange()
    	XCTAssert(a.counter == 2 && b.counter == 2)
    	XCTAssert(hub.isEmpty)
    }

    func testReferences() {

		// ObserverHubReference is something internal to ObserverHub, but here is a sandbox to check it a bit.

    	var a: AnyObject?

    	a = TestObserver()

    	let ref1 = ObserverHubReference(ref: a!, observerType: TestObserverProtocol.self)
    	let ref2 = ObserverHubReference(ref: a!, observerType: TestObserverProtocol.self)

    	XCTAssertTrue(String(describing: ref1).starts(with: "Active"))
    	XCTAssertTrue(String(describing: ref2).starts(with: "Active"))

    	ref1.markAsUnsubscribed()
    	XCTAssertTrue(String(describing: ref1).starts(with: "Unsubscribed"))
    	XCTAssertTrue(String(describing: ref2).starts(with: "Active"))

		a = nil
    	XCTAssertTrue(String(describing: ref1).starts(with: "Unsubscribed"))
    	XCTAssertTrue(String(describing: ref2).starts(with: "Dead"))
    }

    func testUnsubscribeWhileNotifying() {

		let a = TestObserver()
		let b = TestObserver()
		hub.add(a)
		hub.add(b)

		notifyDidChange()
		XCTAssert(a.counter == 1 && b.counter == 1)

		// When `a` is called below it causes `b` to be removed just before it is supposed to be called. We need to make
		// sure that `b` is not callback in this case as it might with some other implementations.
		// Something like that can happen indirectly in the actual code, i.e. without `a` knowing.
		a.callback = { p in self.hub.remove(b) }
		notifyDidChange()
		XCTAssert(a.counter == 2 && b.counter == 1)
    }

    func testDoesNotAllowNestedNotificiations() {

		let a = TestObserver()
		hub.add(a)

		a.callback = { p in self.notifyDidChange() }
		shouldAssert(notifyDidChange(), "Should assert on nested notifications")
    }

    func testFlagsDeadRefs() {

		var a: TestObserver? = TestObserver()

		hub.add(a!)
    	a = nil

    	// OK, the observer has gone. Should be flagged on next add/remove/forEach.
    	let b = TestObserver()
		shouldAssert(hub.add(b), "Should assert when observers go away without being removed")
    }
}
