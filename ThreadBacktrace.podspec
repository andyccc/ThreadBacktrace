#
# Be sure to run `pod lib lint ThreadBacktrace.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'ThreadBacktrace'
  s.version          = '0.2.0'
  s.summary          = '获取线程调用栈 & 解析堆栈'

  s.description      = <<-DESC
  获取线程调用堆栈 & 解析符号
  Mach-O 存在符号表则 读取符号表并解析
  Mach-O 不存在符号表则 利用 runtime 获取当前镜像中所有 Class 的方法。自制符号表并解析
                       DESC

  s.homepage         = 'https://github.com/Boy-Rong/ThreadBacktrace'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'andyccc' => 'andyccc' }
  s.source           = { :git => 'https://github.com/andyccc/ThreadBacktrace.git', :tag => s.version.to_s }

  s.ios.deployment_target = '8.0'
  
  s.swift_versions = ['5.1', '5.2', '5.3']
  
  s.source_files = 'ThreadBacktrace/Source/**/*.{swift,h,c}'
  
  s.pod_target_xcconfig = {
    "DEFINES_MODULE" => "YES"
  }

end
