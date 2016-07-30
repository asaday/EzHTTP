//
//  ViewController.swift
//  EzHTTPSample
//

import UIKit
import EzHTTP

class ViewController: UIViewController {

	override func viewDidLoad() {
		super.viewDidLoad()

		HTTP.sharedInstance.config.HTTPMaximumConnectionsPerHost = 6
		HTTP.sharedInstance.config.timeoutIntervalForRequest = 15
		HTTP.sharedInstance.logHandler = HTTP.defaultLogHandler

		HTTP.sharedInstance.escapeATS = true

		let lbl = UILabel(frame: view.bounds)
		lbl.numberOfLines = 0
		view.addSubview(lbl)

		HTTP.get("http://httpbin.org/get") {
			lbl.text = $0.string
		}
	}
}

