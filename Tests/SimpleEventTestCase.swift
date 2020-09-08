//
// MMMObservables. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

import XCTest
@testable import MMMObservables

private protocol P {

	// Only the 'observable' part is visible from the outside.
	var changeEvent: SimpleEventObservable { get }
}

class SimpleEventTestCase: XCTestCase {

	class ImpOfP: P {

		// This would be private in the actual implementation, fileprivate allows to access it from the test case.
		fileprivate let _changeEvent = SimpleEvent()

		public var changeEvent: SimpleEventObservable { return _changeEvent }
	}

	static var callCounter: Int = 0

	class UserOfP {

		fileprivate let p: P

		fileprivate init(p: P) {

			self.p = p

			// Want the listeners to use `self` here, so can play with retain cycles. Try using a strong ref for `token2`.

			p.changeEvent.addObserver(&token1) { [weak self] (_) in
				self!.bump(by: 1)
			}

			p.changeEvent.addObserver(&token2) { [weak self] (_) in
				self!.bump(by: 2)
			}
		}

		var token1: SimpleEventToken?
		var token2: SimpleEventToken?

		func bump(by: Int) {
			callCounter += by
		}
	}

	func testBasics() {

		SimpleEventTestCase.callCounter = 0

		let p = ImpOfP()

		do {

			let u = UserOfP(p: p)

			p._changeEvent.trigger()
			XCTAssertEqual(SimpleEventTestCase.callCounter, 3)

			// Not triggered yet and should not mark as triggered when the condition is false.
			p._changeEvent.trigger(if: false)
			XCTAssertEqual(SimpleEventTestCase.callCounter, 3)

			// When notifications are merged, then only one should happen eventually.
			p._changeEvent.coalescingNotifications {

				p._changeEvent.trigger(if: true)
				p._changeEvent.trigger(if: true)

				// Nesting is supported, only the outermost block send the notification.
				p._changeEvent.coalescingNotifications {
					p._changeEvent.trigger()
				}

				p._changeEvent.trigger(if: true)

				// Passing `false` should not reset the trigger.
				p._changeEvent.trigger(if: false)

				// Should not be notified yet, only after leaving the block.
				XCTAssertEqual(SimpleEventTestCase.callCounter, 3)
			}

			XCTAssertEqual(SimpleEventTestCase.callCounter, 6)

			// An observer can be explicitly removed using the token...
			u.token1?.remove()
			// ...and it should be safe to do this more than once.
			u.token1?.remove()

			// Let's verify that it's gone.
			p._changeEvent.trigger()
			XCTAssertEqual(SimpleEventTestCase.callCounter, 8)

			// An observer can also be removed implicitly by dropping the token.
			// (Ending the scope here will deallocate `u` and drop its token2.)
		}

		// Let's verify that the second one is gone as well.
		p._changeEvent.trigger()
		XCTAssertEqual(SimpleEventTestCase.callCounter, 8)
	}

	class UserOfPClassic: SimpleEventObserver {

		fileprivate let p: P

		fileprivate init(p: P) {

			self.p = p

			p.changeEvent.addObserver(self)
		}

		deinit {
			p.changeEvent.removeObserver(self)
		}

		func simpleEventDidTrigger(_ event: SimpleEventObservable) {
			callCounter += 3
		}
	}

	func testClassic() {

		SimpleEventTestCase.callCounter = 0

		let p = ImpOfP()

		var u: UserOfPClassic? = .init(p: p)

		p._changeEvent.trigger()
		XCTAssertEqual(SimpleEventTestCase.callCounter, 3)

		// When `u` deallocates it should remove its observer as well.
		u = nil
		p._changeEvent.trigger()
		XCTAssertEqual(SimpleEventTestCase.callCounter, 3)
	}
}
