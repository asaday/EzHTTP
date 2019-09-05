
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)

import Foundation

// MARK: - NetworkIndicator

open class NetworkIndicator: NSObject {
	public static let shared = NetworkIndicator()
	public var handler: ((_ visible: Bool) -> Void)?

	var states: [String: Bool] = [:]
	var queues: [OperationQueue] = []
	var indicatorTimer: Timer?
	var visible: Bool = false
	static let operationCountKey = "operationCount"

	public static func setState(_ key: String, _ state: Bool) { shared.setState(key, state: state) }
	public static func start(_ key: String) { shared.setState(key, state: true) }
	public static func stop(_ key: String) { shared.setState(key, state: false) }

	public static func addOberveQueue(_ queue: OperationQueue) {
		queue.addObserver(shared, forKeyPath: operationCountKey, options: .new, context: nil)
		shared.queues.append(queue)
	}

	public static func removeOberveQueue(_ queue: OperationQueue) {
		queue.removeObserver(shared, forKeyPath: operationCountKey)
		if let idx = shared.queues.firstIndex(of: queue) { shared.queues.remove(at: idx) }
	}

	open override func observeValue(forKeyPath keyPath: String?, of _: Any?, change: [NSKeyValueChangeKey: Any]?, context _: UnsafeMutableRawPointer?) {
		if keyPath != NetworkIndicator.operationCountKey { return }
		startIndicator()
	}

	var total: Int {
		var t: Int = 0
		t += states.values.reduce(0) { $0 + ($1 ? 1 : 0) }
		t += queues.reduce(0) { $0 + $1.operationCount }
		return t
	}

	deinit {
		for q in queues { q.removeObserver(self, forKeyPath: NetworkIndicator.operationCountKey) }
		indicatorTimer?.invalidate()
		indicatorTimer = nil
	}

	func setState(_ key: String, state: Bool) {
		if key == "" { return }
		states[key] = state
		startIndicator()
	}

	func startIndicator() {
		guard let h = handler else { return }
		if total <= 0 || visible { return }
		DispatchQueue.main.async {
			self.visible = true
			self.indicatorTimer?.invalidate()
			self.indicatorTimer = Timer.scheduledTimer(timeInterval: 0.3, target: self, selector: #selector(self.stopIndicator), userInfo: nil, repeats: true)
			h(true)
		}
		// UIApplication.shared.isNetworkActivityIndicatorVisible = true
		// shared does not execute in extention, so manualy
	}

	@objc func stopIndicator() {
		if total > 0 { return }
		visible = false
		indicatorTimer?.invalidate()
		indicatorTimer = nil
		handler?(false)
		//			UIApplication.shared.isNetworkActivityIndicatorVisible = false
	}
}
