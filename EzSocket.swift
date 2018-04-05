
// Copyright (c) NagisaWorks asaday
// The MIT License (MIT)

import Foundation

protocol EzSocketDelegate: class {
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

		inputStream?.schedule(in: .main, forMode: .defaultRunLoopMode)
		outputStream?.schedule(in: .main, forMode: .defaultRunLoopMode)

		inputStream?.open()
		outputStream?.open()
	}

	func disconnect() {
		inputStream?.remove(from: .main, forMode: .defaultRunLoopMode)
		inputStream?.close()
		inputStream = nil

		outputStream?.remove(from: .main, forMode: .defaultRunLoopMode)
		outputStream?.close()
		outputStream = nil
	}

	internal func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		switch eventCode {
		case .endEncountered:
			delegate?.didDisconnect(error: nil)

		case .errorOccurred:
			delegate?.didDisconnect(error: aStream.streamError)

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

	func read(delimiter: Data) {
		requestLength = 0
		requestDelimiter = delimiter
		DispatchQueue.main.async { self.readOut() }
	}

	func read(length: Int) {
		requestLength = length
		requestDelimiter = nil
		DispatchQueue.main.async { self.readOut() }
	}

	func write(_ data: Data) {
		writeBuf.append(data)
		if let s = outputStream { doWrite(stream: s) }
	}

	private func doRead(stream: InputStream) {
		let size = 4096
		let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
		while stream.hasBytesAvailable {
			let read = stream.read(buf, maxLength: size)
			readBuf.append(buf, count: read)
		}
		buf.deallocate(capacity: size)
		readOut()
	}

	private func readOut() {
		if readBuf.count == 0 { return }
		var len = 0

		if requestLength > 0 {
			if readBuf.count < requestLength { return }
			len = requestLength
			requestLength = 0
		}

		if let d = requestDelimiter, let ra = readBuf.range(of: d) {
			len = ra.upperBound
			requestDelimiter = nil
		}

		if len == 0 { return }
		let r = Data(readBuf.prefix(len))
		readBuf = Data(readBuf.suffix(from: len))
		delegate?.didRead(data: r)
	}

	private func doWrite(stream: OutputStream) {
		if !isWritable { return }
		if writeBuf.count == 0 { return }
		let b = writeBuf
		writeBuf = Data()

		b.withUnsafeBytes { a -> Void in
			stream.write(a, maxLength: b.count)
		}
	}
}