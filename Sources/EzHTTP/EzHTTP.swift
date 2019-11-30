
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)

import Foundation

// MARK: - URLSession

public extension URLSession {
	func requestData(_ request: URLRequest, _ completionHandler: @escaping (Data?, HTTPURLResponse?, NSError?) -> Void) -> URLSessionDataTask? {
		let task = dataTask(with: request) { d, r, e in
			completionHandler(d, r as? HTTPURLResponse, e as NSError?)
		}
		task.resume()
		return task
	}

	func get(_ urls: String, _ completionHandler: @escaping (Data?, HTTPURLResponse?, NSError?) -> Void) -> URLSessionDataTask? {
		guard let url = URL(string: urls) else { return nil }
		return requestData(URLRequest(url: url), completionHandler)
	}
}

// MARK: - URLRequest

public extension URLRequest {
	var curlComand: String {
		var r = "curl "

		if let method = httpMethod, method != "GET" {
			r += "-X \(method) "
		}

		r += "'" + (url?.absoluteString ?? "") + "' "

		for (k, v) in allHTTPHeaderFields ?? [:] {
			r += "-H '\(k): \(v)' "
		}

		for (k, v) in HTTP.shared.session?.configuration.httpAdditionalHeaders ?? [:] {
			if let ks = k as? String, let vs = v as? String {
				r += "-H '\(ks): \(vs)' "
			}
		}

		if let u = url, let cookies = HTTPCookieStorage.shared.cookies(for: u), cookies.count > 0 {
			r += "-H 'Cookie: " + cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ") + "' "
		}

		if let body = httpBody {
			r += "-d '" + (String(data: body, encoding: .utf8) ?? "(binary?)") + "' "
		}

		return r
	}
}

// for files
public extension URLSession {
	func requestFile(_ request: URLRequest, _ completionHandler: @escaping (URL?, HTTPURLResponse?, NSError?) -> Void) -> URLSessionDownloadTask {
		let task = downloadTask(with: request) { u, r, e in
			completionHandler(u, r as? HTTPURLResponse, e as NSError?)
		}
		task.resume()
		return task
	}
}

extension NSMutableData {
	func appendString(_ s: String) {
		if let d = s.data(using: String.Encoding.utf8, allowLossyConversion: true) { append(d) }
	}
}

// MARK: - HTTP

public class HTTP: NSObject, URLSessionDelegate {
	public static let shared: HTTP = HTTP()
	public static let HTTPErrorDomain = "http"

	public enum Method: String { case OPTIONS, GET, HEAD, POST, PUT, PATCH, DELETE, TRACE, CONNECT }

	open var illegalStatusCodeAsError: Bool = true // retuen error when http status error
	open var escapeATS: Bool = false // you can call http when 'Allow Arbitrary Loads' = NO
	open var allowSelfSignedSSL: Bool = false // if yes, set 'Allow Arbitrary Loads' = YES (should use only debug)
	open var postASJSON: Bool = false // force set json when POST, but you had better to use method json customized
	open var timeout: TimeInterval?

	open var baseURL: URL?
	open var errorHandler: ResponseHandler?
	open var successHandler: ResponseHandler?
	open var logHandler: ResponseHandler?
	open var stubHandler: ((_ request: URLRequest) -> Response?)?
	open var retryHandler: ((_ result: Response) -> Bool)?
	open var indicatorHandler: ((_ visible: Bool) -> Void)? {
		didSet {
			if !isUseIndicator {
				NetworkIndicator.addOberveQueue(squeue)
				NetworkIndicator.addOberveQueue(hqueue)
				isUseIndicator = true
			}
			NetworkIndicator.shared.handler = indicatorHandler
		}
	}

	var isUseIndicator = false

	open var session: URLSession?
	open var squeue = OperationQueue()
	open var hqueue = OperationQueue()

	open class Task {
		open var sessionTask: URLSessionTask?
		open var httpOperation: Operation?
		open var retriedCount: Int = 0
		open func cancel() {
			sessionTask?.cancel()
			sessionTask = nil
			httpOperation?.cancel()
			httpOperation = nil
		}
	}

	open class MultipartFile: NSObject {
		open var mime: String
		open var filename: String
		open var data: Data
		public init(mime: String, filename: String, data: Data) {
			self.mime = mime
			self.filename = filename
			self.data = data
		}
	}

	public enum ParamMode: String { case query = "???Query", form = "???Form", json = "???Json", multipartForm = "???MultipartForm", path = "???path", header = "???header", body = "???body" }

