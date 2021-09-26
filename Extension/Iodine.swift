//
// Copyright © 2021 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation

final public class Iodine: NSObject {
    public private(set) var ipv6Support: Bool = true
    public private(set) var nameserverHost: String? = nil
    public private(set) var topDomain: String? = nil
    public private(set) var password: String? = nil
    public private(set) var maxDownstreamFragmentSize: Int = 0
    public private(set) var rawMode: Bool = true
    public private(set) var lazyMode: Bool = true
    public private(set) var selectTimeout: Int = 4
    public private(set) var hostnameMaxLength: Int = 0xFF
    public private(set) var forceDnsType: String? = nil
    public private(set) var forceEncoding: String? = nil
    
    public weak var delegate: IodineDelegate?
    
    private var iodineToNetworkExtensionSocket: Int32 = -1
    private var networkExtensionToIodineSocket: Int32 = -1
    private var dnsSocket: Int32 = -1
    private var topDomainPtr: UnsafeMutablePointer<CChar>?
    private var passwordPtr: UnsafeMutablePointer<CChar>?
    
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    
    private var runQueue: DispatchQueue?
    private var isSetupComplete: Bool = false
    private var isRunning: Bool = false
    private var nameserver = sockaddr_storage()
    
    private var defaultNameserver: sockaddr_storage? {
        var state = __res_9_state()
        var servers = [res_9_sockaddr_union](repeating: res_9_sockaddr_union(), count: Int(NI_MAXSERV))
        res_9_ninit(&state)
        defer {
            res_9_nclose(&state)
        }
        let count = res_9_getservers(&state, &servers, NI_MAXSERV)
        guard count > 0 else {
            return nil
        }
        servers.removeLast(Int(NI_MAXSERV - count))
        var result = sockaddr_storage()
        guard var server = servers.first(where: { server in
            self.ipv6Support || server.sin6.sin6_family != AF_INET6
        }) else {
            return nil
        }
        withUnsafePointer(to: &server) { addr in
            let ptr = UnsafeRawPointer(addr).assumingMemoryBound(to: sockaddr_storage.self)
            result = ptr.pointee
        }
        return result
    }
    
    public var tunDnsServer: String? {
        guard var defaultNameserver = defaultNameserver else {
            return nil
        }
        let dnsHostname = String(cString: format_addr(&defaultNameserver, Int32(defaultNameserver.ss_len)))
        return dnsHostname
    }
    
    public convenience init(options: [String : Any]? = nil) {
        self.init()
        guard let options = options else {
            return
        }
        if let ipv6Support = options[IodineSettings.ipv6Support] as? Bool {
            self.ipv6Support = ipv6Support
        }
        if let nameserverHost = options[IodineSettings.nameserverHost] as? String, nameserverHost.count > 0 {
            self.nameserverHost = nameserverHost
        }
        if let topDomain = options[IodineSettings.topDomain] as? String, topDomain.count > 0 {
            self.topDomain = topDomain
        }
        if let password = options[IodineSettings.password] as? String, password.count > 0 {
            self.password = String(password.prefix(32))
        }
        let maxDownstreamFragmentSize: Int?
        if let maxDownstreamFragmentSizeString = options[IodineSettings.maxDownstreamFragmentSize] as? String, maxDownstreamFragmentSizeString.count > 0 {
            maxDownstreamFragmentSize = Int(maxDownstreamFragmentSizeString)
        } else {
            maxDownstreamFragmentSize = options[IodineSettings.maxDownstreamFragmentSize] as? Int
        }
        if let maxDownstreamFragmentSize = maxDownstreamFragmentSize {
            if maxDownstreamFragmentSize > 0xffff {
                self.maxDownstreamFragmentSize = 0xffff
            } else {
                self.maxDownstreamFragmentSize = maxDownstreamFragmentSize
            }
        }
        if let rawMode = options[IodineSettings.rawMode] as? Bool {
            self.rawMode = rawMode
        }
        if let lazyMode = options[IodineSettings.lazyMode] as? Bool {
            self.lazyMode = lazyMode
            if !lazyMode {
                self.selectTimeout = 1
            }
        }
        let selectTimeout: Int?
        if let selectTimeoutString = options[IodineSettings.selectTimeout] as? String, selectTimeoutString.count > 0 {
            selectTimeout = Int(selectTimeoutString)
        } else {
            selectTimeout = options[IodineSettings.selectTimeout] as? Int
        }
        if let selectTimeout = selectTimeout {
            if selectTimeout < 1 {
                self.selectTimeout = 1
            } else {
                self.selectTimeout = selectTimeout
            }
        }
        let hostnameMaxLength: Int?
        if let hostnameMaxLengthString = options[IodineSettings.hostnameMaxLength] as? String, hostnameMaxLengthString.count > 0 {
            hostnameMaxLength = Int(hostnameMaxLengthString)
        } else {
            hostnameMaxLength = options[IodineSettings.hostnameMaxLength] as? Int
        }
        if let hostnameMaxLength = hostnameMaxLength {
            if hostnameMaxLength > 255 {
                self.hostnameMaxLength = 255
            } else if hostnameMaxLength < 10 {
                self.hostnameMaxLength = 10
            } else {
                self.hostnameMaxLength = hostnameMaxLength
            }
        }
        if let forceDnsType = options[IodineSettings.forceDnsType] as? String, forceDnsType.count > 0 {
            self.forceDnsType = forceDnsType
        }
        if let forceEncoding = options[IodineSettings.forceEncoding] as? String, forceEncoding.count > 0 {
            self.forceEncoding = forceEncoding
        }
    }
    
