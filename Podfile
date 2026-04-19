source 'https://cdn.cocoapods.org/'

platform :osx, '11.0'
use_frameworks!

target 'RealmBrowser' do
    pod 'Realm'

    target 'RealmBrowserTests' do
      inherit! :search_paths
    end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Realm's private headers use quoted imports; newer Xcode treats that as an error.
      config.build_settings['CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER'] = 'NO'
    end
  end
end
