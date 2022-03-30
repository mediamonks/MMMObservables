//
// MMMObservables. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

/// You pass an array of `SimpleEventObservable`'s and it listens to them all.
///
/// It will collect all events that occur and forward them to a single callback. If you supply
/// a `debounceTimeout` it will also debounce events. You can supply a specific policy for
/// the debounce method.
///
/// **Debounce Policy:**
///  - `default` will reset the timer every time one of the events trigger;
///  - `debounceLeading` will trigger the first time, but will ignore all future triggers for the duration of `debounceTimeout`;
///  - `throttle` will trigger events at most every `debounceTimeout` seconds.
///
/// **Example:**
/// ```
/// let observer = SimpleEventGroupObserver(events: event1, event2, event3) { _ in
///     // If any of the events trigger at the same time, we get only a single callback.
/// }
///
/// let debounceObserver = SimpleEventGroupObserver(
///     events: event1, event2, event3,
///     debounceTimeout: 0.1,
///     debouncePolicy: .throttle
/// ) { _ in
///     // If every event triggers at random within 1 seconds, this callback will be called
///     // at most every 0.1 seconds.
/// }
/// ```
public final class SimpleEventGroupObserver: SimpleEventObserver {
    
    /// What type of policy we should use for debouncing events.
    public enum DebouncePolicy {
        /// A default `debounce` method, every time one of the events trigger, the timer will be reset.
        case `default`
        /// The first time an event triggers, we call it straight away, but wait ignore all triggers for `debounceTimeout`.
        case debounceLeading
        /// Call events at most every `debounceTimeout` seconds.
        case throttle
    }
    
	private var events: [SimpleEventObservable]
	private let block: ([SimpleEventObservable]) -> ()
	
    private let debounceTimeout: TimeInterval
    private let debouncePolicy: DebouncePolicy
    
	/// - Parameters:
	///   - events: Events to listen to.
	///   - debounceTimeout: The amount of time to debounce for; `0` if you don't want any debouncing.
    ///   - debouncePolicy: How we should debounce, have a look at the ``DebouncePolicy`` cases for more info.
	///   - block: The callback block to call when a/multiple events fired.
	public init(
		events: [SimpleEventObservable],
		debounceTimeout: TimeInterval = 0,
        debouncePolicy: DebouncePolicy = .default,
		block: @escaping ([SimpleEventObservable]) -> ()
	) {
		self.events = events
		self.block = block
        
        self.debounceTimeout = debounceTimeout
        self.debouncePolicy = debouncePolicy
		
		events.forEach { $0.addObserver(self) }
	}
    
    /// - Parameters:
    ///   - events: Events to listen to.
    ///   - debounceTimeout: The amount of time to debounce for; `0` if you don't want any debouncing.
    ///   - debouncePolicy: How we should debounce, have a look at the ``DebouncePolicy`` cases for more info.
    ///   - block: The callback block to call when a/multiple events fired.
    public convenience init(
        events: SimpleEventObservable...,
        debounceTimeout: TimeInterval = 0,
        debouncePolicy: DebouncePolicy = .default,
        block: @escaping ([SimpleEventObservable]) -> ()
    ) {
        self.init(
            events: events,
            debounceTimeout: debounceTimeout,
            debouncePolicy: debouncePolicy,
            block: block
        )
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
		events.removeAll()
	}
	
	// MARK: - SimpleEventObserver
    
    private lazy var coalescing = CoalescingCallback { [weak self] in
        guard let self = self else {
            assertionFailure("Lost self in callback?")
            return
        }
        self.block(self.events)
        
        // We reset the throttle inside the coalescing callback to make sure we're
        // actually finished.
        self.throttlePaused = false
    }
    
    private var timer: Timer?
    private var throttlePaused: Bool = false
    
	public func simpleEventDidTrigger(_ event: SimpleEventObservable) {

		guard debounceTimeout > 0 else {
            coalescing.schedule()
			return
		}
        
        switch debouncePolicy {
        case .default:
            
            resetTimer()
            
            self.timer = Timer.scheduledTimer(withTimeInterval: debounceTimeout, repeats: false) { [weak self] _ in
                self?.coalescing.schedule()
            }
            
        case .debounceLeading:
            
            if timer == nil {
                coalescing.schedule()
            } else {
                resetTimer()
            }
            
            self.timer = Timer.scheduledTimer(withTimeInterval: debounceTimeout, repeats: false) { [weak self] _ in
                self?.resetTimer()
            }
            
        case .throttle:
            
            guard !throttlePaused else {
                // We don't do anything, we're throttling right now.
                return
            }
            
            throttlePaused = true
            
            self.timer = Timer.scheduledTimer(withTimeInterval: debounceTimeout, repeats: false) { [weak self] _ in
                self?.coalescing.schedule()
            }
        }
	}
	
	private func resetTimer() {
        timer?.invalidate()
        timer = nil
	}
}