	public override init() {
		super.init()
		hqueue.maxConcurrentOperationCount = 12
		session = URLSession(configuration: .default, delegate: self, delegateQueue: squeue)
	}

	deinit {
		if isUseIndicator {
			NetworkIndicator.removeOberveQueue(squeue)
			NetworkIndicator.removeOberveQueue(hqueue)
		}
	}

	public func urlSession(_: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		if allowSelfSignedSSL {
			var credential: URLCredential?
			if let trust = challenge.protectionSpace.serverTrust { credential = URLCredential(trust: trust) }
			completionHandler(URLSession.AuthChallengeDisposition.useCredential, credential)
			return
		}
		completionHandler(URLSession.AuthChallengeDisposition.performDefaultHandling, nil)
	}

	open func setConfig(_ config: URLSessionConfiguration) {
		session = URLSession(configuration: config, delegate: self, delegateQueue: squeue)
	}

	open func request(_ request: URLRequest, handler: @escaping ResponseHandler) -> Task? {
		return requestR(request, orgtask: nil, handler: handler)
	}

	private func requestR(_ request: URLRequest, orgtask: Task?, handler: @escaping ResponseHandler) -> Task? {
		let handlecall: ((_ res: Response, _ task: Task?) -> Void) = { result, task in
			if result.error != nil || result.data == nil {
				if self.retryHandler?(result) ?? false {
					let nt = self.requestR(request, orgtask: task, handler: handler)
					task?.httpOperation = nt?.httpOperation
					task?.sessionTask = nt?.sessionTask
					task?.retriedCount = (task?.retriedCount ?? 0) + 1
					return
				}
				self.errorHandler?(result)
			} else {
				self.successHandler?(result)
			}
			self.logHandler?(result)
			handler(result)
		}

		if let stub = stubHandler, let r = stub(request) {
			handlecall(r, nil)
			return nil
		}

		let isMain = Thread.isMainThread
		let startTime = Date()
		let task = Task()

		var otask: Task?
		if retryHandler != nil { otask = orgtask ?? task }

		let completion: ((Data?, HTTPURLResponse?, NSError?) -> Void) = { data, response, error in
			let duration = Date().timeIntervalSince(startTime)
			var err = error

			if self.illegalStatusCodeAsError, let status = response?.statusCode, status >= 400 {
				err = NSError(domain: HTTP.HTTPErrorDomain, code: status, userInfo: [NSLocalizedDescriptionKey: "\(status) : " + HTTPURLResponse.localizedString(forStatusCode: status)])
			}

			// checker if (otask?.retriedCount ?? 0) < 2 { err = NSError(domain: "", code: 1, userInfo: nil) }

			let res = Response(data: data, error: err, response: response, request: request, duration: duration, retriedCount: otask?.retriedCount ?? 0)
			if isMain {
				DispatchQueue.main.async { handlecall(res, otask) }
			} else {
				DispatchQueue.global(qos: .background).async { handlecall(res, otask) }
			}
		}

		if escapeATS, SockHTTPOperation.isATSBlocked(request.url) { // HTTP
			let op = SockHTTPOperation(request: request, completion: completion)
			op.rehttpsSession = session
			hqueue.addOperation(op)
			task.httpOperation = op
			return task
		}

		// normal
		task.sessionTask = session?.requestData(request, completion)
		return task
	}

	func encodeQuery(_ params: [String: Any]?) -> String {
		func escape(_ v: String) -> String {
			var cs = NSMutableCharacterSet.urlQueryAllowed
			cs.remove(charactersIn: ":#[]@!$&'()*+,;=")
			return v.addingPercentEncoding(withAllowedCharacters: cs) ?? v
		}

		func encode(_ key: String, _ value: Any) -> [String] {
			var r: [String] = []

			switch value {
			case let dic as [String: Any]: for (k, v) in dic { r += encode("\(key)[\(k)]", v) }
			case let ar as [Any]: for v in ar { r += encode("\(key)[]", v) }
			case let s as String: r.append(escape(key) + "=" + escape(s))
			case let d as Data: r.append(escape(key) + "=" + d.base64EncodedString(options: []))
			default: r.append(escape(key) + "=" + escape("\(value)"))
			}
			return r
		}

		guard let params = params else { return "" }
		var r: [String] = []
		for (k, v) in params { r += encode(k, v) }
		return r.joined(separator: "&")
	}

