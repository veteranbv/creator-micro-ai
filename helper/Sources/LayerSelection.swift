// Track device state without activating a workspace on the first connection.
struct LayerSelection {
    private var lastLayer: Int?

    mutating func ready(_ layer: Int?) -> Int? {
        guard let layer, (1...4).contains(layer) else { return nil }
        let changed = lastLayer != nil && lastLayer != layer
        lastLayer = layer
        return changed ? layer : nil
    }

    mutating func observe(_ layer: Int?) {
        guard let layer, (1...4).contains(layer) else { return }
        lastLayer = layer
    }
}
