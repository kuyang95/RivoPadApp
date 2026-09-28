require 'xcodeproj'
require 'fileutils'
base = ENV.fetch('HWP_INLINE_QA_DIR', '/tmp/rivopad-inline-qa')
repo = File.expand_path('../../..', __dir__)
device_signing = ENV['HWP_INLINE_QA_DEVICE_SIGNING'] == '1'
development_team = ENV.fetch('HWP_INLINE_QA_DEVELOPMENT_TEAM', 'Z3TXJ872H6')
FileUtils.mkdir_p(base + '/Sources')
FileUtils.mkdir_p(base + '/Tests')
models = File.read(repo + '/shortcuts_example/Documents/HWP/HWPDocumentEditing.swift')
File.write(base + '/Sources/HWPDocumentModels.swift', models)
theme = File.read(repo + '/shortcuts_example/DesignSystem/VisionCraftUI.swift').split('struct VisionCraftSectionHeader:', 2).first
File.write(base + '/Sources/VisionCraftTheme.swift', theme)
project = Xcodeproj::Project.new(base + '/InlineQA.xcodeproj')
app = project.new_target(:application, 'InlineQA', :ios, '26.2')
test = project.new_target(:unit_test_bundle, 'InlineQATests', :ios, '26.2')
test.add_dependency(app)
package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
package.repositoryURL = 'https://github.com/weichsel/ZIPFoundation.git'
package.requirement = { 'kind' => 'exactVersion', 'version' => '0.9.20' }
project.root_object.package_references << package
[app, test].each do |target|
  product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product.product_name = 'ZIPFoundation'
  product.package = package
  target.package_product_dependencies << product
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product
  target.frameworks_build_phase.files << build_file
end
sources = [base + '/Sources/HWPDocumentModels.swift', base + '/Sources/VisionCraftTheme.swift', __dir__ + '/App.swift', __dir__ + '/CellFixture.swift', __dir__ + '/Support.swift']
sources += %w[OLECompoundFile OLECompoundFileWriter HWP5TextExtractor HWPXTextExtractor].map { |n| repo + '/shortcuts_example/LLM/' + n + '.swift' }
sources += %w[HWPPDFRenderer HWPPDFPreview HWPHeaderFooterEditing HWPHeaderFooterWriter HWPHeaderFooterSheet HWPHyperlinkEditing HWPHyperlinkEditingWriter HWPHyperlinkEditingControls HWPImageEditing HWPImageEditingWriter HWPImageEditingControls HWPTableDeletion HWPTableDeletionWriter HWPTableInsertion HWPTableInsertionWriter HWPTableInsertionSheet HWPPageNumberEditing HWPPageNumberWriter HWPPageNumberSheet HWPPageSetup HWPPageSetupWriter HWPPageSetupSheet HWPColumnSetup HWPColumnSetupSheet HWPTableSizing HWPTableSizingSheet HWPTableCellEditing HWPTableStructureEditing HWPTableStructureWriter HWPTableStructureDocument HWPCellFormatting HWPCellFormattingSheet HWPCellFormattingWriter HWPListFormatting HWPFindReplace HWPTablePageLayout HWPTableEditing HWPTableLayoutWriter HWPXParagraphWriter HWPXLineLayoutWriter HWPXFormattingWriter HWPParagraphEditing HWP5ParagraphWriter HWP5LineLayoutWriter HWP5StructuredDocumentParser HWP5DocumentRewriter HWP5FormattingWriter HWPDocumentFormatting HWPFormattingToolbar HWPTextRunEditing HWPDocumentSceneModels HWPChartOOXMLParser HanyangPUANormalizer HWPDocumentFontResolver HWPXLayoutParser HWPFlowLayout HWPMetricLineText HWPShapeEditing HWPShapeEditingWriter HWPShapeEditingControls HWPTextBoxEditing HWPTextBoxStructureWriter HWPEquationEditing HWPEquationEditingWriter HWPNoteEditing HWPNoteEditingWriter HWPNoteEditingControls HWPObjectContentEditingControls HWPOriginalDocumentCanvas HWPDocumentNavigation HWPDocumentNavigationControls HWPDocumentZoomView HWPEquationCanvasView HWPInlineEditingSession HWPInlineTextEditor].map { |n| repo + '/shortcuts_example/Documents/HWP/' + n + '.swift' }
sources.each { |p| app.add_file_references([project.main_group.new_file(p)]) }
%w[hangul_design_application.hwp mss_voucher.hwpx].each do |name|
  fixture = repo + '/shortcuts_exampleTests/HWPXViewerFixtures/' + name
  [app, test].each { |target| target.resources_build_phase.add_file_reference(project.main_group.new_file(fixture)) }
end
%w[Batang-Regular.ttf Gulim-Regular.ttf Gungsuh-Regular.ttf Dotum-Regular.ttf].each do |f|
  app.resources_build_phase.add_file_reference(project.main_group.new_file(repo + '/shortcuts_example/' + f))
