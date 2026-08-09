//
//  PrefControlViewController.swift
//  iina
//
//  Created by lhc on 20/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

@objcMembers
class PrefControlViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefControlViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.control", comment: "Control")
  }

  var preferenceTabImage: NSImage {
    return .sf("computermouse", "command", withConfiguration: symbolConfiguration)!
  }

  override var sectionViews: [NSView] {
    return [sectionTrackpadView, sectionMouseView]
  }

  @IBOutlet var sectionTrackpadView: NSView!
  @IBOutlet var sectionMouseView: NSView!

  override func viewDidLoad() {
    super.viewDidLoad()

    // 通过 XIB identifier 标记过滤 sectionMouseView 子视图。
    // 保留标记为 "keep" 的控件以及隐藏的 SectionTitleMouse 标题，移除其余鼠标/滚轮动作配置控件。
    let keepIdentifiers: Set<String> = ["keep", "SectionTitleMouse"]
    sectionMouseView.subviews
      .filter { !keepIdentifiers.contains($0.identifier?.rawValue ?? "") }
      .forEach { $0.removeFromSuperview() }
  }

}
