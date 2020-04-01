//
//  ObjDecoder.swift
//  EzHTTP
//

import Foundation

public typealias ObjectDecoderConverter = ((_ path: [CodingKey], _ container: [String: Any]) -> Any?)

public class ObjectDecoder: Decoder {
	var converter: ObjectDecoderConverter?
	var useThrow = false

	public var codingPath: [CodingKey] = []
	public var userInfo: [CodingUserInfoKey: Any] = [:]
	var container: Any = NSNull()

	public init(converter: ObjectDecoderConverter? = nil) {
		self.converter = converter
	}

	func throwDecodingError(_ e: DecodingError) throws {
		if useThrow { throw e }
	}

	public func decode<T: Decodable>(_ type: T.Type, from value: Any) throws -> T {
		var src = value
		if let s = src as? String { src = s.data(using: .utf8) ?? Data() }
		if let d = src as? Data { src = try JSONSerialization.jsonObject(with: d, options: []) }
		if let a = src as? AnyCodable { src = a.value }

		container = src
		return try decodeValue(container, type: type)
	}

	public func optionalDecode<T: Decodable>(_ type: T.Type, from value: Any?) -> T? {
		guard let v = value else { return nil }
		do { return try decode(type, from: v) }
		catch { return nil }
	}

	public func forceDecode<T: Decodable>(_ type: T.Type, from value: Any?) -> T {
		if let v = optionalDecode(type, from: value) { return v }
		return try! decodeValue(NSNull(), type: type)
	}

	public func forceInitialize<T: Decodable>(_ type: T.Type) -> T {
		return try! decodeValue(NSNull(), type: type)
	}

	public func singleValueContainer() throws -> SingleValueDecodingContainer {
		return self
	}

	public func unkeyedContainer() throws -> UnkeyedDecodingContainer {
		guard let v = container as? [Any] else {
			try throwDecodingError(DecodingError.valueNotFound([Any].self, DecodingError.Context(codingPath: codingPath, debugDescription: "not array")))
			return UnkeyDC(decoder: self, container: [])
		}
		return UnkeyDC(decoder: self, container: v)
	}

	public func container<Key>(keyedBy _: Key.Type) throws -> KeyedDecodingContainer<Key> {
		guard let v = container as? [String: Any] else {
			try throwDecodingError(DecodingError.typeMismatch([String: Any].self, DecodingError.Context(codingPath: codingPath, debugDescription: "no key")))
			return KeyedDecodingContainer(KeyDCP<Key>(decoder: self, container: [:]))
		}
		return KeyedDecodingContainer(KeyDCP<Key>(decoder: self, container: v))
	}

	func copy(with value: Any) -> ObjectDecoder {
		let d = ObjectDecoder()
		d.container = value
		d.codingPath = codingPath
		d.userInfo = userInfo
		d.useThrow = useThrow
		d.converter = converter
		return d
	}

	func decodeValue<T>(_ value: Any, type: T.Type) throws -> T where T: Decodable {
		return try (unbox(value: value, type: type) as? T) ?? type.init(from: copy(with: value))
	}

	// for array
	struct UnkeyDC: UnkeyedDecodingContainer {
		let decoder: ObjectDecoder
		var codingPath: [CodingKey] { return decoder.codingPath }
		var count: Int? { return container.count }
		var isAtEnd: Bool { return currentIndex >= container.count }
		var currentIndex: Int = 0
		let container: [Any]

		init(decoder: ObjectDecoder, container: [Any]) {
			self.decoder = decoder
			self.container = container
		}

		mutating func popValue() throws -> Any {
			if isAtEnd {
				try decoder.throwDecodingError(DecodingError.valueNotFound(Any.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unkeyed at end")))
			}
			let value = container[currentIndex]
			currentIndex += 1
			return value
		}

		mutating func decodeNil() throws -> Bool {
			decoder.codingPath.append(CodingKeys(intValue: currentIndex)!)
			defer { decoder.codingPath.removeLast() }
			if try popValue() is NSNull { return true }
			currentIndex -= 1
			return false
		}

		mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
			decoder.codingPath.append(CodingKeys(intValue: currentIndex)!)
			defer { decoder.codingPath.removeLast() }
			return try decoder.decodeValue(popValue(), type: type)
		}

		mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
			return try superDecoder().container(keyedBy: type)
		}

		mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
			return try superDecoder().unkeyedContainer()
		}

		mutating func superDecoder() throws -> Decoder {
			return try decoder.copy(with: popValue())
		}
	}

	// for dictionary
	struct KeyDCP<Key: CodingKey>: KeyedDecodingContainerProtocol {
		let decoder: ObjectDecoder
		var codingPath: [CodingKey] { return decoder.codingPath }
		var allKeys: [Key] { return container.keys.compactMap { Key(stringValue: $0) } }
		let container: [String: Any]

		init(decoder: ObjectDecoder, container: [String: Any]) {
			self.decoder = decoder
			self.container = container
		}

		func getValue(key: Key) throws -> Any {
			var ov: Any?
			if let c = decoder.converter?(codingPath, container) { ov = c }
			else { ov = container[key.stringValue] }
			guard let v = ov else {
				try decoder.throwDecodingError(DecodingError.keyNotFound(key, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No value associated with key")))
				return NSNull() // dont throw no key
			}
			return v
		}

		func contains(_ key: Key) -> Bool {
			return container.keys.contains(key.stringValue)
		}

		func decodeNil(forKey key: Key) throws -> Bool {
			decoder.codingPath.append(key)
			defer { decoder.codingPath.removeLast() }
			return try getValue(key: key) is NSNull
		}

		func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
			decoder.codingPath.append(key)
			defer { decoder.codingPath.removeLast() }
			return try decoder.decodeValue(getValue(key: key), type: type)
		}

		func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
			return try superDecoder(forKey: key).container(keyedBy: type)
		}

		func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
			return try superDecoder(forKey: key).unkeyedContainer()
		}

		func superDecoder() throws -> Decoder {
			return try superDecoder(forKey: Key(stringValue: "super")!)
		}

		func superDecoder(forKey key: Key) throws -> Decoder {
			return try decoder.copy(with: getValue(key: key))
		}
	}
}

// for single value
extension ObjectDecoder: SingleValueDecodingContainer {
	public func decodeNil() -> Bool { return container is NSNull }
	public func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
		return try decodeValue(container, type: type)
	}
}

extension ObjectDecoder {
	func decodeNumber(_ value: Any) throws -> NSNumber {
		if let v = value as? NSNumber { return v }
		if let v = value as? Int { return NSNumber(value: v) }
		if let s = value as? String {
			if s.lowercased() == "true" { return NSNumber(value: true) }
			if s.lowercased() == "false" { return NSNumber(value: false) }
			if let v = Int(s) { return NSNumber(value: v) }
		}
		try throwDecodingError(DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: codingPath, debugDescription: "decode number")))

		return 0 // default
	}

	func decodeString(_ value: Any) throws -> String {
		if let v = value as? String { return v }
		if let v = value as? NSNumber { return v.stringValue }
		try throwDecodingError(DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: codingPath, debugDescription: "decode number")))
		return "" // default
	}

	func dateFormat(_ s: String) -> Date? {
        if #available(iOS 10.0, tvOS 10.0, macOS 10.12, *) {
			let formatter = ISO8601DateFormatter()
			formatter.formatOptions = .withInternetDateTime
			return formatter.date(from: s)
		} else {
			let formatter = DateFormatter()
			formatter.locale = Locale(identifier: "en_US_POSIX")
			formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
			formatter.timeZone = TimeZone(secondsFromGMT: 0)
			return formatter.date(from: s)
		}
	}

	func unbox<T>(value: Any, type: T.Type) throws -> Any? {
		switch type {
		case is Int.Type: return try decodeNumber(value).intValue
		case is Float.Type: return try decodeNumber(value).floatValue
		case is Double.Type: return try decodeNumber(value).doubleValue
		case is Bool.Type: return try decodeNumber(value).boolValue
		case is Int8.Type: return try decodeNumber(value).int8Value
		case is Int16.Type: return try decodeNumber(value).int16Value
		case is Int32.Type: return try decodeNumber(value).int32Value
		case is Int64.Type: return try decodeNumber(value).int64Value
		case is UInt.Type: return try decodeNumber(value).uintValue
		case is UInt8.Type: return try decodeNumber(value).uint8Value
		case is UInt16.Type: return try decodeNumber(value).uint16Value
		case is UInt32.Type: return try decodeNumber(value).uint32Value
		case is UInt64.Type: return try decodeNumber(value).uint64Value
		case is String.Type: return try decodeString(value)
		case is URL.Type:
			return try (URL(string: decodeString(value)) ?? URL(fileURLWithPath: "none"))
		case is Data.Type:
			if let d = value as? Data { return d }
			if let s = value as? String { return Data(base64Encoded: s) }
		case is Date.Type:
			if let d = value as? Date { return d }
			if let s = value as? String, let d = dateFormat(s) { return d }
			if let n = value as? Int { return Date(timeIntervalSince1970: TimeInterval(n)) }

		default: break
		}

		if !useThrow {
			if type is AnyCodable.Type { return AnyCodable(value) }
		}

		if let v = value as? T { return v }
		return nil
	}
}

