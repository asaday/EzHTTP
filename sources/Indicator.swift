
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)

import Foundation

// MARK: - NetworkIndicator

open class NetworkIndicator: NSObject {
	static let shared = NetworkIndicator()
	var states: [String: Bool] = [:]
	var queues: [OperationQueue] = []
	var indicatorTimer: Timer?
	var visible: Bool = false
	var enabled: Bool = false

	public static func setState(_ key: String, _ state: Bool) { shared.setState(key, state: state) }
	public static func start(_ key: String) { shared.setState(key, state: true) }
	public static func stop(_ key: String) { shared.setState(key, state: false) }

	public static func addOberveQueue(_ queue: OperationQueue) {
		queue.addObserver(shared, forKeyPath: "operationCount", options: .new, context: nil)
		shared.queues.append(queue)
	}

	public static func removeOberveQueue(_ queue: OperationQueue) {
		queue.removeObserver(shared, forKeyPath: "operationCount")
		if let idx = shared.queues.index(of: queue) { shared.queues.remove(at: idx) }
	}

	open override func observeValue(forKeyPath keyPath: String?, of _: Any?, change _: [NSKeyValueChangeKey: Any]?, context _: UnsafeMutableRawPointer?) {
		if !enabled { return }
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
		if key == "" { return }
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

	@objc func stopIndicator() {
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
