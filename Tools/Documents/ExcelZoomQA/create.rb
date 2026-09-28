require 'xcodeproj'
require 'fileutils'
base = ENV.fetch('EXCEL_ZOOM_QA_DIR', '/tmp/rivopad-excel-zoom-qa')
repo = File.expand_path('../../..', __dir__)
FileUtils.mkdir_p(base)
project = Xcodeproj::Project.new(base + '/ExcelZoomQA.xcodeproj')
app = project.new_target(:application, 'ExcelZoomQA', :ios, '26.2')
test = project.new_target(:ui_test_bundle, 'ExcelZoomQAUITests', :ios, '26.2')
test.add_dependency(app)
source = ENV.fetch('EXCEL_ZOOM_QA_SOURCE', repo + '/shortcuts_example/Documents/ExcelZoomScrollView.swift')
[__dir__ + '/App.swift', source].each do |path|
  app.add_file_references([project.main_group.new_file(path)])
end
test.add_file_references([project.main_group.new_file(__dir__ + '/ZoomUITests.swift')])
[app, test].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'net.rivo.excelzoomqa.' + target.name
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  end
end
app.build_configurations.each { |c| c.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES' }
test.build_configurations.each { |c| c.build_settings['TEST_TARGET_NAME'] = 'ExcelZoomQA' }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(test)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'ExcelZoomQA', true)
