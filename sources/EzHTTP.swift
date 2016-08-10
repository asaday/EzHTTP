
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)

import Foundation

public extension NSURLRequest {
	convenience init(string str: String) {
		self.init(URL: NSURL(string: str) ?? NSURL())
	}
}

// MARK: - NSURLSession

public extension NSURLSession {

	func requestData(request: NSURLRequest, _ completionHandler: (NSData?, NSURLResponse?, NSError?) -> Void) -> NSURLSessionDataTask? {
		let task = dataTaskWithRequest(request, completionHandler: completionHandler)
		task.resume()
		return task
	}

	func get(urls: String, _ completionHandler: (NSData?, NSURLResponse?, NSError?) -> Void) -> NSURLSessionDataTask? {
		guard let url = NSURL(string: urls) else { return nil }
		return requestData(NSURLRequest(URL: url), completionHandler)
	}
}

// for files
public extension NSURLSession {

	func requestFile(request: NSURLRequest, _ completionHandler: (NSURL?, NSURLResponse?, NSError?) -> Void) -> NSURLSessionDownloadTask {
		let task = downloadTaskWithRequest(request, completionHandler: completionHandler)
		task.resume()
		return task
	}
}

extension NSMutableData {
	func appendString(s: String) {
		if let d = s.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true) { appendData(d) }
	}
}

// MARK: - HTTP

public class HTTP: NSObject, NSURLSessionDelegate {
	public static let sharedInstance: HTTP = HTTP()

	public enum Method: String {
		case OPTIONS, GET, HEAD, POST, PUT, PATCH, DELETE, TRACE, CONNECT
	}

	public let config = NSURLSessionConfiguration.defaultSessionConfiguration()
	public var baseURL: NSURL? = nil
	public var postASJSON: Bool = false

	public var errorHandler: ResponseHandler?
	public var successHandler: ResponseHandler?
	public var logHandler: ResponseHandler?
	public var stubHandler: ((request: NSURLRequest) -> Response?)?

	public var useIndicator: Bool = true
	public var escapeATS: Bool = false

	var session: NSURLSession?
	var squeue: NSOperationQueue?
	var hqueue: NSOperationQueue?

	public class Task {
		public var sessionTask: NSURLSessionTask?
		public var httpOperation: NSOperation?
		public func cancel() {
			sessionTask?.cancel()
			sessionTask = nil
			httpOperation?.cancel()
			httpOperation = nil
		}
	}
	public class MultipartFile: NSObject {
		public var mime: String
		public var filename: String
		public var data: NSData
		public init(mime: String, filename: String, data: NSData) {
			self.mime = mime
			self.filename = filename
			self.data = data
		}
	}

	override init () {
		super.init()
		// config.HTTPMaximumConnectionsPerHost = 6
		// config.timeoutIntervalForRequest = 15
		// logHandler = HTTP.defaultLogHandler
	}

	deinit {
		NetworkIndicator.removeOberveQueue(squeue)
		NetworkIndicator.removeOberveQueue(hqueue)
	}

