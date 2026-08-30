//
//  RegimenWidgetBundle.swift
//  RegimenWidget
//
//  Created by Alec Agayan on 8/29/26.
//

import WidgetKit
import SwiftUI

@main
struct RegimenWidgetBundle: WidgetBundle {
    var body: some Widget {
        RegimenWidget()
        RegimenWidgetControl()
        RegimenWidgetLiveActivity()
    }
}
