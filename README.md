
# EzHTTP

EzHTTP is easy-to-use library for HTTP access for your iOS application. 

- simplest API
- auto make request (query,form,json)
- useful response (use as string,json,data)
- auto indicator show/hide
- log,stub handler
- esacape AppTransportSecurity
- short code

## Requirements

- iOS 8.0+
- Xcode 8+ (for swift3)

(for swift 2.x , use version 0.0.x)

## Installation

### CocoaPods

To install EzHTTP with CocoaPods, add EzHTTP to the devendencies in your __Podfile__.

	pod 'EzHTTP'

Then, run `pod install` command in your project. 

### Carthage

You can also install EzHTTP using Carthage. Add EzHTTP in your __Cartfile__. 

	github "asaday/EzHTTP"

Then, run `carthage update` command in your project.

## Usage

Begin by importing the EzHTTP.

	import EzHTTP

### Request

Simple GET request

	HTTP.get("https://httpbin.org/get") { print($0.string) }

Async

	let r = HTTP.getAsync("https://httpbin.org/get")
	print(r.string)

POST 

	HTTP.request(.POST, "https://httpbin.org/post", params: ["form1": "TEST"]) {}

POST with custom Headers

	HTTP.request(.POST, "https://httpbin.org/post",headers: ["Custom-Content":"HAHAHA"])

POST with JSON

	HTTP.sharedInstance.postASJSON = true // default is false

	HTTP.request(.POST, "https://httpbin.org/post", params: ["foo": "bar"]) {}

Other methods

	HTTP.request(.DELETE, "https://httpbin.org/delete") {}

- OPTIONS, GET, HEAD, POST, PUT, PATCH, DELETE, TRACE, CONNECT

Create a request

	let req:NSMutableURLRequest = HTTP.createRequest(.GET, "https://httpbin.org/get", params: [:], headers: [:])
	HTTP.request(req!){}


### Response body

- data
- error
- response


##### Retrieve as String

- `$0.string` String?
- `$0.stringValue` String

##### JSON

- `$0.jsonObject` NSObject?
- `$0.jsonObjectValue` NSObject


##### Data

- `$0.data` NSData
- `$0.dataValue` NSData?

##### Error

- `if let error = $0.error {...}`

##### misc

- `status` Int Response status code
- `headers` [String: String] Response headers 
- `duration`
- `request`
- `description`

### Request make

	let req:NSMutableURLRequest = HTTP.create(.GET,"https://httpbin.org/", params: 	["foo":"bar"],headers: ["Custom-Content":"HAHAHA"])

#### params

- normal

method | in param
---|---
GET| query
POST,PUT | application/x-www-form-urlencoded or application/json
POST with file | multipart/form-data

to JSON `HTTP.shard.postASJSON = true`

to use file, add in params HTTP.MultipartFile, auto changed to multipart/form-data

in json mode, data is auto convered to base64

- on demand change request params mode

use HTTP.makeParams() or

	params = [ParamMode.Query.rawValue: ["foo":bar"],
			ParamMode.Form.rawValue: ["aaa":"bbb"]]


### Log,Stub

	typealias ResponseHandler = ((result: Response) -> Void)
	public var errorHandler: ResponseHandler?
	public var successHandler: ResponseHandler?
	public var logHandler: ResponseHandler?
	public var stubHandler: ((request: NSURLRequest) -> Response?)?

to use 

	HTTP.shared.logHander = {}
	
kind|desc
---|---
error | called at error
success | called at success
log | every called
stub | call and get response. if response is nil, do as normal 


### ATS escape

ATS(AppTransportSecurity) is enabled(default) and call as http://, request to server as socket connection (not use NSURLSession,NSURLConnection :-)

	HTTP.shared.escapeATS = true // default is false

	HTTP.get("http://httpbin.org/get") {
		print($0.string)
	}

auto checked NSAllowsArbitraryLoads and NSExceptionAllowsInsecureHTTPLoads/NSExceptionDomains

- protcol HTTP/1.1 
- cookie managed (NSHTTPCookieStorage.sharedHTTPCookieStorage)
- auto redirect
- redirect to HTTPS, auto changed to use NSURLSession
- chunked mode (stream)
