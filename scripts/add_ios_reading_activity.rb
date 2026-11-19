# Add the Live Activity to the existing Lingfer app without recreating targets.
require 'xcodeproj'
project = Xcodeproj::Project.open(File.expand_path('../ios/Runner.xcodeproj', __dir__))
runner = project.targets.find { |t| t.name == 'Runner' }
widget = project.targets.find { |t| t.name == 'LingferActivity' } || project.new_target(:app_extension, 'LingferActivity', :ios, '17.0')
group = project.main_group.find_subpath('LingferActivity', true)
group.path = 'LingferActivity'
shared = project.main_group.find_subpath('Shared', false)
runner_group = project.main_group.find_subpath('Runner', false)
def source(target, group, name)
  ref = group.files.find { |f| f.path == name } || group.new_file(name)
  target.source_build_phase.add_file_reference(ref) unless target.source_build_phase.files_references.include?(ref)
end
source(widget, group, 'ReadingActivityWidget.swift')
%w[ReadingActivityAttributes.swift ReadingActivityIntents.swift].each do |name|
  source(widget, shared, name)
  source(runner, shared, name)
end
source(runner, runner_group, 'ReadingActivityManager.swift')
group.new_file('Info.plist') unless group.files.any? { |f| f.path == 'Info.plist' }
widget_config = group.files.find { |f| f.path == 'Activity.xcconfig' } || group.new_file('Activity.xcconfig')
widget.build_configurations.each do |config|
  config.base_configuration_reference = widget_config
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.wang.yudu.LingferActivity',
    'PRODUCT_NAME' => '$(TARGET_NAME)', 'DEVELOPMENT_TEAM' => '8MRN4PZDSG',
    'CODE_SIGN_STYLE' => 'Automatic', 'INFOPLIST_FILE' => 'LingferActivity/Info.plist',
    'IPHONEOS_DEPLOYMENT_TARGET' => '17.0', 'SWIFT_VERSION' => '5.0',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) LINGFER_WIDGET_EXTENSION',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES', 'SKIP_INSTALL' => 'YES',
    'TARGETED_DEVICE_FAMILY' => '1,2', 'GENERATE_INFOPLIST_FILE' => 'NO',
    'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
  })
end
runner.add_dependency(widget) unless runner.dependencies.any? { |d| d.target == widget }
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
unless embed.files_references.include?(widget.product_reference)
  file = embed.add_file_reference(widget.product_reference)
  file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy', 'CodeSignOnCopy'] }
end
project.save
puts 'Attached LingferActivity to the existing Runner app.'