	func hasMultipartFile(_ params: [String: Any]?) -> Bool {
		guard let params = params else { return false }
		for v in params.values {
			if v is MultipartFile { return true }
		}
		return false
	}

	func encodeMultiPart(_ params: [String: Any]?, boundary: String) -> Data {
		guard let params = params else { return Data() }
		let r = NSMutableData()

		for (k, v) in params {
			if v is MultipartFile { continue }
			r.appendString("--\(boundary)\r\n")
			r.appendString("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n")
		}

		for (k, v) in params {
			guard let d = v as? MultipartFile else { continue }
			r.appendString("--\(boundary)\r\n")
			var cda = ["form-data", "name=\"\(k)\""]
			if !d.filename.isEmpty { cda.append("filename=\"\(d.filename)\"") }
			r.appendString("Content-Disposition: " + cda.joined(separator: "; ") + "\r\n")
			r.appendString("Content-Type: \(d.mime)\r\n\r\n")
			r.append(d.data)
			r.appendString("\r\n")
		}

		r.appendString("--\(boundary)--\r\n")
		return r as Data
	}

	// url is String or URL
	open func createRequest(_ method: Method, _ url: URL, params: [String: Any]?, headers: [String: String]?) -> URLRequest {
		var req = URLRequest(url: url)
		req.httpMethod = method.rawValue
		if let t = timeout { req.timeoutInterval = t }

		func addContentType(_ s: String) {
			if req.value(forHTTPHeaderField: "Content-Type") != nil { return }
			req.setValue(s, forHTTPHeaderField: "Content-Type")
		}

		// config header is auto merged
		headers?.forEach { req.setValue($1, forHTTPHeaderField: $0) }
		if let r = params?[ParamMode.header.rawValue] as? [String: String] {
			r.forEach { req.setValue($1, forHTTPHeaderField: $0) }
		}

		var sp = params
		sp?[HTTP.ParamMode.header.rawValue] = nil
		sp?[HTTP.ParamMode.path.rawValue] = nil

		let postmode = (method == .POST || method == .PUT || method == .PATCH)

		var queries = sp?[ParamMode.query.rawValue] as? [String: Any]
		if !postmode, queries == nil { queries = sp }

		if let p = queries, var uc = URLComponents(url: url, resolvingAgainstBaseURL: false) {
			var q = encodeQuery(p)
			if let oq = uc.percentEncodedQuery { q = oq + "&" }
			if !q.isEmpty {
				uc.percentEncodedQuery = q
				if let uu = uc.url { req.url = uu }
			}
		}

		if !postmode { return req }

		var mode = ParamMode.form
		if postASJSON { mode = .json }

		if let r = sp?[ParamMode.json.rawValue] as? [String: Any] {
			sp = r
			mode = .json
		}

		if let r = sp?[ParamMode.form.rawValue] as? [String: Any] {
			sp = r
			mode = .form
		}

		if let r = sp?[ParamMode.multipartForm.rawValue] as? [String: Any] {
			sp = r
			mode = .multipartForm
		}

		if let r = sp?[ParamMode.body.rawValue] {
			if let d = r as? Data { req.httpBody = d }
			if let d = r as? String { req.httpBody = d.data(using: .utf8) }
			return req
		}

		if let r = sp?[ParamMode.json.rawValue] as? [Any] { // for array json
			if JSONSerialization.isValidJSONObject(r) { req.httpBody = try? JSONSerialization.data(withJSONObject: r, options: []) }
			addContentType("application/json")
			return req
		}

		if !postASJSON, hasMultipartFile(sp) { mode = .multipartForm }

		guard let p = sp else { return req }
		switch mode {
		case .json:
			if JSONSerialization.isValidJSONObject(p) { req.httpBody = try? JSONSerialization.data(withJSONObject: p, options: []) }
			if req.httpBody == nil { req.httpBody = "{}".data(using: .utf8) } // no-data value
			addContentType("application/json")

		case .form:
			req.httpBody = encodeQuery(p).data(using: String.Encoding.utf8, allowLossyConversion: true)
			addContentType("application/x-www-form-urlencoded; charset=utf-8")

		case .multipartForm:
			let boundary = "Boundary" + NSUUID().uuidString.replacingOccurrences(of: "-", with: "")
			req.httpBody = encodeMultiPart(p, boundary: boundary)
			addContentType("multipart/form-data; boundary=\(boundary)")

		default:
			break
		}

		return req
	}

