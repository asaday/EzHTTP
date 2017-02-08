
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)

import XCTest
import EzHTTP

class EzHTTPSampleTests: XCTestCase {

	var host = "https://httpbin.org" // or https

	func findJSONString(_ json: NSObject?, path: String) -> String {
		guard let json = json else { return "" }
		var paths = path.components(separatedBy: "/")
		let last = paths.removeLast()
		guard var dst: [String: Any] = json as? [String: Any] else { return "" }
		for p in paths {
			guard let s = dst[p] as? [String: Any] else { return "" }
			dst = s
		}
		return dst[last] as? String ?? ""
	}

	override func setUp() {
		super.setUp()
		HTTP.shared.escapeATS = true
	}

	override func tearDown() {
		super.tearDown()
	}

//    func testPerformanceExample() {
//        self.measureBlock { }
//    }

	func testGet() {
		let expectation = self.expectation(description: "")

		HTTP.get(host + "/get?a=b") { (res) in
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "args/a"), "b")
			expectation.fulfill()
		}
		waitForExpectations(timeout: 5, handler: nil)
	}

	func testGetURL() {
		let expectation = self.expectation(description: "")
		
		let url = URL(string: host + "/get?a=b")!
		HTTP.get(url) { (res) in
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "args/a"), "b")
			expectation.fulfill()
		}
		waitForExpectations(timeout: 5, handler: nil)
	}

	func testGetParam() {
		let expectation = self.expectation(description: "")

		HTTP.get(host + "/get", params: ["a": "b"], headers: ["Aaa": "bbb"]) { (res) in
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "args/a"), "b")
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "headers/Aaa"), "bbb")
			expectation.fulfill()
		}
		waitForExpectations(timeout: 5, handler: nil)
	}

	func testGetRedirect() {
		let expectation = self.expectation(description: "")

		HTTP.get(host + "/redirect/3") { (res) in
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "url"), self.host + "/get")
			expectation.fulfill()
		}
		waitForExpectations(timeout: 5, handler: nil)
	}

	func testGetPNG() {
		let expectation = self.expectation(description: "")

		HTTP.get(host + "/image/png") { (res) in
			XCTAssertNil(res.error)
			let img = UIImage(data: res.dataValue)
			XCTAssertNotNil(img)
			expectation.fulfill()
		}
		waitForExpectations(timeout: 5, handler: nil)
	}

	func testCookie() {
		let expectation = self.expectation(description: "")

		HTTPCookieStorage.shared.removeCookies(since: Date(timeIntervalSince1970: 0))

		let cv = UUID().uuidString

		HTTP.get(host + "/cookies/set?k2=v2&k1=\(cv)") { (res) in
			print(res.stringValue)

			HTTP.get(self.host + "/get") { res in
				print(res.stringValue)

				var r: [String: String] = [:]

				if let cookies = HTTPCookieStorage.shared.cookies {
					for c in cookies {
						if c.domain == "httpbin.org" { r[c.name] = c.value }
					}
				}

				XCTAssertEqual(r["k1"], cv)
				XCTAssertEqual(r["k2"], "v2")
				expectation.fulfill()
			}
		}
		waitForExpectations(timeout: 5, handler: nil)
	}

	func testPost() {
		let expectation = self.expectation(description: "")
		HTTP.request(.POST, host + "/post", params: ["a": "b"]) { (res) in
			print(res.stringValue)
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "form/a"), "b")
			expectation.fulfill()
		}
		waitForExpectations(timeout: 5, handler: nil)
	}

	func testPostJSON() {
		let expectation = self.expectation(description: "")
		HTTP.request(.POST, host + "/post", params: [HTTP.ParamMode.json.rawValue:["a": "b"]]) { (res) in
			print(res.stringValue)
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "json/a"), "b")
			expectation.fulfill()
		}
		waitForExpectations(timeout: 5, handler: nil)
	}

	// need json post check
	//curl -X POST -H "Content-type: application/json" -d '{"k":"v"}' https://httpbin.org/post
	
	func testPostMQ() {
		let expectation = self.expectation(description: "")
		HTTP.request(.POST, host + "/post", params: HTTP.makeParams(query: ["q": "p"], form: ["a": "b"])) { (res) in
			print(res.stringValue)
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "form/a"), "b")
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "args/q"), "p")
			expectation.fulfill()
		}
		waitForExpectations(timeout: 5, handler: nil)
	}

	func testPostFile() {
		let expectation = self.expectation(description: "")

		let file = HTTP.MultipartFile(mime: "iage/png", filename: "name", data: "aaa".data(using: String.Encoding.utf8)!)

		HTTP.request(.POST, host + "/post", params: ["a": "b", "c": file]) { (res) in
			print(res.stringValue)
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "form/a"), "b")
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "files/c"), "aaa")
			expectation.fulfill()
		}
		waitForExpectations(timeout: 5, handler: nil)
	}

	func testGetRedirectHTTPS() {
		let expectation = self.expectation(description: "")

		// first call is HTTP,and eveolute to HTTPS by server redirect
		HTTP.get(host + "/redirect-to?url=https%3A%2F%2Fhttpbin.org%2Fget%3Fa=b") { (res) in
			XCTAssertNil(res.error)
			XCTAssertEqual(self.findJSONString(res.jsonObject, path: "args/a"), "b")
			expectation.fulfill()
		}
		waitForExpectations(timeout: 5, handler: nil)

	}

	func testChunk() {
		let expectation = self.expectation(description: "")

		HTTP.request(.GET, "http://www.httpwatch.com/httpgallery/chunked/chunkedimage.aspx") { (res) in
			// HTTP.request(.GET, host + "/stream-bytes/4096?chunk_size=256") { (res) in
			XCTAssertNil(res.error)
			expectation.fulfill()
		}
		waitForExpectations(timeout: 15, handler: nil)

	}

}
