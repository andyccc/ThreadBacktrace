# ThreadBacktrace

[![Version](https://img.shields.io/cocoapods/v/ThreadBacktrace.svg?style=flat)](https://cocoapods.org/pods/ThreadBacktrace)
[![License](https://img.shields.io/cocoapods/l/ThreadBacktrace.svg?style=flat)](https://cocoapods.org/pods/ThreadBacktrace)
[![Platform](https://img.shields.io/cocoapods/p/ThreadBacktrace.svg?style=flat)](https://cocoapods.org/pods/ThreadBacktrace)

 获取线程调用堆栈 & 解析符号
  Mach-O 存在符号表则 读取符号表并解析
  Mach-O 不存在符号表则 利用 runtime 获取当前镜像中所有 Class 的方法。自制符号表并解析

## Example

获取主线程调用栈
```swift
BacktraceOfMainThread()
```
获取当前线程调用栈
```swift
BacktraceOfMainThread()
```

解析堆栈符号，需真实的 ASLR
```swift
Symbolic(of stack: [UInt], aslr: Int)
```

## Requirements

## Installation

ThreadBacktrace is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'ThreadBacktrace'
```

## Author

andyccc

## License

ThreadBacktrace is available under the MIT license. See the LICENSE file for more info.