    private func setup() throws {
        guard !isSetupComplete else {
            throw IodineError.internalError
        }
        
        if let forceDnsType = forceDnsType {
            let forceDnsTypePtr = forceDnsType.unsafeAllocate()!
            client_set_qtype(forceDnsTypePtr)
            forceDnsTypePtr.deallocate()
        }
        
        if let forceEncoding = forceEncoding {
            let forceEncodingPtr = forceEncoding.unsafeAllocate()
            client_set_qtype(forceEncodingPtr)
            forceEncodingPtr?.deallocate()
        }
        
        let family = ipv6Support ? AF_UNSPEC : AF_INET
        if let host = nameserverHost {
            let hostPtr = host.unsafeAllocate()!
            let len = get_addr(hostPtr, DNS_PORT, family, 0, &nameserver)
            hostPtr.deallocate()
            guard len > 0 else {
                throw IodineError.invalidNameserverHost
            }
            client_set_nameserver(&nameserver, len)
        } else {
            guard let defaultNameserver = defaultNameserver else {
                throw IodineError.defaultDnsNotFound
            }
            nameserver = defaultNameserver
            client_set_nameserver(&nameserver, Int32(nameserver.ss_len))
        }
        
        guard let topdomain = topDomain else {
            throw IodineError.invalidTopdomain()
        }
        var errormsg: UnsafeMutablePointer<CChar>? = nil
        if let topDomainPtr = topDomainPtr {
            topDomainPtr.deallocate()
        }
        topDomainPtr = topdomain.unsafeAllocate()
        guard check_topdomain(topDomainPtr, 0, &errormsg) == 0 else {
            throw IodineError.invalidTopdomain(message: errormsg?.string)
        }
        client_set_topdomain(topDomainPtr)
        
        client_set_selecttimeout(Int32(selectTimeout))
        client_set_lazymode(lazyMode ? 1 : 0)
        client_set_hostname_maxlen(Int32(hostnameMaxLength))
        
        if let password = password {
            if let passwordPtr = passwordPtr {
                passwordPtr.deallocate()
            }
            passwordPtr = password.unsafeAllocate(capacity: 33)
            client_set_password(passwordPtr)
        }
        
        runQueue = DispatchQueue(label: "Iodine")
        isSetupComplete = true
    }
    
    public func start() throws {
        guard !isRunning else {
            throw IodineError.internalError
        }
        
        iodine_srand()
        client_init()
        
        if !isSetupComplete {
            try setup()
        }
        
        var fds = [Int32](repeating: -1, count: 2)
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
            throw IodineError.socketCreateFailed
        }
        iodineToNetworkExtensionSocket = fds[0]
        networkExtensionToIodineSocket = fds[1]
        
        print("Connecting to DNS...", to: &StdioRedirect.standardError)
        dnsSocket = open_dns_from_host(nil, 0, Int32(nameserver.ss_family), AI_PASSIVE)
        guard dnsSocket >= 0 else {
            stop()
            throw IodineError.dnsOpenFailed
        }
        
