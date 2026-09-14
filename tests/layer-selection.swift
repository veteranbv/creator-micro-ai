@main
enum LayerSelectionTests {
    static func main() {
        var selection = LayerSelection()
        precondition(selection.ready(nil) == nil)
        precondition(selection.ready(0) == nil)
        precondition(selection.ready(1) == nil) // Cold start never steals focus.
        precondition(selection.ready(1) == nil) // Same layer after reconnect.
        precondition(selection.ready(3) == 3) // Changed while disconnected.
        precondition(selection.ready(3) == nil) // No duplicate activation.
        selection.observe(4) // A live layer event or acknowledged focus command.
        precondition(selection.ready(4) == nil)
        selection.observe(9) // Invalid data cannot corrupt the known layer.
        precondition(selection.ready(4) == nil)
        precondition(selection.ready(2) == 2)
        selection.interruptActivation()
        selection.interruptActivation() // Repeated errors retain the interrupted request.
        precondition(selection.ready(nil) == nil)
        precondition(selection.ready(9) == nil)
        precondition(selection.ready(2) == 2) // Same layer must resume the canceled activation.
        precondition(selection.ready(2) == nil) // Recovery retries only once.
        selection.observe(3)
        selection.interruptActivation()
        precondition(selection.ready(4) == 4) // The device's newer layer supersedes the interrupted one.
        precondition(selection.ready(4) == nil)
        print("PASS: cold start, reconnect, live layer updates and invalid layers. No events were posted.")
    }
}
