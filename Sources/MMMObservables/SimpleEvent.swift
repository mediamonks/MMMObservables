//
// MMMObservables. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

/// A point where multiple observers can register to be notified when the corresponding object or its parts
/// might need attention (aka 'signal', 'event', etc in other libs).
///
/// Note that the observers might be notified much later than the actual event happened and multiple "need attention"
/// events might be combined into one. Use regular observers/delegates in case every event counts or needs to be reacted
/// upon immediately.
///
/// This is the only part of the actual implementation that should be visible to the outside users of your objects
/// (see `SimpleEvent` and `LazySimpleEvent`).
public protocol SimpleEventObservable: AnyObject {

	/// The argument of the closure is the object that was used with `addObserver()`.
	typealias ObserverBlock = (SimpleEventObservable) -> Void

	/**
	Adds the given closure into the list of parties to be notified when the corresponding event happens.
	Returns a token that should be kept while there is an interest in the events.

	The observer is automatically removed when the token is deallocated. You can also remove the observer
	explicitly via the token's `remove()` method.

	In the first version of this API the token was a normal return value, but that was distracting attention from
	the event itself on the calling site and it made it easier to forget to keep the token.

	Compare this:

		yourObject.changeEvent.addObserver(&yourObjectChangeToken) {
			// ...
		}

	with the initial version:

		yourObjectChangeToken = yourObject.changeEvent.addObserver {
			// ...
		}

	The initial version has a benefit when `yourObject` is an optional however.
	In this case `yourObject?.changeEvent.addObserver` always returns something and thus
	is going to update `yourObjectChangeToken` in any case ensuring you are unsubscribed if `yourObjectChangeToken`
	had something before. See the version added on the extension of this protocol.
	*/
	func addObserver(_ token: inout SimpleEventToken?, _ block: @escaping ObserverBlock)

	/**
	Adds a "delegate-style" observer into the list of parties to be notified when the corresponding event happens.
	As usual with delegates only a weak reference to them is kept.

	You must remove the observer explicitly by calling `removeObserver()` exactly once.

	- Note:
		- The same object cannot be added more than once.
		- If the observer object is deallocated before it is removed, then a corresponding assertion might fire
		  in Debug when other observers are added/removed or notifications are made.
	*/
	func addObserver(_ observer: SimpleEventObserver)

	/// Removes the observer added earlier via `addObserver()`. Should be called exactly once.
	func removeObserver(_ observer: SimpleEventObserver)
}

extension SimpleEventObservable {

	/// A version of `addObserver()` that returns the token instead of updating one by reference.
	///
	/// This is more convenient when the observable object might be `nil`: your token is updated in any case
	/// ensuring you are not subscribed to the previous object.
	public func addObserver(_ block: @escaping ObserverBlock) -> SimpleEventToken? {
		var token: SimpleEventToken?
		self.addObserver(&token, block)
		return token
	}
}

/// A token returned by `SimpleEventObservable.addObserver()` that can be used to remove the added observer either
/// explicitly via `remove()` or automatically when the token is deallocated.
/// (So keep a reference to it while interested in notifications!)
public protocol SimpleEventToken: AnyObject {

	/// Removes the corresponding observer. It is safe to call it more than once.
	/// (Called automatically when the token is deallocated.)
	func remove()
}

/// Protocol for objects that want to be notified in a "classic" delegate-like manner when an event they subscribed to
/// via `SimpleEventObservable.addObserver()` is triggered.
public protocol SimpleEventObserver: AnyObject {

	/// The exact instance of `SimpleEventObservable` that was used when subscribing to the event is passed so
	/// the observer can distinguish between different events it has subscribed to.
	func simpleEventDidTrigger(_ event: SimpleEventObservable)
}

/// Helps to notify multiple parties about something interesting.
///
/// (Consider using `LazySimpleEvent` instead which coalesces notifications and defers them to the next run loop cycle
/// completely avoiding nested notifications.)
///
/// Typically only `SimpleEventObservable` part of this object is exposed to the "outside users" of your class
/// or protocol while the whole object is hidden and is controlled only by your implementation.
///
/// - Note: This class (as most of the others) is *not* supposed to be thread-safe on its own.
public class SimpleEvent: SimpleEventObservable {

	public init() {
	}

	// MARK: -

	// Using `ObserverHub` for the implementation as it has some small details ironed out already.
	private lazy var observerHub = ObserverHub<SimpleEventObserver>()

	// MARK: - SimpleEventObservable

	public func addObserver(_ token: inout SimpleEventToken?, _ block: @escaping ObserverBlock) {
		token = ObserverToken(observerHub: observerHub, block: block)
	}

	public func addObserver(_ observer: SimpleEventObserver) {
		observerHub.add(observer)
	}

	public func removeObserver(_ observer: SimpleEventObserver) {
		observerHub.remove(observer)
	}

	// `true`, when the object has been marked as 'triggered' but the observers have not been notified yet.
	private var isTriggered = false

	// If greater than zero, then we are within a coalescing ("batch update") block.
	// If the object is marked as 'triggered' while we are within this block, then the observers won't be notified
	// till we exit the outermost block.
	private var coalescingLevel: Int = 0

	/// In case the event is 'triggered' one or more times while in this block, then the observers will be
	/// notified only once and only after the outermost block ends.
	public func coalescingNotifications(block: () -> ()) {

		coalescingLevel += 1

		block()

		coalescingLevel -= 1
		assert(coalescingLevel >= 0)

		if coalescingLevel == 0 {
			notifyIfNeeded()
		}
	}