        print("Opening streams...", to: &StdioRedirect.standardError)
        guard openStream() else {
            stop()
            throw IodineError.internalError
        }
        
        let dnsHostname = String(cString: format_addr(&nameserver, Int32(nameserver.ss_len)))
        print("Sending DNS queries for \(topDomain ?? "(null)") to \(dnsHostname)", to: &StdioRedirect.standardError);
        guard client_handshake(dnsSocket, rawMode ? 1 : 0, maxDownstreamFragmentSize > 0 ? 0 : 1, Int32(maxDownstreamFragmentSize)) == 0 else {
            stop()
            throw IodineError.handshakeFailed
        }
        
        if client_get_conn() == CONN_RAW_UDP {
            let rawAddr = client_get_raw_addr()
            print("Sending raw traffic directly to \(rawAddr?.string ?? "(unknown)")", to: &StdioRedirect.standardError)
        }
        
        print("Connection setup complete, transmitting data.", to: &StdioRedirect.standardError)
        
        self.isRunning = true
        runQueue!.async {
            client_tunnel(self.networkExtensionToIodineSocket, self.dnsSocket)
            self.isRunning = false
            self.delegate?.iodineDidStop()
        }
    }
    
    public func stop() {
        closeStream()
        if iodineToNetworkExtensionSocket >= 0 {
            close(iodineToNetworkExtensionSocket)
            iodineToNetworkExtensionSocket = -1
        }
        if networkExtensionToIodineSocket >= 0 {
            close(networkExtensionToIodineSocket)
            networkExtensionToIodineSocket = -1
        }
        if dnsSocket >= 0 {
            close_dns(dnsSocket)
            dnsSocket = -1
        }
        client_stop()
        runQueue!.sync {
            print("Service has stopped.", to: &StdioRedirect.standardError)
        }
    }
}

extension Iodine: StreamDelegate {
    fileprivate func openStream() -> Bool {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocket(kCFAllocatorDefault,
                                     iodineToNetworkExtensionSocket,
                                     &readStream,
                                     &writeStream)
        
        inputStream = readStream?.takeRetainedValue()
        if inputStream == nil {
            return false
        }
        outputStream = writeStream?.takeRetainedValue()
        if outputStream == nil {
            inputStream = nil
            return false
        }
        inputStream!.delegate = self
        inputStream!.schedule(in: .main, forMode: .common)
        outputStream!.schedule(in: .main, forMode: .common)
        inputStream!.open()
        outputStream!.open()
        return true
    }
    
    fileprivate func closeStream() {
        if inputStream != nil {
            inputStream!.remove(from: .current, forMode: .common)
            inputStream!.close()
            inputStream = nil
        }
        if outputStream != nil {
            outputStream!.remove(from: .current, forMode: .common)
            outputStream!.close()
            outputStream = nil
        }
    }
    
    public func stream(_ stream: Stream, handle: Stream.Event) {
        switch handle {
        case .hasBytesAvailable:
            do {
                let (data, protocols) = try readDataFrom(stream: stream as! InputStream)
                delegate?.iodineReadData(data, withProtocols: protocols)
            } catch {
                delegate?.iodineError(error)
            }
        case .errorOccurred:
            delegate?.iodineError(stream.streamError)
        default:
            break
        }
    }
    