	open func createURL(_ url: String, inpath: [String: String]? = nil) -> URL? {
		if inpath == nil { return URL(string: url, relativeTo: baseURL) }

		let ms: NSMutableString = NSMutableString(string: url)
		inpath?.forEach { k, v in
			ms.replaceOccurrences(of: "{\(k)}", with: v, options: .caseInsensitive, range: NSMakeRange(0, ms.length))
		}

		return URL(string: ms as String, relativeTo: baseURL)
	}
}

// for debbug
public extension HTTP {
	static func defaultLogHandler(_ res: Response) {
		print("⚡ \(res.description)\n")
	}

	static func defaultRetryHandler(_ res: Response) -> Bool {
		print("retry\(res.retriedCount) \(res.request?.url?.absoluteString ?? "") \n")
		return res.retriedCount < 3
	}
}

// MARK: static

public extension HTTP {
	static func createRequest(_ method: Method, _ url: URL, params: [String: Any]?, headers: [String: String]?) -> URLRequest? {
		return shared.createRequest(method, url, params: params, headers: headers)
	}

	static func createRequest(_ method: Method, _ urlstring: String, params: [String: Any]?, headers: [String: String]?) -> URLRequest? {
		guard let url = shared.createURL(urlstring, inpath: params?[ParamMode.path.rawValue] as? [String: String]) else { return nil }
		return createRequest(method, url, params: params, headers: headers)
	}

	// request
	@discardableResult static func request(_ request: URLRequest, _ handler: @escaping ResponseHandler) -> Task? {
		return shared.request(request, handler: handler)
	}

	// url
	@discardableResult static func request(_ method: Method, _ url: URL, params: [String: Any]? = nil, headers: [String: String]? = nil, _ handler: @escaping ResponseHandler) -> Task? {
		return request(shared.createRequest(method, url, params: params, headers: headers), handler)
	}

	@discardableResult static func request(_ method: Method, _ url: URL, json: Any, headers: [String: String]? = nil, _ handler: @escaping ResponseHandler) -> Task? {
		return request(shared.createRequest(method, url, params: [HTTP.ParamMode.json.rawValue: json], headers: headers), handler)
	}

	@discardableResult static func request(_ method: Method, _ url: URL, body: Any, headers: [String: String]? = nil, _ handler: @escaping ResponseHandler) -> Task? {
		return request(shared.createRequest(method, url, params: [HTTP.ParamMode.body.rawValue: body], headers: headers), handler)
	}

	@discardableResult static func get(_ url: URL, params: [String: Any]? = nil, headers: [String: String]? = nil, _ handler: @escaping ResponseHandler) -> Task? {
		return request(.GET, url, params: params, headers: headers, handler)
	}

	// url string
	@discardableResult static func request(_ method: Method, _ urlstring: String, params: [String: Any]? = nil, headers: [String: String]? = nil, _ handler: @escaping ResponseHandler) -> Task? {
		guard let url = shared.createURL(urlstring, inpath: params?[ParamMode.path.rawValue] as? [String: String]) else { handler(makeURLErrorResponse()); return nil }
		return request(method, url, params: params, headers: headers, handler)
	}

	@discardableResult static func request(_ method: Method, _ urlstring: String, json: Any, headers: [String: String]? = nil, _ handler: @escaping ResponseHandler) -> Task? {
		guard let url = shared.createURL(urlstring) else { handler(makeURLErrorResponse()); return nil }
		return request(method, url, json: json, headers: headers, handler)
	}

	@discardableResult static func request(_ method: Method, _ urlstring: String, body: Any, headers: [String: String]? = nil, _ handler: @escaping ResponseHandler) -> Task? {
		guard let url = shared.createURL(urlstring) else { handler(makeURLErrorResponse()); return nil }
		return request(method, url, body: body, headers: headers, handler)
	}

	@discardableResult static func get(_ urlstring: String, params: [String: Any]? = nil, headers: [String: String]? = nil, _ handler: @escaping ResponseHandler) -> Task? {
		guard let url = shared.createURL(urlstring, inpath: params?[ParamMode.path.rawValue] as? [String: String]) else { handler(makeURLErrorResponse()); return nil }
		return get(url, params: params, headers: headers, handler)
	}

	// async
	static func requestSync(_ request: URLRequest) -> Response {
		var r = Response(error: NSError(domain: HTTPErrorDomain, code: -3, userInfo: [NSLocalizedDescriptionKey: "t/o"]))
		let sem = DispatchSemaphore(value: 0)

		DispatchQueue.global(qos: .background).async {
			HTTP.request(request) {
				r = $0
				sem.signal()
			}
		}
		_ = sem.wait(timeout: .now() + 30)
		return r
	}

