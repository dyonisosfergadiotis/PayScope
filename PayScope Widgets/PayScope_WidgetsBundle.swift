//
//  PayScope_WidgetsBundle.swift
//  PayScope Widgets
//
//  Created by Dyonisos Fergadiotis on 18.02.26.
//

import WidgetKit
import SwiftUI

@main
struct PayScope_WidgetsBundle: WidgetBundle {
    var body: some Widget {
        PayScopeStartShiftControl()
        PayScopeEndShiftControl()
        PayScopeAddTipControl()
        PayScopeMarkTodaySickControl()
        PayScope_WidgetsControl()
        PayScope_CurrentShiftCardWidget()
        PayScope_WidgetsLiveActivity()
        PayScope_WidgetsRectangularLockScreen()
        PayScope_WidgetsInlineLockScreen()
    }
}
