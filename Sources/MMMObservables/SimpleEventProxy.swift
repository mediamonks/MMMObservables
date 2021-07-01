//
// MMMObservables. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

/// You pass an array of `SimpleEventObservable`'s and it fires a single event if one of them fires, it does this lazily.
///
/// This fixes the issue where you attach listeners to multiple events only to trigger a single event (e.g. inside your
/// `ViewModel`); since it inherits from `LazySimpleEvent` you can trigger the proxy itself as well, this is intentional.
///
/// **Example usage**
///	```
///	// Create a private proxy to trigger from 'inside' the model.
///	private lazy var proxy = SimpleEventProxy(events: parent.didChange, child.didChange)
///
///	// Change handler for the 'outside'.
/// public var didChange: SimpleEventObservable { proxy }
///	```
public final class SimpleEventProxy: LazySimpleEvent {
	
	private var tokens: [SimpleEventToken?] = []
	
	public init(queue: DispatchQueue = .main, events: [SimpleEventObservable]) {
		super.init(queue: queue)
		
		let callback: (SimpleEventObservable) -> Void = { [weak self] _ in
			self?.trigger()
		}
		
		tokens = events.map { $0.addObserver(callback) }
	}
	
	public convenience init(queue: DispatchQueue = .main, events: SimpleEventObservable...) {
		self.init(queue: queue, events: events)
	}
}