	// async url
	static func requestSync(_ method: Method, _ url: URL, params: [String: Any]? = nil, headers: [String: String]? = nil) -> Response {
		return requestSync(HTTP.shared.createRequest(method, url, params: params, headers: headers))
	}

	static func requestSync(_ method: Method, _ url: URL, json: Any, headers: [String: String]? = nil) -> Response {
		return requestSync(shared.createRequest(method, url, params: [HTTP.ParamMode.json.rawValue: json], headers: headers))
	}

	static func requestSync(_ method: Method, _ url: URL, body: Any, headers: [String: String]? = nil) -> Response {
		return requestSync(shared.createRequest(method, url, params: [HTTP.ParamMode.body.rawValue: body], headers: headers))
	}

	static func getSync(_ url: URL, headers: [String: String]? = nil) -> Response {
		return requestSync(.GET, url, params: nil, headers: headers)
	}

	// async url string
	static func requestSync(_ method: Method, _ urlstring: String, params: [String: Any]? = nil, headers: [String: String]? = nil) -> Response {
		guard let url = shared.createURL(urlstring, inpath: params?[ParamMode.path.rawValue] as? [String: String]) else { return makeURLErrorResponse() }
		return requestSync(method, url, params: params, headers: headers)
	}

	static func requestSync(_ method: Method, _ urlstring: String, json: Any, headers: [String: String]? = nil) -> Response {
		guard let url = shared.createURL(urlstring) else { return makeURLErrorResponse() }
		return requestSync(method, url, json: json, headers: headers)
	}

	static func requestSync(_ method: Method, _ urlstring: String, body: Any, headers: [String: String]? = nil) -> Response {
		guard let url = shared.createURL(urlstring) else { return makeURLErrorResponse() }
		return requestSync(shared.createRequest(method, url, params: [HTTP.ParamMode.body.rawValue: body], headers: headers))
	}

	static func getSync(_ urlstring: String, headers: [String: String]? = nil) -> Response {
		return requestSync(.GET, urlstring, params: nil, headers: headers)
	}

	// error
	fileprivate static func makeURLErrorResponse() -> Response {
		return Response(error: NSError(domain: HTTPErrorDomain, code: -2, userInfo: [NSLocalizedDescriptionKey: "Bad URL"]))
	}

	// param for multi pattern
	static func makeParams(query: [String: Any]? = nil, form: [String: Any]? = nil, json: [String: Any]? = nil) -> [String: Any] {
		var r: [String: Any] = [:]
		if let v = query { r[ParamMode.query.rawValue] = v }
		if let v = form { r[ParamMode.form.rawValue] = v }
		if let v = json { r[ParamMode.json.rawValue] = v }
		return r
	}

	// batch operation
	static func batch(reuqests: [URLRequest], completion: @escaping ([Response]) -> Void) {
		let srcQueue: DispatchQueue = Thread.isMainThread ? .main : DispatchQueue.global(qos: .background)
		let length = reuqests.count

		DispatchQueue.global(qos: .background).async {
			let grp = DispatchGroup()
			var idxresults: [Int: Response] = [:]
			for (idx, r) in reuqests.enumerated() {
				grp.enter()
				request(r) {
					idxresults[idx] = $0
					grp.leave()
				}
			}

			grp.notify(queue: srcQueue) {
				var r: [Response] = []
				for idx in 0 ..< length { if let a = idxresults[idx] { r.append(a) } }
				if r.count != length { r.removeAll() }
				completion(r)
			}
		}
	}

	// objdecoder request
	static func requestAndDecode<T: Codable>(_ request: URLRequest, _ handler: @escaping (T?, Response) -> Void) -> Task? {
		return shared.request(request) { handler(ObjectDecoder().optionalDecode(T.self, from: $0.data), $0) }
	}

	// objdecoder url
	@discardableResult static func requestAndDecode<T: Codable>(_ method: Method, _ url: URL, params: [String: Any]? = nil, headers: [String: String]? = nil, _ handler: @escaping (T?, Response) -> Void) -> Task? {
		return requestAndDecode(shared.createRequest(method, url, params: params, headers: headers), handler)
	}

	@discardableResult static func requestAndDecode<T: Codable>(_ method: Method, _ url: URL, json: Any, headers: [String: String]? = nil, _ handler: @escaping (T?, Response) -> Void) -> Task? {
		return requestAndDecode(shared.createRequest(method, url, params: [HTTP.ParamMode.json.rawValue: json], headers: headers), handler)
	}

