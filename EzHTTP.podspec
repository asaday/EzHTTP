
Pod::Spec.new do |s|

s.name         = "EzHTTP"
s.version      = "0.0.1"
s.summary      = "Easy HTTP access library"

s.homepage     = "http://nagisaworks.com"
s.license     = { :type => "MIT" }
s.author       = { "asaday" => "" }

s.platform     = :ios, "8.0"
s.source       = { :path=> ".", :tag => s.version }
s.source_files  = "sources/**/*.{swift,h,m}"
s.requires_arc = true

end
