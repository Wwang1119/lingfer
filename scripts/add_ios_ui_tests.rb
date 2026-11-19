require 'xcodeproj'
project = Xcodeproj::Project.open(File.expand_path('../ios/Runner.xcodeproj', __dir__))
runner = project.targets.find { |t| t.name == 'Runner' }
tests = project.targets.find { |t| t.name == 'RunnerUITests' } || project.new_target(:ui_test_bundle, 'RunnerUITests', :ios, '15.5')
group = project.main_group.find_subpath('RunnerUITests', true)
group.path = 'RunnerUITests'
ref = group.files.find { |f| f.path == 'ReadingUITests.swift' } || group.new_file('ReadingUITests.swift')
tests.source_build_phase.add_file_reference(ref) unless tests.source_build_phase.files_references.include?(ref)
tests.build_configurations.each do |c|
  c.build_settings.merge!({'PRODUCT_NAME' => '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER' => 'com.wang.yudu.RunnerUITests', 'GENERATE_INFOPLIST_FILE' => 'YES', 'SWIFT_VERSION' => '5.0', 'IPHONEOS_DEPLOYMENT_TARGET' => '15.5', 'TEST_TARGET_NAME' => 'Runner', 'DEVELOPMENT_TEAM' => '8MRN4PZDSG', 'TARGETED_DEVICE_FAMILY' => '1,2'})
end
tests.add_dependency(runner) unless tests.dependencies.any? { |d| d.target == runner }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(runner, tests)
scheme.save_as(project.path, 'RunnerUITests', true)
puts 'Attached UI tests to existing Runner project'