end
%w[HWPPDFExportTests HWPHeaderFooterTests HWPHyperlinkEditingTests HWPImageEditingTests HWPTableDeletionTests HWPTableInsertionTests HWPPageNumberTests HWPPageBreakTests HWPPageSetupTests HWPTableSizingTests HWPTableCellEditingTests HWPTableStructureTests HWPCellFormattingTests HWPCharacterFormattingTests HWPListFormattingTests HWPFindReplaceTests HWPTableEditingTests HWPInlineEditingTests HWPParagraphEditingTests HWPFormattingTests HWPDocumentEditingTests HWPDocumentRegressionTests HWPEmptyParagraphEditingTests HWPDocumentNavigationTests HWPXViewerTests].each do |name|
  testpath = base + '/Tests/' + name + '.swift'
  source = File.read(repo + '/shortcuts_exampleTests/' + name + '.swift').sub('@testable import shortcuts_example', '@testable import InlineQA')
  # The standalone host excludes document-library coordination; those three model tests run in the full app.
  source = source.gsub(/^    func test(?:ViewModelPDFIncludesPendingInputAndPreservesDirtyUndoAndOriginalFile|ViewModelHeaderFooterUndoRedoPendingTextSaveAndConflict|ViewModelTableDeletionUndoRedoPendingInputSaveAndConflict|ViewModelTableInsertionUndoRedoPendingTextSaveAndConflict|ViewModelPageNumberUndoRedoSaveAndConflict|ViewModelPageBreakUndoRedoPendingInputSaveAndConflict|ViewModelPageSetupUndoRedoRestoresLayoutAndUnsavedText|ViewModelHWPPageSetupRepeatedSaveAndConflict|ViewModelTableSizingUndoRedoKeepsUnsavedInputAndOriginalFile|ViewModelHWPResizeRepeatedSaveAndExternalFileConflict|ViewModelMergeSplitUndoRedoAndSaveKeepsBothCellsContent|ViewModelHWPRepeatedCellChangesSaveAndUndoToCleanBaseline|ViewModelTableStructureUndoRedoKeepsDiskSnapshotAndPendingEdits|ViewModelTableStructureStillRejectsExternalFileChanges|ViewModelRepeatedHWPStructureOperationsSaveToOriginalFormat|ViewModelCellStyleUndoRedoAndSaveAllParagraphs|ViewModelCharacterEffectsDirtyUndoRedoAndSave|ViewModelListsUndoRedoEnterAndSaveHWPX|ViewModelReplaceAllIsOneUndoRestoresLayoutAndSaves|ViewModelRejectsStaleMatchWithoutApplyingAnotherUndoEntry|ViewModelBatchCellGrowthUsesOneUndoAndKeepsBothHeights|ViewModelTableGrowthUndoRedoAndSave|ViewModelImageCropUndoRedoAndSave|ParagraphUndoRedoRestoresStructureSelectionAndSave|TableCellParagraphUndoRedoAndSaveInBothFormats|ViewModelFormattingOnlyUndoRedoAndFileSave)\b.*?(?=^    (?:private )?func |^\})/m, '')
  source = source.gsub(/    #if canImport\(UIKit\)\n    @MainActor\n    func testRealHWPRowEditingSupportsUndoRedoAndSameFormatSave\b.*?    #endif/m, '')
  File.write(testpath, source)
  test.add_file_references([project.main_group.new_file(testpath)])
end
[app, test].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['SWIFT_DEFAULT_ACTOR_ISOLATION'] = 'MainActor'
    config.build_settings['SWIFT_APPROACHABLE_CONCURRENCY'] = 'YES'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'net.rivo.inlineqa.' + target.name
    config.build_settings['CODE_SIGNING_ALLOWED'] = device_signing ? 'YES' : 'NO'
    if device_signing
      config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
      config.build_settings['DEVELOPMENT_TEAM'] = development_team
    end
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['ENABLE_TESTABILITY'] = 'YES'
    config.build_settings['SWIFT_STRICT_CONCURRENCY'] = 'complete'
    config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
    config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
    config.build_settings['OTHER_LDFLAGS'] = ['$(inherited)', '-lz']
  end
end
app.build_configurations.each do |config|
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
end
test.build_configurations.each do |config|
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/InlineQA.app/InlineQA'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end
uitest = project.new_target(:ui_test_bundle, 'InlineQAUITests', :ios, '26.2')
uitest.add_dependency(app)
uitest.add_file_references([
  project.main_group.new_file(__dir__ + '/InlineQAUITests.swift'),
  project.main_group.new_file(__dir__ + '/Manual225Batch2UITests.swift'),
  project.main_group.new_file(__dir__ + '/Manual225Batch4UITests.swift'),
  project.main_group.new_file(__dir__ + '/Manual225Batch5UITests.swift')
])
uitest.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'net.rivo.inlineqa.uitests'
  config.build_settings['CODE_SIGNING_ALLOWED'] = device_signing ? 'YES' : 'NO'
  if device_signing
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['DEVELOPMENT_TEAM'] = development_team
  end
  config.build_settings['TEST_TARGET_NAME'] = 'InlineQA'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(test)
scheme.add_test_target(uitest)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'InlineQA', true)
