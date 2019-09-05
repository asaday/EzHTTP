
# EzHTTP

[![Build Status](https://travis-ci.org/asaday/EzHTTP.svg?branch=master)](https://travis-ci.org/asaday/EzHTTP) 
[![Version Status](https://img.shields.io/cocoapods/v/EzHTTP.svg?style=flat)](http://cocoadocs.org/docsets/EzHTTP) 
[![Platform](http://img.shields.io/cocoapods/p/EzHTTP.svg?style=flat)](http://cocoapods.org/?q=EzHTTP) 


EzHTTP is easy-to-use library for HTTP access for your iOS application. 

- simplest API
- auto make request (query,form,json)
- useful response (use as string,json,data)
- auto indicator show/hide
- log,stub handler
- escape App-Transport-Security
- short code

## Requirements

- iOS 8.0+
- Xcode 8+

(for swift 2.x , use version 0.0.x)

## Installation

### CocoaPods

To install EzHTTP with CocoaPods, add EzHTTP to the devendencies in your __Podfile__.

	pod 'EzHTTP'

Then, run `pod install` command in your project. 

### Swift Package

You can also install EzHTTP using Swift Package Xcode11 later

	https://github.com/asaday/EzHTTP.git


## Usage

Begin by importing the EzHTTP.

	import EzHTTP

### Request

Simple GET request

	HTTP.get("https://httpbin.org/get") { print($0.string) }

POST with form

	HTTP.request(.POST, "https://httpbin.org/post", params: ["form1": "TEST"]) {}

	// auto appended header "Content-Type: application/x-www-form-urlencoded; charset=utf-8"
	// or if included HTTP.MultipartFile() , header is "multipart/form-data; boundary=..."

POST with JSON

	HTTP.request(.POST, "https://httpbin.org/post", json: ["foo": "bar"]) {}

	// auto appended header "Content-Type: application/json"

POST with custom Headers

	HTTP.request(.POST, "https://httpbin.org/post",headers: ["Custom-Content":"HAHAHA"])

POST with raw data

	// data is String or Data

	HTTP.request(.POST, "https://httpbin.org/post", body: data, headers:["Content-Type": "application/atom+xml"]) {}

Other methods

	HTTP.request(.DELETE, "https://httpbin.org/delete") {}

- OPTIONS, GET, HEAD, POST, PUT, PATCH, DELETE, TRACE, CONNECT

Create a request

	let req:NSMutableURLRequest = HTTP.createRequest(.GET, "https://httpbin.org/get", params: [:], headers: [:])
	HTTP.request(req!){}

sync

	let r = HTTP.getSync("https://httpbin.org/get")
	print(r.string)


### Response body

- data
- error
- response


##### Retrieve as String

- `$0.string` String?
- `$0.stringValue` String

##### JSON

- `$0.jsonObject` NSObject? (json decoded)
- `$0.jsonObjectValue` NSObject (json decoded)


##### Data

- `$0.data` Data?
- `$0.dataValue` Data

##### Error

- `if let error = $0.error {...}`

##### misc

- `status` Int Response status code
- `headers` [String: String] Response headers 
- `duration`
- `request`
- `description`
- `retriedCount`

### Request make

	let req:NSMutableURLRequest = HTTP.create(.GET,"https://httpbin.org/", params: 	["foo":"bar"],headers: ["Custom-Content":"HAHAHA"])

#### params

##### normal

method | in param
---|---
GET| query
POST,PUT | application/x-www-form-urlencoded or application/json
POST with file | multipart/form-data

change to JSON POST `HTTP.shard.postASJSON = true`

to use file, add in params HTTP.MultipartFile, auto changed to multipart/form-data

in json mode, data is auto convered to base64

##### on demand change request params mode

use HTTP.makeParams() or

	params = [HTTP.ParamMode.query.rawValue: ["foo":bar"],
			HTTP.ParamMode.form.rawValue: ["aaa":"bbb"]]


- ParamMode

key|description
---|---
query| in query ?aaa=bbb
form| as application/x-www-form-urlencoded
json| as application/json
multipartForm| as multipart/form-data; boundary=...
path| in path https://example.com/{user}
header| in header


- path example

	URLstring = "https://example.com/{user}"  
	param = [HTTP.ParamMode.path.rawValue: ["user": "123"]]

make URL as

	"https://example.com/123"


### Log,Stub,Retry

	var errorHandler: ((result: Response) -> Void)?
	var successHandler: ((result: Response) -> Void)?
	var logHandler: ((result: Response) -> Void)?
	var stubHandler: ((request: NSURLRequest) -> Response?)?
	var retryHandler: ((_ result: Response) -> Bool)?


to use 

	HTTP.shared.logHandler = { print($0.stringValue) }

or you can use preset handler

	HTTP.shared.logHandler = HTTP.defaultLogHandler
	HTTP.shared.retryHandler = HTTP.defaultRetryHandler

retry hanlder example

	HTTP.shared.retryHandler = { return $0.retriedCount < 3 }


	
kind|desc
---|---
error | called at error
success | called at success
log | every called
stub | call and get response. if response is nil, do as normal http access 
retry | judge retry


### self signed SSL

If you want to use self signed SSL authentication, make the following settings.

set Allow Arbitrary Loads = YES

and

	HTTP.shared.allowSelfSignedSSL = true


### ATS escape

ATS(AppTransportSecurity) is enabled(default) and call as http://, request to server as socket connection (not use NSURLSession,NSURLConnection :-)

	HTTP.shared.escapeATS = true // default is false

	HTTP.get("http://httpbin.org/get") {
		print($0.string)
	}

auto checked NSAllowsArbitraryLoads and NSExceptionAllowsInsecureHTTPLoads/NSExceptionDomains

- protocol HTTP/1.1 
- cookie managed (NSHTTPCookieStorage.sharedHTTPCookieStorage)
- auto redirect
- redirect to HTTPS, auto changed to use NSURLSession
- chunked mode (stream)
