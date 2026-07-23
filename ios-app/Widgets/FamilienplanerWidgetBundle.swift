import WidgetKit
import SwiftUI

@main
struct FamilienplanerWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Home-/Sperrbildschirm
        HeuteWidget()
        TermineWidget()
        QuickActionsWidget()
        // Live Activity (Sperrbildschirm-Banner + Dynamic Island)
        TerminActivityWidget()
    }
}
