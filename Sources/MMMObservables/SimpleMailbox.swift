//
// MMMObservables. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

import Foundation

/// A box where somebody can put a value replacing whatever was there before, and somebody else can later check it
/// and/or take with them. (Essentially a non-blocking, non-thread-safe queue of 1 element.)
///
/// Change notifications are performed via an event owned by the object hosting the mailbox.
///
/// I am not splitting it into "taking" and "placing parts" yet because of the generic parameter and because
/// it's made for view models where both view and its owner have equal access to fields.
///
/// This is one more step towards avoid unbounded queued events in the app. Using a mailbox allows to act on certain
/// events a bit later than they were emitted.
public class SimpleMailbox<T> {

	/// The event associated with the mailbox.
	private let event: LazySimpleEvent

	/// - Parameter event: The event that should be triggered when the value in the mailbox changes.
	///   Have to use "lazy" version here because putting and taking a value both trigger the same event
	///   potentially causing "event ping-pong".
	public init(event: LazySimpleEvent) {
		self.event = event
	}

	/// The current value, if any. Anyone can peek at it.
	public private(set) var value: T? {
		didSet {
			event.trigger()
		}
	}

	/// `true`, if there is a value in the mailbox. (Handy when the value itself is an optional.)
	public var hasValue: Bool {
		// Comparing to `nil` can trip Swift when T itself has `.none` case.
		if case .some = value {
			return true
		} else {
			return false
		}
	}

	/// Returns the current value in the mailbox, if any, taking it by leaving `nil` here.
	public func take() -> T? {
		if let value = self.value {
			self.value = Optional<T>.none // Again, `nil` can trip Swift when T has `.none` case.
			return value
		} else {
			return Optional<T>.none
		}
	}

	/// Puts a new value into the mailbox replacing the current value, if any.
	public func replaceEvenIfSame(_ value: T) {
		self.value = value
	}

	/// Puts a new value into the mailbox only if it's empty.
	///
	/// - Returns: `true`, if the value has been successfully placed.
	@discardableResult
	public func placeIfFits(_ value: T) -> Bool {
		if !hasValue {
			self.value = value
			return true
		} else {
			return false
		}
	}
}

extension SimpleMailbox where T: Equatable {

	/// Puts a new value into the mailbox replacing the current one and triggering a notification
	/// only if the new value differs. This is when `T` is `Equatable`.
	///
	/// (Calling it `put()` could imply the possibility of storing multiple values.)
	public func replace(_ value: T) {
		if self.value != value {
			self.value = value
		}
	}
}
