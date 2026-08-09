//
//  SettingsPageControl.swift
//  iina
//
//  Created by Hechen Li on 2026-02-01.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate let ui = SettingsUIHelper.sharedUI


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

  private lazy var sensSeek: SliderView = .init(key: .relativeSeekAmount)
  private lazy var sensVolume: SliderView = .init(key: .volumeScrollAmount)
  private lazy var sensSpeed: SliderView = .init(key: .playbackSpeedScrollAmount)

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

fileprivate class SliderView: SettingsAccessory.Base {
  init(key: Preference.Key) {
    super.init()

    let label = NSTextField(labelWithString: ui.localized("\(key.rawValue).label"))
    label.translatesAutoresizingMaskIntoConstraints = false
    let slider = NSSlider()
    slider.translatesAutoresizingMaskIntoConstraints = false

    slider.allowsTickMarkValuesOnly = true
    slider.numberOfTickMarks = 4
    slider.minValue = 1
    slider.maxValue = 4
    slider.size(width: 100)
    slider.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue)

    view.addSubview(label)
    view.addSubview(slider)

    label.padding(.leading(SettingsSubList.indent + 8), .vertical(12))
    slider.padding(.trailing(16))
      .center(.y, with: label)
      .flexibleSpacingTo(view: label)
  }
}
