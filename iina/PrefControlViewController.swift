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
    return [sectionTrackpadView]
  }

  @IBOutlet var sectionTrackpadView: NSView!
  @IBOutlet var sectionMouseView: NSView!

}
