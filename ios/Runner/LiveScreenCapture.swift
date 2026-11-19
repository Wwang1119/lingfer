import AVFoundation
import AVKit
import Combine
import Flutter
import OSLog
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif
import SwiftUI
import UIKit
import Vision

protocol LiveCaptureDriving: AnyObject { func stop() }

private struct LivePreviewLine {
  let range: NSRange
  let rect: CGRect
}

/// Owns a visible, explicitly authorized screen-sharing session. Frames remain local.
final class LiveReadingSession: NSObject, ObservableObject {
  static let shared = LiveReadingSession()
  @Published var running = false
  @Published var preparing = false
  @Published var paused = false
  @Published var pictureInPictureActive = false
  @Published var activityMessage = ""
  @Published var activityActive = false
  @Published private(set) var presentationMode:LiveReadingPresentation = .floating
  private var presentation=LivePresentationPolicy()
  var floatingPreviewHidden:Bool {presentation.hidden}
  var preparingFloatingPreview:Bool {preparing && presentationMode == .floating}
  private var captureAuthorized=false
  private var mayStartFloatingPreview:Bool {
    presentation.wantsFloating && (running || preparing && captureAuthorized)
  }
  private var choseDefaultPresentation=false
  private var audioPreparing=false
  private var audioReady=false
  private var previewAudioWanted=false
  private var activityDetailIndex=0
  private var activityActions=0
  let diagnosticsEnabled=ProcessInfo.processInfo.arguments.contains("--lingfer-live-qa") || ProcessInfo.processInfo.environment["LINGFER_LIVE_QA"] == "1"
  private var lastActivityDetailKey=""
  private var deferredLiveText:String?
  @Published var message = "开启系统读屏后，切换到想阅读的 App。"
  @Published private(set) var previewQAState = ""
  @Published private(set) var lastBackgroundDiagnostics = ""
  @Published private(set) var captureSummary = "等待识别屏幕上的正文"
  @Published private(set) var captureCoverageNotice = "仅识别当前屏幕；未滚动到的内容不会自动读取。"
  private var sourceReadyForPreview=false
  private var acceptedViewportPage=0
  private var firstBodyKey=""
  private var firstBodyConfirmations=0
  private var startupLineCount=0
  private var startupCharacterCount=0
  private var startupOCRPasses=0
  private var startupOCRErrorCode=0
  private var startupAudioErrorCode=0
  private var startupAudioResult=0
  private var startupPiPErrorCode=0
  private var startupCaptureErrorCode=0
  private var receivedCaptureFrame=false
  private var pipStartsOutsideActive=0
  private var startupAttempt=0
  private var startupTime:TimeInterval=0
  private static let startupLog=Logger(subsystem:"com.wang.yudu",category:"LiveReadingStartup")
  private var lastStartupDiagnosticsAt:TimeInterval=0
  private var startupTask:UIBackgroundTaskIdentifier = .invalid
  private var startupTaskAttempted=false
  private var startupTaskGeneration=0
  private var startupTaskTimeout:DispatchWorkItem?
  let model = ShareReadingModel()
  private let activityVocabulary=ShareReadingModel()
  private var activityVocabularyKey:LiveVocabularyRequestKey?
  private var selectedActivityWordID:String?
  let previewLayer = AVSampleBufferDisplayLayer()
  var sink: FlutterEventSink?
  private var driver: LiveCaptureDriving?
  private var subscriptions = Set<AnyCancellable>()
  private var controller: UIViewController?
  private var pip: AVPictureInPictureController?
  private var pipObservation:NSKeyValueObservation?
  private var previewTimebase:CMTimebase?
  private var previewPlayback:LivePreviewPlayback?
  private var previewPlaybackPaused=false
  private var previewSkipActions=0
  private var previewInteractionUntil:TimeInterval=0
  private var pipRequested=false
  private var pipStarting=false
  private var pipStopRequested=false
  private var previewRequestTimeout:DispatchWorkItem?
  private var renderScheduled=false
  private var pendingRenderWords:[ShareWord]?
  private var previewHeartbeat: DispatchSourceTimer?
  private var previewSourceView:UIView?
  private weak var pendingPreviewView:UIView?
  private var previewRecoveries=0
  private var previewStarts=0
  private let frameQueue = DispatchQueue(label:"lingfer.live.frames",qos:.userInitiated)
  private var lastScan: TimeInterval = 0
  private var scanBusy = false
  private var lastText = ""
  private var sequence = 0
  private var startedAt: TimeInterval = 0
  private var epoch = 0
  private var previewSourceText = ""
  private var previewLines: [LivePreviewLine] = []
  private var previewFocus = 0
  private var previewContextDescription = "等待阅读页面"
  private var acceptedPages = 0
  private var viewport=LiveReadingViewport()
  private var viewportPage=0
  private var viewportSettled=true
  private var selectedWordID:String?
  private var selectedTranslationID:String?
  private var manualSelection=false
  private var selectionMovement:CGFloat=0
  private var selectionAnchor=LiveSelectionAnchorTracker()
  private var selectionAnchorSource=""
  private var missingAnchorFrames=0
  private var translationIndex=0
  private var transientControlsVisible=false
  private struct TranslationLayoutInput:Hashable {let source:String;let translation:String?}
  private var translationLayoutInputs:[TranslationLayoutInput]=[]
  private var translationLayoutPages:[TranslationPage]=[]
  private var translationMeasurements:[TranslationLayoutInput:([String],[String])]=[:]
  // Accessed only on frameQueue. AVKit controls can briefly obscure the marker.
  private var lastPreviewMasks:[CGRect] = []
  private var lastPreviewMaskTime:TimeInterval = 0
  private var lastPreviewMaskEpoch = -1

  override init() {
    super.init()
    if diagnosticsEnabled {preserveOrRestoreQAState();model.refreshAIConsent();activityVocabulary.refreshAIConsent()}
    model.source="实时读屏";model.loading=false
    activityVocabulary.readingMode="learning";activityVocabulary.loading=false;activityVocabulary.persistsSource=false
    activityVocabulary.$words.receive(on:DispatchQueue.main).sink { [weak self] words in
      guard let self,self.running,self.separatesActivityVocabulary else{return}
      self.updateActivity(companionWords:words)
    }.store(in:&subscriptions)
    model.onPageChange={ [weak self] in
      guard let self,self.running,self.model.readingMode == "translation" else {return}
      self.render(words:[])
      self.updateActivity()
      self.emit(["kind":"translation","text":self.model.text,"translationSegments":self.model.pageParts.map{$0.json},"translationLoading":self.model.loading,"translationError":self.model.error as Any? ?? NSNull()])
    }
    model.onStoreChange={ [weak self] in self?.emit(["kind":"changed"]) }
    model.$loading.receive(on:DispatchQueue.main).sink { [weak self] _ in
      guard let self,self.running else{return}
      self.refreshCaptureSummary();self.render(words:self.model.words);self.updateActivity()
    }.store(in:&subscriptions)
    previewLayer.videoGravity = .resizeAspect
    model.$words.receive(on:DispatchQueue.main).sink { [weak self] words in
      guard let self else {return}
      // Published values arrive before the model property itself is assigned.
      self.publish(words:words)
      self.render(words:words)
      self.updateActivity(words:words)
    }.store(in:&subscriptions)
    model.$error.receive(on:DispatchQueue.main).sink { [weak self] value in
      guard let self,let value else{return}
      self.message=value;self.emit(["kind":"error","message":value])
      self.updateActivity()
    }.store(in:&subscriptions)
    for name in [UIApplication.didEnterBackgroundNotification,UIApplication.didBecomeActiveNotification,
      .AVSampleBufferDisplayLayerRequiresFlushToResumeDecodingDidChange,
      .AVSampleBufferDisplayLayerFailedToDecode] {
      NotificationCenter.default.publisher(for:name).receive(on:DispatchQueue.main).sink { [weak self] note in
        guard let self,self.running || self.preparingFloatingPreview else{return}
        if note.name == UIApplication.didBecomeActiveNotification {
          self.recordStartupDiagnostics("foreground",force:true)
          if self.previewRequestTimeout != nil {self.clearPreviewRequest()}
          if self.presentation.wantsFloating,self.pip?.isPictureInPictureActive == true {
            self.presentation.restoreInline();self.stopPreviewForTransition()
          }
        }
        self.refreshPreviewIfNeeded();self.render(words:self.model.words)
      }.store(in:&subscriptions)
    }
    NotificationCenter.default.publisher(for:UIApplication.didEnterBackgroundNotification).receive(on:DispatchQueue.main).sink { [weak self] _ in
      guard let self,(self.running || self.preparing),self.presentation.wantsFloating else{return}
      self.recordStartupDiagnostics("background",force:true)
      self.armStartupTaskTimeout()
      self.requestAutomaticPreview()
    }.store(in:&subscriptions)
  }

