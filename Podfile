platform :ios, '26.2'

project 'shortcuts_example.xcodeproj'
use_frameworks! :linkage => :static

target 'shortcuts_example' do
  pod 'FirebaseAILogic', '12.17.0'
  pod 'GoogleMLKit/TextRecognitionKorean', '8.0.0'

  target 'shortcuts_exampleTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.generated_projects.each do |project|
    project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '26.2'
      end
    end
  end
end
