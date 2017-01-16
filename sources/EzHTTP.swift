
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)

import Foundation


// MARK: - NSURLSession

public extension URLSession {

	func requestData(_ request: URLRequest, _ completionHandler: @escaping (Data?, HTTPURLResponse?, NSError?) -> Void) -> URLSessionDataTask? {
		let task = dataTask(with: request) { (d, r, e) in
			completionHandler(d, r as? HTTPURLResponse, e as? NSError)
		}
		task.resume()
		return task
	}

	func get(_ urls: String, _ completionHandler: @escaping (Data?, HTTPURLResponse?, NSError?) -> Void) -> URLSessionDataTask? {
		guard let url = URL(string: urls) else { return nil }
		return requestData(URLRequest(url: url), completionHandler)
	}
}

// for files
public extension URLSession {

	func requestFile(_ request: URLRequest, _ completionHandler: @escaping (URL?, HTTPURLResponse?, NSError?) -> Void) -> URLSessionDownloadTask {
		let task = downloadTask(with: request) { (u, r, e) in
			completionHandler(u, r as? HTTPURLResponse, e as? NSError)
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

open class HTTP: NSObject, URLSessionDelegate {
	open static let shared: HTTP = HTTP()

	public enum Method: String { case OPTIONS, GET, HEAD, POST, PUT, PATCH, DELETE, TRACE, CONNECT }

	open let config = URLSessionConfiguration.default
	open var baseURL: URL? = nil
	open var postASJSON: Bool = false

	open var errorHandler: ResponseHandler?
	open var successHandler: ResponseHandler?
	open var logHandler: ResponseHandler?
	open var stubHandler: ((_ request: URLRequest) -> Response?)?

	open var useIndicator: Bool = true
	open var escapeATS: Bool = false

	var session: URLSession?
	var squeue: OperationQueue?
	var hqueue: OperationQueue?

	open class Task {
		open var sessionTask: URLSessionTask?
		open var httpOperation: Operation?
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

	public enum ParamMode: String { case query = "???Query", form = "???Form", json = "???Json", multipartForm = "???MultipartForm" }

	override init () {
		super.init()
		// config.HTTPMaximumConnectionsPerHost = 6
		// config.timeoutIntervalForRequest = 15
		// logHandler = HTTP.defaultLogHandler
		NetworkIndicator.setState("", false) // to skip lazy load
	}

	deinit {
		NetworkIndicator.removeOberveQueue(squeue)
		NetworkIndicator.removeOberveQueue(hqueue)
	}

	open func request(_ request: URLRequest, handler: @escaping ResponseHandler) -> Task? {

		let handlecall: ((_ res: Response) -> Void) = { result in
			if result.data == nil { self.errorHandler?(result) }
				else { self.successHandler?(result) }
			self.logHandler?(result)
			handler(result)
		}

		if let stub = stubHandler, let r = stub(request) {
			handlecall(r)
			return nil
		}

		if session == nil {
			let q = OperationQueue()
			if useIndicator { NetworkIndicator.addOberveQueue(q) }
			session = URLSession(configuration: config, delegate: self, delegateQueue: q)
			squeue = q
		}

		let isMain = Thread.isMainThread
		let startTime = Date()
		let task = Task()

		let comp: ((Data?, HTTPURLResponse?, NSError?) -> Void) = { (data, response, error) in
			let duration = Date().timeIntervalSince(startTime)
			let res = Response(data: data, error: error, response: response, request: request, duration: duration)
			if isMain {
				DispatchQueue.main.async { handlecall(res) }
			} else {
				DispatchQueue.global(qos: DispatchQoS.QoSClass.background).async { handlecall(res) }
			}
		}

		if escapeATS && SockHTTPOperation.isATSBlocked(request.url) { // HTTP
			if hqueue == nil {
				let q = OperationQueue ()
				q.maxConcurrentOperationCount = 12
				if useIndicator { NetworkIndicator.addOberveQueue(q) }
				hqueue = q
			}

			let op = SockHTTPOperation(request: request, completion: comp)
			op.rehttpsSession = session
			hqueue?.addOperation(op)
			task.httpOperation = op

		} else { // normal
			task.sessionTask = session?.requestData(request, comp)
		}
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
			r.appendString("Content-Disposition: form-data; name=\"\(k)\"; filename=\"\(d.filename)\"\r\n")
			r.appendString("Content-Type: \(d.mime)\r\n\r\n")
			r.append(d.data)
			r.appendString("\r\n")
		}

		r.appendString("--\(boundary)--\r\n")
		return r as Data
	}

// url is String or URL
	open func createRequest(_ method: Method, _ url: URL, params: [String: Any]?, headers: [String: String]?) -> URLRequest? {

		var req = URLRequest(url: url)
		req.httpMethod = method.rawValue
		req.timeoutInterval = config.timeoutIntervalForRequest
		headers?.forEach { req.setValue($1, forHTTPHeaderField: $0) }
		// config header is auto merged

		let postmode = (method == .POST || method == .PUT || method == .PATCH)

		var queryParams = params?[ParamMode.query.rawValue] as? [String: Any]
		if !postmode && queryParams == nil { queryParams = params }

		if let p = queryParams, var uc = URLComponents(url: url, resolvingAgainstBaseURL: false) {
			var q = encodeQuery(p)
			if let oq = uc.percentEncodedQuery { q = oq + "&" }
			if !q.isEmpty {
				uc.percentEncodedQuery = q
				if let uu = uc.url { req.url = uu }
			}
		}

		if !postmode { return req }

		var sp = params
		var mode = ParamMode.form
		if postASJSON { mode = .json }

		if let r = params?[ParamMode.json.rawValue] as? [String: AnyObject] {
			sp = r
			mode = .json
		}

		if let r = params?[ParamMode.form.rawValue] as? [String: AnyObject] {
			sp = r
			mode = .form
		}

		if let r = params?[ParamMode.multipartForm.rawValue] as? [String: AnyObject] {
			sp = r
			mode = .multipartForm
		}

		if !postASJSON && hasMultipartFile(sp) { mode = .multipartForm }

		guard let p = sp else { return req }
		switch mode {
		case .json:
			req.httpBody = try? JSONSerialization.data(withJSONObject: p, options: [])
			req.setValue("application/json", forHTTPHeaderField: "Content-Type")

		case .form:
			req.httpBody = encodeQuery(p).data(using: String.Encoding.utf8, allowLossyConversion: true)
			req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

		case .multipartForm:
			let boundary = "Boundary" + NSUUID().uuidString.replacingOccurrences(of: "-", with: "")
			req.httpBody = encodeMultiPart(p, boundary: boundary)
			req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

		default:
			break
		}

		return req
	}

	open func createURL(_ url: String) -> URL? {
		return URL(string: url, relativeTo: baseURL)
	}
}

// for debbug
extension HTTP {

	public static func defaultLogHandler(_ res: Response) {
		print(res)
	}
}

// MARK: static

public extension HTTP {
	static func createRequest(_ method: Method, _ url: URL, params: [String: Any]?, headers: [String: String]?) -> URLRequest? {
		return shared.createRequest(method, url, params: params, headers: headers)
	}

	static func createRequest(_ method: Method, _ urlstring: String, params: [String: Any]?, headers: [String: String]?) -> URLRequest? {
		guard let url = shared.createURL(urlstring) else { return nil }
		return createRequest(method, url, params: params, headers: headers)
	}

	@discardableResult static func request(_ request: URLRequest, _ handler: @escaping ResponseHandler) -> Task? {
		return shared.request(request, handler: handler)
	}

	@discardableResult static func request(_ method: Method, _ url: URL, params: [String: Any]? = nil, headers: [String: String]? = nil, _ handler: @escaping ResponseHandler) -> Task? {
		guard let req = shared.createRequest(method, url, params: params, headers: headers) else { return nil }
		return request(req, handler)
	}

	@discardableResult static func request(_ method: Method, _ urlstring: String, params: [String: Any]? = nil, headers: [String: String]? = nil, _ handler: @escaping ResponseHandler) -> Task? {
		guard let url = shared.createURL(urlstring) else { return nil }
		return request(method, url, params: params, headers: headers, handler)
	}

	@discardableResult static func get(_ url: URL, params: [String: Any]? = nil, headers: [String: String]? = nil, _ handler: @escaping ResponseHandler) -> Task? {
		return request(.GET, url, params: params, headers: headers, handler)
	}

	@discardableResult static func get(_ urlstring: String, params: [String: Any]? = nil, headers: [String: String]? = nil, _ handler: @escaping ResponseHandler) -> Task? {
		guard let url = shared.createURL(urlstring) else { return nil }
		return get(url, params: params, headers: headers, handler)
	}

	// async
	static func requestASync(_ request: URLRequest) -> Response {
		var r = Response(error: NSError(domain: "http", code: -2, userInfo: nil))
		var done = false

		HTTP.request(request) { r = $0; done = true }
		while done == false { CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.02, false) }
		return r
	}

	static func requestASync(_ method: Method, _ url: URL, params: [String: Any]? = nil, headers: [String: String]? = nil) -> Response {
		guard let req = HTTP.createRequest(method, url, params: params, headers: headers) else {
			return Response(error: NSError(domain: "http", code: -2, userInfo: nil))
		}
		return requestASync(req as URLRequest)
	}

	static func requestASync(_ method: Method, _ urlstring: String, params: [String: Any]? = nil, headers: [String: String]? = nil) -> Response {
		guard let url = shared.createURL(urlstring), let req = HTTP.createRequest(method, url, params: params, headers: headers) else {
			return Response(error: NSError(domain: "http", code: -2, userInfo: nil))
		}
		return requestASync(req as URLRequest)
	}

	static func getASync(_ url: URL, headers: [String: String]? = nil) -> Response {
		return requestASync(.GET, url, params: nil, headers: headers)
	}

	static func getASync(_ urlstring: String, headers: [String: String]? = nil) -> Response {
		return requestASync(.GET, urlstring, params: nil, headers: headers)
	}

	// param for multi pattern
	static func makeParams(query: [String: Any]? = nil, form: [String: Any]? = nil, json: [String: Any]? = nil) -> [String: Any] {

		var r: [String: Any] = [:]
		if let v = query { r[ParamMode.query.rawValue] = v }
		if let v = form { r[ParamMode.form.rawValue] = v }
		if let v = json { r[ParamMode.json.rawValue] = v }
		return r
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

		public init(data: Data?, error: NSError?, response: HTTPURLResponse?, request: URLRequest?, duration: TimeInterval) {
			self.data = data
			self.error = error
			self.response = response
			self.request = request
			self.duration = duration
		}

		public init(error: NSError) {
			self.init(data: nil, error: error, response: nil, request: nil, duration: 0)
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

		public var status: Int { return response?.statusCode ?? 0 }
		public var dataValue: Data { return data ?? Data() }
		public var stringValue: String { return string ?? "" }
		public var jsonObjectValue: NSObject { return jsonObject ?? NSObject() }
		public var headers: [AnyHashable: String] { return response?.allHeaderFields as? [AnyHashable: String] ?? [:] }

		public var description: String {
			var result = "[Res] "
			result += request?.url?.absoluteString ?? "unknownURL"
			result += " (\( Int((duration) * 1000))ms)\n"

			if let e = error { result += "Error:" + e.localizedDescription }

			if let d = data {
				if let s = String(data: d, encoding: String.Encoding.utf8) {
					if s.characters.count < 24 { result += s }
						else { result += (s as NSString).substring(to: 24) + "...length: \(s.characters.count)" }
				} else {
					return "data length: \(d.count / 1024) KB"
				}
			} else {
				result += "(no-data)"
			}
			return result
		}
	}

}

