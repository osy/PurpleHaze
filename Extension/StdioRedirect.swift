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

public class StdioRedirect {
    static public var standardError = FileHandle.standardError
    static public let shared = StdioRedirect()
    
    private var standardOutput: Pipe
    private var standardError: Pipe
    private var origStdout: Int32 = -1
    private var origStderr: Int32 = -1
    
    private static var logUrl: URL? {
        guard let bundleId = Bundle.main.bundleIdentifier as NSString? else {
            return nil
        }
        let groupBundleId = "group." + bundleId.deletingPathExtension
        let containerUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupBundleId)
        return containerUrl?.appendingPathComponent("log.txt")
    }
    
    private init() {
        //var lastOutputLine = ""
        standardOutput = Pipe()
        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            //let data = lastOutputLine.data(using: .utf8)! + handle.availableData
            //lastOutputLine = StdioRedirect.logData(data)
            try! handle.availableData.append(fileURL: StdioRedirect.logUrl!)
        }
        //var lastErrorLine = ""
        standardError = Pipe()
        standardError.fileHandleForReading.readabilityHandler = { handle in
            //let data = lastErrorLine.data(using: .utf8)! + handle.availableData
            //lastErrorLine = StdioRedirect.logData(data)
            try! handle.availableData.append(fileURL: StdioRedirect.logUrl!)
        }
    }
    
    // used for debugging only
    private static func logData(_ data: Data) -> String {
        guard let log = String(data: data, encoding: .utf8), log.count > 0 else {
            return ""
        }
        var last = ""
        var lines = log.split(whereSeparator: \.isNewline)
        if !log.last!.isNewline && lines.count > 0 {
            last = String(lines.popLast()!)
        }
        for line in lines {
            if !line.contains("[Iodine]") {
                NSLog("[Iodine] %@", String(line))
            }
        }
        return last
    }
    
    public func start() throws {
        origStdout = dup(STDOUT_FILENO)
        guard origStdout >= 0 else {
            throw RedirectError.cannotDuplicateStdout
        }
        origStderr = dup(STDERR_FILENO)
        guard origStderr >= 0 else {
            throw RedirectError.cannotDuplicateStderr
        }
        guard dup2(standardOutput.fileHandleForWriting.fileDescriptor, STDOUT_FILENO) >= 0 else {
            throw RedirectError.cannotRedirectStdout
        }
        guard dup2(standardError.fileHandleForWriting.fileDescriptor, STDERR_FILENO) >= 0 else {
            throw RedirectError.cannotRedirectStderr
        }
        guard let logUrl = StdioRedirect.logUrl else {
            throw RedirectError.cannotAccessGroupContainer
        }
        // remove file if it exists
        try? FileManager.default.removeItem(at: logUrl)
    }
    
    public func stop() {
        if origStdout >= 0 {
            dup2(origStdout, STDOUT_FILENO)
            close(origStdout)
            origStdout = -1
        }
        if origStderr >= 0 {
            dup2(origStderr, STDERR_FILENO)
            close(origStderr)
            origStderr = -1
        }
    }
    
    public enum RedirectError: Error {
        case cannotDuplicateStdout
        case cannotDuplicateStderr
        case cannotRedirectStdout
        case cannotRedirectStderr
        case cannotAccessGroupContainer
    }
}

fileprivate extension Data {
    func append(fileURL: URL) throws {
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } else {
            try write(to: fileURL, options: .atomic)
        }
    }
}

extension FileHandle: TextOutputStream {
  public func write(_ string: String) {
    guard let data = string.data(using: .utf8) else {
      fatalError()
    }
    self.write(data)
  }
}
