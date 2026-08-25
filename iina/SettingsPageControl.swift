//
//  SettingsPageControl.swift
//  iina
//
//  Created by Hechen Li on 2026-02-01.
//  Copyright © 2026 lhc. All rights reserved.
//

class SettingsPageControl: SettingsPage {
  override var identifier: String {
    "control"
  }

  override var title: String {
    return NSLocalizedString("preference.control", comment: "control")
  }

  override var image: NSImage {
    return .sf("computermouse", "command", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsControlLocalizable"
  }

  override func content() -> [SettingsSection] {
    return sections {
      sectionTrackpad()
    }
  }

  private func sectionTrackpad() -> SettingsSection {
    return section {
      SettingsList(title: .text_Trackpad) {
        SettingsItem.PopupButton()
          .bindTo(.pinchAction, ofType: Preference.PinchAction.self)
          .image(name: "rectangle.fill")
        SettingsItem.PopupButton()
          .bindTo(.forceTouchAction, ofType: Preference.MouseClickAction.self)
          .availableTags([0, 1, 2, 3])
      }
    }
  }
}
