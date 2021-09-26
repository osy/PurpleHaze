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

import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var iodine: Iodine?

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        var mtu: Int?
        var clientIp: String?
        var serverIp: String?
        var subnetMask: String?
        do {
            try StdioRedirect.shared.start()
        } catch {
            completionHandler(error)
            return
        }
        let savedOptions: [String: Any]?
        if let options = options {
            UserDefaults.standard.set(options, forKey: IodineSettings.lastSavedSettings)
            savedOptions = options
        } else {
            savedOptions = UserDefaults.standard.dictionary(forKey: IodineSettings.lastSavedSettings)
        }
        iodine = Iodine(options: savedOptions)
        iodine!.delegate = self
        NotificationCenter.default.addObserver(forName: IodineSetMTUNotification as NSNotification.Name, object: nil, queue: nil) { notification in
            mtu = notification.userInfo![kIodineMTU] as? Int
        }
        NotificationCenter.default.addObserver(forName: IodineSetIPNotification as NSNotification.Name, object: nil, queue: nil) { notification in
            clientIp = notification.userInfo![kIodineClientIP] as? String
            serverIp = notification.userInfo![kIodineServerIP] as? String
            subnetMask = notification.userInfo![kIodineSubnetMask] as? String
        }
        do {
            try iodine!.start()
            guard clientIp != nil && serverIp != nil && subnetMask != nil else {
                throw IodineError.internalError
            }
        } catch {
            print("ERROR starting iodine: \(error.localizedDescription)", to: &StdioRedirect.standardError)
            completionHandler(error)
            return
        }
        print("Network server: \(serverIp!), client: \(clientIp!), subnet: \(subnetMask!)", to: &StdioRedirect.standardError)
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "255.255.255.255")
        let ipv4 = NEIPv4Settings(addresses: [clientIp!], subnetMasks: [subnetMask!])
        ipv4.includedRoutes = [.default(), .init(destinationAddress: serverIp!, subnetMask: subnetMask!)]
        settings.ipv4Settings = ipv4
        print("Network MTU: \(mtu ?? 0)", to: &StdioRedirect.standardError)
        if let mtu = mtu {
            settings.mtu = NSNumber(value: mtu)
        }
        configureDnsAndProxy(for: settings, with: savedOptions)
        setTunnelNetworkSettings(settings) { error in
            if error == nil {
                print("Tunnel started successfully!", to: &StdioRedirect.standardError)
                self.readPackets()
            } else {
                print("ERROR in setTunnelNetworkSettings: \(error?.localizedDescription ?? "(unknown)")", to: &StdioRedirect.standardError)
            }
            completionHandler(error)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        iodine = nil
        StdioRedirect.shared.stop()
        completionHandler()
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        iodine?.stop()
        completionHandler()
    }
    
    override func wake() {
        do {
            try iodine?.start()
        } catch {
            cancelTunnelWithError(error)
        }
    }
    
    private func readPackets() {
        packetFlow.readPackets { packets, protocols in
            for (i, packet) in packets.enumerated() {
                self.iodine?.writeData(packet, family: protocols[i].int32Value)
            }
            self.readPackets()
        }
    }
    
    private func configureDnsAndProxy(for config: NETunnelNetworkSettings, with options: [String: Any]?) {
        var dnsServer = "8.8.8.8"
        if let customDns = options?[IodineSettings.dnsServer] as? String, customDns.count > 0 {
            dnsServer = customDns
        }
        print("Network DNS: \(dnsServer)", to: &StdioRedirect.standardError)
        config.dnsSettings = NEDNSSettings(servers: [dnsServer])
        let proxy = NEProxySettings()
        if let pacConfigUrl = options?[IodineSettings.pacConfigUrl] as? String, pacConfigUrl.count > 0 {
            proxy.autoProxyConfigurationEnabled = true
            proxy.proxyAutoConfigurationURL = URL(string: pacConfigUrl)
            print("Network PAC URL: \(pacConfigUrl)", to: &StdioRedirect.standardError)
        }
        if let pacJavascript = options?[IodineSettings.pacJavascript] as? String, pacJavascript.count > 0 {
            proxy.autoProxyConfigurationEnabled = true
            proxy.proxyAutoConfigurationJavaScript = pacJavascript
            print("Network PAC Javascript: \(pacJavascript)", to: &StdioRedirect.standardError)
        }
        let httpProxyPortString = options?[IodineSettings.httpProxyPort] as? String
        let httpProxyPort = Int(httpProxyPortString ?? "0") ?? 0
        if let httpProxyServer = options?[IodineSettings.httpProxyServer] as? String, httpProxyServer.count > 0 {
            proxy.httpEnabled = true
            proxy.httpServer = NEProxyServer(address: httpProxyServer, port: httpProxyPort)
            print("Network HTTP Proxy: \(httpProxyServer):\(httpProxyPort)", to: &StdioRedirect.standardError)
        }
        let httpsProxyPortString = options?[IodineSettings.httpsProxyPort] as? String
        let httpsProxyPort = Int(httpsProxyPortString ?? "0") ?? 0
        if let httpsProxyServer = options?[IodineSettings.httpsProxyServer] as? String, httpsProxyServer.count > 0 {
            proxy.httpsEnabled = true
            proxy.httpsServer = NEProxyServer(address: httpsProxyServer, port: httpsProxyPort)
            print("Network HTTPS Proxy: \(httpsProxyServer):\(httpsProxyPort)", to: &StdioRedirect.standardError)
        }
    }
}

extension PacketTunnelProvider: IodineDelegate {
    func iodineError(_ error: Error?) {
        print("ERROR: \(error?.localizedDescription ?? "(unknown)")", to: &StdioRedirect.standardError)
        cancelTunnelWithError(error)
    }
    
    func iodineReadData(_ data: [Data], withProtocols protocols: [NSNumber]) {
        packetFlow.writePackets(data, withProtocols: protocols)
    }
    
    func iodineDidStop() {
        print("Tunnel stopped.", to: &StdioRedirect.standardError)
        cancelTunnelWithError(nil)
    }
}
