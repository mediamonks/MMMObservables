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
public class SimpleMailbox<T: Equatable> {

	/// The event associated with the mailbox.
	private let event: LazySimpleEvent

	/// Pass the event that should be triggered when the value in the mailbox changes.
	/// Have to use "lazy" one here because if putting a value triggers an event where handler takes it,
	/// then the take is going to trigger a nested notification which is not supported by regular `SimpleEvent`.
	public init(event: LazySimpleEvent) {
		self.event = event
	}

	/// Current value in the mailbox, if any; can be freely peeked at many times by anyone.
	public private(set) var value: T? {
		didSet {
			if value != oldValue {
				event.trigger()
			}
		}
	}

	/// `true`, if there is a value in the mailbox. (Handy when the value itself is an optional.)
	public var hasValue: Bool {
		return value != Optional<T>.none // `nil` can trip Swift when T has `.none` member as well
	}

	/// Returns the current value in the mailbox, if any, taking it by leaving `nil` here.
	public func take() -> T? {
		let result = self.value
		self.value = Optional<T>.none // `nil` can trip Swift when T has `.none` member as well
		return result
	}

	/// Puts a new value into the mailbox replacing the current value, if any.
	///
	/// (Calling it `put()` could imply the possibility of storing multiple values.)
	public func replace(_ value: T) {
		self.value = value
	}
}