  var supported: Bool {
    #if canImport(ScreenCaptureKit)
    if #available(iOS 27.0, *) {return true}
    #endif
    return false
  }
  func status()->[String:Any] {
    var value=CompanionStore.status()
    value.merge(["supported":supported,"running":running,"paused":paused,"captureMessage":message,
      "pictureInPictureSupported":AVPictureInPictureController.isPictureInPictureSupported(),"pictureInPictureActive":pictureInPictureActive,
      "liveActivityActive":activityActive,"liveActivityMessage":activityMessage]) {_,new in new}
    // A newly created live model is empty. While stopped, a share extension may
    // have written a newer document; preserve that coordinated App Group state.
    if running {
      value.merge(["detectedLanguage":model.effectiveSource,"lastText":model.text,
        "translationSegments":model.pageParts.map{$0.json},"translationLoading":model.loading,"translationError":model.error as Any? ?? NSNull(),
        "lastHits":encodedWords(model.words),"lastOptionsSignature":signature]) {_,new in new}
    }
    return value
  }
  private var signature:String {"\(model.sourceLanguage)|\(model.targetLanguage)|\(model.level)|\(model.difficulty)\(model.readingMode == "translation" ? "|translation" : "")"}
  private func encodedWords(_ words:[ShareWord])->String {
    (try? String(data:JSONEncoder().encode(words),encoding:.utf8)) ?? "[]"
  }
  private func emit(_ event:[String:Any]) {sink?(event)}
  private func publish(words:[ShareWord]) {
    guard running else{return}
    refreshCaptureSummary(words:words)
    let json=(try? JSONEncoder().encode(words)) ?? Data("[]".utf8)
    let hits=(try? JSONSerialization.jsonObject(with:json)) ?? []
    CompanionStore.defaults.merge(["lastHits":String(data:json,encoding:.utf8) ?? "[]","lastOptionsSignature":signature,"lastDetectedLanguage":model.effectiveSource])
    emit(["kind":"capture","text":model.text,"hits":hits,"detectedLanguage":model.effectiveSource,"durationMs":Int((Date.timeIntervalSinceReferenceDate-startedAt)*1000)])
  }
  private func refreshCaptureSummary(words:[ShareWord]?=nil) {
    let characters=(deferredLiveText ?? model.text).filter{!$0.isWhitespace}.count
    if model.readingMode == "translation" {
      let completed=model.pageParts.filter{$0.translation != nil}.count
      captureSummary="已识别 \(characters) 字 · 对照 \(completed)/\(model.pageParts.count) 组"
    } else {captureSummary="已识别 \(characters) 字 · 当前范围 \((words ?? model.words).count) 词"}
  }
  private func preserveOrRestoreQAState() {
    // Keep fixture reading from replacing the user's previous reading. This
    // backup stays in the app's own coordinated store and excludes credentials.
    let defaults=CompanionStore.defaults,key="liveFixtureStateBackupV1"
    let keys=["lastText","lastHits","lastOptionsSignature","lastDetectedLanguage","lastTranslationSegments","lastTranslatedText","lastTranslationSource","lastTranslationTarget","lastDocumentUpdatedAt","liveReadingHistoryV1","level","sourceLanguage","targetLanguage","generalDifficulty","automatic","readingMode"]
    let arguments=ProcessInfo.processInfo.arguments
    let consentKeys=["aiConsentVersion","aiConsentAllowed"]
    let flutterConsentKeys=["flutter.companion_ai_consent_version_v1","flutter.companion_ai_consent_allowed_v1"]
    let flutterKeys=["flutter.companion_level_v1","flutter.companion_reading_preferences_v1","flutter.companion_last_live_reading_v1"]
    let publicFixture=diagnosticsEnabled && arguments.contains("--qa-preserve-reading") && arguments.contains("--qa-public-reading-fixture")
    if arguments.contains("--qa-preserve-reading") {
      let existing=defaults.string(forKey:key).flatMap{$0.data(using:.utf8)}.flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}
      var snapshot=existing ?? defaults.snapshot().filter{keys.contains($0.key)}
      if existing == nil {
        snapshot["_flutter"]=flutterKeys.reduce(into:[String:Any]()) { values,name in
          if let value=UserDefaults.standard.object(forKey:name) {values[name]=value}
        }
      }
      if publicFixture,snapshot["_aiConsentBackupVersion"] as? Int != 1 {
        // A missing dictionary entry records actual absence, not false/null.
        // Older reading backups can be extended before the first AI fixture.
        snapshot["_aiConsentBackupVersion"]=1
        snapshot["_aiConsent"]=defaults.snapshot().filter{consentKeys.contains($0.key)}
        snapshot["_flutterAIConsent"]=flutterConsentKeys.reduce(into:[String:Any]()) { values,name in
          if let value=UserDefaults.standard.object(forKey:name) {values[name]=value}
        }
      }
      guard let data=try? JSONSerialization.data(withJSONObject:snapshot),let raw=String(data:data,encoding:.utf8),defaults.set(raw,forKey:key) else{return}
      if publicFixture {
        // Explicit public-fixture automation only. A diagnostic launch or
        // a user's real screen-sharing authorization is never AI consent.
        if CompanionStore.setAIConsent(allowed:true) {
          UserDefaults.standard.set(CompanionStore.aiConsentVersion,forKey:flutterConsentKeys[0])
          UserDefaults.standard.set(true,forKey:flutterConsentKeys[1])
        }
      }
    }
    if arguments.contains("--qa-restore-reading"),let raw=defaults.string(forKey:key),let data=raw.data(using:.utf8),let saved=try? JSONSerialization.jsonObject(with:data) as? [String:Any] {
      var values:[String:Any]=keys.reduce(into:[:]){$0[$1]=""}
      values.merge(saved.filter{keys.contains($0.key)}){_,new in new};values[key]=""
      var removing:[String]=[]
      let restoresConsent=saved["_aiConsentBackupVersion"] as? Int == 1
      if restoresConsent {
        let original=saved["_aiConsent"] as? [String:Any] ?? [:]
        for name in consentKeys {
          if let value=original[name] {values[name]=value} else {removing.append(name)}
        }
      }
      guard defaults.merge(values,removing:removing) else{return}
      let flutter=saved["_flutter"] as? [String:Any] ?? [:]
      for name in flutterKeys {
        if let value=flutter[name] {UserDefaults.standard.set(value,forKey:name)} else {UserDefaults.standard.removeObject(forKey:name)}
      }
      if restoresConsent {
        let original=saved["_flutterAIConsent"] as? [String:Any] ?? [:]
        for name in flutterConsentKeys {
          if let value=original[name] {UserDefaults.standard.set(value,forKey:name)} else {UserDefaults.standard.removeObject(forKey:name)}
        }
        NotificationCenter.default.post(name:Notification.Name("lingferAIConsentChanged"),object:nil)
      }
    }
  }
  func configure() {
    let defaults=CompanionStore.defaults
    let before=signature
    model.readingMode=defaults.string(forKey:"readingMode") ?? "learning"
    model.level=defaults.string(forKey:"level") ?? "cet4"
    model.sourceLanguage=defaults.string(forKey:"sourceLanguage") ?? "auto"
    model.targetLanguage=defaults.string(forKey:"targetLanguage") ?? "zh"
    model.difficulty=defaults.string(forKey:"generalDifficulty") ?? "intermediate"
    if running,!model.text.isEmpty,before != signature { model.accept(model.text,source:"实时读屏") }
  }
  func open(from presenter:UIViewController,completion:(()->Void)? = nil) {
    configure()
    if !choseDefaultPresentation {
      choseDefaultPresentation=true
      let saved=UserDefaults.standard.string(forKey:"lingfer.livePresentation")
      let value=saved.flatMap(LiveReadingPresentation.init(rawValue:)) ?? .floating
      presentation.select(value);presentationMode=value
    }
    if let controller {
      if controller.presentingViewController == nil {presenter.present(controller,animated:true,completion:completion)}
      else {completion?()}
      return
    }
    let host=UIHostingController(rootView:LiveReadingHost(session:self))
    host.overrideUserInterfaceStyle = .light
    host.modalPresentationStyle = .pageSheet
    controller=host;presenter.present(host,animated:true,completion:completion)
  }
  func dismiss() {
    if preparing {cancelPreparation()}
    controller?.dismiss(animated:true)
  }
  func start() {
    guard !running else {setPaused(false);return}
    guard !preparing else{return}
    #if canImport(ScreenCaptureKit)
    guard #available(iOS 27.0, *) else {message="实时读屏需要 iOS 27 或以上；当前系统可继续使用分享和截图阅读。";return}
    pipObservation=nil;pip=nil;pipStarting=false;pipStopRequested=false
    clearPreviewRequest()
    startupAttempt += 1;startupTime=ProcessInfo.processInfo.systemUptime
    captureAuthorized=false;receivedCaptureFrame=false
    sequence=0;previewStarts=0;pipStartsOutsideActive=0
    sourceReadyForPreview=false
    firstBodyKey="";firstBodyConfirmations=0
    startupLineCount=0;startupCharacterCount=0;startupOCRPasses=0;startupOCRErrorCode=0
    startupPiPErrorCode=0;startupCaptureErrorCode=0;startupAudioErrorCode=0;startupAudioResult=0
    lastBackgroundDiagnostics="";lastStartupDiagnosticsAt=0
    startupTaskAttempted=false
    presentation.select(presentationMode)
    message="请在系统面板选择共享整个屏幕。"
    preparing=true
    if preparingFloatingPreview {beginStartupTask();preparePreviewAudio()}
    // Request the activity while our UI is visible, before the system picker
    // takes focus. Cancellation tears it down; it never authorizes capture.
    if #available(iOS 16.2, *),presentationMode == .island {
      let waiting=ReadingActivityAttributes.ContentState.preview(paused:false,mode:model.readingMode,count:0,terms:[],status:"等待系统屏幕共享授权")
      activityMessage=ReadingActivityManager.shared.start(waiting) ?? "长按灵动岛可翻页、暂停或停止；通知中心也可操作。"
      activityActive=ReadingActivityManager.shared.active
    }
    let capture=SystemScreenCapture(session:self)
    driver=capture
    recordStartupDiagnostics("picker-present",force:true)
    capture.present()
    #else
    message="系统读屏需要在 iOS 27 或以上的 iPhone 真机开启；模拟器可验证分享和截图阅读。"
    #endif
  }
  func cancelPreparation(message:String="已取消系统读屏授权。") {
    recordStartupDiagnostics("picker-cancelled",force:true)
    endStartupTask("startup-cancelled")
    clearPreviewRequest()
    pip?.canStartPictureInPictureAutomaticallyFromInline=false
    stopPreviewForTransition()
    let capture=driver;driver=nil;preparing=false;captureAuthorized=false
    capture?.stop();releasePreviewAudio()
    pipObservation=nil;pip=nil;pipStarting=false;pictureInPictureActive=false
    previewLayer.flushAndRemoveImage()
    if #available(iOS 16.2, *) {ReadingActivityManager.shared.end()}
    activityActive=false;activityMessage="";self.message=message
  }
  func didAuthorizeCapture() {
    captureAuthorized=true
    recordStartupDiagnostics("picker-authorized",force:true)
    // The filter is the user's authorization. Arm PiP here because the capture
    // completion handler can arrive after the user has already switched apps.
    if preparingFloatingPreview,sequence==0 {renderNow(words:[])}
    requestAutomaticPreview()
  }
  func didStart() {
    guard preparing else{return}
    epoch += 1
    previewPlayback=nil;previewSkipActions=0;previewInteractionUntil=0
    acceptedViewportPage=0
    captureSummary="正在读取屏幕正文…";captureCoverageNotice="仅识别当前屏幕；浮窗遮挡的区域可移开后补读。"
    running=true;preparing=false;paused=false;lastText=""
    previewSourceText="";previewLines=[];previewFocus=0;acceptedPages=0
    viewport=LiveReadingViewport();viewportPage=0;viewportSettled=true;selectedWordID=nil;selectedTranslationID=nil;manualSelection=false;missingAnchorFrames=0
    selectionMovement=0;transientControlsVisible=false;previewRecoveries=0;translationIndex=0
    selectionAnchor.reset();selectionAnchorSource=""
    activityDetailIndex=0;activityActions=0;lastActivityDetailKey="";deferredLiveText=nil
    activityVocabularyKey=nil;selectedActivityWordID=nil
    activityVocabulary.words=[];activityVocabulary.loading=false
    model.preservesLiveResults=true
    model.liveTranslationSentenceLimit=2
    model.beginLiveHistory()
    if !pictureInPictureActive {
      message=presentationMode == .island ? "读屏已开启，切换到阅读 App 后，长按灵动岛或从通知中心查看。" : "读屏已开启，切换到阅读 App，停稳后自动识别正文。"
    }
    recordStartupDiagnostics("capture-started",force:true)
    if presentation.wantsFloating {
      beginStartupTask()
      if let view=pendingPreviewView {attachPreview(to:view)}
      renderNow(words:[])
      requestAutomaticPreview()
    }
    updateActivity()
    previewHeartbeat?.cancel()
    let heartbeat=DispatchSource.makeTimerSource(queue:.main)
    heartbeat.schedule(deadline:.now(),repeating:1,leeway:.milliseconds(120))
    heartbeat.setEventHandler { [weak self] in
      guard let self,self.running else{return}
      self.render(words:self.model.words)
      self.updateActivity()
      self.recordStartupDiagnostics("heartbeat")
    }
    previewHeartbeat=heartbeat;heartbeat.resume()
    emit(["kind":"status","running":true,"paused":false])

  }
  func captureFailed(_ error:Error) {
    startupCaptureErrorCode=(error as NSError).code
    recordStartupDiagnostics("capture-failed",force:true)
    stop()
    message="读屏已结束：\(error.localizedDescription)"
    emit(["kind":"status","running":false,"paused":false]);emit(["kind":"error","message":message])
  }
  func setPaused(_ value:Bool) {
    guard running else{return}
    paused=value;message=value ? "已暂停识别，浮窗与灵动岛保留当前结果。" : "正在随屏识别。"
    pip?.invalidatePlaybackState()
    render(words:model.words);updateActivity()
    emit(["kind":"status","running":running,"paused":paused])
  }
  func stop() {
    endStartupTask("startup-stop")
    model.finishLiveHistory()
    epoch += 1
    let current=driver;driver=nil;running=false;preparing=false;paused=false;captureAuthorized=false
    pip?.canStartPictureInPictureAutomaticallyFromInline=false
    current?.stop();model.cancel();activityVocabulary.cancel();activityVocabulary.loading=false;stopPreviewForTransition()
    clearPreviewRequest();pipStarting=false
    previewHeartbeat?.cancel();previewHeartbeat=nil
    if #available(iOS 16.2, *) {ReadingActivityManager.shared.end()}
    activityActive=false;activityMessage=""
    pictureInPictureActive=false
    presentation.select(presentationMode);deferredLiveText=nil
    previewLines=[];previewSourceText=""
    selectionAnchor.reset();selectionAnchorSource="";selectionMovement=0
    model.loading=false
    previewLayer.flushAndRemoveImage()
    previewPlayback=nil
    releasePreviewAudio()
    message="读屏已停止，捕获资源已释放。"
    frameQueue.async {self.lastScan=0;self.scanBusy=false;self.lastPreviewMasks=[];self.lastPreviewMaskTime=0;self.lastPreviewMaskEpoch = -1}
    emit(["kind":"status","running":false,"paused":false])
  }
  func receive(_ sample:CMSampleBuffer,isCurrentCapture:@escaping()->Bool) {
    guard let pixel=CMSampleBufferGetImageBuffer(sample) else{return}
    frameQueue.async { [weak self] in
      guard let self else{return}
      let now=Date.timeIntervalSinceReferenceDate
      guard now-self.lastScan>=0.6,!self.scanBusy else{return}
      self.scanBusy=true
      DispatchQueue.main.async {
        guard isCurrentCapture() else {self.frameQueue.async{self.scanBusy=false};return}
        if !self.receivedCaptureFrame {
          self.receivedCaptureFrame=true
          self.recordStartupDiagnostics("capture-first-frame",force:true)
        }
        // Capturing our own reader would feed its translations back into OCR.
        guard self.running,!self.paused,UIApplication.shared.applicationState == .background else {self.frameQueue.async{self.scanBusy=false};return}
        // AVKit's controls and PiP restoration change the visible occlusion,
        // not the article. Do not replace the card during that brief transition.
        guard Date.timeIntervalSinceReferenceDate>=self.previewInteractionUntil else {self.frameQueue.async{self.scanBusy=false};return}
        let language=self.model.sourceLanguage
        let token=self.epoch
        let floating=self.pictureInPictureActive
        self.frameQueue.async {
          self.lastScan=now
          self.recognize(pixel,language:language,epoch:token,floating:floating)
        }
      }
    }
  }
  private func recognize(_ pixel:CVPixelBuffer,language:String,epoch:Int,floating:Bool) {
    defer {scanBusy=false}
    let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.usesLanguageCorrection=false;request.minimumTextHeight=0.003
    request.regionOfInterest=CGRect(x:0,y:0,width:1,height:1)
    let supported=(try? request.supportedRecognitionLanguages()) ?? ["en-US","zh-Hans"]
    let map=["en":"en-US","zh":"zh-Hans","ja":"ja-JP","ko":"ko-KR","fr":"fr-FR","de":"de-DE","es":"es-ES","pt":"pt-BR","it":"it-IT","hi":"hi-IN"]
    request.recognitionLanguages=(map[language].map{[$0]} ?? ["en-US","zh-Hans","ja-JP","ko-KR","fr-FR","de-DE","es-ES","pt-BR","it-IT"]).filter{supported.contains($0)}
    // The functional footer is Chinese even for an English/Japanese article.
    // Recognize that local UI marker too so it can never become source text.
    if supported.contains("zh-Hans"),!request.recognitionLanguages.contains("zh-Hans") {request.recognitionLanguages.append("zh-Hans")}
    if #available(iOS 16.0, *) {request.automaticallyDetectsLanguage=language=="auto"}
    do {
      try VNImageRequestHandler(cvPixelBuffer:pixel,options:[:]).perform([request])
      let observations=request.results ?? []
      let visible=observations.compactMap{$0.topCandidates(1).first?.string}.joined(separator:" ")
      let compactVisible=LiveViewportLine.key(visible)
      if compactVisible.contains("lingfercard") {return}
      if compactVisible.contains("语渡随屏阅读"),compactVisible.contains("词卡") {return}
      // An expanded island/Lock Screen card is our controller, not a newly
      // opened article. Keep the reading result instead of translating it back.
      if visible.contains("语渡"),visible.contains("词卡"),visible.contains("停止"),
         visible.contains("暂停") || visible.contains("继续") { return }
      // The preview identifies itself, so its floating video isn't read as source text.
      let markers=floating ? observations.filter{observation in
        guard let title=observation.topCandidates(1).first?.string else{return false}
        let key=LiveViewportLine.key(title)
        return title.count<70 && (key.hasPrefix("点浮窗") || key.hasPrefix("lingfer"))
      } : []
      let detectedMasks=markers.map { marker -> CGRect in
        var box=marker.boundingBox
        var title=marker.topCandidates(1).first?.string ?? "点浮窗"
        let legacy=LiveViewportLine.key(title).hasPrefix("lingfer")
        if !legacy,let candidate=marker.topCandidates(1).first,let range=candidate.string.range(of:"点浮窗"),
           let located=try? candidate.boundingBox(for:range) {
          box=located.boundingBox;title="点浮窗"
        }
        let titleWidth=(title as NSString).size(withAttributes:[.font:UIFont.systemFont(ofSize:legacy ? 26 : 20,weight:legacy ? .semibold : .regular)]).width
        let width=min(1,box.width*800/titleWidth)
        let height=width*CGFloat(CVPixelBufferGetWidth(pixel))/CGFloat(CVPixelBufferGetHeight(pixel))*500/800
        let top=box.maxY+height*(legacy ? 20 : 464)/500
        return CGRect(x:box.minX-width*(legacy ? 225 : 28)/800,y:top-height,width:width,height:height).insetBy(dx:-0.012,dy:-0.012)
      }
      let now=Date.timeIntervalSinceReferenceDate
      if lastPreviewMaskEpoch != epoch {lastPreviewMasks=[];lastPreviewMaskTime=0;lastPreviewMaskEpoch=epoch}
      if !floating {lastPreviewMasks=[];lastPreviewMaskTime=0}
      if !detectedMasks.isEmpty {lastPreviewMasks=detectedMasks;lastPreviewMaskTime=now}
      // Keep the last measured exclusion briefly while the system playback
      // controls fade. Do not read our own translated video back as a new page.
      let masks = !detectedMasks.isEmpty ? detectedMasks : floating && now-lastPreviewMaskTime<8 ? lastPreviewMasks : []
      var previousBox:CGRect?
      let raw=observations.compactMap { observation -> LiveViewportLine? in
        guard let value=observation.topCandidates(1).first?.string else{return nil}
        let box=observation.boundingBox
        let paragraph=previousBox.map{$0.minY-box.maxY>max($0.height,box.height)*1.6 || box.minY>$0.maxY} ?? false
        previousBox=box
        return LiveViewportLine(text:(paragraph ? "\n" : "")+value,rect:box)
      }
      // Keep visible columns beside the PiP; exclude only its real rectangle.
      let incoming=LiveReadingContent.visible(raw,excluding:masks)
      if LiveReadingViewport.hasSelectionToolbar(incoming) {
        DispatchQueue.main.async {
          guard self.running,!self.paused,self.epoch==epoch else{return}
          self.transientControlsVisible=true;self.message="选词菜单显示中，保留当前阅读位置。";self.render(words:self.model.words)
        }
        return
      }
      DispatchQueue.main.async {
        guard self.running,!self.paused,self.epoch == epoch else{return}
        guard Date.timeIntervalSinceReferenceDate>=self.previewInteractionUntil else{return}
        self.transientControlsVisible=false
        if self.diagnosticsEnabled {
          self.startupOCRPasses += 1
          self.startupLineCount=incoming.count
          self.startupCharacterCount=incoming.reduce(0){$0+$1.key.count}
        }
        if !self.sourceReadyForPreview {
          guard LiveReadingContent.hasReadingBody(incoming) else {
            self.captureSummary="正在等待可读正文…";return
          }
          let key=incoming.map{$0.key}.joined(separator:"|")
          if key==self.firstBodyKey {self.firstBodyConfirmations += 1} else {self.firstBodyKey=key;self.firstBodyConfirmations=1}
        }
        let snapshot=self.viewport.update(incoming)
        let key=snapshot.text.components(separatedBy:.whitespacesAndNewlines).filter{!$0.isEmpty}.joined(separator:" ")
        // A different OCR snapshot can result from the PiP controls hiding
        // lines. Keep the selected result until we actually accept new source;
        // otherwise a geometry-only page change discards a manual selection
        // before the overlap/visible-anchor checks have a chance to retain it.
        self.viewportPage=snapshot.page
        self.viewportSettled=snapshot.settled
        self.captureCoverageNotice = masks.isEmpty ? "仅含屏幕上已读到的正文；未滚动到的内容不在本次识别范围。" : "浮窗遮住的新文字可能尚未读到；移开浮窗后会自动补读。"
        self.previewSourceText=String(snapshot.text.prefix(12000))
        let length=(self.previewSourceText as NSString).length
        self.previewLines=snapshot.lines.filter{NSMaxRange($0.0)<=length}.map{LivePreviewLine(range:$0.0,rect:$0.1)}
        if !self.model.text.isEmpty {
          let projection=LiveSourceProjection(self.model.text)
          let current=self.previewSourceText as NSString
          self.previewLines=self.previewLines.compactMap { line in
            projection.range(of:current.substring(with:line.range)).map{LivePreviewLine(range:$0,rect:line.rect)}
          }
          self.previewSourceText=self.model.text
        }
        if self.selectionAnchorSource != self.model.text {self.pinSelectionGeometry()}
        if let movement=self.selectionAnchor.netMovement(in:self.previewLines.map{($0.range,$0.rect)}) {
          self.selectionMovement=abs(movement)
          if self.selectionMovement>0.10 {self.manualSelection=false}
        }
        if snapshot.settled {self.alignSelectionToViewport()}
        self.render(words:self.model.words)
        self.updateActivity()
        guard snapshot.settled,!key.isEmpty else{return}
        if key == self.lastText {
          self.deferredLiveText=nil;self.refreshCaptureSummary();return
        }
        // Adding a few newly exposed lines must not cancel an in-flight
        // translation, clear the card or retranslate the whole overlapping page.
        let mapped=self.previewLines.count
        let visibleKnown=Double(mapped)/Double(max(1,snapshot.lines.count))
        let samePage=self.sourceReadyForPreview && self.acceptedViewportPage==snapshot.page
        let stillReading=samePage && (self.model.readingMode == "translation" ? self.selectedTranslationID != nil && visibleKnown>=0.45 : self.model.words.contains{self.rect(of:$0) != nil} && visibleKnown>=0.45)
        let meaningfulAddition=LiveReadingContent.addedCharacters(from:self.model.text,to:snapshot.text)>=12
        if self.model.loading {
          self.deferredLiveText=snapshot.text
          self.refreshCaptureSummary()
          return
        }
        if stillReading && !meaningfulAddition {
          self.deferredLiveText=nil;self.refreshCaptureSummary();return
        }
        self.deferredLiveText=nil
        self.lastText=key
        if !samePage {
          self.selectedWordID=nil;self.selectedTranslationID=nil;self.manualSelection=false
          self.missingAnchorFrames=0;self.selectionMovement=0
          self.selectionAnchor.reset();self.selectionAnchorSource=""
        }
        self.sourceReadyForPreview=true;self.acceptedViewportPage=snapshot.page
        self.acceptedPages += 1
        self.startedAt=Date.timeIntervalSinceReferenceDate
        self.model.liveHistoryPageKey="\(epoch):\(snapshot.page)"
        self.model.accept(snapshot.text,source:"实时读屏 · 原文留在本机")
        self.refreshCaptureSummary()
        if self.acceptedPages==1 {self.recordStartupDiagnostics("first-reading-body",force:true)}
        self.message="已更新当前页面。"
        self.updateActivity()
      }
    } catch {
      let code=(error as NSError).code
      DispatchQueue.main.async {if self.running {self.startupOCRErrorCode=code;self.message="当前画面暂未读清，停稳后会自动重试。"}}
    }
  }

  func attachPreview(to view:UIView) {
    // SwiftUI can measure a replacement view off-window or at zero size during
    // scene transitions. Never steal the active PiP layer into that placeholder.
    guard running || preparingFloatingPreview,view.window != nil,view.bounds.width>1,view.bounds.height>1 else{return}
    pendingPreviewView=view
    if (pip?.isPictureInPictureActive == true || pipStarting),previewSourceView !== view {return}
    let attachmentChanged=previewSourceView !== view || previewLayer.superlayer !== view.layer || previewLayer.frame != view.bounds
    previewSourceView=view
    if previewLayer.superlayer !== view.layer {previewLayer.removeFromSuperlayer();view.layer.addSublayer(previewLayer)}
    previewLayer.frame=view.bounds
    if attachmentChanged {recordStartupDiagnostics("attach",force:true)}
    if pip == nil,AVPictureInPictureController.isPictureInPictureSupported() {
      synchronizePreviewPlayback(count:model.readingMode == "translation" ? translationPages.count : model.words.count,position:previewFocus)
      let source=AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer:previewLayer,playbackDelegate:self)
      pip=AVPictureInPictureController(contentSource:source);pip?.delegate=self
      pip?.canStartPictureInPictureAutomaticallyFromInline=mayStartFloatingPreview
      pip?.requiresLinearPlayback = !(previewPlayback?.canSkip == true && previewTimebase != nil)
      pipObservation=pip?.observe(\.isPictureInPicturePossible,options:[.new]) { [weak self] controller,_ in
        DispatchQueue.main.async {
          guard let self,controller === self.pip else{return}
          self.recordStartupDiagnostics("pip-possible-changed",force:true)
          self.startQueuedPreviewIfPossible()
        }
      }
      recordStartupDiagnostics("pip-controller-created",force:true)
    }
    if attachmentChanged || sequence==0 {render(words:model.words)}
    startQueuedPreviewIfPossible()
  }
  func previewLeftWindow(_ view:UIView) {
    if previewSourceView === view {recordStartupDiagnostics("preview-detached",force:true)}
  }
  private func clearPreviewRequest() {
    pipRequested=false
    previewRequestTimeout?.cancel();previewRequestTimeout=nil
  }
  private func startQueuedPreviewIfPossible() {
    guard mayStartFloatingPreview,pipRequested,!pipStarting,
          UIApplication.shared.applicationState == .background else{return}
    if previewRequestTimeout == nil {
      let timeout=DispatchWorkItem { [weak self] in
        guard let self,self.pipRequested else{return}
        self.recordStartupDiagnostics("pip-request-timeout",force:true)
        self.clearPreviewRequest()
        self.endStartupTask("startup-unavailable")
        self.message="翻译浮窗未能自动打开，请点“显示翻译浮窗”重试。"
      }
      previewRequestTimeout=timeout
      DispatchQueue.main.asyncAfter(deadline:.now()+8,execute:timeout)
    }
    guard let pip,!pip.isPictureInPictureActive,pip.isPictureInPicturePossible,audioReady,sequence>0,
          previewSourceView?.window != nil else{return}
    clearPreviewRequest();pipStarting=true
    recordStartupDiagnostics("pip-start-requested",force:true)
    pip.startPictureInPicture()
  }
  private func stopPreviewForTransition() {
    guard let pip,pip.isPictureInPictureActive || pipStarting else{return}
    pipStopRequested=true;pip.stopPictureInPicture()
  }
  private func requestAutomaticPreview() {
    guard mayStartFloatingPreview else{return}
    // The system can promote the waiting card when the app leaves the foreground.
    // OCR only starts after that transition and updates the card independently.
    pip?.canStartPictureInPictureAutomaticallyFromInline=true
    preparePreviewAudio()
    if pip?.isPictureInPictureActive == true || pipStarting {clearPreviewRequest();return}
    if !pipRequested {
      pipRequested=true
      recordStartupDiagnostics("pip-queued",force:true)
    }
    startQueuedPreviewIfPossible()
  }
  func startPictureInPicture() {
    guard running else {message="请先开启系统读屏。";return}
    if startupTask == .invalid {startupTaskAttempted=false;beginStartupTask()}
    guard AVPictureInPictureController.isPictureInPictureSupported() else {message="这台设备暂不支持画中画，可从通知中心的语渡实时活动查看摘要。";return}
    if presentationMode != .floating || !presentation.wantsFloating {setPresentation(.floating);return}
    if UIApplication.shared.applicationState == .background,pip?.isPictureInPictureActive == true {
      recoverPreview();message="已重新绘制浮窗，原文与阅读位置保留。";return
    }
    render(words:model.words)
    pip?.invalidatePlaybackState()
    message=UIApplication.shared.applicationState == .background ? "正在开启画中画…" : "浮窗已准备，切换至阅读 App 后自动显示。"
    requestAutomaticPreview()
  }
  func setPresentation(_ mode:LiveReadingPresentation) {
    // Re-selecting the visible segment must not tear down and recreate AVKit,
    // ActivityKit or the audio session while their prior transition is pending.
    guard !preparing,mode != presentationMode || presentation.hidden else{return}
    presentation.select(mode);presentationMode=mode
    UserDefaults.standard.set(mode.rawValue,forKey:"lingfer.livePresentation")
    pip?.canStartPictureInPictureAutomaticallyFromInline=running && presentation.wantsFloating
    if running {
      if mode == .island {
        endStartupTask("startup-island")
        clearPreviewRequest()
        if pip?.isPictureInPictureActive == true || pipStarting {stopPreviewForTransition()}
        else {releasePreviewAudio()}
        message="已切换灵动岛，读屏继续。长按语渡卡片查看，通知中心也可操作。"
        if #available(iOS 16.2, *) {
          activityMessage=ReadingActivityManager.shared.start(activityState()) ?? "长按灵动岛查看；通知中心也可打开。"
          activityActive=ReadingActivityManager.shared.active
        }
      } else {
        startupTaskAttempted=false;beginStartupTask()
        if #available(iOS 16.2, *) {ReadingActivityManager.shared.end()}
        activityActive=false;activityMessage=""
        preparePreviewAudio();requestAutomaticPreview();message="已选择浮窗，返回文章后自动显示。"
      }
      updateActivity()
    }
  }
  private func preparePreviewAudio() {
    previewAudioWanted=true
    reconcilePreviewAudio()
  }
  private func beginStartupTask() {
    guard running || preparingFloatingPreview,presentation.wantsFloating,AVPictureInPictureController.isPictureInPictureSupported(),!startupTaskAttempted,startupTask == .invalid,pip?.isPictureInPictureActive != true else{return}
    startupTaskAttempted=true;startupTaskGeneration += 1
    let generation=startupTaskGeneration
    startupTask=UIApplication.shared.beginBackgroundTask(withName:"Lingfer initial reading preview") { [weak self] in
      DispatchQueue.main.async {
        guard let self,self.startupTaskGeneration==generation else{return}
        self.endStartupTask("startup-expired")
      }
    }
    recordStartupDiagnostics("startup-task",force:true)
    if UIApplication.shared.applicationState == .background {armStartupTaskTimeout()}
  }
  private func armStartupTaskTimeout() {
    guard startupTask != .invalid,startupTaskTimeout==nil else{return}
    let generation=startupTaskGeneration
    let timeout=DispatchWorkItem { [weak self] in
      guard let self,self.startupTaskGeneration==generation else{return}
      self.endStartupTask("startup-timeout")
    }
    startupTaskTimeout=timeout
    DispatchQueue.main.asyncAfter(deadline:.now()+15,execute:timeout)
  }
  private func endStartupTask(_ stage:String) {
    startupTaskTimeout?.cancel();startupTaskTimeout=nil
    let task=startupTask;startupTask = .invalid;startupTaskGeneration += 1
    guard task != .invalid else{return}
    UIApplication.shared.endBackgroundTask(task)
    recordStartupDiagnostics(stage,force:true)
  }
  private func reconcilePreviewAudio() {
    let wanted=previewAudioWanted && (running || preparing) && presentation.wantsFloating
    guard !audioPreparing,audioReady != wanted else{return}
    audioPreparing=true
    if !wanted {
      if #available(iOS 27.0, *) {
        AVAudioSession.sharedInstance().deactivate(options:[]) { [weak self] _,_ in
          DispatchQueue.main.async {
            guard let self else{return}
            self.audioPreparing=false;self.audioReady=false;self.reconcilePreviewAudio()
          }
        }
      } else {audioPreparing=false;audioReady=false}
      return
    }
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback,mode:.moviePlayback,options:[.mixWithOthers])
    } catch {
      audioPreparing=false;startupAudioResult = -1;startupAudioErrorCode=(error as NSError).code
      recordStartupDiagnostics("audio-category-failed",force:true)
      endStartupTask("startup-audio-failed");message="浮窗音视频会话暂不可用，读屏仍在继续。";return
    }
    if #available(iOS 27.0, *) {
      AVAudioSession.sharedInstance().activate(options:[]) { [weak self] activated,error in
        DispatchQueue.main.async {
          guard let self else{return};self.audioPreparing=false
          self.audioReady=activated
          self.startupAudioResult=activated ? 1 : -1;self.startupAudioErrorCode=(error as NSError?)?.code ?? 0
          self.recordStartupDiagnostics("audio",force:true)
          // Serialize activation and deactivation. A late activation from the
          // prior mode settles first, then reconciles the latest user choice.
          guard self.previewAudioWanted,(self.running || self.preparing),self.presentation.wantsFloating else {self.reconcilePreviewAudio();return}
          if activated {self.render(words:self.model.words);self.startQueuedPreviewIfPossible()}
          else {self.endStartupTask("startup-audio-failed");self.message="翻译浮窗暂不可用，可继续使用实时活动。"}
        }
      }
    }
  }
  private func releasePreviewAudio() {
    previewAudioWanted=false
    reconcilePreviewAudio()
  }
  private var separatesActivityVocabulary:Bool {presentationMode.separatesVocabulary(readingMode:model.readingMode)}
  private var activityShowsTranslation:Bool {model.readingMode == "translation" && !separatesActivityVocabulary}
  private func syncActivityVocabulary() {
    guard running,separatesActivityVocabulary else {
      if activityVocabulary.loading {activityVocabulary.cancel();activityVocabulary.loading=false;activityVocabularyKey=nil}
      return
    }
    guard !paused else{return}
    guard !model.text.isEmpty,!lastText.isEmpty,LiveViewportLine.key(model.text)==LiveViewportLine.key(lastText) else{return}
    let key=LiveVocabularyRequestKey(text:model.text,source:model.sourceLanguage,target:model.targetLanguage,level:model.level,difficulty:model.difficulty)
    guard key != activityVocabularyKey else{return}
    activityVocabularyKey=key;selectedActivityWordID=nil;activityDetailIndex=0;lastActivityDetailKey=""
    activityVocabulary.sourceLanguage=model.sourceLanguage;activityVocabulary.targetLanguage=model.targetLanguage
    activityVocabulary.level=model.level;activityVocabulary.difficulty=model.difficulty
    activityVocabulary.loading=true
    activityVocabulary.accept(model.text,source:"随屏词卡")
  }
  private func activityWords(primary:[ShareWord]?=nil,companion:[ShareWord]?=nil)->[ShareWord] {
    guard separatesActivityVocabulary else{return primary ?? model.words}
    let known=Set(CompanionStore.defaults.stringArray(forKey:"known") ?? [])
    return (companion ?? activityVocabulary.words).filter{!known.contains($0.id)}
  }
  @available(iOS 16.2, *)
  private func activityState(words:[ShareWord]?=nil,companionWords:[ShareWord]?=nil)->ReadingActivityAttributes.ContentState {
    let typeCategory=UIApplication.shared.preferredContentSizeCategory.rawValue
    let type=ReadingActivityTypography(category:typeCategory)
    let words=activityWords(primary:words,companion:companionWords)
    let pages=translationPages
    let part=pages.indices.contains(translationIndex) ? pages[translationIndex] : pages.first
    let nearby=separatesActivityVocabulary ? words.filter{rect(of:$0) != nil}.min{abs((rect(of:$0)?.midY ?? 0)-0.65)<abs((rect(of:$1)?.midY ?? 0)-0.65)} : nil
    let selected=words.first{$0.id==(separatesActivityVocabulary ? selectedActivityWordID : selectedWordID)} ?? nearby ?? words.first
    if separatesActivityVocabulary {selectedActivityWordID=selected?.id}
    let index=selected.flatMap{word in words.firstIndex{$0.id==word.id}} ?? 0
    let detailKey=activityShowsTranslation ? part?.id ?? "" : selected?.id ?? ""
    if detailKey != lastActivityDetailKey {activityDetailIndex=0;lastActivityDetailKey=detailKey}
    let details=activityDetails(word:selected,translation:part?.translation)
    activityDetailIndex=min(activityDetailIndex,max(0,details.count-1))
    let detail=details.indices.contains(activityDetailIndex) ? details[activityDetailIndex] : ""
    var context=""
    if let selected,!activityShowsTranslation {
      for limit in stride(from:48,through:18,by:-6) {
        let excerpt=LivePreviewExcerpt.make(context:selected.context,surface:selected.surface,limit:limit)
        if excerpt.highlight != nil,ReadingActivityText.height(excerpt.text,font:.systemFont(ofSize:12))<=16 {context=excerpt.text;break}
      }
    }
    let loading=separatesActivityVocabulary ? activityVocabulary.loading : model.loading
    let status=separatesActivityVocabulary ? activityVocabulary.error ?? (loading ? "正在翻译当前页面…" : "本页当前范围无待学词；浮窗继续显示整段译文。") : model.error ?? (model.loading ? "正在翻译当前页面…" : model.text.isEmpty ? "切换到阅读 App 后自动识别" : "当前范围没有待学词，可切换整页对照")
    return .preview(paused:paused,mode:activityShowsTranslation ? "translation" : "learning",
      count:activityShowsTranslation ? pages.count : words.count,
      terms:activityShowsTranslation ? [] : selected.map { word in
        let sourcePages=ReadingActivityText.pages(word.surface,size:type.wordSize(word.surface),lines:2,weight:.semibold)
        let visible=sourcePages.isEmpty ? word.surface : sourcePages[min(activityDetailIndex,sourcePages.count-1)]
        return [(visible,detail)]
      } ?? [],
      source:activityShowsTranslation ? part?.source ?? "" : context,
      translation:activityShowsTranslation ? detail : "",
      status:status,
      position:activityShowsTranslation ? translationIndex : index,
      total:activityShowsTranslation ? pages.count : words.count,
      detailPosition:activityDetailIndex,detailTotal:max(1,details.count),presentation:presentation.wantsFloating ? "floating" : "island",typeCategory:typeCategory,originalTerm:selected?.surface)
  }
  private func activityDetails(word:ShareWord?,translation:String?)->[String] {
    let type=ReadingActivityTypography(category:UIApplication.shared.preferredContentSizeCategory.rawValue)
    if activityShowsTranslation {return ReadingActivityText.pages(translation ?? "",size:type.translationSize,lines:type.translationLines)}
    guard let word else{return []}
    let meanings=ReadingActivityText.pages(word.shortTranslation,size:type.meaningSize(word.surface),lines:type.meaningLines(word.surface))
    let sourcePages=ReadingActivityText.pages(word.surface,size:type.wordSize(word.surface),lines:2,weight:.semibold)
    return (0..<max(meanings.count,sourcePages.count)).map {meanings.isEmpty ? "" : meanings[min($0,meanings.count-1)]}
  }
  func moveActivitySelection(_ direction:Int) {
    guard running else{return}
    activityActions += 1
    if separatesActivityVocabulary {
      let words=activityWords();guard !words.isEmpty else {
        if activityVocabulary.error != nil,!activityVocabulary.loading {activityVocabularyKey=nil;syncActivityVocabulary()}
        updateActivity();return
      }
      let index=words.firstIndex{$0.id==selectedActivityWordID} ?? 0
      let details=activityDetails(word:words[index],translation:nil)
      let next=activityDetailIndex+direction
      if details.indices.contains(next) {activityDetailIndex=next}
      else {
        let selected=words[(index+direction+words.count)%words.count]
        selectedActivityWordID=selected.id;lastActivityDetailKey=selected.id
        let pages=activityDetails(word:selected,translation:nil)
        activityDetailIndex=direction<0 ? max(0,pages.count-1) : 0
        let context=LiveViewportLine.key(selected.context)
        if let match=translationPages.firstIndex(where:{LiveViewportLine.key($0.source).contains(context)}) {
          translationIndex=match;selectedTranslationID=translationPages[match].id
        }
      }
      manualSelection=true;pinSelectionGeometry();render(words:model.words);updateActivity();return
    }
    let pages=translationPages
    let word=model.words.first{$0.id==selectedWordID} ?? model.words.first
    let current=pages.indices.contains(translationIndex) ? pages[translationIndex].translation : nil
    let details=activityDetails(word:word,translation:current)
    let next=activityDetailIndex+direction
    if details.indices.contains(next) {activityDetailIndex=next}
    else {
      moveSelection(direction)
      let nextWord=model.words.first{$0.id==selectedWordID} ?? model.words.first
      let nextText=pages.indices.contains(translationIndex) ? pages[translationIndex].translation : nil
      let nextDetails=activityDetails(word:nextWord,translation:nextText)
      activityDetailIndex=direction<0 ? max(0,nextDetails.count-1) : 0
    }
    manualSelection=true;pinSelectionGeometry();updateActivity()
  }
  private func updateActivity(words:[ShareWord]?=nil,companionWords:[ShareWord]?=nil) {
    guard running,presentationMode == .island else{return}
    if #available(iOS 16.2, *) {
      ReadingActivityManager.shared.update(activityState(words:words,companionWords:companionWords))
      activityActive=ReadingActivityManager.shared.active
    }
  }
  /// Numeric lifecycle evidence only. Never include source text, translations,
  /// URLs, account information or error descriptions in startup diagnostics.
  var startupDiagnostics:String {
    let source=previewSourceView,window=source?.window
    var ancestor=source,hidden=false
    while let view=ancestor {
      hidden = hidden || view.isHidden || view.alpha<0.01
      ancestor=view.superview
    }
    func size(_ rect:CGRect?)->String {
      guard let rect,rect.width.isFinite,rect.height.isFinite else{return "0x0"}
      return "\(Int(rect.width.rounded()))x\(Int(rect.height.rounded()))"
    }
    let ready:Bool
    if #available(iOS 17.4, *) {ready=previewLayer.isReadyForDisplay} else {ready=previewLayer.status == .rendering}
    let elapsed=Int((ProcessInfo.processInfo.systemUptime-startupTime)*1000)
    return "session=\(startupAttempt) elapsedMs=\(elapsed) app=\(UIApplication.shared.applicationState.rawValue) " +
      "captureFrame=\(receivedCaptureFrame ? 1 : 0) captureError=\(startupCaptureErrorCode) " +
      "sourceReady=\(sourceReadyForPreview ? 1 : 0) confirmations=\(firstBodyConfirmations) ocrPasses=\(startupOCRPasses) lines=\(startupLineCount) characters=\(startupCharacterCount) settled=\(viewportSettled ? 1 : 0) " +
      "startupTask=\(startupTask == .invalid ? 0 : 1) startupAttempted=\(startupTaskAttempted ? 1 : 0) audioReady=\(audioReady ? 1 : 0) audioPreparing=\(audioPreparing ? 1 : 0) audioResult=\(startupAudioResult) audioError=\(startupAudioErrorCode) " +
      "pipRequested=\(pipRequested ? 1 : 0) pipStarting=\(pipStarting ? 1 : 0) possible=\(pip?.isPictureInPicturePossible == true ? 1 : 0) active=\(pip?.isPictureInPictureActive == true ? 1 : 0) pipStartsOutsideActive=\(pipStartsOutsideActive) " +
      "sourceWindow=\(window == nil ? 0 : 1) sourceHidden=\(hidden ? 1 : 0) sourceBounds=\(size(source?.bounds)) layerBounds=\(size(previewLayer.bounds)) attached=\(previewLayer.superlayer == nil ? 0 : 1) layerReady=\(ready ? 1 : 0) layerStatus=\(previewLayer.status.rawValue) " +
      "frames=\(sequence) pages=\(acceptedPages) pipError=\(startupPiPErrorCode) ocrError=\(startupOCRErrorCode)"
  }
  private func recordStartupDiagnostics(_ stage:String,force:Bool=false) {
    guard running || preparing else{return}
    let background=UIApplication.shared.applicationState == .background
    guard force || diagnosticsEnabled && background && !pictureInPictureActive else{return}
    let now=Date.timeIntervalSinceReferenceDate
    guard force || now-lastStartupDiagnosticsAt>=2 else{return}
    let value="stage=\(stage) \(startupDiagnostics)"
    if diagnosticsEnabled,background {lastBackgroundDiagnostics=value}
    lastStartupDiagnosticsAt=now
    if force {Self.startupLog.notice("\(value,privacy:.public)")}
    if diagnosticsEnabled {print("LINGFER PIP STARTUP",value)}
  }
  var previewDiagnostics:String {
    let ready:Bool
    if #available(iOS 17.4, *) {ready=previewLayer.isReadyForDisplay} else {ready=previewLayer.status == .rendering}
    let anchor=model.words.first{$0.id==selectedWordID}.flatMap{rect(of:$0)}.map{Int((1-$0.midY)*100)} ?? -1
    return "preview ready=\(ready) state=\(previewLayer.status.rawValue) frames=\(sequence) pages=\(acceptedPages) requests=\(model.requestCount) networkMs=\(model.lastRequestDurationMs ?? -1) wordRequests=\(activityVocabulary.requestCount) islandWords=\(activityWords().count) wordLoading=\(activityVocabulary.loading) loading=\(model.loading) words=\(model.words.count) items=\(previewPlayback?.count ?? 0) focus=\(previewFocus) anchorTop=\(anchor) recoveries=\(previewRecoveries) shows=\(previewStarts) settled=\(viewportSettled) display=\(presentationMode.rawValue) floating=\(pictureInPictureActive) islandActive=\(activityActive) hidden=\(presentation.hidden) pending=\(deferredLiveText != nil) detail=\(activityDetailIndex) actions=\(activityActions) skipActions=\(previewSkipActions) clock=\(previewTimebase != nil) skip=\(pip?.requiresLinearPlayback == false) bounds=\(previewLayer.bounds) attached=\(previewLayer.superlayer != nil) pip=\(pip?.isPictureInPicturePossible ?? false) error=\(previewLayer.error?.localizedDescription ?? "none") context=\(previewContextDescription)"
  }

  private typealias TranslationPage=(id:String,source:String,translation:String,group:Int,groups:Int,sourcePage:Int,sourcePages:Int,targetPage:Int,targetPages:Int)
  private var translationPages:[TranslationPage] {
    let inputs=model.pageParts.map{TranslationLayoutInput(source:$0.source,translation:$0.translation)}
    if inputs==translationLayoutInputs {return translationLayoutPages}
    let style=NSMutableParagraphStyle();style.lineSpacing=5;style.lineBreakMode = .byWordWrapping
    let attributes:[NSAttributedString.Key:Any]=[.font:UIFont.systemFont(ofSize:30),.paragraphStyle:style]
    func measured(_ text:String,height:CGFloat)->[String] {
      LivePreviewPagination.chunks(text) { candidate in
        (candidate as NSString).boundingRect(with:CGSize(width:744,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes,context:nil).height<=height
      }
    }
    var occurrences:[String:Int]=[:]
    var nextMeasurements:[TranslationLayoutInput:([String],[String])]=[:]
    let pages=model.pageParts.enumerated().flatMap { index,part -> [TranslationPage] in
      let occurrence=occurrences[part.source,default:0];occurrences[part.source]=occurrence+1
      guard let translated=part.translation,!translated.isEmpty else{return []}
      let key=inputs[index]
      let pair=translationMeasurements[key] ?? (measured(part.source,height:143),measured(translated,height:153))
      nextMeasurements[key]=pair
      let originals=pair.0,targets=pair.1
      guard !originals.isEmpty,!targets.isEmpty else{return []}
      return (0..<max(originals.count,targets.count)).map { page in
        let a=min(page,originals.count-1),b=min(page,targets.count-1)
        return ("\(part.source)|occ:\(occurrence)|\(page)",originals[a],targets[b],index+1,model.pageParts.count,a+1,originals.count,b+1,targets.count)
      }
    }
    translationLayoutInputs=inputs;translationLayoutPages=pages;translationMeasurements=nextMeasurements
    return pages
  }

  private func rect(of word:ShareWord)->CGRect? {
    guard previewSourceText==model.text else{return nil}
    let source=model.text as NSString
    let range=word.sourceStart.flatMap { start in word.sourceEnd.flatMap { end -> NSRange? in
      guard start>=0,end>start,end<=source.length else{return nil}
      let range=NSRange(location:start,length:end-start)
      return source.substring(with:range).caseInsensitiveCompare(word.surface) == .orderedSame ? range : nil
    }} ?? source.range(of:word.surface,options:.caseInsensitive)
    guard range.location != NSNotFound else{return nil}
    return previewLines.first{NSIntersectionRange($0.range,range).length>0}?.rect
  }

  private func alignSelectionToViewport() {
    guard previewSourceText==model.text,!manualSelection else{return}
    if model.readingMode == "translation" {
      let pages=translationPages
      let projection=LiveSourceProjection(model.text)
      let normalizedSource=LiveViewportLine.key(model.text) as NSString
      let ranges:[NSRange?]=pages.map { page in
        let key=LiveViewportLine.key(page.source)
        guard !key.isEmpty else{return nil}
        let match=normalizedSource.range(of:key)
        guard match.location != NSNotFound else{return nil}
        // A repeated fragment has no trustworthy single position. Retain the
        // selected card instead of assigning it the first matching paragraph.
        let tail=match.location+1
        if tail<normalizedSource.length,normalizedSource.range(of:key,options:[],range:NSRange(location:tail,length:normalizedSource.length-tail)).location != NSNotFound {return nil}
        return projection.range(of:page.source)
      }
      let candidates=pages.indices.compactMap { i -> (Int,CGFloat)? in
        guard let range=ranges[i] else{return nil}
        let visible=previewLines.filter{NSIntersectionRange($0.range,range).length>0}.map(\.rect)
        let preferred=visible.filter{$0.midY>0.15 && $0.midY<0.88}
        return (preferred.isEmpty ? visible : preferred).min{abs($0.midY-0.65)<abs($1.midY-0.65)}.map{(i,$0.midY)}
      }
      if let active=pages.firstIndex(where:{$0.id==selectedTranslationID}) {
        if ranges[active]==nil || candidates.contains(where:{$0.0==active}) {missingAnchorFrames=0;return}
      }
      if selectedTranslationID != nil,!candidates.contains(where:{pages[$0.0].id==selectedTranslationID}),selectionMovement<0.08 {return}
      missingAnchorFrames += 1
      let preferred=candidates.filter{$0.1>0.15 && $0.1<0.88}
      if selectedTranslationID==nil || missingAnchorFrames>=2,let closest=(preferred.isEmpty ? candidates : preferred).min(by:{abs($0.1-0.65)<abs($1.1-0.65)}) {selectedTranslationID=pages[closest.0].id;missingAnchorFrames=0;pinSelectionGeometry()}
    } else {
      if let active=model.words.first(where:{$0.id==selectedWordID}),rect(of:active) != nil {missingAnchorFrames=0;return}
      if let active=model.words.first(where:{$0.id==selectedWordID}),rect(of:active)==nil,selectionMovement<0.08 {return}
      missingAnchorFrames += 1
      if selectedWordID==nil || missingAnchorFrames>=2 {
        if let closest=defaultVisibleWord(in:model.words) {selectedWordID=closest.id;missingAnchorFrames=0;pinSelectionGeometry()}
      }
    }
  }

  private func pinSelectionGeometry() {
    selectionMovement=0
    guard previewSourceText==model.text else {selectionAnchor.reset();selectionAnchorSource="";return}
    selectionAnchor.pin(previewLines.map{($0.range,$0.rect)})
    selectionAnchorSource=model.text
  }

  private func defaultVisibleWord(in words:[ShareWord])->ShareWord? {
    let candidates=words.compactMap {word in rect(of:word).map{(word,$0.midY)}}
    let preferred=candidates.filter{$0.1>0.15 && $0.1<0.88}
    return (preferred.isEmpty ? candidates : preferred).min{abs($0.1-0.65)<abs($1.1-0.65)}?.0
  }

  func moveSelection(_ direction:Int) {
    guard running else{return}
    if model.readingMode == "translation" {
      let pages=translationPages;guard !pages.isEmpty else{return}
      let old=pages.firstIndex{$0.id==selectedTranslationID} ?? translationIndex
      translationIndex=(old+direction+pages.count)%pages.count;selectedTranslationID=pages[translationIndex].id
    } else {
      let words=model.words;guard !words.isEmpty else{return}
      let old=words.firstIndex{$0.id==selectedWordID} ?? 0
      selectedWordID=words[(old+direction+words.count)%words.count].id
    }
    manualSelection=true;pinSelectionGeometry();missingAnchorFrames=0
    activityDetailIndex=0;lastActivityDetailKey=""
    render(words:model.words);updateActivity()
  }

  private func refreshPreviewIfNeeded() {
    if #available(iOS 17.0, *) {
      let renderer=previewLayer.sampleBufferRenderer
      if renderer.requiresFlushToResumeDecoding || renderer.status == .failed {renderer.flush();previewRecoveries += 1}
    } else if previewLayer.requiresFlushToResumeDecoding || previewLayer.status == .failed {previewLayer.flush();previewRecoveries += 1}
  }

  func recoverPreview() {
    guard running else{return}
    if #available(iOS 17.0, *) {previewLayer.sampleBufferRenderer.flush()} else {previewLayer.flush()}
    previewRecoveries += 1;render(words:model.words);pip?.invalidatePlaybackState()
  }

  private func synchronizePreviewPlayback(count:Int,position:Int) {
    let state=LivePreviewPlayback(count:count,position:position)
    if previewTimebase == nil {
      var timebase:CMTimebase?
      if CMTimebaseCreateWithSourceClock(allocator:kCFAllocatorDefault,sourceClock:CMClockGetHostTimeClock(),timebaseOut:&timebase) == noErr,
         let timebase {
        CMTimebaseSetRate(timebase,rate:0)
        previewTimebase=timebase;previewLayer.controlTimebase=timebase
      }
    }
    let changed=previewPlayback != state || previewPlaybackPaused != paused
    if changed,let timebase=previewTimebase {
      // A previous card may be queued later on the virtual timeline. Retain
      // its displayed image while discarding that queue before seeking back.
      if #available(iOS 17.0, *) {previewLayer.sampleBufferRenderer.flush()} else {previewLayer.flush()}
      CMTimebaseSetTime(timebase,time:CMTime(seconds:state.timeSeconds,preferredTimescale:600))
    }
    previewPlayback=state;previewPlaybackPaused=paused
    let linear = !state.canSkip || previewTimebase == nil
    if pip?.requiresLinearPlayback != linear {pip?.requiresLinearPlayback=linear}
    if changed {pip?.invalidatePlaybackState()}
  }

  private func location(of word:ShareWord)->String {
    guard previewSourceText == model.text else{return "当前页面"}
    let source=model.text as NSString
    var range=NSRange(location:NSNotFound,length:0)
    if let start=word.sourceStart,let end=word.sourceEnd,start>=0,end>start,end<=source.length {
      let proposed=NSRange(location:start,length:end-start)
      if source.substring(with:proposed).caseInsensitiveCompare(word.surface) == .orderedSame {range=proposed}
    }
    if range.location == NSNotFound {range=source.range(of:word.surface,options:.caseInsensitive)}
    guard range.location != NSNotFound else{return "当前页面"}
    guard let line=previewLines.first(where:{NSIntersectionRange($0.range,range).length>0}) else {
      if let first=previewLines.map({$0.range.location}).min(),range.location<first {return "在画面上方 · 可向上找回"}
      if let last=previewLines.map({NSMaxRange($0.range)}).max(),range.location>last {return "在画面下方 · 可向下找回"}
      return "位置核对中 · 保留当前词"
    }
    let area=line.rect.midY>0.66 ? "上部" : line.rect.midY<0.33 ? "下部" : "中部"
    return "\(area) · 距顶 \(Int((1-line.rect.midY)*100))%"
  }

  private func drawContext(_ source:String,surface:String,in rect:CGRect,ink:UIColor,accent:UIColor) {
    var excerpt=LivePreviewExcerpt.make(context:source,surface:surface,limit:90)
    let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=7;paragraph.lineBreakMode = .byWordWrapping
    let font=UIFont.systemFont(ofSize:39)
    let attributes:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:ink,.paragraphStyle:paragraph]
    // Measure the reflowed sentence rather than truncating the end of a line:
    // the target must stay visible with CJK text, emoji and long PDF lines too.
    for limit in stride(from:90,through:40,by:-10) {
      excerpt=LivePreviewExcerpt.make(context:source,surface:surface,limit:limit)
      let bounds=(excerpt.text as NSString).boundingRect(with:CGSize(width:rect.width,height:.greatestFiniteMagnitude),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes,context:nil)
      if bounds.height<=rect.height {break}
    }
    let value=NSMutableAttributedString(string:excerpt.text,attributes:attributes)
    if let range=excerpt.highlight {
      value.addAttributes([.font:UIFont.systemFont(ofSize:39,weight:.bold),.foregroundColor:accent,.backgroundColor:accent.withAlphaComponent(0.13)],range:range)
    }
    value.draw(with:rect,options:[.usesLineFragmentOrigin,.usesFontLeading],context:nil)
    previewContextDescription="\(surface.isEmpty ? "原文" : surface)|\(excerpt.text)|highlight=\(excerpt.highlight != nil)"
  }

  private func render(words:[ShareWord]) {
    pendingRenderWords=words
    guard !renderScheduled else{return}
    renderScheduled=true
    // SwiftUI attachment, model publishers and capture completion can all land
    // in one run-loop pass. Draw once using their newest state, leaving touch
    // handling and the segment selection free to update first.
    DispatchQueue.main.async { [weak self] in
      guard let self else{return}
      self.renderScheduled=false
      let latest=self.pendingRenderWords ?? self.model.words;self.pendingRenderWords=nil
      self.renderNow(words:latest)
    }
  }

  private func renderNow(words currentWords:[ShareWord]) {
    guard running || preparingFloatingPreview else{return}
    syncActivityVocabulary()
    let words=sourceReadyForPreview ? currentWords : []
    let parts=sourceReadyForPreview ? translationPages : []
    let count=model.readingMode == "translation" ? parts.count : words.count
    if model.readingMode == "translation" {
      let before=selectedTranslationID
      translationIndex=parts.firstIndex{$0.id==selectedTranslationID} ?? min(translationIndex,max(0,parts.count-1))
      previewFocus=translationIndex
      if parts.indices.contains(translationIndex) {selectedTranslationID=parts[translationIndex].id}
      if before != selectedTranslationID {pinSelectionGeometry()}
    } else {
      let before=selectedWordID
      let closest=defaultVisibleWord(in:words).flatMap{selected in words.firstIndex{$0.id==selected.id}}
      previewFocus=words.firstIndex{$0.id==selectedWordID} ?? closest ?? 0
      if words.indices.contains(previewFocus) {selectedWordID=words[previewFocus].id}
      if before != selectedWordID {pinSelectionGeometry()}
    }
    synchronizePreviewPlayback(count:count,position:previewFocus)
    // An island-only reader does not need a continuously allocated video.
    // Keep the shared cursor/diagnostics, and create frames when PiP is chosen.
    if presentationMode == .island || presentation.hidden {
      if model.readingMode == "translation",parts.indices.contains(previewFocus) {
        previewContextDescription="translation|\(parts[previewFocus].source)|\(parts[previewFocus].translation)"
      } else if words.indices.contains(previewFocus) {
        let word=words[previewFocus]
        let excerpt=LivePreviewExcerpt.make(context:word.context,surface:word.surface,limit:60)
        previewContextDescription="\(word.surface)|\(excerpt.text)|highlight=\(excerpt.highlight != nil)"
      }
      publishPreviewDiagnostics();return
    }
    refreshPreviewIfNeeded()
    let width=800,height=500
    var pixel:CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault,width,height,kCVPixelFormatType_32BGRA,[kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true,kCVPixelBufferIOSurfacePropertiesKey:[:]] as CFDictionary,&pixel)
    guard let pixel else{return}
    guard CVPixelBufferLockBaseAddress(pixel,[])==kCVReturnSuccess else{return}
    var locked=true;defer{if locked {CVPixelBufferUnlockBaseAddress(pixel,[])}}
    guard let context=CGContext(data:CVPixelBufferGetBaseAddress(pixel),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue|CGBitmapInfo.byteOrder32Little.rawValue) else{return}
    let traits=previewSourceView?.traitCollection ?? UITraitCollection.current
    context.setFillColor(NativeReadingTheme.backgroundUI.resolvedColor(with:traits).cgColor);context.fill(CGRect(x:0,y:0,width:width,height:height))
    context.translateBy(x:0,y:CGFloat(height));context.scaleBy(x:1,y:-1)
    UIGraphicsPushContext(context)
    var pushed=true;defer{if pushed {UIGraphicsPopContext()}}
    let ink=NativeReadingTheme.inkUI.resolvedColor(with:traits)
    let accent=NativeReadingTheme.accentUI.resolvedColor(with:traits)
    let muted=NativeReadingTheme.mutedUI.resolvedColor(with:traits)
    let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byTruncatingTail
    func label(_ value:String,_ rect:CGRect,_ size:CGFloat,_ color:UIColor,_ weight:UIFont.Weight = .regular) {
      (value as NSString).draw(in:rect,withAttributes:[.font:UIFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.paragraphStyle:paragraph])
    }
    let waiting=model.loading || deferredLiveText != nil || !sourceReadyForPreview || !viewportSettled
    let finished=model.pageParts.filter{$0.translation != nil}.count
    let status=paused ? "已暂停" : !sourceReadyForPreview ? "正在识别首屏" : model.loading ? (model.readingMode == "translation" ? "正在翻译 \(finished)/\(model.pageParts.count)" : "正在筛选词汇") : deferredLiveText != nil ? "正在补充新内容" : !viewportSettled ? "等待页面停稳" : ""
    label(status,CGRect(x:458,y:22,width:282,height:30),21,accent,.medium)
    if waiting,!paused {
      let angle=CGFloat(Date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:2)*Double.pi)
      context.setStrokeColor(accent.withAlphaComponent(0.85).cgColor);context.setLineWidth(3)
      context.addArc(center:CGPoint(x:759,y:36),radius:9,startAngle:angle,endAngle:angle+CGFloat.pi*1.35,clockwise:false);context.strokePath()
    }
    let body=NSMutableParagraphStyle();body.lineSpacing=5;body.lineBreakMode = .byWordWrapping
    let bodyAttributes:[NSAttributedString.Key:Any]=[.font:UIFont.systemFont(ofSize:30),.foregroundColor:ink,.paragraphStyle:body]
    if model.readingMode == "translation",!parts.isEmpty {
      let part=parts[previewFocus]
      label("句组 \(part.group)/\(part.groups) · 对照 \(previewFocus+1)/\(parts.count)",CGRect(x:28,y:22,width:425,height:30),22,muted)
      label("原文\(part.sourcePages>1 ? " · 续页 \(part.sourcePage)/\(part.sourcePages)" : "")",CGRect(x:28,y:64,width:744,height:25),21,muted)
      (part.source as NSString).draw(in:CGRect(x:28,y:96,width:744,height:143),withAttributes:bodyAttributes)
      label("译文\(part.targetPages>1 ? " · 续页 \(part.targetPage)/\(part.targetPages)" : "")",CGRect(x:28,y:262,width:744,height:25),21,accent)
      (part.translation as NSString).draw(in:CGRect(x:28,y:294,width:744,height:153),withAttributes:bodyAttributes)
      previewContextDescription="translation|\(part.source)|\(part.translation)"
    } else if !words.isEmpty {
      let word=words[previewFocus]
      label("本屏 \(model.text.filter{!$0.isWhitespace}.count) 字 · \(previewFocus+1)/\(words.count) 词",CGRect(x:28,y:22,width:425,height:30),22,muted)
      label("原句片段 · \(location(of:word))",CGRect(x:28,y:68,width:744,height:30),24,muted)
      let range=word.sourceStart.flatMap { start in word.sourceEnd.map{NSRange(location:start,length:max(0,$0-start))} }
      let sentence=LivePreviewExcerpt.sentence(source:model.text,surface:word.surface,range:range) ?? word.context
      drawContext(sentence,surface:word.surface,in:CGRect(x:28,y:110,width:744,height:190),ink:ink,accent:accent)
      label(word.surface,CGRect(x:28,y:326,width:744,height:53),43,accent,.semibold)
      label(word.shortTranslation,CGRect(x:28,y:389,width:744,height:54),36,ink)
    } else if !sourceReadyForPreview {
      label("等待屏幕正文",CGRect(x:28,y:68,width:744,height:30),24,muted)
      drawContext("切换到阅读 App，停稳页面后自动识别。",surface:"",in:CGRect(x:28,y:110,width:744,height:190),ink:ink,accent:accent)
      label(running ? "读屏已开启" : "正在开启读屏",CGRect(x:32,y:340,width:736,height:82),36,accent,.medium)
      previewContextDescription="等待阅读页面"
    } else {
      label(model.text.isEmpty ? "等待屏幕正文" : "识别预览 · 共 \(model.text.filter{!$0.isWhitespace}.count) 字",CGRect(x:28,y:68,width:744,height:30),24,muted)
      drawContext(model.text.isEmpty ? "切换到阅读 App，停稳页面后自动识别。" : model.text,surface:"",in:CGRect(x:28,y:110,width:744,height:190),ink:ink,accent:accent)
      let state=model.error ?? (model.loading ? "正在筛选与翻译…" : model.text.isEmpty ? "读屏已开启" : "当前范围暂无待学词")
      label(state,CGRect(x:32,y:340,width:736,height:82),36,accent,.medium)
    }
    context.setStrokeColor(NativeReadingTheme.lineUI.resolvedColor(with:traits).cgColor)
    let separator:CGFloat=model.readingMode == "translation" ? 249 : 314
    context.setLineWidth(1);context.move(to:CGPoint(x:32,y:separator));context.addLine(to:CGPoint(x:768,y:separator));context.strokePath()
    // This functional footer doubles as the local self-video OCR marker. No
    // separate brand header occupies the space needed for original text.
    let navigationHint=model.readingMode == "translation" ? "点浮窗 · 快退 / 快进切换对照" : "点浮窗 · 快退上一词 / 快进下一词"
    let footer=paused ? "点浮窗 · 已固定，前后切换已完成内容" : transientControlsVisible ? "点浮窗 · 保留当前结果" : count>1 && previewTimebase != nil ? navigationHint : "点浮窗 · 返回语渡查看完整结果"
    label(footer,CGRect(x:28,y:464,width:744,height:28),20,muted)
    // Finish CPU drawing and release the IOSurface lock before the asynchronous
    // video renderer takes the frame. Never enqueue a CPU-locked pixel buffer.
    context.flush();UIGraphicsPopContext();pushed=false
    CVPixelBufferUnlockBaseAddress(pixel,[]);locked=false
    var format:CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:pixel,formatDescriptionOut:&format)
    guard let format else{return}
    let time=previewTimebase.map{CMTimebaseGetTime($0)} ?? CMClockGetTime(CMClockGetHostTimeClock())
    var timing=CMSampleTimingInfo(duration:CMTime(value:1,timescale:1),presentationTimeStamp:time,decodeTimeStamp:.invalid)
    var sample:CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:pixel,formatDescription:format,sampleTiming:&timing,sampleBufferOut:&sample)
    guard let sample else{return}
    if previewTimebase == nil,let attachments=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:true) {
      let item=unsafeBitCast(CFArrayGetValueAtIndex(attachments,0),to:CFMutableDictionary.self)
      CFDictionarySetValue(item,Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
    if #available(iOS 17.0, *) {previewLayer.sampleBufferRenderer.enqueue(sample)} else {previewLayer.enqueue(sample)}
    sequence += 1
    if sequence==1 {
      pip?.invalidatePlaybackState()
      recordStartupDiagnostics("preview-first-frame",force:true)
      startQueuedPreviewIfPossible()
    }
    publishPreviewDiagnostics()
  }
  private func publishPreviewDiagnostics() {
    // Only the explicit UI-test mode observes diagnostics. Publishing each video
    // frame would re-render the whole reading sheet; publish semantic changes only.
    if diagnosticsEnabled {
      let value="\(activityVocabulary.requestCount)|\(activityVocabulary.words.count)|\(activityVocabulary.loading)|\(acceptedPages)|\(previewFocus)|\(paused)|\(previewRecoveries)|\(previewStarts)|\(model.requestCount)|\(model.loading)|\(model.lastRequestDurationMs ?? -1)|\(viewportSettled)|\(transientControlsVisible)|\(previewSkipActions)|\(previewContextDescription)"
      if previewQAState != value {
        DispatchQueue.main.async { [weak self] in
          guard let self,self.running,self.previewQAState != value else{return}
          self.previewQAState=value
        }
      }
    }
  }
}

