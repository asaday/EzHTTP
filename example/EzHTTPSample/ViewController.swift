
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)

import EzHTTP
import UIKit

class ViewController: UIViewController {
	override func viewDidLoad() {
		super.viewDidLoad()

		HTTP.shared.logHandler = HTTP.defaultLogHandler
		HTTP.shared.retryHandler = HTTP.defaultRetryHandler
		HTTP.shared.illegalStatusCodeAsError = true

		HTTP.shared.escapeATS = true

		let lbl = UILabel(frame: view.bounds)
		lbl.numberOfLines = 0
		view.addSubview(lbl)

		HTTP.get("https://httpbin.org/get") {
			lbl.text = $0.string
			print($0.error ?? "")
		}
	}
}
