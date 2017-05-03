
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)

import UIKit
import EzHTTP

class ViewController: UIViewController {

	override func viewDidLoad() {
		super.viewDidLoad()

		HTTP.shared.config.httpMaximumConnectionsPerHost = 6
		HTTP.shared.config.timeoutIntervalForRequest = 15
		HTTP.shared.logHandler = HTTP.defaultLogHandler

		HTTP.shared.escapeATS = true

		let lbl = UILabel(frame: view.bounds)
		lbl.numberOfLines = 0
		view.addSubview(lbl)

		HTTP.get("http://httpbin.org/get") {
			lbl.text = $0.string
		}
	}
}