extension Decoder {
	public func tes<T: RawRepresentable>(_ def: T) throws -> T where T.RawValue == String {
		return try T(rawValue: singleValueContainer().decode(String.self)) ?? def
	}

	public func es<T: RawRepresentable>(_ def: T) -> T where T.RawValue == String {
		return (try? tes(def)) ?? def
	}
}

struct CodingKeys: CodingKey {
	var stringValue: String
	var intValue: Int?
	init?(intValue: Int) { stringValue = "\(intValue)"; self.intValue = intValue }
	init?(stringValue: String) { self.stringValue = stringValue }
}

public struct AnyCodable: Codable {
	var value: Any
	public init(_ value: Any) { self.value = value }

	public init(from decoder: Decoder) throws {
		if let container = try? decoder.container(keyedBy: CodingKeys.self) {
			var result: [String: Any] = [:]
			try container.allKeys.forEach { (key) throws in
				result[key.stringValue] = try container.decode(AnyCodable.self, forKey: key).value
			}
			value = result
			return
		}
		if var container = try? decoder.unkeyedContainer() {
			var result: [Any] = []
			while !container.isAtEnd { result.append(try container.decode(AnyCodable.self).value) }
			value = result
			return
		}
		if let container = try? decoder.singleValueContainer() {
			if let v = try? container.decode(Int.self) { value = v; return }
			if let v = try? container.decode(Double.self) { value = v; return }
			if let v = try? container.decode(Bool.self) { value = v; return }
			if let v = try? container.decode(String.self) { value = v; return }
			if let v = try? container.decode([AnyCodable].self) { value = v; return }
			if let v = try? container.decode([String: AnyCodable].self) { value = v; return }
		}
		throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "can not decode"))
	}

	public func encode(to encoder: Encoder) throws {
		if let array = value as? [Any] {
			var container = encoder.unkeyedContainer()
			for value in array {
				let decodable = AnyCodable(value)
				try container.encode(decodable)
			}
			return
		}
		if let dictionary = value as? [String: Any] {
			var container = encoder.container(keyedBy: CodingKeys.self)
			for (key, value) in dictionary {
				let codingKey = CodingKeys(stringValue: key)!
				let decodable = AnyCodable(value)
				try container.encode(decodable, forKey: codingKey)
			}
			return
		}

		var container = encoder.singleValueContainer()
		if let intVal = value as? Int { try container.encode(intVal); return }
		if let doubleVal = value as? Double { try container.encode(doubleVal); return }
		if let boolVal = value as? Bool { try container.encode(boolVal); return }
		if let stringVal = value as? String { try container.encode(stringVal); return }
		throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "can not encode"))
	}
}

extension Decoder {
	func sv() throws -> String {
		return try singleValueContainer().decode(String.self)
	}
}

public class ObjectEncoder: JSONEncoder {
	public override init() {
		super.init()
		dateEncodingStrategy = .custom { d, encoder in
			var container = encoder.singleValueContainer()
			try container.encode(Int(d.timeIntervalSince1970))
		}
	}
}
