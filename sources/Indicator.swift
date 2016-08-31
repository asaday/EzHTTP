
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)


import Foundation

// MARK: - NetworkIndicator

open class NetworkIndicator: NSObject {
	static let sharedManager = NetworkIndicator()
	var states: [String: Bool] = [:]
	var queues: [OperationQueue] = []
	var indicatorTimer: Timer? = nil
	var visible: Bool = false

	open static func setState(_ key: String, _ state: Bool) { sharedManager.setState(key, state: state) }
	open static func start(_ key: String) { sharedManager.setState(key, state: true) }
	open static func stop(_ key: String) { sharedManager.setState(key, state: false) }

	open static func addOberveQueue(_ queue: OperationQueue?) {
		guard let queue = queue else { return }
		queue.addObserver(sharedManager, forKeyPath: "operationCount", options: .new, context: nil)
		sharedManager.queues.append(queue)
	}
	open static func removeOberveQueue(_ queue: OperationQueue?) {
		guard let queue = queue else { return }
		queue.removeObserver(sharedManager, forKeyPath: "operationCount")
		if let idx = sharedManager.queues.index(of: queue) { sharedManager.queues.remove(at: idx) }
	}

	open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
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

	func setState(_ key: String, state: Bool) {
		states[key] = state
		startIndicator()
	}

	func startIndicator() {
		#if os(iOS)
			if total <= 0 || visible { return }

			DispatchQueue.main.async {
				if self.total <= 0 { return }

				UIApplication.shared.isNetworkActivityIndicatorVisible = true
				self.visible = true

				self.indicatorTimer?.invalidate()
				self.indicatorTimer = Timer.scheduledTimer(timeInterval: 0.3, target: self, selector: #selector(self.stopIndicator), userInfo: nil, repeats: true)
			}
		#endif
	}

	func stopIndicator() {
		#if os(iOS)
			if total > 0 { return }
			DispatchQueue.main.async {
				UIApplication.shared.isNetworkActivityIndicatorVisible = false
				self.visible = false
				self.indicatorTimer?.invalidate()
				self.indicatorTimer = nil
			}
		#endif
	}
}
