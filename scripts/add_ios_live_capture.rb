# Attach the live reader to the existing app, sharing its current reading model.
require 'xcodeproj'
project = Xcodeproj::Project.open(File.expand_path('../ios/Runner.xcodeproj', __dir__))
runner = project.targets.find { |t| t.name == 'Runner' }
share = project.targets.find { |t| t.name == 'LingferShare' }
def attach_source(target, reference)
  target.source_build_phase.add_file_reference(reference) unless target.source_build_phase.files_references.include?(reference)
end
def reference(group, path)
  group.files.find { |f| f.path == path } || group.new_file(path)
end
shared = project.main_group.find_subpath('Shared', false)
model = reference(shared, 'NativeReadingModel.swift')
attach_source(runner, model)
attach_source(share, model)
runner_group = project.main_group.find_subpath('Runner', false)
attach_source(runner, reference(runner_group, 'LiveScreenCapture.swift'))
share_group = project.main_group.find_subpath('LingferShare', false)
%w[ShareViewController.swift OfflineLexicon.swift].each { |name| attach_source(runner, reference(share_group,name)) }
%w[../../assets/data/vocabulary.json ../../assets/licenses/ECDICT-LICENSE.txt].each do |path|
  ref=reference(share_group,path)
  runner.resources_build_phase.add_file_reference(ref) unless runner.resources_build_phase.files_references.include?(ref)
end
framework = project.frameworks_group.files.find { |f| f.name == 'ScreenCaptureKit.framework' } || project.frameworks_group.new_file('System/Library/Frameworks/ScreenCaptureKit.framework', :sdk_root)
framework.name = 'ScreenCaptureKit.framework'
runner.frameworks_build_phase.files.select { |f| f.file_ref == framework }.each(&:remove_from_project)
runner.build_configurations.each do |config|
  config.build_settings['OTHER_LDFLAGS[sdk=iphoneos*]'] = '$(inherited) -weak_framework ScreenCaptureKit'
end
project.save
puts 'Attached live capture to existing Runner; share model remains shared'
