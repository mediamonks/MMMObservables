//
// MMMObservables. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

/// You pass an array of `SimpleEventObservable`'s and it listens to them all.
///
/// By default it will debounce the events, so if you have 5 events firing at the same time, you won't
/// get 5 callbacks, but just one after the `debounceTimeout` has passed. (The latter is 0 by default, so
/// on the next cycle of the run loop.)
public final class SimpleEventGroupObserver: SimpleEventObserver {
	
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
		events.removeAll()
	}
	
	// MARK: -
	public func simpleEventDidTrigger(_ event: SimpleEventObservable) {

		guard let interval = debounceTimeout else {
			block(event)
			return
		}
		
		resetTimer()
		
		let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
			self?.block(event)
		}
		
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
