//
// MMMObservables. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

import Foundation

/// Coalesces several calls of the same block on the given queue.
///
/// Handy when need to do a single thing in response to many async events and it does not matter how many of them
/// or how many times they have occurred.
public class CoalescingCallback {

	private let source: DispatchSourceUserDataOr

	public init(queue: DispatchQueue = .main, block: @escaping () -> Void) {
		self.source = DispatchSource.makeUserDataOrSource(queue: queue)
		self.source.setEventHandler(handler: block)
		self.source.resume()
	}

	/// Schedules the invocation of the block set when initializing the receiver.
	/// Safe to call multiple times, the block will be scheduled only once.
	public func schedule() {
		self.source.or(data: 1)
	}
}
