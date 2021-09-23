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
        iodine = Iodine(options: options)
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
            completionHandler(error)
        }
        print("Setting up tunnel with server: \(serverIp!), client: \(clientIp!), subnet: \(subnetMask!)")
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: serverIp!)
        let ipv4 = NEIPv4Settings(addresses: [clientIp!], subnetMasks: [subnetMask!])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: clientIp!, subnetMask: subnetMask!)]
        ipv4.excludedRoutes = [.default()]
        settings.ipv4Settings = ipv4
        if let mtu = mtu {
            settings.mtu = NSNumber(value: mtu)
        }
        setTunnelNetworkSettings(settings) { error in
            if error == nil {
                self.readPackets()
            }
            completionHandler(error)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        iodine = nil
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Add code here to handle the message.
        if let handler = completionHandler {
            handler(messageData)
        }
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
            for packet in packets {
                self.iodine?.writeData(packet)
            }
            self.readPackets()
        }
    }
}

extension PacketTunnelProvider: IodineDelegate {
    func iodineError(_ error: Error?) {
        cancelTunnelWithError(error)
    }
    
    func iodineReadData(_ data: Data) {
        packetFlow.writePackets([data], withProtocols: [NSNumber(value: AF_INET)])
    }
}
