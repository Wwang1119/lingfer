# Idempotently attach the native sharing extension to the existing Flutter app.
require 'xcodeproj'

project = Xcodeproj::Project.open(File.expand_path('../ios/Runner.xcodeproj', __dir__))
runner = project.targets.find { |target| target.name == 'Runner' }
share = project.targets.find { |target| target.name == 'LingferShare' } || project.new_target(:app_extension, 'LingferShare', :ios, '15.5')

def file(group, path)
  group.files.find { |ref| ref.path == path } || group.new_file(path)
end

def source(target, ref)
  target.source_build_phase.add_file_reference(ref) unless target.source_build_phase.files_references.include?(ref)
end

def resource(target, ref)
  target.resources_build_phase.add_file_reference(ref) unless target.resources_build_phase.files_references.include?(ref)
end

shared_group = project.main_group.find_subpath('Shared', true)
shared_group.set_source_tree('<group>')
shared_group.path = 'Shared'
store = file(shared_group, 'CompanionStore.swift')
source(runner, store)
source(share, store)
privacy = file(shared_group, 'PrivacyInfo.xcprivacy')
resource(runner, privacy)
resource(share, privacy)

runner_group = project.main_group.find_subpath('Runner', false)
source(runner, file(runner_group, 'ShareStatePlugin.swift'))
file(runner_group, 'Runner.entitlements')

group = project.main_group.find_subpath('LingferShare', true)
group.path = 'LingferShare'
group.set_source_tree('<group>')
%w[ShareViewController.swift OfflineLexicon.swift].each { |name| source(share, file(group, name)) }
resource(share, file(group, 'WebPagePreprocessor.js'))
file(group, 'Info.plist')
file(group, 'LingferShare.entitlements')
resource(share, file(group, '../../assets/data/vocabulary.json'))
resource(share, file(group, '../../assets/licenses/ECDICT-LICENSE.txt'))

generated = project.files.find { |ref| ref.path == 'Flutter/Generated.xcconfig' }
share.build_configurations.each do |config|
  config.base_configuration_reference = generated
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.wang.yudu.LingferShare',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'DEVELOPMENT_TEAM' => '8MRN4PZDSG',
    'CODE_SIGN_STYLE' => 'Automatic',
    'CODE_SIGN_ENTITLEMENTS' => 'LingferShare/LingferShare.entitlements',
    'INFOPLIST_FILE' => 'LingferShare/Info.plist',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'SWIFT_VERSION' => '5.0',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'SKIP_INSTALL' => 'YES',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'IPHONEOS_DEPLOYMENT_TARGET' => '15.5',
    'MARKETING_VERSION' => '$(FLUTTER_BUILD_NAME)',
    'CURRENT_PROJECT_VERSION' => '$(FLUTTER_BUILD_NUMBER)',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  })
end
runner.build_configurations.each { |config| config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements' }
runner.add_dependency(share) unless runner.dependencies.any? { |dependency| dependency.target == share }
embed = runner.copy_files_build_phases.find { |phase| phase.name == 'Embed App Extensions' } || runner.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
unless embed.files_references.include?(share.product_reference)
  built = embed.add_file_reference(share.product_reference)
  built.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy', 'CodeSignOnCopy'] }
end
runner.build_phases.delete(embed)
thin = runner.build_phases.index { |phase| phase.respond_to?(:name) && phase.name == 'Thin Binary' }
runner.build_phases.insert(thin || runner.build_phases.length, embed)
project.save
puts 'Attached LingferShare to existing Runner target'