#if canImport(ScreenCaptureKit)
@available(iOS 27.0, *)
private final class SystemScreenCapture:NSObject,LiveCaptureDriving,SCContentSharingPickerObserver,SCStreamOutput,SCStreamDelegate {
  weak var session:LiveReadingSession?
  private var stream:SCStream?
  private var stopped = false
  private let sampleQueue=DispatchQueue(label:"lingfer.screen.samples")
  init(session:LiveReadingSession) {self.session=session;super.init()}
  func present() {
    let picker=SCContentSharingPicker.shared
    guard picker.isAvailable else {session?.cancelPreparation(message:"系统读屏当前不可用，请稍后重试。");return}
    var config=SCContentSharingPickerConfiguration();config.showsMicrophoneControl=false
    picker.defaultConfiguration=config;picker.add(self);picker.isActive=true;picker.present()
  }
  func contentSharingPicker(_ picker:SCContentSharingPicker,didCancelFor stream:SCStream?) {
    DispatchQueue.main.async { [weak self] in
      guard let self,!self.stopped,self.session?.preparing == true else{return}
      self.session?.cancelPreparation()
    }
  }
  func contentSharingPickerStartDidFailWithError(_ error:Error) {
    DispatchQueue.main.async { [weak self] in
      guard let self,!self.stopped else{return}
      self.session?.captureFailed(error)
    }
  }
  func contentSharingPicker(_ picker:SCContentSharingPicker,didUpdateWith filter:SCContentFilter,for stream:SCStream?) {
    DispatchQueue.main.async { [weak self] in self?.startCapture(with:filter) }
  }
  private func startCapture(with filter:SCContentFilter) {
    guard !stopped else {return}
    session?.didAuthorizeCapture()
    if let current=self.stream {current.stopCapture(completionHandler:nil)}
    let config=SCStreamConfiguration();config.width=1080
    config.height=Int(1080*max(1,filter.contentRect.height)/max(1,filter.contentRect.width))
    let next=SCStream(filter:filter,configuration:config,delegate:self)
    do {try next.addStreamOutput(self,type:.screen,sampleHandlerQueue:sampleQueue)} catch {session?.captureFailed(error);return}
    self.stream=next
    next.startCapture { [weak self] error in DispatchQueue.main.async {
      guard let self,!self.stopped,self.stream === next else {next.stopCapture(completionHandler:nil);return}
      if let error {self.session?.captureFailed(error)} else {self.session?.didStart()}
    }}
  }
  func stream(_ stream:SCStream,didOutputSampleBuffer sampleBuffer:CMSampleBuffer,of type:SCStreamOutputType) {
    guard type == .screen else{return}
    session?.receive(sampleBuffer) { [weak self] in
      guard let self else{return false}
      return !self.stopped && self.stream === stream
    }
  }
  func stream(_ stream:SCStream,didStopWithError error:Error) {DispatchQueue.main.async {if !self.stopped,self.stream === stream {self.session?.captureFailed(error)}}}
  func stop() {stopped=true;SCContentSharingPicker.shared.remove(self);SCContentSharingPicker.shared.isActive=false;stream?.stopCapture(completionHandler:nil);stream=nil}
}
#endif

