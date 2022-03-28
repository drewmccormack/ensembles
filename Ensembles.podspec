Pod::Spec.new do |s|

  s.name         = "Ensembles"
  s.version      = "1.10"
  s.summary      = "A peer-to-peer synchronization framework for Core Data."

  s.description  =  <<-DESC
                    Ensembles extends Apple's Core Data framework to add 
                    synchronization for Mac OS and iOS. 
                    Multiple SQLite persistent stores can be coupled together 
                    via a file synchronization platform like iCloud or Dropbox. 
                    The framework can be readily extended to support any 
                    service capable of moving files between devices, including 
                    custom servers.
                    DESC

  s.homepage = "https://github.com/drewmccormack/ensembles"
  s.license = { 
    :type => 'MIT', 
    :file => 'LICENCE.txt' 
  }
  s.author = { "Drew McCormack" => "drewmccormack@mac.com" }

  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.8'
  
  s.source        = { 
    :git => 'https://github.com/drewmccormack/ensembles.git', 
    :tag => s.version.to_s
  }
  
  s.requires_arc  = true
  
  s.default_subspec = 'Core'
  
  s.subspec 'Core' do |ss|
    ss.source_files = 'Framework/**/*.{h,m}'
    ss.exclude_files = 'Framework/Tests', 'Framework/Extensions/**/*.{h,m}'
    ss.resources = 'Framework/Resources/*'
    ss.frameworks = 'CoreData'
  end
  
  s.subspec 'DropboxV2' do |ss|
    # Bump deployment targets to match ObjectiveDropboxOfficial's
    ss.ios.deployment_target = '9.0'
    ss.osx.deployment_target = '10.10'
    ss.dependency 'Ensembles/Core'
    ss.dependency 'ObjectiveDropboxOfficial', '6.2.3'
    ss.source_files = 'Framework/Extensions/CDEDropboxV2CloudFileSystem.{h,m}'
  end
  
  s.subspec 'Multipeer' do |ss|
    ss.dependency 'Ensembles/Core'
    ss.dependency 'SSZipArchive'
    ss.framework = 'MultipeerConnectivity'
    ss.source_files = 'Framework/Extensions/CDEMultipeerCloudFileSystem.{h,m}'
  end
  
end