	@discardableResult static func requestAndDecode<T: Codable>(_ method: Method, _ url: URL, body: Any, headers: [String: String]? = nil, _ handler: @escaping (T?, Response) -> Void) -> Task? {
		return requestAndDecode(shared.createRequest(method, url, params: [HTTP.ParamMode.body.rawValue: body], headers: headers), handler)
	}

	// objdecoder url string
	@discardableResult static func requestAndDecode<T: Codable>(_ method: Method, _ urlstring: String, params: [String: Any]? = nil, headers: [String: String]? = nil, _ handler: @escaping (T?, Response) -> Void) -> Task? {
		guard let url = shared.createURL(urlstring, inpath: params?[ParamMode.path.rawValue] as? [String: String]) else { handler(nil, makeURLErrorResponse()); return nil }
		return requestAndDecode(method, url, params: params, headers: headers, handler)
	}

	@discardableResult static func requestAndDecode<T: Codable>(_ method: Method, _ urlstring: String, json: Any, headers: [String: String]? = nil, _ handler: @escaping (T?, Response) -> Void) -> Task? {
		guard let url = shared.createURL(urlstring) else { handler(nil, makeURLErrorResponse()); return nil }
		return requestAndDecode(method, url, json: json, headers: headers, handler)
	}

	@discardableResult static func requestAndDecode<T: Codable>(_ method: Method, _ urlstring: String, body: Any, headers: [String: String]? = nil, _ handler: @escaping (T?, Response) -> Void) -> Task? {
		guard let url = shared.createURL(urlstring) else { handler(nil, makeURLErrorResponse()); return nil }
		return requestAndDecode(method, url, body: body, headers: headers, handler)
	}
}

extension String {
	var length: Int {
		#if swift(>=3.2)
			return count
		#else
			return characters.count
		#endif
	}
}

// MARK: response

public extension HTTP {
	typealias ResponseHandler = ((_ result: Response) -> Void)

	struct Response: CustomStringConvertible {
		public let data: Data?
		public let error: NSError?
		public let response: HTTPURLResponse?
		public let request: URLRequest?
		public let duration: TimeInterval
		public let retriedCount: Int

		public init(data: Data?, error: NSError?, response: HTTPURLResponse?, request: URLRequest?, duration: TimeInterval = 0, retriedCount: Int = 0) {
			self.data = data
			self.error = error
			self.response = response
			self.request = request
			self.duration = duration
			self.retriedCount = retriedCount
		}

		public init(error: NSError) {
			self.init(data: nil, error: error, response: nil, request: nil)
		}

		public var string: String? {
			guard let d = data else { return nil }
			return String(data: d, encoding: String.Encoding.utf8)
		}

		public var jsonObject: NSObject? {
			guard let dat = data else { return nil }
			guard let json = try? JSONSerialization.jsonObject(with: dat, options: .allowFragments) else { return nil }
			return json as? NSObject
		}

		public var jsonDictionary: NSDictionary? {
			return jsonObject as? NSDictionary
		}

		public var status: Int { return response?.statusCode ?? 0 }
		public var dataValue: Data { return data ?? Data() }
		public var stringValue: String { return string ?? "" }
		public var jsonObjectValue: NSObject { return jsonObject ?? NSObject() }
		public var headers: [AnyHashable: String] { return response?.allHeaderFields as? [AnyHashable: String] ?? [:] }

		public var description: String {
			var result = "[Request \(request?.url?.absoluteString ?? "")]\n"
			result += request?.curlComand ?? ""

			result += "\n[Response \(Int(duration * 1000))ms \(response?.statusCode ?? 0) (" + HTTPURLResponse.localizedString(forStatusCode: response?.statusCode ?? 0) + ") \(response?.url?.absoluteString ?? "")]\n"
			for (k, v) in response?.allHeaderFields ?? [:] { result += "< \(k): \(v)\n" }

			if let e = error { result += "Error:" + e.localizedDescription }

			if let d = data {
				if let s = String(data: d, encoding: String.Encoding.utf8) {
					if s.length < 512 { result += s }
					else { result += (s as NSString).substring(to: 512) + "...length: \(s.length)" }
				} else {
					result += "data length: \(d.count / 1024) KB"
				}
			} else {
				result += "(no-data)"
			}

			result += "\n[EOD]"
			return result
		}
	}
}
