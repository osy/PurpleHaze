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
    
    public weak var delegate: IodineDelegate?
    
    private var iodineToNetworkExtensionSocket: Int32 = -1
    private var networkExtensionToIodineSocket: Int32 = -1
    private var dnsSocket: Int32 = -1
    
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
    
    public convenience init(options: [String : NSObject]? = nil) {
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
            self.password = password
        }
        if let maxDownstreamFragmentSize = options[IodineSettings.maxDownstreamFragmentSize] as? Int {
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
        if let selectTimeout = options[IodineSettings.selectTimeout] as? Int {
            if selectTimeout < 1 {
                self.selectTimeout = 1
            } else {
                self.selectTimeout = selectTimeout
            }
        }
        if let hostnameMaxLength = options[IodineSettings.hostnameMaxLength] as? Int {
            if hostnameMaxLength > 255 {
                self.hostnameMaxLength = 255
            } else if hostnameMaxLength < 10 {
                self.hostnameMaxLength = 10
            } else {
                self.hostnameMaxLength = hostnameMaxLength
            }
        }
    }
    
    private func setup() throws {
        guard !isSetupComplete else {
            throw IodineError.internalError
        }
        
        let family = ipv6Support ? AF_UNSPEC : AF_INET
        if let host = nameserverHost {
            let len = get_addr(host.unsafePointer, DNS_PORT, family, 0, &nameserver)
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
        guard check_topdomain(topdomain.unsafePointer, 0, &errormsg) == 0 else {
            throw IodineError.invalidTopdomain(message: errormsg?.string)
        }
        client_set_topdomain(topdomain)
        
        client_set_selecttimeout(Int32(selectTimeout))
        client_set_lazymode(lazyMode ? 1 : 0)
        client_set_hostname_maxlen(Int32(hostnameMaxLength))
        
        if let password = password {
            client_set_password(password)
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
        
        var cstr = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        inet_ntop(Int32(nameserver.ss_family), &nameserver, &cstr, socklen_t(INET6_ADDRSTRLEN))
        let dnsHostname = String(cString: cstr)
        print("Connecting to DNS: \(dnsHostname)")
        dnsSocket = open_dns_from_host(nil, 0, Int32(nameserver.ss_family), AI_PASSIVE)
        guard dnsSocket >= 0 else {
            stop()
            throw IodineError.dnsOpenFailed(host: dnsHostname)
        }
        
        print("Opening streams...")
        guard openStream() else {
            stop()
            throw IodineError.internalError
        }
        
        print("Sending handshake...")
        guard client_handshake(dnsSocket, rawMode ? 1 : 0, maxDownstreamFragmentSize > 0 ? 0 : 1, Int32(maxDownstreamFragmentSize)) == 0 else {
            stop()
            throw IodineError.handshakeFailed
        }
        
        if client_get_conn() == CONN_RAW_UDP {
            let rawAddr = client_get_raw_addr()
            print("Sending raw traffic directly to \(rawAddr?.string ?? "(unknown)")")
        }
        
        print("Connection setup complete, transmitting data.\n")
        
        self.isRunning = true
        runQueue!.async {
            client_tunnel(self.networkExtensionToIodineSocket, self.dnsSocket)
            self.isRunning = false
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
            print("Service has stopped.")
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
        inputStream!.open()
        outputStream!.open()
        return true
    }
    
    fileprivate func closeStream() {
        if inputStream != nil {
            inputStream!.close()
            inputStream = nil
        }
        if outputStream != nil {
            outputStream!.close()
            outputStream = nil
        }
    }
    
    public func stream(_ stream: Stream, handle: Stream.Event) {
        switch handle {
        case .hasBytesAvailable:
            do {
                try delegate?.iodineReadData(Data(reading: stream as! InputStream))
            } catch {
                delegate?.iodineError(error)
            }
        case .errorOccurred:
            delegate?.iodineError(stream.streamError)
        default:
            break
        }
    }
    
    public func writeData(_ data: Data) {
        guard isRunning, let outputStream = outputStream else {
            delegate?.iodineError(IodineError.notConnected)
            return
        }
        data.withUnsafeBytes { bytes in
            _ = outputStream.write(bytes.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count)
        }
    }
}

public enum IodineError: LocalizedError {
    case internalError
    case invalidNameserverHost
    case defaultDnsNotFound
    case invalidTopdomain(message: String? = nil)
    case socketCreateFailed
    case dnsOpenFailed(host: String)
    case handshakeFailed
    case notConnected
    
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
        case .dnsOpenFailed(let host):
            return NSLocalizedString("Failed to open connection to DNS server: \(host)", comment: "Iodine")
        case .handshakeFailed:
            return NSLocalizedString("Failed to establish handshake with server.", comment: "Iodine")
        case .notConnected:
            return NSLocalizedString("Not connected.", comment: "Iodine")
        }
    }
}

fileprivate extension String {
    var unsafePointer: UnsafeMutablePointer<CChar> {
        let utf8 = self.utf8CString
        let result = UnsafeMutableBufferPointer<CChar>.allocate(capacity: utf8.count)
        _ = result.initialize(from: utf8)
        return result.baseAddress!
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

// https://stackoverflow.com/a/42561021
fileprivate extension Data {
    init(reading input: InputStream) throws {
        self.init()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }
        while input.hasBytesAvailable {
            let read = input.read(buffer, maxLength: bufferSize)
            if read < 0 {
                //Stream error occured
                throw input.streamError!
            } else if read == 0 {
                //EOF
                break
            }
            self.append(buffer, count: read)
        }
    }
}
