
# EzHTTP

Easy to HTTP access.

```
HTTP.get("https://httpbin.org/get") { print($0.string) }
```

## Requirements

- iOS 8.0+
- Xcode 7+

## Integration

### Cocoapods

you can use Cocoapods install EzHTTP by adding it to your Podfile

```
use_frameworks!
...
pod 'EzHTTP'
...
```

### Carthage

you can use Carthage install EzHTTP by adding it to your Cartfile

```
github "asaday/EzHTTP"
```

## Usage


example

```
import EzHTTP

HTTP.get("https://httpbin.org/get") {
	print($0.string)
}
```



