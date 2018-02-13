
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)

import UIKit
import EzHTTP

class ViewController: UIViewController {

	override func viewDidLoad() {
		super.viewDidLoad()

		let config = URLSessionConfiguration.default
		config.httpMaximumConnectionsPerHost = 6
		config.timeoutIntervalForRequest = 15
		config.httpAdditionalHeaders = ["AAA": "BBB"]
		HTTP.shared.setConfig(config)
		HTTP.shared.logHandler = HTTP.defaultLogHandler
		HTTP.shared.illegalStatusCodeAsError = true

		// HTTP.shared.escapeATS = true

		let lbl = UILabel(frame: view.bounds)
		lbl.numberOfLines = 0
		view.addSubview(lbl)

		HTTP.get("https://httpbin.org/get") {
			lbl.text = $0.string
		}
	}
}
