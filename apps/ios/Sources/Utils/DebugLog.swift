import Foundation

@inline(__always)
func DLog(_ message: @autoclosure () -> String,
          file: StaticString = #file,
          function: StaticString = #function,
          line: UInt = #line) {
#if DEBUG
    let filename = (String(describing: file) as NSString).lastPathComponent
    print("[DEBUG] \(filename):\(line) \(function) — \(message())")
#endif
}