	/// Marks the event as 'triggered' if the given `condition` is `true`. Then, if the event is marked as 'triggered'
	/// (either now or earlier), it notifies all the observers and resets the 'triggered' state. This is unless
	/// notifications are being coalesced now via `coalescingNotifications(block:)`, in the latter case only one
	/// notification will trigger after the outermost coalescing block completes.
	public func trigger(`if` condition: Bool = true) {
		isTriggered = isTriggered || condition
		notifyIfNeeded()
	}

	private func notifyIfNeeded() {

		if isTriggered && coalescingLevel <= 0 {

			isTriggered = false

			observerHub.forEach { $0.simpleEventDidTrigger(self) }
		}
	}
}

/// Another implementation of `SimpleEventObservable` that automatically coalesces all calls to `trigger()`
/// waking up the observers only once on the next cycle of the given dispatch queue (main by default).
///
/// This way `SimpleEvent`'s `coalescingNotifications()` is not needed here and the issue with nested calls
/// is automatically avoided.
public class LazySimpleEvent: SimpleEventObservable {

	private let queue: DispatchQueue

	/// The event is going to be scheduled on the specified queue.
	public init(queue: DispatchQueue = .main) {
		self.queue = queue
	}

	// MARK: -

	private lazy var callback: CoalescingCallback = {
		return CoalescingCallback(queue: queue) { [weak self] in
			guard let self = self else { return }
			self.observerHub.forEach { $0.simpleEventDidTrigger(self) }
		}
	}()

	// Using `ObserverHub` for the implementation as it has some small details ironed out already.
	private lazy var observerHub = {
		return ObserverHub<SimpleEventObserver>()
	}()

	// MARK: - SimpleEventObservable

	public func addObserver(_ token: inout SimpleEventToken?, _ block: @escaping ObserverBlock) {
		token = ObserverToken(observerHub: observerHub, block: block)
	}

	public func addObserver(_ observer: SimpleEventObserver) {
		observerHub.add(observer)
	}

	public func removeObserver(_ observer: SimpleEventObserver) {
		observerHub.remove(observer)
	}

	/// Marks the event as 'triggered' so the observers are notified a bit later on the next run loop cycle
	/// unless `condition` is `false`.
	public func trigger(`if` condition: Bool = true) {
		if condition {
			callback.schedule()
		}
	}
}

/// Serves as a proxy from `SimpleEventObserver` into a user block and as an observer token at the same time.
/// Internal class used as `SimpleEventToken` by `SimpleEvent` and `LazySimpleEvent`
fileprivate class ObserverToken: SimpleEventObserver, SimpleEventToken {

	private let observerHub: ObserverHub<SimpleEventObserver>

	private var block: SimpleEventObservable.ObserverBlock?

	public init(observerHub: ObserverHub<SimpleEventObserver>, block: @escaping SimpleEventObservable.ObserverBlock) {

		self.observerHub = observerHub
		self.block = block

		self.observerHub.add(self)
	}

	deinit {
		remove()
	}

	private var removed: Bool = false

	public func remove() {
		if !removed {
			removed = true
			observerHub.remove(self)
			block = nil
		}
	}

	public func simpleEventDidTrigger(_ event: SimpleEventObservable) {

		guard let block = block else {
			preconditionFailure("Got a notification after being removed?")
		}

		block(event)
	}
}

/// You pass an array of `SimpleEventObservable`'s and it listens to them all.
///
/// By default it will debounce the events, so if you have 5 events firing at the same time, you won't
/// get 5 callbacks, but just one after the `debounceTimeout` has passed. (The latter is 0 by default, so
/// on the next cycle of the run loop.)
public class SimpleEventGroupObserver: SimpleEventObserver {
	
	private let debounceTimeout: TimeInterval?
	private var events: [SimpleEventObservable]
	private let block: (SimpleEventObservable) -> ()
	
	private var debounceTimer: Timer?
	
	/// - Parameters:
	///   - events: Events to listen to.
	///   - debounceTimeout: The amount of time to debounce for; `nil` if you don't want any debouncing.
	///   - block: The callback block to call when a/multiple events fired.
	public init(
		events: [SimpleEventObservable],
		debounceTimeout: TimeInterval? = 0,
		block: @escaping (SimpleEventObservable) -> ()
	) {
		self.events = events
		self.debounceTimeout = debounceTimeout
		self.block = block
		
		events.forEach { $0.addObserver(self) }
	}
	
	deinit {
		remove()
	}
	
	/// Removes the listeners.
	/// 
	/// Safe to call multiple times, also called automatically when the object is deallocated.
	public func remove() {

		resetTimer()

		events.forEach { $0.removeObserver(self) }
		// To not keep the references and avoid double removes.
		events = []
	}
	
	// MARK: -
	public func simpleEventDidTrigger(_ event: SimpleEventObservable) {

		guard let debounceTimeout = debounceTimeout else {
			block(event)
			return
		}
		
		resetTimer()
		
		let timer = Timer(timeInterval: debounceTimeout, repeats: false, block: { [weak self] _ in
			self?.block(event)
		})
		
		debounceTimer = timer

		#if swift(>=4.2)
			RunLoop.main.add(timer, forMode: .common)
		#else
			RunLoop.main.add(timer, forMode: .commonModes)
		#endif
	}
	
	private func resetTimer() {
		debounceTimer?.invalidate()
		debounceTimer = nil
	}
}