extension LiveReadingSession:AVPictureInPictureSampleBufferPlaybackDelegate,AVPictureInPictureControllerDelegate {
  func pictureInPictureControllerWillStartPictureInPicture(_ controller:AVPictureInPictureController) {
    guard controller === pip else{return}
    clearPreviewRequest();pipStarting=true
    recordStartupDiagnostics("pip-will-start",force:true)
  }
  func pictureInPictureControllerDidStartPictureInPicture(_ controller:AVPictureInPictureController) {
    guard controller === pip else{controller.stopPictureInPicture();return}
    pipStarting=false
    if mayStartFloatingPreview,UIApplication.shared.applicationState != .active {pipStartsOutsideActive += 1}
    recordStartupDiagnostics("pip-started",force:true)
    guard mayStartFloatingPreview else {stopPreviewForTransition();return}
    if UIApplication.shared.applicationState == .active {presentation.restoreInline();stopPreviewForTransition();return}
    endStartupTask("startup-pip-ready")
    previewStarts += 1
    if previewStarts>1,(previewPlayback?.count ?? 0)>0 {
      previewInteractionUntil=max(previewInteractionUntil,Date.timeIntervalSinceReferenceDate+3)
    }
    pictureInPictureActive=true;message="翻译浮窗已开启，回到语渡查看后再返回文章也会继续显示。";refreshPreviewIfNeeded();render(words:model.words)
  }
  func pictureInPictureControllerDidStopPictureInPicture(_ controller:AVPictureInPictureController) {
    guard controller === pip else{return}
    let requestedStop=pipStopRequested
    pipStopRequested=false;pipStarting=false;pictureInPictureActive=false
    clearPreviewRequest()
    if !requestedStop {presentation.didStop(inForeground:UIApplication.shared.applicationState != .background)}
    controller.canStartPictureInPictureAutomaticallyFromInline=mayStartFloatingPreview
    recordStartupDiagnostics("pip-stopped",force:true)
    if let view=pendingPreviewView {attachPreview(to:view)}
    if !presentation.wantsFloating {releasePreviewAudio()}
    if running {
      message=presentationMode == .island ? "灵动岛模式 · 读屏继续，长按语渡卡片查看。" : presentation.wantsFloating ? "正在 App 内查看，返回文章时继续显示浮窗。" : "已收起浮窗，读屏继续；可重新显示或切换灵动岛。"
      if presentation.wantsFloating,UIApplication.shared.applicationState == .background {DispatchQueue.main.async{self.requestAutomaticPreview()}}
      updateActivity()
    }
  }
  func pictureInPictureController(_ controller:AVPictureInPictureController,setPlaying playing:Bool) {setPaused(!playing)}
  func pictureInPictureControllerTimeRangeForPlayback(_ controller:AVPictureInPictureController)->CMTimeRange {
    guard let state=previewPlayback,previewTimebase != nil else {return CMTimeRange(start:.zero,duration:.positiveInfinity)}
    return CMTimeRange(start:.zero,duration:CMTime(seconds:state.durationSeconds,preferredTimescale:600))
  }
  func pictureInPictureControllerIsPlaybackPaused(_ controller:AVPictureInPictureController)->Bool {paused}
  func pictureInPictureController(_ controller:AVPictureInPictureController,didTransitionToRenderSize size:CMVideoDimensions) {}
  func pictureInPictureController(_ controller:AVPictureInPictureController,skipByInterval skipInterval:CMTime,completion completionHandler:@escaping()->Void) {
    // Only AVKit's actual skip buttons call this delegate. Complete after the
    // cursor and control timebase have moved, without requesting translation.
    defer {completionHandler()}
    if diagnosticsEnabled {print("LINGFER PIP SKIP interval=\(skipInterval.seconds) running=\(running) canSkip=\(previewPlayback?.canSkip == true) active=\(controller.isPictureInPictureActive)")}
    guard running,previewPlayback?.canSkip == true,skipInterval.seconds.isFinite,skipInterval.seconds != 0 else{return}
    previewInteractionUntil=Date.timeIntervalSinceReferenceDate+3
    previewSkipActions += 1
    moveSelection(skipInterval.seconds<0 ? -1 : 1)
  }
  func pictureInPictureController(_ controller:AVPictureInPictureController,failedToStartPictureInPictureWithError error:Error) {
    guard controller === pip else{return}
    pipStarting=false
    clearPreviewRequest()
    startupPiPErrorCode=(error as NSError).code;recordStartupDiagnostics("pip-failed",force:true)
    endStartupTask("startup-pip-failed")
    if running,presentation.wantsFloating {message="画中画未能开启：\(error.localizedDescription)。读屏继续，可回到阅读面板重试。"}
  }
  func pictureInPictureController(_ controller:AVPictureInPictureController,restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:@escaping(Bool)->Void) {
    guard running else {completionHandler(false);return}
    presentation.restoreInline()
    let root=UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.flatMap{$0.windows}.first{$0.isKeyWindow}?.rootViewController
    if let root {
      var presenter=root
      while let next=presenter.presentedViewController {presenter=next}
      open(from:presenter) {completionHandler(true)}
    } else {completionHandler(false)}
  }
}

