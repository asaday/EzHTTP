
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)

import XCTest
import EzHTTP

class EzHTTPSampleTests: XCTestCase {

	var host = "http://httpbin.org" // or https

	func findJSONString(json: NSObject?, path: String) -> String {
		guard let json = json else { return "" }
		var paths = path.componentsSeparatedByString("/")
		let last = paths.removeLast()
		guard var dst: [String: AnyObject] = json as? [String: AnyObject] else { return "" }
		for p in paths {
			guard let s = dst[p] as? [String: AnyObject] else { return "" }
			dst = s
		}
		return dst[last] as? String ?? ""
	}

	override func setUp() {
		super.setUp()
		HTTP.sharedInstance.escapeATS = true
	}

	override func tearDown() {
		super.tearDown()
	}

//    func testPerformanceExample() {
//        self.measureBlock { }
//    }

	func testGet() {
		let expectation = expectationWithDescription("")

		HTTP.get(host + "/get?a=b") { (res) in
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "args/a"), "b")
			expectation.fulfill()
		}
		waitForExpectationsWithTimeout(5, handler: nil)
	}

	func testGetParam() {
		let expectation = expectationWithDescription("")

		HTTP.get(host + "/get", params: ["a": "b"], headers: ["Aaa": "bbb"]) { (res) in
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "args/a"), "b")
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "headers/Aaa"), "bbb")
			expectation.fulfill()
		}
		waitForExpectationsWithTimeout(5, handler: nil)
	}

	func testGetRedirect() {
		let expectation = expectationWithDescription("")

		HTTP.get(host + "/redirect/3") { (res) in
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "url"), self.host + "/get")
			expectation.fulfill()
		}
		waitForExpectationsWithTimeout(5, handler: nil)
	}

	func testGetPNG() {
		let expectation = expectationWithDescription("")

		HTTP.get(host + "/image/png") { (res) in
			XCTAssertNil(res.error)
			let img = UIImage(data: res.dataValue)
			XCTAssertNotNil(img)
			expectation.fulfill()
		}
		waitForExpectationsWithTimeout(5, handler: nil)
	}

	func testCookie() {
		let expectation = expectationWithDescription("")

		NSHTTPCookieStorage.sharedHTTPCookieStorage().removeCookiesSinceDate(NSDate(timeIntervalSince1970: 0))

		let cv = NSUUID().UUIDString

		HTTP.get(host + "/cookies/set?k2=v2&k1=\(cv)") { (res) in
			print(res.stringValue)

			HTTP.get(self.host + "/get") { res in
				print(res.stringValue)

				var r: [String: String] = [:]

				if let cookies = NSHTTPCookieStorage.sharedHTTPCookieStorage().cookies {
					for c in cookies {
						if c.domain == "httpbin.org" { r[c.name] = c.value }
					}
				}

				XCTAssertEqual(r["k1"], cv)
				XCTAssertEqual(r["k2"], "v2")
				expectation.fulfill()
			}
		}
		waitForExpectationsWithTimeout(5, handler: nil)
	}

	func testPost() {
		let expectation = expectationWithDescription("")
		HTTP.request(.POST, host + "/post", params: ["a": "b"]) { (res) in
			print(res.stringValue)
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "form/a"), "b")
			expectation.fulfill()
		}
		waitForExpectationsWithTimeout(5, handler: nil)
	}

	func testPostFile() {
		let expectation = expectationWithDescription("")

		let file = HTTP.MultipartFile(mime: "iage/png", filename: "name", data: "aaa".dataUsingEncoding(NSUTF8StringEncoding)!)

		HTTP.request(.POST, host + "/post", params: ["a": "b", "c": file]) { (res) in
			print(res.stringValue)
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "form/a"), "b")
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "files/c"), "aaa")
			expectation.fulfill()
		}
		waitForExpectationsWithTimeout(5, handler: nil)
	}

	func testGetRedirectHTTPS() {
		let expectation = expectationWithDescription("")

		// first call is HTTP,and eveolute to HTTPS by server redirect
		HTTP.get(host + "/redirect-to?url=https%3A%2F%2Fhttpbin.org%2Fget%3Fa=b") { (res) in
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "args/a"), "b")
			expectation.fulfill()
		}
		waitForExpectationsWithTimeout(5, handler: nil)

	}

	func testChunk() {
		let expectation = expectationWithDescription("")

		HTTP.request(.GET, "http://www.httpwatch.com/httpgallery/chunked/chunkedimage.aspx") { (res) in
			// HTTP.request(.GET, host + "/stream-bytes/4096?chunk_size=256") { (res) in
			XCTAssertNil(res.error)
			expectation.fulfill()
		}
		waitForExpectationsWithTimeout(15, handler: nil)

	}

}
