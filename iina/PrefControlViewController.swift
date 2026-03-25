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
    return makeSymbol("computermouse", fallbackImage: "pref_control")
  }

  override var sectionViews: [NSView] {
    return [sectionMouseView, sectionTrackpadView]
  }

  @IBOutlet var sectionTrackpadView: NSView!
  @IBOutlet var sectionMouseView: NSView!

  override func viewDidLoad() {
    super.viewDidLoad()

    guard
      let acceptsFirstMouseButton = sectionMouseView.subviews.first(where: { $0 is NSButton && !($0 is NSPopUpButton) }),
      let mouseImageContainer = sectionMouseView.subviews.first(where: {
        $0.subviews.first is NSImageView
      })
    else { return }

    sectionMouseView.subviews
      .filter { $0 != acceptsFirstMouseButton && $0 != mouseImageContainer }
      .forEach { $0.removeFromSuperview() }

    sectionMouseView.removeConstraints(sectionMouseView.constraints)
    acceptsFirstMouseButton.translatesAutoresizingMaskIntoConstraints = false
    mouseImageContainer.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      mouseImageContainer.leadingAnchor.constraint(equalTo: sectionMouseView.leadingAnchor),
      mouseImageContainer.topAnchor.constraint(equalTo: sectionMouseView.topAnchor),
      acceptsFirstMouseButton.leadingAnchor.constraint(equalTo: mouseImageContainer.trailingAnchor, constant: 20),
      acceptsFirstMouseButton.centerYAnchor.constraint(equalTo: mouseImageContainer.centerYAnchor),
      sectionMouseView.bottomAnchor.constraint(equalTo: acceptsFirstMouseButton.bottomAnchor, constant: 18),
      sectionMouseView.trailingAnchor.constraint(greaterThanOrEqualTo: acceptsFirstMouseButton.trailingAnchor, constant: 8),
    ])

    sectionMouseView.frame.size.height = 56
  }
}
