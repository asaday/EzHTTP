
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)


import Foundation

// MARK: - NetworkIndicator

public class NetworkIndicator: NSObject {
	static let sharedManager = NetworkIndicator()
	var states: [String: Bool] = [:]
	var queues: [NSOperationQueue] = []
	var indicatorTimer: NSTimer? = nil
	var visible: Bool = false

	public static func setState(key: String, _ state: Bool) { sharedManager.setState(key, state: state) }
	public static func start(key: String) { sharedManager.setState(key, state: true) }
	public static func stop(key: String) { sharedManager.setState(key, state: false) }

	public static func addOberveQueue(queue: NSOperationQueue?) {
		guard let queue = queue else { return }
		queue.addObserver(sharedManager, forKeyPath: "operationCount", options: .New, context: nil)
		sharedManager.queues.append(queue)
	}
	public static func removeOberveQueue(queue: NSOperationQueue?) {
		guard let queue = queue else { return }
		queue.removeObserver(sharedManager, forKeyPath: "operationCount")
		if let idx = sharedManager.queues.indexOf(queue) { sharedManager.queues.removeAtIndex(idx) }
	}

	override public func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String: AnyObject]?, context: UnsafeMutablePointer<Void>) {
		if keyPath != "operationCount" { return }
		startIndicator()
	}

	var total: Int {
		var total: Int = 0
		for (_, v) in states { total += v ? 1 : 0 }
		for q in queues { total += q.operationCount }
		return total
	}

	deinit {
		for q in queues { q.removeObserver(self, forKeyPath: "operationCount") }
		indicatorTimer?.invalidate()
		indicatorTimer = nil
	}

	func setState(key: String, state: Bool) {
		states[key] = state
		startIndicator()
	}

	func startIndicator() {
		#if os(iOS)
			if total <= 0 || visible { return }

			dispatch_async(dispatch_get_main_queue()) {
				if self.total <= 0 { return }

				UIApplication.sharedApplication().networkActivityIndicatorVisible = true
				self.visible = true

				self.indicatorTimer?.invalidate()
				self.indicatorTimer = NSTimer.scheduledTimerWithTimeInterval(0.3, target: self, selector: #selector(self.stopIndicator), userInfo: nil, repeats: true)
			}
		#endif
	}

	func stopIndicator() {
		#if os(iOS)
			if total > 0 { return }
			dispatch_async(dispatch_get_main_queue()) {
				UIApplication.sharedApplication().networkActivityIndicatorVisible = false
				self.visible = false
				self.indicatorTimer?.invalidate()
				self.indicatorTimer = nil
			}
		#endif
	}
}
