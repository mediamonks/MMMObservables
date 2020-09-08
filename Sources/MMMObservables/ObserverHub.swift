//
// MMMObservables. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

/**
Helps with implementation of "observable" objects.

(Swift version of `MMMObserverHub`, type-safe and does not require your observers or observer protocols
to be ObjC-compatible.)

Properties:

- Observers are referenced weakly.
- If an observer is added/removed during a notification cycle, then it won't be called during this cycle.
- As usual, thread-safety (if ever needed) should be handled by the user of the class.

Flags the following conditions in debug builds:

- Observers added more than once.
- Observers not being of reference types (so structs cannot be accidentally installed as observers).
- Observers removed more than once (or tried to be removed without being added first).
- Observers not explicitly removed before their deallocation.
- Nested notification cycles.
*/
public final class ObserverHub<T> {

	typealias Reference = ObserverHubReference

	private var observers = [Reference]()

	private func cleanup() {

		// Let's flag all the observers that have gone without being removed explicitly.
		assert(
			!observers.contains(where: { $0.isDead }),
			"One or more observers were not removed: \(observers.filter({ $0.isDead }))"
		)

		// Let's check for the references that are gone already.
		observers.removeAll { $0.ref == nil }
	}

	/// True, if no observers are installed yet.
	public var isEmpty: Bool {
		return observers.isEmpty
	}

	public func add(_ observer: T) {

		assert(
			type(of: observer as Any) is AnyClass,
			"Trying to add a value of type \(type(of: observer as Any)) as an observer conforming to \(T.self). " +
			"Value types cannot work as observers however."
		)

		let ref = observer as AnyObject

		// Intentionally installing the same observer more than once makes no sense, so if we detect a case like that
		// then it must be unintentional double addition or a case of a forgotten removal.
		// The latter can be serious, so not forgiving it.
		assert(
			!observers.contains(where: { $0.ref === ref }),
			"The same instance of \(type(of: ref)) is added again as an observer conforming to \(T.self). " +
			"Perhaps forgot to remove it?"
		)

		observers.append(Reference(ref: ref, observerType: T.self))

		cleanup()
	}

	public func remove(_ observer: T) {

		let observer = observer as AnyObject
		if let index = observers.firstIndex(where: { $0.ref === observer }) {
			observers.remove(at: index).markAsUnsubscribed()
		} else {
			#if DEBUG
			// We cannot seem to find this observer. Should crash unless it looks like that the observer is trying
			// to remove itself from its `deinit` and thus our reference to it has been automatically nullified.
			if let index = observers.firstIndex(where: { $0.isDead && $0.unownedRef === observer }) {
				// Removig it here will avoid dead entry assertion in cleanup().
				observers.remove(at: index)
			} else {
				assertionFailure("Trying to remove an observer that was not installed?")
			}
			#endif
		}

		cleanup()
	}

	// Tells if are within forEach().
	// Used only for diagnostics, the optimizer should be able to eliminate this in release builds.
	private var notifying: Bool = false

	/// Calls the given closure for every observer currently subscribed.
	public func forEach(_ body: (T) -> Void) {

		// As mentioned in MMMObserverHub:
		// Imagine we have two observers with didStart and didEnd methods and when we are notifying observer 1 about
		// didStart it causes somehow a notification about didEnd. We start notifying observer 1 and 2 about didEnd,
		// but observer 2 has not seen the notification about didStart yet, which can be a problem.
		// Cases like this can be resolved by queuing notifications instead of sending them directly,
		// but this is something the user of the class should take care of, here we simly crash early.
		assert(!notifying, "Nested notifications should be avoided")
		notifying = true

		// In case an entry is removed while we are looping (as a result of an observer call), then we still might
		// encounter it here as we are using a copy of the array. This is not going to be a problem though, because
		// when the entry is removed it is marked as such and thus the corresponding observer won't be notified.
		for o in observers {
			if let ref = o.ref {
				body(ref as! T)
			}
		}

		notifying = false

		cleanup()
	}

	public init() {
	}
}

/// A wrapper for weak references to observers stored by `ObserverHub<T>` keeping some diagnostics data in debug builds.
/// (Could be private but want access it from a unit test.)
internal class ObserverHubReference: CustomStringConvertible {

	weak var ref: AnyObject?

	#if DEBUG
	unowned(unsafe) let unownedRef: AnyObject
	let diagnostics: String
	#endif

	private var unsubscribed: Bool = false

	func markAsUnsubscribed() {
		ref = nil
		unsubscribed = true
	}

	var isDead: Bool {
		return ref == nil && !unsubscribed
	}

	init(ref: AnyObject, observerType: @autoclosure () -> Any) {

		self.ref = ref

		#if DEBUG
		self.unownedRef = ref
		let protocolName = String(describing: type(of: observerType()))
			.replacingOccurrences(of: "\\.Protocol$", with: "", options: .regularExpression)
		self.diagnostics = "observer (\(protocolName)) on \(String(reflecting: ref))"
		#endif
	}

	var description: String {

		get {

			#if DEBUG
			let diagnostics = self.diagnostics
			#else
			let diagnostics = "observer"
			#endif

			if unsubscribed {
				return "Unsubscribed \(diagnostics)"
			} else if ref == nil {
				return "Dead \(diagnostics)"
			} else {
				return "Active \(diagnostics)"
			}
		}
	}
}
