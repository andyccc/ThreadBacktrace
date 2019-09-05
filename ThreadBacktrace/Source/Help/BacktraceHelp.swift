//
//  BacktraceHelp.swift
//  ThreadBacktrace
//
//  Created by yans on 2019/9/5.
//

import Foundation
import Darwin

//MARK: 线程相关 私有
/// 获取线程调用堆栈
@_silgen_name("mach_backtrace")
public func backtrace(_ thread: thread_t,
                      stack: UnsafeMutablePointer<UnsafeMutableRawPointer?>,
                      maxSymbols: Int32) -> Int32

//MARK: extension
extension Character {
    var isAscii: Bool {
        return unicodeScalars.allSatisfy { $0.isASCII }
    }
    var ascii: UInt32? {
        return isAscii ? unicodeScalars.first?.value : nil
    }
}

extension String {
    var ascii : [Int8] {
        var unicodeValues = [Int8]()
        for code in unicodeScalars {
            unicodeValues.append(Int8(code.value))
        }
        return unicodeValues
    }
}
