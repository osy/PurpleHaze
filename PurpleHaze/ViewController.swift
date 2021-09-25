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

import UIKit
import NetworkExtension

class ViewController: UIViewController {
    var vpnObserver: Any?
    var vpnManager: NEVPNManager?
    
    var lastLogIndex: UInt64 = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        refreshLog()
        setupVpn()
    }
    
    func showError(message: String?) {
        let alertMessage = message ?? NSLocalizedString("An error has occurred.", comment: "Main")
        let alert = UIAlertController(title: nil, message: alertMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Main"), style: .default, handler: nil))
        DispatchQueue.main.async {
            self.present(alert, animated: true)
        }
    }

    func showError(_ error: Error?) {
        showError(message: error?.localizedDescription)
    }
}

extension ViewController {
    var tunnelBundleId: String {
        Bundle.main.bundleIdentifier!.appending(".Iodine")
    }
    
    func setupVpn() {
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            DispatchQueue.global(qos: .background).async {
                if !(managers?.isEmpty ?? true), let manager = managers?[0] {
                    if error != nil {
                        self.showError(error)
                    } else {
                        self.startExistingTunnel(with: manager)
                    }
                } else {
                    self.createAndStartTunnel()
                }
            }
        }
    }
    
    func createAndStartTunnel() {
        let manager = NETunnelProviderManager()
        manager.localizedDescription = NSLocalizedString("Iodine DNS Tunnel", comment: "Main")
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleId
        proto.serverAddress = ""
        manager.protocolConfiguration = proto
        manager.isEnabled = true
        let lock = DispatchSemaphore(value: 0)
        var error: Error?
        manager.saveToPreferences { err in
            error = err
            lock.signal()
        }
        lock.wait()
        if let err = error {
            showError(err)
        } else {
            startExistingTunnel(with: manager)
        }
    }
    
    func startExistingTunnel(with manager: NEVPNManager) {
        if manager.connection.status == .connected {
            // Connection already established, nothing to do here
            return
        }
        
        let lock = DispatchSemaphore(value: 0)
        self.vpnObserver = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: manager.connection, queue: nil, using: { [weak self] _ in
            guard let _self = self else {
                return
            }
            print("[VPN] Connected? \(manager.connection.status == .connected)")
            lock.signal()
            if manager.connection.status == .disconnected {
                _self.vpnDidDisconnect(for: manager)
            } else if manager.connection.status == .connected {
                _self.vpnDidConnect(for: manager)
            }
        })
        let options = [IodineSettings.topDomain: "t.example.com" as NSObject,
                       IodineSettings.password: "password" as NSObject,
                       IodineSettings.captureLog: true as NSObject]
        do {
            try manager.connection.startVPNTunnel(options: options)
        } catch NEVPNError.configurationDisabled {
            showError(message: NSLocalizedString("VPN has been disabled in settings or another VPN configuration is selected.", comment: "Main"))
        } catch {
            showError(error)
        }
        if lock.wait(timeout: .now() + .seconds(60)) == .timedOut {
            showError(message: NSLocalizedString("Failed to start tunnel.", comment: "Main"))
        }
    }
    
    func stopTunnel(with manager: NEVPNManager) {
        if manager.connection.status == .disconnected {
            return
        }
        
        manager.connection.stopVPNTunnel()
    }
    
    func vpnDidConnect(for manager: NEVPNManager) {
        vpnManager = manager
    }
    
    func vpnDidDisconnect(for manager: NEVPNManager) {
        vpnObserver = nil
        vpnManager = nil
    }
}

extension ViewController {
    private var logUrl: URL? {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return nil
        }
        let groupBundleId = "group." + bundleId
        let containerUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupBundleId)
        return containerUrl?.appendingPathComponent("log.txt")
    }
    
    private func getNewLogLines() -> String? {
        guard let logUrl = logUrl else {
            return nil
        }
        guard let handle = try? FileHandle(forReadingFrom: logUrl) else {
            return nil
        }
        defer {
            handle.closeFile()
        }
        handle.seek(toFileOffset: lastLogIndex)
        let newlines = String(data: handle.readDataToEndOfFile(), encoding: .utf8)
        lastLogIndex = handle.offsetInFile
        return newlines
    }
    
    func refreshLog() {
        let lines = getNewLogLines()
        if let lines = lines, lines.count > 0 {
            print(lines, separator: "")
        }
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0, execute: refreshLog)
    }
}

