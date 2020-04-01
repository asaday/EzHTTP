
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)

import Foundation

class SockHTTPOperation: Operation, EzSocketDelegate {
	var request: URLRequest
	let completion: (Data?, HTTPURLResponse?, NSError?) -> Void

	var socket: EzSocket?
	var url: URL?
	var response: HTTPURLResponse?
	var redirectCount: Int = 0

	var rehttpsSession: URLSession?
	var rehttpsTask: URLSessionDataTask?

	enum Sequence: Int { case header, body, chunkedLength, chunkedBody, chunkBodyTail }
	var sequence: Sequence = .header
	var chunkData: NSMutableData?
	let CRLFData = Data([0x0D, 0x0A])
	let CRLFCRLFData = Data([0x0D, 0x0A, 0x0D, 0x0A])

	class func isATSBlocked(_ url: URL?) -> Bool {
		guard let url = url else { return false }
		if url.scheme != "http" { return false }

		guard let dic = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any] else { return true }

		if dic["NSAllowsArbitraryLoads"] as? Bool ?? false { return false }
		guard let domains = dic["NSExceptionDomains"] as? [String: Any] else { return true }
		for (k, v) in domains {
			if k != url.host { continue }
			guard let dkv = v as? [String: Any] else { continue }
			if dkv["NSExceptionAllowsInsecureHTTPLoads"] as? Bool ?? false { return false }
		}
		return true
	}

	init(request: URLRequest, completion: @escaping (Data?, HTTPURLResponse?, NSError?) -> Void) {
		self.request = request
		self.completion = completion
		super.init()
	}

	override var isAsynchronous: Bool {
		return true
	}

	fileprivate var _executing: Bool = false
	override var isExecuting: Bool {
		get { return _executing }
		set {
			willChangeValue(forKey: "isExecuting")
			_executing = newValue
			didChangeValue(forKey: "isExecuting")
		}
	}

	fileprivate var _finished: Bool = false
	override var isFinished: Bool {
		get { return _finished }
		set {
			willChangeValue(forKey: "isFinished")
			_finished = newValue
			didChangeValue(forKey: "isFinished")
		}
	}

	override func cancel() {
		closeSocket()
		rehttpsTask?.cancel()
		super.cancel()
	}

	override func start() {
		if isCancelled {
			isFinished = true
			return
		}
		guard let u = request.url, let _ = request.httpMethod else {
			let error = NSError(domain: HTTP.HTTPErrorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: ""])
			completion(nil, nil, error)
			isFinished = true
			return
		}
		url = u

		isExecuting = true
		main()
	}

	override func main() {
		if isCancelled {
			done()
			return
		}

		guard let host = url?.host else {
			compError(2, msg: "")
			return
		}

		let port = url?.port ?? 80

		socket = EzSocket()
		socket?.delegate = self

		DispatchQueue.global(qos: .background).async {
			self.socket?.connect(toHost: host, onPort: port)
		}
	}

	func didDisconnect(error: Error?) {
		if !isExecuting { return }

		if let e = error {
			compError(e as NSError)
			return
		}

		done()
	}

	func didConnect() {
		var headlines: [String] = []
		guard let u = url else { return }
		var path = u.path
		if let q = u.query { path += "?" + q }
		headlines.append("\(request.httpMethod ?? "GET") \(path) HTTP/1.1")
		headlines.append("Host: \(u.host ?? "")")

		var agent = "" // "Mozilla/5.0 (iPhone; CPU iPhone OS 10_0_0 like Mac OS X) AppleWebKit/601.0.0 (KHTML, like Gecko) Version/10.0 Mobile/13F69 Safari/601.0 "
		agent += (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "") + "/" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + " "
		agent += "CFNetwork/758.99.99 Darwin/15.6.99 "
		agent += "EzHTTP/1"
		// TODO: better to use NSUserDefaults

		var headers: [String: String] = ["Accept": "*/*", "User-Agent": agent]
		if let reqheaders = request.allHTTPHeaderFields {
			for (k, v) in reqheaders { headers[k] = v }
		}
		if let cookies = HTTPCookieStorage.shared.cookies(for: u) {
			let cheaders = HTTPCookie.requestHeaderFields(with: cookies)
			for (k, v) in cheaders { headers[k] = v }
		}

		if let d = request.httpBody { headers["Content-Length"] = "\(d.count)" }

		headlines.append(contentsOf: headers.map { "\($0): \($1)" })
		headlines.append("")
		headlines.append("")

		var dat = headlines.joined(separator: "\r\n").data(using: String.Encoding.utf8, allowLossyConversion: true) ?? Data()
		if let d = request.httpBody { dat.append(d) }

		socket?.write(dat)
		socket?.read(delimiter: CRLFCRLFData)
	}

	func didRead(data: Data) {
		if isCancelled {
			done()
			return
		}

		switch sequence {
		case .header:
			guard let r = makeResponse(data) else {
				compError(3, msg: "http make response error")
				return
			}

			if r.statusCode >= 301, r.statusCode <= 308 {
				if redirectCount > 10 {
					compError(3, msg: "http redirect over")
					return
				}

				if let location = r.allHeaderFields["Location"] as? String {
					closeSocket()
					url = URL(string: location, relativeTo: url) ?? url
					if url?.scheme == "https" {
						var nreq = request
						nreq.url = url
						rehttpsTask = rehttpsSession?.requestData(nreq) { d, r, e in
							if !self.isCancelled { self.completion(d, r, e) }
							self.done()
						}
						return
					}
				}
				main()
				return
			}

			response = r

			if (response?.allHeaderFields["Transfer-Encoding"] as? String) == "chunked" {
				socket?.read(delimiter: CRLFData)
				chunkData = NSMutableData()
				sequence = .chunkedLength
				return
			}

			guard let lenstr = response?.allHeaderFields["Content-Length"] as? String, let len = Int(lenstr) else {
				compError(4, msg: "http no-length")
				return
			}

			sequence = .body
			socket?.read(length: len)

		case .body:
			completion(data, response, nil)
			done()

		case .chunkedLength:
			let scanner = Scanner(string: String(data: data, encoding: String.Encoding.utf8) ?? "")
			var hexValue: UInt32 = 0
			if scanner.scanHexInt32(&hexValue) == false {
				compError(5, msg: "http illegal chunk len")
				return
			}
			if hexValue == 0 {
				completion(chunkData as Data?, response, nil)
				done()
				return
			}
			sequence = .chunkedBody
			socket?.read(length: Int(hexValue))

		case .chunkedBody:
			chunkData?.append(data)
			sequence = .chunkBodyTail
			socket?.read(delimiter: CRLFData)

		case .chunkBodyTail:
			sequence = .chunkedLength
			socket?.read(delimiter: CRLFData)
		}
	}

	func makeResponse(_ data: Data) -> HTTPURLResponse? {
		guard let hs = String(data: data, encoding: String.Encoding.utf8) else { return nil }
		var headlines = hs.components(separatedBy: "\r\n")

		let st = headlines[0].components(separatedBy: " ")
		if st.count <= 2 { return nil }
		guard let status = Int(st[1]) else { return nil }

		headlines.removeFirst()
		var headers: [String: String] = [:]
		guard let u = url else { return nil }

		for h in headlines {
			guard let ra = h.range(of: ":") else { continue }
			let k = h.prefix(upTo: ra.lowerBound).trimmingCharacters(in: CharacterSet.whitespaces)
			let v = h.suffix(from: ra.upperBound).trimmingCharacters(in: CharacterSet.whitespaces)

			if k == "Set-Cookie" {
				let cookies = HTTPCookie.cookies(withResponseHeaderFields: [k: v], for: u)
				HTTPCookieStorage.shared.setCookies(cookies, for: url, mainDocumentURL: url)
				continue
			}
			headers[k] = v
		}

		return HTTPURLResponse(url: u, statusCode: status, httpVersion: st[0], headerFields: headers)
	}

	func closeSocket() {
		socket?.delegate = nil
		socket?.disconnect()
		socket = nil
	}

	func done() {
		closeSocket()
		isExecuting = false
		isFinished = true
	}

	func compError(_ error: NSError) {
		completion(nil, nil, error)
		done()
	}

	func compError(_ code: Int, msg: String) {
		let error = NSError(domain: HTTP.HTTPErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: msg])
		compError(error)
	}
}