    private func readPacketFrom(stream: InputStream, headerLength: Int, lengthOffset: Int, lengthIncludesHeader: Bool) throws -> Data {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: headerLength)
        defer {
            buffer.deallocate()
        }
        guard stream.read(buffer, maxLength: headerLength) == headerLength else {
            throw IodineError.incompletePacket
        }
        let raw = UnsafeRawPointer(buffer.advanced(by: lengthOffset)).load(as: UInt16.self)
        let lengthField = NSSwapBigShortToHost(raw)
        let payloadLength: Int
        if lengthIncludesHeader {
            payloadLength = Int(lengthField) - headerLength
        } else {
            payloadLength = Int(lengthField)
        }
        guard payloadLength >= 0 else {
            throw IodineError.invalidPacket
        }
        var data = Data(bytes: buffer, count: headerLength)
        let remaining = UnsafeMutablePointer<UInt8>.allocate(capacity: payloadLength)
        defer {
            remaining.deallocate()
        }
        guard stream.read(remaining, maxLength: payloadLength) == payloadLength else {
            throw IodineError.incompletePacket
        }
        data.append(Data(bytes: remaining, count: payloadLength))
        return data
    }
    
    private func readDataFrom(stream: InputStream) throws -> ([Data], [NSNumber]) {
        var packets = [Data]()
        var protocols = [NSNumber]()
        while stream.hasBytesAvailable {
            let headerBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
            defer {
                headerBuf.deallocate()
            }
            guard stream.read(headerBuf, maxLength: 4) == 4 else {
                throw IodineError.incompletePacket
            }
            let raw = UnsafeRawPointer(headerBuf).load(as: UInt32.self)
            let family = Int32(NSSwapBigIntToHost(raw))
            if family == AF_INET || family == 0x0800 {
                packets.append(try readPacketFrom(stream: stream, headerLength: 20, lengthOffset: 2, lengthIncludesHeader: true))
                protocols.append(NSNumber(value: AF_INET))
            } else if family == AF_INET6 || family == 0x86DD {
                packets.append(try readPacketFrom(stream: stream, headerLength: 40, lengthOffset: 4, lengthIncludesHeader: false))
                protocols.append(NSNumber(value: AF_INET6))
            } else {
                throw IodineError.unrecognizedFamily(family)
            }
        }
        return (packets, protocols)
    }
    
    public func writeData(_ data: Data, family: Int32) {
        guard isRunning, let outputStream = outputStream else {
            delegate?.iodineError(IodineError.notConnected)
            return
        }
        var familyNtohl = family.bigEndian
        var packet = withUnsafeBytes(of: &familyNtohl) { bytes in
            Data(bytes: bytes.baseAddress!, count: bytes.count)
        }
        packet.append(data)
        packet.withUnsafeBytes { bytes in
            _ = outputStream.write(bytes.bindMemory(to: UInt8.self).baseAddress!, maxLength: packet.count)
        }
    }
}

public enum IodineError: LocalizedError {
    case internalError
    case invalidNameserverHost
    case defaultDnsNotFound
    case invalidTopdomain(message: String? = nil)
    case socketCreateFailed
    case dnsOpenFailed
    case handshakeFailed
    case notConnected
    case invalidPacket
    case incompletePacket
    case unrecognizedFamily(_ family: Int32)
    
    public var errorDescription: String? {
        switch self {
        case .internalError:
            return NSLocalizedString("An internal error has occurred.", comment: "Iodine")
        case .invalidNameserverHost:
            return NSLocalizedString("Invalid nameserver host.", comment: "Iodine")
        case .defaultDnsNotFound:
            return NSLocalizedString("Cannot get default DNS address.", comment: "Iodine")
        case .invalidTopdomain(let message):
            return NSLocalizedString("Invalid top domain: \(message ?? "unknown cause")", comment: "Iodine")
        case .socketCreateFailed:
            return NSLocalizedString("Failed to create socketpair for communication.", comment: "Iodine")
        case .dnsOpenFailed:
            return NSLocalizedString("Failed to open connection to DNS server.", comment: "Iodine")
        case .handshakeFailed:
            return NSLocalizedString("Failed to establish handshake with server.", comment: "Iodine")
        case .notConnected:
            return NSLocalizedString("Not connected.", comment: "Iodine")
        case .invalidPacket:
            return NSLocalizedString("Invalid packet.", comment: "Iodine")
        case .incompletePacket:
            return NSLocalizedString("Incomplete packet.", comment: "Iodine")
        case .unrecognizedFamily(let family):
            return NSLocalizedString("Unrecognized family \(family).", comment: "Iodine")
        }
    }
}

fileprivate extension String {
    func unsafeAllocate(capacity: Int = 0) -> UnsafeMutablePointer<CChar>? {
        let utf8 = self.utf8CString
        let result = UnsafeMutableBufferPointer<CChar>.allocate(capacity: capacity > 0 ? capacity : utf8.count)
        let (_, lastIndex) = result.initialize(from: utf8)
        let remaining = UnsafeMutableBufferPointer<CChar>(rebasing: result.suffix(from: lastIndex))
        remaining.initialize(repeating: 0)
        return result.baseAddress
    }
}

fileprivate extension UnsafePointer where Pointee == CChar {
    var string: String {
        String(cString: self)
    }
}

fileprivate extension UnsafeMutablePointer where Pointee == CChar {
    var string: String {
        String(cString: self)
    }
}
