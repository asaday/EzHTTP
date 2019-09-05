
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)

import Foundation

protocol EzSocketDelegate: AnyObject {
	func didConnect()
	func didDisconnect(error: Error?)
	func didRead(data: Data)
}

class EzSocket: NSObject, StreamDelegate {
	weak var delegate: EzSocketDelegate?
	private var inputStream: InputStream?
	private var outputStream: OutputStream?

	private var writeBuf = Data()
	private var readBuf = Data()
	private var requestLength = 0
	private var requestDelimiter: Data?
	private var isWritable = false

	deinit {
		disconnect()
	}

	func connect(toHost: String, onPort: Int) {
		isWritable = false

		Stream.getStreamsToHost(withName: toHost, port: onPort, inputStream: &inputStream, outputStream: &outputStream)

		if inputStream == nil || outputStream == nil {
			delegate?.didDisconnect(error: NSError(domain: "ezsocket", code: -1, userInfo: nil) as Error)
			return
		}

		inputStream?.delegate = self
		outputStream?.delegate = self

		inputStream?.schedule(in: .current, forMode: .default)
		outputStream?.schedule(in: .current, forMode: .default)

		inputStream?.open()
		outputStream?.open()
		CFRunLoopRun()
	}

	func disconnect() {
		CFRunLoopStop(CFRunLoopGetCurrent())
		inputStream?.remove(from: .current, forMode: .default)
		outputStream?.remove(from: .current, forMode: .default)
		inputStream?.close()
		outputStream?.close()
		inputStream = nil
		outputStream = nil
	}

	func read(delimiter: Data) {
		requestLength = 0
		requestDelimiter = delimiter
		readOut()
	}

	func read(length: Int) {
		requestLength = length
		requestDelimiter = nil
		readOut()
	}

	func write(_ data: Data) {
		writeBuf.append(data)
		if let s = outputStream { doWrite(stream: s) }
	}

	internal func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		switch eventCode {
		case .endEncountered:
			delegate?.didDisconnect(error: nil)
			disconnect()

		case .errorOccurred:
			delegate?.didDisconnect(error: aStream.streamError)
			disconnect()

		case .openCompleted:
			if aStream == outputStream {
				delegate?.didConnect()
			}

		case .hasBytesAvailable:
			if aStream == inputStream, let s = inputStream {
				doRead(stream: s)
			}

		case .hasSpaceAvailable:
			if aStream == outputStream, let s = outputStream {
				isWritable = true
				doWrite(stream: s)
			}

		default: break
		}
	}

	private func doRead(stream: InputStream) {
		let size = 4096
		let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
		while stream.hasBytesAvailable {
			let read = stream.read(buf, maxLength: size)
			readBuf.append(buf, count: read)
		}
		buf.deallocate()
		readOut()
	}

	private func readOut() {
		if readBuf.count == 0 { return }
		var len = 0

		if requestLength > 0 {
			if readBuf.count < requestLength { return }
			len = requestLength
		}

		if let d = requestDelimiter {
			guard let ra = readBuf.range(of: d) else { return }
			len = ra.upperBound
		}

		if len == 0 { return }
		let r = Data(readBuf.prefix(len))
		readBuf = Data(readBuf.suffix(from: len))
		requestLength = 0
		requestDelimiter = nil
		delegate?.didRead(data: r)
	}

	private func doWrite(stream: OutputStream) {
		if !isWritable || writeBuf.count == 0 { return }
		let a = [UInt8](writeBuf)
		writeBuf = Data()

		stream.write(a, maxLength: a.count)
	}
}
