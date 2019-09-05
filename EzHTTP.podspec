
Pod::Spec.new do |s|

s.name = "EzHTTP"
s.version = "3.5.0"
s.summary = "Easy HTTP access library"
s.swift_version = "5.0"

s.homepage = "https://nagisaworks.com"
s.license = { :type => "MIT" }
s.author = { "asaday" => "" }

s.requires_arc = true
s.swift_version = "5.0"
s.osx.deployment_target = "10.10"
s.ios.deployment_target = "8.0"
s.tvos.deployment_target = "9.0"

s.source = { :git=> "https://github.com/asaday/EzHTTP.git", :tag => s.version }
s.source_files  = "Sources/EzHTTP/*.swift"

end

