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

    // Remove mouse/scroll action controls from the Mouse section.
    // Only keep the "accepts first mouse" checkbox, "seek type" popup + label + description,
    // and the mouse image container (identified via XIB `identifier="keep"`).
    let keepIdentifiers: Set<String> = ["keep", "SectionTitleMouse"]
    sectionMouseView.subviews
      .filter { !keepIdentifiers.contains($0.identifier?.rawValue ?? "") }
      .forEach { $0.removeFromSuperview() }
  }

}
