
Pod::Spec.new do |s|

s.name         = "EzHTTP"
s.version      = "3.0.10"
s.summary      = "Easy HTTP access library"

s.homepage     = "http://nagisaworks.com"
s.license     = { :type => "MIT" }
s.author       = { "asaday" => "" }

s.platform     = :ios, "8.0"
s.source       = { :git=> "https://github.com/asaday/EzHTTP.git", :tag => s.version }
s.source_files  = "sources/**/*.{swift,h,m}"
s.requires_arc = true

s.module_map = 'resources/module.modulemap'
s.private_header_files = "sources/GCDAsyncSocket.h"

s.pod_target_xcconfig =  { 'SWIFT_VERSION' => '3.0' }

end
