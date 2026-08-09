//
//  PlayerWindowController.swift
//  iina
//
//  Created by Yuze Jiang on 2/15/20.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

class PlayerWindowController: NSWindowController, NSWindowDelegate {

  unowned var player: PlayerCore
  
  var videoView: VideoView {
    fatalError("Subclass must implement")
  }

  var menuActionHandler: MainMenuActionHandler!
  
  var isOntop = false {
    didSet {
      player.mpv.setFlag(MPVOption.Window.ontop, isOntop)
    }
  }
  var loaded = false
  
  let subsystem: Logger.Subsystem

  init(playerCore: PlayerCore) {
    self.player = playerCore
    subsystem = Logger.makeSubsystem("window\(player.playerNumber)", ["macwindow"])
    super.init(window: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  // Cached user defaults values
  internal lazy var followGlobalSeekTypeWhenAdjustSlider: Bool = Preference.bool(for: .followGlobalSeekTypeWhenAdjustSlider)
  internal lazy var useExactSeek: Preference.SeekOption = Preference.enum(for: .useExactSeek)
  internal lazy var relativeSeekAmount: Int = Preference.integer(for: .relativeSeekAmount)
  internal lazy var volumeScrollAmount: Int = Preference.integer(for: .volumeScrollAmount)
  internal lazy var playbackSpeedScrollAmount: Int = Preference.integer(for: .playbackSpeedScrollAmount)
  internal lazy var singleClickAction: Preference.MouseClickAction = Preference.enum(for: .singleClickAction)
  internal lazy var doubleClickAction: Preference.MouseClickAction = Preference.enum(for: .doubleClickAction)
  internal lazy var horizontalScrollAction: Preference.ScrollAction = Preference.enum(for: .horizontalScrollAction)
  internal lazy var verticalScrollAction: Preference.ScrollAction = Preference.enum(for: .verticalScrollAction)
  
  internal var observedPrefKeys: [Preference.Key] = [
    .enableToneMapping,
    .toneMappingTargetPeak,
    .loadIccProfile,
    .toneMappingAlgorithm,
    .themeMaterial,
    .showRemainingTime,
    .alwaysFloatOnTop,
    .maxVolume,
    .useExactSeek,
    .relativeSeekAmount,
    .volumeScrollAmount,
    .playbackSpeedScrollAmount,
    .singleClickAction,
    .doubleClickAction,
    .horizontalScrollAction,
    .verticalScrollAction,
    .playlistShowMetadata,
    .playlistShowMetadataInMusicMode,
    .autoSwitchToMusicMode,
  ]
  
  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }
    
    switch keyPath {
    case PK.enableToneMapping.rawValue,
      PK.toneMappingTargetPeak.rawValue,
      PK.loadIccProfile.rawValue,
      PK.toneMappingAlgorithm.rawValue:
      videoView.refreshEdrMode()
    case PK.themeMaterial.rawValue:
      if let newValue = change[.newKey] as? Int {
        setMaterial(Preference.Theme(rawValue: newValue))
      }
    case PK.showRemainingTime.rawValue:
      if let newValue = change[.newKey] as? Bool {
        rightLabel.mode = newValue ? .remaining : .duration
      }
    case PK.alwaysFloatOnTop.rawValue:
      if let newValue = change[.newKey] as? Bool {
        if player.info.state == .playing {
          setWindowFloatingOnTop(newValue)
        }
      }
    case PK.maxVolume.rawValue:
      if let newValue = change[.newKey] as? Int {
        volumeSlider.maxValue = Double(newValue)
        if player.mpv.getDouble(MPVOption.Audio.volume) > Double(newValue) {
          player.mpv.setDouble(MPVOption.Audio.volume, Double(newValue))
        }
      }
    case PK.useExactSeek.rawValue:
      if let newValue = change[.newKey] as? Int {
        useExactSeek = Preference.SeekOption(rawValue: newValue)!
      }
    case PK.relativeSeekAmount.rawValue:
      if let newValue = change[.newKey] as? Int {
        relativeSeekAmount = newValue.clamped(to: 1...5)
      }
    case PK.volumeScrollAmount.rawValue:
      if let newValue = change[.newKey] as? Int {
        volumeScrollAmount = newValue.clamped(to: 1...4)
      }
    case PK.playbackSpeedScrollAmount.rawValue:
      if let newValue = change[.newKey] as? Int {
        playbackSpeedScrollAmount = newValue.clamped(to: 1...4)
      }
    case PK.singleClickAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        singleClickAction = Preference.MouseClickAction(rawValue: newValue)!
      }
    case PK.doubleClickAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        doubleClickAction = Preference.MouseClickAction(rawValue: newValue)!
      }
    case PK.horizontalScrollAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        horizontalScrollAction = Preference.ScrollAction(rawValue: newValue)!
      }
    case PK.verticalScrollAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        verticalScrollAction = Preference.ScrollAction(rawValue: newValue)!
      }
    case PK.autoSwitchToMusicMode.rawValue:
      player.overrideAutoSwitchToMusicMode = false
    default:
      return
    }
  }

  @IBOutlet weak var volumeSlider: NSSlider!
  @IBOutlet weak var muteButton: NSButton!
  @IBOutlet weak var playButton: NSButton!
  @IBOutlet weak var playSlider: PlaySlider!
  @IBOutlet weak var rightLabel: DurationDisplayTextField!
  @IBOutlet weak var leftLabel: DurationDisplayTextField!

  /** Differentiate between single clicks and double clicks. */
  internal var singleClickTimer: Timer?
  internal var mouseExitEnterCount = 0

  // Scroll direction

  /** The direction of current scrolling event. */
  enum ScrollDirection {
    case horizontal
    case vertical
  }

  internal var scrollDirection: ScrollDirection?

  /** We need to pause the video when a user starts seeking by scrolling.
   This property records whether the video is paused initially so we can
   recover the status when scrolling finished. */
  private var wasPlayingBeforeSeeking = false
  
  /** Subclasses should set these value to true if the mouse is in some
   special views (e.g. volume slider, play slider) before calling
   `super.scrollWheel()` and set them back to false after calling
   `super.scrollWheel()`.*/
  internal var seekOverride = false
  internal var volumeOverride = false

  internal var mouseActionDisabledViews: [NSView?] {[]}

  /** This variable is true when the window ready to show but waiting for size from mpv.
   In the `notifyWindowVideoSizeChanged()` call, this variable will be checked and the
   window will be shown if this variable is true.
   */
  internal var pendingShow = false

  // MARK: - Initialization

  override func windowDidLoad() {
    super.windowDidLoad()
    loaded = true
    // Issue #5319 seemed to be triggered by the window not loading. Need to know when the window
    // has loaded to be able to debug such issues.
    log("Player window has been loaded")

    guard let window = window else { return }
    
    // Insert `menuActionHandler` into the responder chain
    menuActionHandler = MainMenuActionHandler(playerCore: player)
    let responder = window.nextResponder
    window.nextResponder = menuActionHandler
    menuActionHandler.nextResponder = responder
    
    window.initialFirstResponder = nil
    window.titlebarAppearsTransparent = true
    
    setMaterial(Preference.enum(for: .themeMaterial))
    
    addObserver(to: .default, forName: .iinaMediaTitleChanged, object: player) { [unowned self] _ in
        self.updateTitle()
    }

    leftLabel.mode = .current
    rightLabel.mode = Preference.bool(for: .showRemainingTime) ? .remaining : .duration

    updateVolume()

    observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }

    addObserver(to: .default, forName: .iinaFileLoaded, object: player) { [unowned self] _ in
      self.updateTitle()
    }

    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [unowned self] _ in
      if Preference.bool(for: .pauseWhenGoesToSleep) {
        self.player.pause()
      }
    }

    addObserver(to: .default, forName: NSScreen.colorSpaceDidChangeNotification, object: nil) { [unowned self] noti in
      player.refreshEdrMode()
    }
  }

  deinit {
    ObjcUtils.silenced {
      for key in self.observedPrefKeys {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }
    }
  }

  internal func addObserver(to notificationCenter: NotificationCenter, forName name: Notification.Name, object: Any? = nil, using block: @escaping (Notification) -> Void) {
    notificationCenter.addObserver(forName: name, object: object, queue: .main, using: block)
  }

  internal func setMaterial(_ theme: Preference.Theme?) {
    guard let window = window, let theme = theme else { return }

    window.appearance = NSAppearance(iinaTheme: theme)
    window.backgroundColor = window.effectiveAppearance.isDark ? .black : .white
  }

  // MARK: - Mouse / Trackpad events


  @discardableResult
  func handleKeyBinding(_ keyBinding: KeyMapping) -> Bool {
    if keyBinding.isIINACommand {
      // - IINA command
      if let iinaCommand = IINACommand(rawValue: keyBinding.rawAction) {
        handleIINACommand(iinaCommand)
        return true
      } else {
        log("Unknown iina command \(keyBinding.rawAction)", level: .error)
        return false
      }
    } else {
      // - mpv command
      let returnValue: Int32
      // execute the command
      switch keyBinding.action.first! {

      case MPVCommand.abLoop.rawValue:
        abLoop()
        returnValue = 0

      case MPVCommand.quit.rawValue:
        // Initiate application termination. AppKit requires this be done from the main thread,
        // however the main dispatch queue must not be used to avoid blocking the queue as per
        // instructions from Apple. IINA must support quitting being initiated by mpv as the user
        // could use mpv's IPC interface to send the quit command directly to mpv. However the
        // shutdown sequence is cleaner when initiated by IINA, so we do not send the quit command
        // to mpv and instead trigger the normal app termination sequence.
        RunLoop.main.perform(inModes: [.common]) {
          NSApp.terminate(nil)
        }
        returnValue = 0

      case MPVCommand.screenshot.rawValue:
        return player.screenshot(fromKeyBinding: keyBinding)
        
      default:
        returnValue = player.mpv.command(rawString: keyBinding.rawAction)
      }

      if returnValue == 0 {
        return true
      } else {
        log("Return value \(returnValue) when executing key command \(keyBinding.rawAction)", level: .error)
        return false
      }
    }
  }

  /// 尝试将鼠标键事件派发给 mpv input.conf 绑定。
  /// 返回 true 表示已处理（调用方应停止后续 IINA 逻辑）；false 表示无绑定，由调用方走原有 IINA 逻辑。
  @discardableResult
  private func handleInputBinding(_ input: String) -> Bool {
    guard let keyBinding = PlayerCore.keyBindings[input] else { return false }
    return handleKeyBinding(keyBinding)
  }

  /// 将 macOS 鼠标按钮编号映射为 mpv 按钮名称。
  private func mpvMouseButtonName(for buttonNumber: Int) -> String? {
    switch buttonNumber {
    case 2: return "MBTN_MID"
    case 3: return "MBTN_FORWARD"
    case 4: return "MBTN_BACK"
    default: return nil
    }
  }

  func abLoop() {
    player.abLoop()
    syncSlider()
  }

  func syncSlider() {
    let a = player.abLoopA
    playSlider.abLoopA.isHidden = a == 0
    playSlider.abLoopA.doubleValue = secondsToPercent(a)
    let b = player.abLoopB
    playSlider.abLoopB.isHidden = b == 0
    playSlider.abLoopB.doubleValue = secondsToPercent(b)
    playSlider.needsDisplay = true
  }

  /// Returns the percent of the total duration of the video the given position in seconds represents.
  ///
  /// The percentage returned must be considered an estimate that could change. The duration of the video is obtained from the
  /// [mpv](https://mpv.io/manual/stable/) `duration` property. The documentation for this property cautions that mpv
  /// is not always able to determine the duration and when it does return a duration it may be an estimate. If the duration is unknown
  /// this method will fallback to using the current playback position, if that is known. Otherwise this method will return zero.
  /// - Parameter seconds: Position in the video as seconds from start.
  /// - Returns: The percent of the video the given position represents.
  private func secondsToPercent(_ seconds: Double) -> Double {
    if let duration = player.info.videoDuration?.second {
      return duration == 0 ? 0 : seconds / duration * 100
    } else if let position = player.info.videoPosition?.second {
      return position == 0 ? 0 : seconds / position * 100
    } else {
      return 0
    }
  }

  override func keyDown(with event: NSEvent) {
    let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
    let normalizedKeyCode = KeyCodeHelper.normalizeMpv(keyCode)
    
    PluginInputManager.handle(
      input: normalizedKeyCode, event: .keyDown, player: player,
      arguments: keyEventArgs(event), handler: {
      if let kb = PlayerCore.keyBindings[normalizedKeyCode] {
        self.handleKeyBinding(kb)
        return true
      }
      return false
    }, defaultHandler: {
      super.keyDown(with: event)
    })
  }
  
  override func keyUp(with event: NSEvent) {
    let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
    let normalizedKeyCode = KeyCodeHelper.normalizeMpv(keyCode)
    
    PluginInputManager.handle(
      input: normalizedKeyCode, event: .keyUp, player: player,
      arguments: keyEventArgs(event)
    )
  }
  
  
  override func mouseDown(with event: NSEvent) {
    PluginInputManager.handle(
      input: PluginInputManager.Input.mouse, event: .mouseDown,
      player: player, arguments: mouseEventArgs(event)
    )
    // we don't call super here because before adding the plugin system,
    // MainWindowController didn't call super at all
  }

  override func mouseUp(with event: NSEvent) {
    guard !event.inAnyOf(mouseActionDisabledViews) else { return }

    PluginInputManager.handle(
      input: PluginInputManager.Input.mouse, event: .mouseUp, player: player,
      arguments: mouseEventArgs(event), defaultHandler: { [self] in
      if event.clickCount == 2 {
        self.handleInputBinding("MBTN_LEFT_DBL")
      } else {
        self.handleInputBinding("MBTN_LEFT")
      }
    })
  }

  /// This method is provided soly for invoking plugin input handlers.
  func informPluginMouseDragged(with event: NSEvent) {
    PluginInputManager.handle(
      input: PluginInputManager.Input.mouse, event: .mouseDrag, player: player,
      arguments: mouseEventArgs(event)
    )
  }

  override func rightMouseDown(with event: NSEvent) {
    PluginInputManager.handle(
      input: PluginInputManager.Input.rightMouse, event: .mouseDown,
      player: player, arguments: mouseEventArgs(event)
    )
  }

  override func rightMouseUp(with event: NSEvent) {
    guard !event.inAnyOf(mouseActionDisabledViews) else { return }

    PluginInputManager.handle(
      input: PluginInputManager.Input.rightMouse, event: .mouseUp, player: player,
      arguments: mouseEventArgs(event), defaultHandler: {
      self.handleInputBinding("MBTN_RIGHT")
    })
  }

  override func otherMouseUp(with event: NSEvent) {
    guard !event.inAnyOf(mouseActionDisabledViews) else { return }

    PluginInputManager.handle(
      input: PluginInputManager.Input.otherMouse, event: .mouseUp, player: player,
      arguments: mouseEventArgs(event), defaultHandler: {
      guard event.type == .otherMouseUp else {
        super.otherMouseUp(with: event)
        return
      }
      if let input = self.mpvMouseButtonName(for: event.buttonNumber) {
        self.handleInputBinding(input)
      }
    })
  }

  internal func performMouseAction(_ action: Preference.MouseClickAction) {
    switch action {
    case .pause:
      player.togglePause()
    default:
      break
    }
  }
  
  override func scrollWheel(with event: NSEvent) {
    // 仅当存在 mpv WHEEL_* 绑定时处理滚轮事件
    if event.phase.isEmpty {
      _ = self.tryWheelBinding(event)
    }
  }

  /// 尝试将鼠标滚轮事件派发给 mpv WHEEL_* binding。
  /// 仅对 phase.isEmpty 的离散滚轮事件生效；trackpad 连续滚动返回 false 走原有逻辑。
  private func tryWheelBinding(_ event: NSEvent) -> Bool {
    let isNatural = event.isDirectionInvertedFromDevice
    let deltaX = isNatural ? event.scrollingDeltaX : -event.scrollingDeltaX
    let deltaY = isNatural ? -event.scrollingDeltaY : event.scrollingDeltaY

    // 主方向判定
    let primaryBinding: String
    let primaryDelta: Double
    if abs(deltaY) >= abs(deltaX) {
      primaryBinding = deltaY > 0 ? "WHEEL_UP" : "WHEEL_DOWN"
      primaryDelta = Double(deltaY)
    } else {
      primaryBinding = deltaX > 0 ? "WHEEL_RIGHT" : "WHEEL_LEFT"
      primaryDelta = Double(deltaX)
    }

    guard PlayerCore.keyBindings[primaryBinding] != nil else { return false }

    // 按 delta 绝对值决定派发次数（整数计数，不做平滑插值）
    let dispatchCount = max(1, Int(abs(primaryDelta).rounded(.awayFromZero)))
    for _ in 0..<dispatchCount {
      _ = handleInputBinding(primaryBinding)
    }
    return true
  }

  // MARK: - Window delegate: Activeness status

  func windowDidBecomeMain(_ notification: Notification) {
    PlayerCore.lastActive = player
    NowPlayingInfoManager.shared.updateInfo(withTitle: true)
    AppDelegate.shared.menuController?.updatePluginMenu()

    NotificationCenter.default.post(name: .iinaMainWindowChanged, object: true)
  }

  /// The window changed its occlusion state.
  ///
  /// If the entire window is now occluded then no action is needed. But if the window has become visible then the view may need to
  /// be drawn.
  /// - Note: The window [isVisible](https://developer.apple.com/documentation/appkit/nswindow/isvisible)
  ///     property is intentionally not used. That property is `true` even when the window is fully obscured. Instead the
  ///     [occlusionState](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.property)
  ///     property is used as it will not indicate the window is visible when it is obscured by other windows.
  func windowDidChangeOcclusionState(_ notification: Notification) {
    guard let window, window.occlusionState.contains(.visible) else { return }
    forceDraw("window became visible")
  }

  func windowDidResignMain(_ notification: Notification) {
    NotificationCenter.default.post(name: .iinaMainWindowChanged, object: false)
  }

  func windowDidChangeScreen(_ notification: Notification) {
    videoView.updateDisplayLink()
  }

  // MARK: - UI

  func setupUI() {
    player.syncUI([.time, .playButton, .volume])
  }

  @objc
  func updateTitle() {
    fatalError("Must implement in the subclass")
  }
  
  func volumeIcon() -> NSImage? {
    guard !player.info.isMuted else { return .sf("speaker.slash.fill") }
    let volume = Int(player.info.volume)
    guard volume >= 0 else {
      log("Volume level \(player.info.volume) is invalid", level: .error)
      return nil
    }
    let symbol = switch Int(player.info.volume) {
    case 0: "speaker.fill"
    case 1...33: "speaker.wave.1.fill"
    case 34...66: "speaker.wave.2.fill"
    default: "speaker.wave.3.fill"
    }
    let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
    return .sf(symbol, withConfiguration: configuration)
  }

  func updateVolume() {
    volumeSlider.doubleValue = player.info.volume
  }
  
  func updatePlayTime(withDuration: Bool, andProgressBar: Bool) {
    // IINA listens for changes to mpv properties such as chapter that can occur during file loading
    // resulting in this function being called before mpv has set its position and duration
    // properties. Confirm the window and file have been loaded.
    guard loaded, player.info.state.loaded else { return }
    // The mpv documentation for the duration property indicates mpv is not always able to determine
    // the video duration in which case the property is not available.
    guard let duration = player.info.videoDuration else {
      log("Video duration not available", level: .warning)
      return
    }
    guard let pos = player.info.videoPosition else {
      log("Video position not available", level: .warning)
      return
    }
    guard let remaining = player.info.videoRemaining else {
      log("Video remaining not available", level: .warning)
      return
    }
    [leftLabel, rightLabel].forEach { $0.updateText(with: duration, given: pos, and: remaining) }
    player.touchBarSupport.touchBarPosLabels.forEach { $0.updateText(with: duration, given: pos,
                                                                     and: remaining) }
    if andProgressBar {
      let percentage = (pos.second / duration.second) * 100
      playSlider.doubleValue = percentage
      player.touchBarSupport.touchBarPlaySlider?.setDoubleValueSafely(percentage)
    }
  }
  
  func updatePlayButtonState(paused: Bool) {
    guard loaded else { return }
    playButton.image = NSImage(named: paused ? "play" : "pause")
  }

  /** This method will not set `isOntop`! */
  func setWindowFloatingOnTop(_ onTop: Bool, updateOnTopStatus: Bool = true) {
    guard let window = window else { return }
    window.level = onTop ? .iinaFloating : .normal
    if (updateOnTopStatus) {
      self.isOntop = onTop
    }
  }

  func handleVideoSizeChange() {
    fatalError("Must implement in the subclass")
  }

  /// Force a draw, if needed.
  ///
  /// If a video is actively being played then there is no need to force a draw as the view is actively being drawn. Otherwise the view
  /// must be drawn. Video tracks can be images or cover art. Even when there isn't a video track drawing sometimes must be forced
  /// to clear a previous image, such as when an audio only file is played in the main window after it was used to play a video.
  /// - Parameters:
  ///   - reason: Reason for forcing drawing.
  ///   - always: Draw even when playback is in progress and there isn't a video track. Used to clear any previous image.
  func forceDraw(_ reason: String, always: Bool = false) {
    guard player.info.state.active else { return }
    if !always {
      let notVideo = player.info.currentTrack(.video)?.isImage ?? true
      guard player.info.state == .paused || notVideo else { return }
    }
    log("Forcing drawing, \(reason)")
    videoView.videoLayer.update(force: true)
  }

  // MARK: - IBActions

  @IBAction func volumeSliderChanges(_ sender: NSSlider) {
    let value = sender.doubleValue
    if Preference.double(for: .maxVolume) > 100, value > 100 && value < 101 {
      NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
    player.setVolume(value)
  }

  @IBAction func playButtonAction(_ sender: NSButton) {
    player.info.state == .paused ? player.resume() : player.pause()
  }

  @IBAction func muteButtonAction(_ sender: NSButton) {
    player.toggleMute()
  }

  @IBAction func playSliderChanges(_ sender: NSSlider) {
    guard player.info.state.active else { return }
    let percentage = 100 * sender.doubleValue / sender.maxValue
    player.seek(percent: percentage, forceExact: !followGlobalSeekTypeWhenAdjustSlider)
  }

  internal func handleIINACommand(_ cmd: IINACommand) {
    switch cmd {
    case .openFile:
      AppDelegate.shared.openFile(self)
    case .openURL:
      AppDelegate.shared.openURL(self)
    case .deleteCurrentFile:
      menuActionHandler.menuDeleteCurrentFile(.dummy)
    case .deleteCurrentFileHard:
      menuActionHandler.menuDeleteCurrentFileHard(.dummy)
    default:
      break
    }
  }

  // MARK: - Utils

  func log(_ message: @autoclosure () -> String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: subsystem)
  }
}


fileprivate func mouseEventArgs(_ event: NSEvent) -> [[String: Any]] {
  return [[
    "x": event.locationInWindow.x,
    "y": event.locationInWindow.y,
    "clickCount": event.clickCount,
    "pressure": event.pressure
  ] as [String : Any]]
}

fileprivate func keyEventArgs(_ event: NSEvent) -> [[String: Any]] {
  return [[
    "x": event.locationInWindow.x,
    "y": event.locationInWindow.y,
    "isRepeat": event.isARepeat
  ] as [String : Any]]
}
