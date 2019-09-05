//
//  ThreadBacktrace.swift
//  ThreadBacktrace
//
//  Created by yans on 2019/9/5.
//

import Foundation
import Darwin

//MARK: 对外接口
/// 获取主线程调用栈
public func BacktraceOfMainThread() -> [String] {
    return _mach_callstack(_machThread(from: .main))
        .map { $0.info }
}

/// 获取当前线程调用栈
public func BacktraceOfCurrentThread() -> [String] {
    return _mach_callstack(_machThread(from: .current))
        .map { $0.info }
}

/// 获取指定线程调用栈数据 StackSymbol
public func Backtrace(of thread: Thread) -> [StackSymbol] {
    return _mach_callstack(_machThread(from: thread))
}

/// 解析堆栈符号，需真实的 ASLR
public func Symbolic(of stack: [UInt], aslr: Int) -> [String] {
    guard !stack.isEmpty else {
        return []
    }
    
    var symbols : [String] = []
    
    for (index, address) in stack.enumerated() {
        let symbol : String
        if (IsAppSymbolTable) {
            symbol = _symbolic(address, index: index, aslr: aslr).info
        }
        else {
            symbol = _stackSymbol(address, index: index).info
        }
        
        symbols.append(symbol)
    }
    
    return symbols
}

/// 获取 指定mach线程 回调栈
private func _mach_callstack(_ thread: thread_t) -> [StackSymbol] {
    // 获取线程堆栈
    var symbols : [StackSymbol] = []
    let stackSize : UInt32 = 128
    let addrs = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: Int(stackSize))
    defer { addrs.deallocate() }
    let frameCount = backtrace(thread, stack: addrs, maxSymbols: Int32(stackSize))
    let buf = UnsafeBufferPointer(start: addrs, count: Int(frameCount))

    // 解析堆栈地址
    for (index, addr) in buf.enumerated() {
        guard let addr = addr else { continue }
        let address = UInt(bitPattern: addr)
        let symbol : StackSymbol
        
        // 根据是否有动态符号表来觉得解析方法
        if (IsAppSymbolTable) {
            symbol = _symbolic(address, index: index)
        }
        else {
            symbol = _stackSymbol(address, index: index)
        }
        
        symbols.append(symbol)
    }
    return symbols
}

/// Thread to mach 线程
private func _machThread(from thread: Thread) -> thread_t {
    guard let (threads, count) = _machAllThread() else {
        return mach_thread_self()
    }

    if thread.isMainThread {
        return get_mach_main_thread()
    }

    var name : [Int8] = []
    let originName = thread.name
    
    for i in 0 ..< count {
        let index = Int(i)
        if let p_thread = pthread_from_mach_thread_np((threads[index])) {
            name.append(Int8(Character("\0").ascii ?? 0))
            pthread_getname_np(p_thread, &name, MemoryLayout<Int8>.size * 256)
            if (strcmp(&name, (thread.name!.ascii)) == 0) {
                thread.name = originName
                return threads[index]
            }
        }
    }

    thread.name = originName
    return mach_thread_self()
}

/// 获取所有线程
private func _machAllThread() -> (thread_act_array_t, mach_msg_type_number_t)? {
    /// 线程List
    var threads : thread_act_array_t?
    /// 线程数
    var count : mach_msg_type_number_t = 0
    /// 进程 ID
    let task = mach_task_self_
    
    guard task_threads(task, &(threads), &count) == KERN_SUCCESS else {
        return nil
    }
    
    return (threads!, count)
}
