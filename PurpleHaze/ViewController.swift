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
    @IBOutlet var topDomainTextField: UITextField!
    @IBOutlet var passwordTextField: UITextField!
    @IBOutlet var logTextView: UITextView!
    @IBOutlet var vpnStartSwitch: UISwitch!
    @IBOutlet var activityIndicator: UIActivityIndicatorView!
    
    var vpnObserver: Any?
    var vpnManager: NEVPNManager?
    
    var lastLogIndex: UInt64 = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initVpn()
        refreshLog()
    }
    
    func showError(message: String?) {
        DispatchQueue.main.async {
            let alertMessage = message ?? NSLocalizedString("An error has occurred.", comment: "Main")
            let alert = UIAlertController(title: nil, message: alertMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Main"), style: .default, handler: nil))
            self.present(alert, animated: true)
            self.vpnStartSwitch.isOn = self.vpnManager?.connection.status == .connected
        }
    }

    func showError(_ error: Error?) {
        showError(message: error?.localizedDescription)
    }
    
    @IBAction func advancedSettingsPressed(_ sender: Any) {
    }
    
    @IBAction func vpnStartSwitchChanged(_ sender: Any) {
        if vpnStartSwitch.isOn {
            clearLog()
            setupVpn(with: vpnManager)
        } else {
            guard let vpnManager = vpnManager else {
                return
            }
            stopTunnel(with: vpnManager)
        }
    }
}

extension ViewController {
    var tunnelBundleId: String {
        Bundle.main.bundleIdentifier!.appending(".Iodine")
    }
    
    func initVpn() {
        DispatchQueue.main.async {
            self.vpnStartSwitch.isEnabled = false
        }
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            if !(managers?.isEmpty ?? true), let manager = managers?[0] {
                self.vpnManager = manager
            }
            if error != nil {
                self.showError(error)
            }
            DispatchQueue.main.async {
                self.vpnStartSwitch.isOn = self.vpnManager?.connection.status == .connected
                self.vpnStartSwitch.isEnabled = true
            }
        }
    }
    
    func setupVpn(with manager: NEVPNManager? = nil) {
        DispatchQueue.main.async {
            self.vpnStartSwitch.isEnabled = false
            self.activityIndicator.startAnimating()
        }
        DispatchQueue.global(qos: .background).async {
            if let manager = manager {
                self.startExistingTunnel(with: manager)
            } else {
                self.createAndStartTunnel()
            }
            DispatchQueue.main.async {
                self.vpnStartSwitch.isEnabled = true
                self.activityIndicator.stopAnimating()
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
            initVpn()
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
            return
        } catch {
            showError(error)
            return
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
        DispatchQueue.main.async {
            self.vpnStartSwitch.isOn = true
        }
    }
    
    func vpnDidDisconnect(for manager: NEVPNManager) {
        vpnObserver = nil
        vpnManager = nil
        DispatchQueue.main.async {
            self.vpnStartSwitch.isOn = false
        }
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
    
    func clearLog() {
        guard let logUrl = logUrl else {
            return
        }
        try? FileManager.default.removeItem(at: logUrl)
        DispatchQueue.main.async {
            self.logTextView.text = ""
        }
    }
    
    func refreshLog() {
        if let lines = getNewLogLines() {
            print(lines, terminator: "")
            if lines.count > 0 {
                DispatchQueue.main.async {
                    self.logTextView.text += lines
                    self.logTextView.scrollToBottom()
                }
            }
        } else {
            DispatchQueue.main.async {
                self.logTextView.text = ""
            }
        }
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0, execute: refreshLog)
    }
}

extension UITextView {
    func scrollToBottom() {
        let textCount: Int = text.count
        guard textCount >= 1 else { return }
        scrollRangeToVisible(NSRange(location: textCount - 1, length: 1))
    }
}
