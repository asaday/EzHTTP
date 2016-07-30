
Pod::Spec.new do |s|

s.name         = "EzHTTP"
s.version      = "0.0.4"
s.summary      = "Easy HTTP access library"

s.homepage     = "http://nagisaworks.com"
s.license     = { :type => "MIT" }
s.author       = { "asaday" => "" }

s.platform     = :ios, "8.0"
s.source       = { :git=> "https://github.com/asaday/EzHTTP.git", :tag => s.version }
s.source_files  = "sources/**/*.{swift,h,m}"
s.requires_arc = true
s.preserve_paths = "modules/module.modulemap"

s.xcconfig= {
  "SWIFT_INCLUDE_PATHS" =>    "${PODS_ROOT}/EzHTTP/modules"
}

end