private struct LivePreview:UIViewRepresentable {
  let session:LiveReadingSession
  func makeUIView(context:Context)->UIView {let view=PreviewView();view.session=session;return view}
  func updateUIView(_ view:UIView,context:Context) {session.attachPreview(to:view)}
  private class PreviewView:UIView {
    weak var session:LiveReadingSession?
    override func layoutSubviews(){super.layoutSubviews();session?.attachPreview(to:self)}
    override func didMoveToWindow() {
      super.didMoveToWindow()
      if window != nil {session?.attachPreview(to:self)} else {session?.previewLeftWindow(self)}
    }
  }
}
private struct LiveReadingHost:View {
  @ObservedObject var session:LiveReadingSession
  @State private var showingPrevious=false
  @Namespace private var displaySelection
  var body:some View {
    Group {
      // Mount the inline source while the picker is up. Capture completion
      // keeps this view identity even when the user immediately switches apps.
      if !session.running && !session.preparingFloatingPreview && !showingPrevious {
        ReadingStartView(model:session.model,message:session.message,start:{session.start()},close:{session.dismiss()},previous:session.model.hasLiveHistory || !session.model.text.isEmpty ? {
          if session.model.hasLiveHistory {_ = session.model.restoreLastLiveHistory()}
          showingPrevious=true
        } : nil,displayControls:AnyView(displayPicker))
      } else {
        ShareReadingView(model:session.model,close:{if !session.running && showingPrevious {showingPrevious=false;session.configure()} else {session.dismiss()}},title:"随屏阅读",doneTitle:"返回",controls:AnyView(controls),compactControls:AnyView(compactControls))
      }
    }.onChange(of:session.running) {running in if running {showingPrevious=false}}
  }
  private var displayPicker:some View {
    HStack(spacing:4) {
      ForEach([LiveReadingPresentation.floating,.island],id:\.rawValue) { mode in
        Button {
          withAnimation(.interactiveSpring(response:0.32,dampingFraction:0.86,blendDuration:0.1)) {session.setPresentation(mode)}
        } label: {
          Text(mode.title).font(.subheadline.weight(session.presentationMode == mode ? .semibold : .regular))
            .frame(maxWidth:.infinity,minHeight:44)
            .foregroundStyle(session.presentationMode == mode ? NativeReadingTheme.onAccent : NativeReadingTheme.accent)
            .background {
              if session.presentationMode == mode {
                Capsule().fill(NativeReadingTheme.accent).matchedGeometryEffect(id:"live-display-selection",in:displaySelection)
              }
            }
        }.buttonStyle(.plain).accessibilityLabel(mode.title).accessibilityIdentifier("live-display-\(mode.rawValue)")
          .accessibilityAddTraits(session.presentationMode == mode ? .isSelected : [])
      }
    }.padding(4).modifier(NativeReadingGlass(radius:26))
      .accessibilityElement(children:.contain).accessibilityLabel("显示方式")
  }
  private var compactControls:some View {
    HStack(spacing:12) {
      if session.running || session.preparingFloatingPreview {
        LivePreview(session:session).frame(width:80,height:50).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityLabel("实时阅读画中画预览")
        Text(session.paused ? "已暂停" : "随屏阅读中").font(.subheadline).frame(maxWidth:.infinity,alignment:.leading)
        Button(session.paused ? "继续识别" : "暂停识别"){session.setPaused(!session.paused)}.accessibilityIdentifier("live-pause")
        Button {session.startPictureInPicture()} label:{Image(systemName:"pip.enter").frame(width:44,height:44)}.accessibilityLabel("显示翻译浮窗").accessibilityIdentifier("live-pip")
        Button("停止"){session.stop()}.frame(minWidth:44,minHeight:44).accessibilityIdentifier("live-stop")
      } else {
        Button("开启系统读屏"){session.start()}.frame(maxWidth:.infinity,minHeight:44).accessibilityIdentifier("live-start")
      }
    }.font(.subheadline).buttonStyle(.plain).foregroundStyle(NativeReadingTheme.accent).padding(.horizontal,18).padding(.vertical,6).background(NativeReadingTheme.background)
      .disabled(session.preparing)
  }
  private var controls:some View {
    VStack(alignment:.leading,spacing:10) {
      displayPicker
      if !session.running && !session.preparingFloatingPreview {
        Button("开启系统读屏"){session.start()}
          .font(.body.weight(.semibold)).frame(maxWidth:.infinity,minHeight:52)
          .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).accessibilityIdentifier("live-start")
      } else {
        HStack(spacing:8) {
          HStack(spacing:7) {
            Circle().fill(session.paused ? NativeReadingTheme.muted : NativeReadingTheme.accent).frame(width:6,height:6)
            Text(session.paused ? "已暂停" : "正在随屏阅读").font(.subheadline.weight(.medium))
          }.frame(maxWidth:.infinity,alignment:.leading)
          Button {session.setPaused(!session.paused)} label: {
            Image(systemName:session.paused ? "play.fill" : "pause.fill").font(.system(size:14,weight:.medium)).frame(width:44,height:44)
          }.buttonStyle(.plain).foregroundStyle(NativeReadingTheme.accent).modifier(NativeReadingGlass(radius:22)).accessibilityLabel(session.paused ? "继续识别" : "暂停识别").accessibilityIdentifier("live-pause")
          Button {session.startPictureInPicture()} label: {
            Image(systemName:"pip.enter").font(.system(size:17,weight:.regular)).frame(width:44,height:44)
          }.buttonStyle(.plain).foregroundStyle(NativeReadingTheme.accent).modifier(NativeReadingGlass(radius:22)).accessibilityLabel(session.pictureInPictureActive ? "重绘翻译浮窗" : "显示翻译浮窗").accessibilityIdentifier("live-pip")
          Button("停止"){session.stop()}.buttonStyle(.plain).font(.subheadline).foregroundStyle(NativeReadingTheme.accent).frame(minWidth:44,minHeight:44).accessibilityIdentifier("live-stop")
        }
        LivePreview(session:session).frame(height:session.presentationMode == .floating ? 88 : 2).clipShape(RoundedRectangle(cornerRadius:18))
          .opacity(session.presentationMode == .floating ? 1 : 0.01).accessibilityLabel("实时阅读画中画预览")
          .accessibilityHidden(session.presentationMode == .island)
        Text(session.message).font(.footnote).foregroundStyle(NativeReadingTheme.muted).lineLimit(3).fixedSize(horizontal:false,vertical:true)
        if session.running {
          Text(session.captureSummary).font(.footnote.weight(.medium)).foregroundStyle(NativeReadingTheme.accent)
            .accessibilityIdentifier("live-capture-summary")
          Text(session.captureCoverageNotice).font(.caption).foregroundStyle(NativeReadingTheme.muted)
            .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("live-capture-coverage")
        }
        HStack(alignment:.firstTextBaseline,spacing:10) {
          if session.pictureInPictureActive {Text("浮窗运行中").accessibilityIdentifier("live-pip-active")}
          else if session.presentationMode == .floating {
            Text(session.floatingPreviewHidden ? "浮窗已收起 · 点浮窗图标重新显示" : "App 内预览 · 返回文章后浮出")
              .accessibilityIdentifier(session.floatingPreviewHidden ? "live-pip-hidden" : "live-pip-inline")
          }
          Text(session.activityMessage).lineLimit(3).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier(session.activityActive ? "live-island-active" : "live-island-unavailable")
        }.font(.caption).foregroundStyle(NativeReadingTheme.muted)
      }
      if session.diagnosticsEnabled {
        // Keep test diagnostics from moving the real controls while OCR runs.
        // The full value remains accessible to the UI test, never in a Beta UI.
        Text(session.previewDiagnostics).font(.caption2).lineLimit(1).frame(height:14).clipped()
          .accessibilityLabel(session.previewDiagnostics).accessibilityIdentifier("live-preview-debug")
        Text(session.lastBackgroundDiagnostics).font(.caption2).lineLimit(1).frame(height:1).clipped()
          .accessibilityLabel(session.lastBackgroundDiagnostics).accessibilityIdentifier("live-background-diagnostics")
        Text(session.startupDiagnostics).font(.caption2).lineLimit(1).frame(height:1).clipped()
          .accessibilityLabel(session.startupDiagnostics).accessibilityIdentifier("live-startup-diagnostics")
        HStack {
          Button("重绘浮窗"){session.recoverPreview()}.accessibilityIdentifier("live-qa-recover")
          Button("上一项"){session.moveSelection(-1)}.accessibilityIdentifier("live-qa-previous")
          Button("下一项"){session.moveSelection(1)}.accessibilityIdentifier("live-qa-next")
        }.font(.caption)
      }
    }.padding(.horizontal,18).padding(.vertical,12).background(NativeReadingTheme.background)
      .disabled(session.preparing)
  }
}