	public func request(request: NSURLRequest, handler: ResponseHandler) -> Task? {

		let handlecall: ((res: Response) -> Void) = { res in
			if res.data == nil { self.errorHandler?(res: res) }
			else { self.successHandler?(res: res) }
			self.logHandler?(res: res)
			handler(res: res)
		}

		if let stub = stubHandler {
			let r = stub(request: request)
			if let r = r {
				handlecall(res: r)
				return nil
			}
		}

		if session == nil {
			let q = NSOperationQueue()
			if useIndicator { NetworkIndicator.addOberveQueue(q) }
			session = NSURLSession(configuration: config, delegate: self, delegateQueue: q)
			squeue = q
		}

		let isMain = NSThread.isMainThread()
		let startTime = NSDate()
		let task = Task()

		let comp: ((NSData?, NSURLResponse?, NSError?) -> Void) = { data, response, error in
			let hresponse = response as? NSHTTPURLResponse
			let duration = NSDate().timeIntervalSinceDate(startTime)
			let res = Response(data: data, error: error, response: hresponse, request: request, duration: duration)
			if isMain {
				dispatch_async(dispatch_get_main_queue()) { handlecall(res: res) }
			} else {
				dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)) { handlecall(res: res) }
			}
		}

		if escapeATS && SockHTTPOperation.isATSBlocked(request.URL) { // HTTP
			if hqueue == nil {
				let q = NSOperationQueue ()
				q.maxConcurrentOperationCount = 6
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

	func encodeQuery(params: [String: AnyObject]?) -> String {

		func escape(v: String) -> String {
			guard let cs = NSCharacterSet.URLQueryAllowedCharacterSet().mutableCopy() as? NSMutableCharacterSet else { return v }
			cs.removeCharactersInString(":#[]@!$&'()*+,;=")
			return v.stringByAddingPercentEncodingWithAllowedCharacters(cs) ?? v
		}

		func encode(key: String, _ value: AnyObject) -> [String] {
			var r: [String] = []

			switch value {
			case let dic as [String: AnyObject]:
				for (k, v) in dic { r += encode("\(key)[\(k)]", v) }
			case let ar as [AnyObject]:
				for v in ar { r += encode("\(key)[]", v) }
			case let s as String:
				r.append(escape(key) + "=" + escape(s))
			case let d as NSData:
				r.append(escape(key) + "=" + d.base64EncodedStringWithOptions([]))
			default:
				r.append(escape(key) + "=" + escape("\(value)"))
			}
			return r
		}

		guard let params = params else { return "" }
		var r: [String] = []
		for (k, v) in params { r += encode(k, v) }
		return r.joinWithSeparator("&")
	}

	func hasMultipartFile(params: [String: AnyObject]?) -> Bool {
		guard let params = params else { return false }
		for v in params.values {
			if v is MultipartFile { return true }
		}
		return false
	}

	func encodeMultiPart(params: [String: AnyObject]?, boundary: String) -> NSData {
		guard let params = params else { return NSData() }
		let r = NSMutableData()

		for (k, v) in params {
			if v is MultipartFile { continue }
			r.appendString("--\(boundary)\r\n")
			r.appendString("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n")
		}

		for (k, v) in params {
			guard let d = v as? MultipartFile else { continue }
			r.appendString("--\(boundary)\r\n")
			r.appendString("Content-Disposition: form-data; name=\"\(k)\"; filename=\"\(d.filename )\"\r\n")
			r.appendString("Content-Type: \(d.mime)\r\n\r\n")
			r.appendData(d.data)
			r.appendString("\r\n")
		}

		r.appendString("--\(boundary)--\r\n")
		return r
	}

	public func createRequest(method: Method, _ urls: String, params: [String: AnyObject]?, headers: [String: String]?) -> NSMutableURLRequest? {
		guard let url = NSURL(string: urls, relativeToURL: baseURL) else { return nil }

		let req = NSMutableURLRequest(URL: url)
		req.HTTPMethod = method.rawValue
		req.timeoutInterval = config.timeoutIntervalForRequest
		headers?.forEach { req.setValue($1, forHTTPHeaderField: $0) }

		if method == .GET || method == .DELETE || method == .HEAD {
			if let uc = NSURLComponents(URL: url, resolvingAgainstBaseURL: false) {
				var q = encodeQuery(params)
				if let oq = uc.percentEncodedQuery { q = oq + "&" }
				if !q.isEmpty {
					uc.percentEncodedQuery = q
					if let uu = uc.URL { req.URL = uu }
				}
			}
		} else {
			if postASJSON {
				if let p = params {
					req.HTTPBody = try? NSJSONSerialization.dataWithJSONObject(p, options: [])
					req.setValue("application/json", forHTTPHeaderField: "Content-Type")
				}
			}
			else {
				if hasMultipartFile(params) {
					let boundary = "Boundary" + NSUUID().UUIDString.stringByReplacingOccurrencesOfString("-", withString: "")
					req.HTTPBody = encodeMultiPart(params, boundary: boundary)
					req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

				} else {
					req.HTTPBody = encodeQuery(params).dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true)
					req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
				}
			}
		}

		// config header is auto merged

		return req
	}

	public func request(method: Method, _ urls: String, params: [String: AnyObject]? = nil, headers: [String: String]? = nil, handler: ResponseHandler) -> Task? {

		guard let req = createRequest(method, urls, params: params, headers: headers) else {
			handler(res: Response(error: NSError(domain: "http", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL making error"])))
			return nil
		}
		return request(req, handler: handler)
	}
}

// for debbug
extension HTTP {

	public static func defaultLogHandler(res: Response) {
		print(res)
	}
}

// MARK: static

public extension HTTP {
	static func createRequest(method: Method, _ urls: String, params: [String: AnyObject]?, headers: [String: String]?) -> NSMutableURLRequest? {
		return sharedInstance.createRequest(method, urls, params: params, headers: headers)
	}

	static func request(request: NSURLRequest, _ handler: ResponseHandler) -> Task? {
		return sharedInstance.request(request, handler: handler)
	}

	static func request(method: Method, _ urls: String, params: [String: AnyObject]? = nil, headers: [String: String]? = nil, _ handler: ResponseHandler) -> Task? {
		return sharedInstance.request(method, urls, params: params, headers: headers, handler: handler)
	}

	static func get(urls: String, params: [String: AnyObject]? = nil, headers: [String: String]? = nil, _ handler: ResponseHandler) -> Task? {
		return sharedInstance.request(.GET, urls, params: params, headers: headers, handler: handler)
	}

	// async
	static func requestASync(request: NSURLRequest) -> Response {
		var r = Response(error: NSError(domain: "http", code: -2, userInfo: nil))
		var done = false

		HTTP.request(request) { r = $0; done = true }
		while done == false { CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, false) }
		return r
	}

	static func requestASync(method: Method, _ urls: String, params: [String: AnyObject]? = nil, headers: [String: String]? = nil) -> Response {
		guard let req = HTTP.createRequest(method, urls, params: params, headers: headers) else {
			return Response(error: NSError(domain: "http", code: -2, userInfo: nil))
		}
		return requestASync(req)
	}

	static func getASync(urls: String, headers: [String: String]? = nil) -> Response {
		return requestASync(.GET, urls, params: nil, headers: headers)
	}

}

// MARK: response
public extension HTTP {
	typealias ResponseHandler = ((res: Response) -> Void)

	struct Response: CustomStringConvertible {

		public let data: NSData?
		public let error: NSError?
		public let response: NSHTTPURLResponse?
		public let request: NSURLRequest?
		public let duration: NSTimeInterval?

		public init(data: NSData?, error: NSError?, response: NSHTTPURLResponse?, request: NSURLRequest?, duration: NSTimeInterval?) {
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
			return String(data: d, encoding: NSUTF8StringEncoding)
		}

		public var jsonObject: NSObject? {
			guard let dat = data else { return nil }
			guard let json = try? NSJSONSerialization.JSONObjectWithData(dat, options: .AllowFragments) else { return nil }
			return json as? NSObject
		}

		public var status: Int { return response?.statusCode ?? 0 }

		public var dataValue: NSData { return data ?? NSData() }
		public var stringValue: String { return string ?? "" }
		public var jsonObjectValue: NSObject { return jsonObject ?? NSObject() }

		public var headers: [String: String] { return response?.allHeaderFields as? [String: String] ?? [:] }

		public var description: String {
			var result = "[Res] "
			result += request?.URL?.absoluteString ?? "unknownURL"
			result += " (\( Int((duration ?? 0) * 1000) )ms)\n"

			if let e = error { result += "Error:" + e.localizedDescription }

			if let d = data {
				if let s = String(data: d, encoding: NSUTF8StringEncoding) {
					if s.characters.count < 24 { result += s }
					else { result += (s as NSString).substringToIndex(24) + "...length: \(s.characters.count)" }
				} else {
					return "data length: \(d.length / 1024) KB"
				}
			} else {
				result += "(no-data)"
			}
			return result
		}
	}

}

