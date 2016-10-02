
# EzHTTP

EzHTTP is easy-to-use library for HTTP access for your iOS application. 


## Requirements

- iOS 8.0+
- Xcode 8+ (for swift3)

(for swift 2.x , use version 0.0.x)

## Installation

### CocoaPods

To install EzHTTP with CocoaPods, add EzHTTP to the devendencies in your __Podfile__.

```
pod 'EzHTTP'
```

Then, run `pod install` command in your project. 

### Carthage

You can also install EzHTTP using Carthage. Add EzHTTP in your __Cartfile__. 

```
github "asaday/EzHTTP"
```

Then, run `carthage update` command in your project.

## Usage

Begin by importing the EzHTTP.

```
import EzHTTP
```

### Request

Simple GET request

```
HTTP.get("https://httpbin.org/get") {
	print($0.string)
}
```

Async

```
let r = HTTP.getAsync("https://httpbin.org/get")
print(r.string)
```

POST 

```
HTTP.request(.POST, "https://httpbin.org/post", params: ["form1": "TEST"]) {}
```

POST with custom Headers

```
HTTP.request(.POST, "https://httpbin.org/post",headers: ["Custom-Content":"HAHAHA"])
``` 

POST with JSON

```
HTTP.sharedInstance.postASJSON = true
HTTP.request(.POST, "https://httpbin.org/post", params: ["foo": "bar"]) {}
```

Other methods

```
HTTP.request(.DELETE, "https://httpbin.org/delete") {}
```

Create a request

```
let req = HTTP.createRequest(.GET, "https://httpbin.org/get", params: [:], headers: [:])
let r = HTTP.requestAsync(req!)
```

### Response body

Retrieve as String

- `$0.string` String?
- `$0.stringValue` String

JSON

- `$0.jsonObject` NSObject?
- `$0.jsonObjectValue` NSObject

NSData

- `$0.dataValue` NSData?

### Response status code

- `$0.status` Int

### Response headers

- `$0.headers` [String: String] 
