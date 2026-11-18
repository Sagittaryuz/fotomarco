import SwiftUI
import UIKit

enum GallerySelectionRange {
    static func applying<ID: Hashable>(_ ids: [ID], from: Int, through: Int, initial: Set<ID>, selecting: Bool) -> Set<ID> {
        guard ids.indices.contains(from), ids.indices.contains(through) else { return initial }
        var result = initial
        for id in ids[min(from, through)...max(from, through)] {
            if selecting { result.insert(id) } else { result.remove(id) }
        }
        return result
    }
}

/// A collection view provides iOS's native two-finger multiple-selection gesture.
struct GalleryGrid<Item: Identifiable, Tile: View>: UIViewRepresentable where Item.ID: Hashable {
    let groups: [GalleryGroup<Item>]
    @Binding var selecting: Bool
    @Binding var selected: Set<Item.ID>
    @Binding var columns: Int
    let tile: (Item) -> Tile
    let open: (Item) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 3
        layout.minimumLineSpacing = 3
        layout.headerReferenceSize = CGSize(width: 1, height: 36)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.allowsMultipleSelection = true
        view.allowsSelectionDuringEditing = true
        view.allowsMultipleSelectionDuringEditing = true
        view.register(GallerySelectionCell.self, forCellWithReuseIdentifier: "tile")
        view.register(GallerySectionHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        let drag = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dragSelection(_:)))
        drag.maximumNumberOfTouches = 1
        drag.delegate = context.coordinator
        view.addGestureRecognizer(drag)
        view.panGestureRecognizer.require(toFail: drag)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)
        context.coordinator.collection = view
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        let oldIDs = coordinator.parent.groups.map { $0.items.map(\.id) }
        let newIDs = groups.map { $0.items.map(\.id) }
        let changed = oldIDs != newIDs || coordinator.parent.columns != columns || coordinator.parent.groups.map(\.title) != groups.map(\.title)
        coordinator.parent = self
        view.isEditing = selecting
        if changed { coordinator.rebuildIndex(); view.collectionViewLayout.invalidateLayout(); view.reloadData() }
        coordinator.synchronizeSelection()
    }

    static func dismantleUIView(_ uiView: UICollectionView, coordinator: Coordinator) {
        coordinator.stopAutoScroll()
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
        var parent: GalleryGrid
        weak var collection: UICollectionView?
        private var dragOrigin: IndexPath?
        private var dragInitial: Set<Item.ID> = []
        private var dragAdds = true
        private var lastPoint: CGPoint?
        private var timer: CADisplayLink?
        private var positions: [Item.ID: IndexPath] = [:]
        private var orderedPaths: [IndexPath] = []
        private var orderedIDs: [Item.ID] = []
        private var pathOffsets: [IndexPath: Int] = [:]

        init(_ parent: GalleryGrid) { self.parent = parent; super.init(); rebuildIndex() }
        func rebuildIndex() {
            positions.removeAll(); orderedPaths.removeAll(); orderedIDs.removeAll(); pathOffsets.removeAll()
            for section in parent.groups.indices {
                for index in parent.groups[section].items.indices {
                    let path = IndexPath(item: index, section: section)
                    positions[parent.groups[section].items[index].id] = path
                    pathOffsets[path] = orderedPaths.count; orderedPaths.append(path)
                    orderedIDs.append(parent.groups[section].items[index].id)
                }
            }
        }
        func numberOfSections(in collectionView: UICollectionView) -> Int { parent.groups.count }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { parent.groups[section].items.count }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "tile", for: indexPath) as! GallerySelectionCell
            let item = parent.groups[indexPath.section].items[indexPath.item]
            cell.contentConfiguration = UIHostingConfiguration { parent.tile(item) }.margins(.all, 0)
            cell.selectionMode = parent.selecting
            cell.showSelected(parent.selected.contains(item.id))
            return cell
        }
        func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
            let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath) as! GallerySectionHeader
            header.label.text = parent.groups[indexPath.section].title
            return header
        }
        func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            let count = max(1, parent.columns)
            let side = floor((collectionView.bounds.width - CGFloat(count - 1) * 3) / CGFloat(count))
            return CGSize(width: max(1, side), height: max(1, side))
        }
        func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
            CGSize(width: collectionView.bounds.width, height: 36)
        }
        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            let item = parent.groups[indexPath.section].items[indexPath.item]
            if parent.selecting {
                parent.selected.insert(item.id)
                (collectionView.cellForItem(at: indexPath) as? GallerySelectionCell)?.showSelected(true)
            } else {
                collectionView.deselectItem(at: indexPath, animated: false)
                parent.open(item)
            }
        }
        func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
            guard parent.selecting else { return }
            parent.selected.remove(parent.groups[indexPath.section].items[indexPath.item].id)
            (collectionView.cellForItem(at: indexPath) as? GallerySelectionCell)?.showSelected(false)
        }
        func collectionView(_ collectionView: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool { true }
        func collectionView(_ collectionView: UICollectionView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
            parent.selecting = true
            collectionView.isEditing = true
            synchronizeSelection()
        }
        func synchronizeSelection() {
            guard let collection else { return }
            let paths = Set(parent.selecting ? parent.selected.compactMap { positions[$0] } : [])
            let current = Set(collection.indexPathsForSelectedItems ?? [])
            for path in current.subtracting(paths) {
                collection.deselectItem(at: path, animated: false)
            }
            for path in paths.subtracting(current) { collection.selectItem(at: path, animated: false, scrollPosition: []) }
            for case let cell as GallerySelectionCell in collection.visibleCells {
                cell.selectionMode = parent.selecting
                if let path = collection.indexPath(for: cell) { cell.showSelected(parent.selected.contains(parent.groups[path.section].items[path.item].id)) }
            }
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let collection else { return false }
            if gestureRecognizer is UIPinchGestureRecognizer { return !parent.selecting }
            return parent.selecting && collection.indexPathForItem(at: gestureRecognizer.location(in: collection)) != nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .ended else { return }
            parent.columns = GalleryZoom.next(columns: parent.columns, magnification: gesture.scale)
        }
        @objc func dragSelection(_ gesture: UIPanGestureRecognizer) {
            guard let collection else { return }
            let point = gesture.location(in: collection)
            switch gesture.state {
            case .began:
                let translation = gesture.translation(in: collection)
                let initialPoint = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
                guard let path = collection.indexPathForItem(at: initialPoint) else { return }
                dragOrigin = path; dragInitial = parent.selected
                dragAdds = !dragInitial.contains(parent.groups[path.section].items[path.item].id)
                lastPoint = point
                let displayLink = CADisplayLink(target: self, selector: #selector(autoScroll))
                displayLink.add(to: .main, forMode: .common); timer = displayLink
                applyRange(to: collection.indexPathForItem(at: point) ?? path)
            case .changed:
                lastPoint = point
                if let path = collection.indexPathForItem(at: point) { applyRange(to: path) }
            default:
                timer?.invalidate(); timer = nil; dragOrigin = nil; lastPoint = nil
            }
        }
        private func applyRange(to end: IndexPath) {
            guard let start = dragOrigin else { return }
            guard let a = pathOffsets[start], let b = pathOffsets[end] else { return }
            parent.selected = GallerySelectionRange.applying(orderedIDs, from: a, through: b, initial: dragInitial, selecting: dragAdds)
            synchronizeSelection()
        }
        @objc private func autoScroll() {
            guard let collection, let point = lastPoint else { return }
            let visibleY = point.y - collection.contentOffset.y
            let edge: CGFloat = 52
            let speed: CGFloat = visibleY < edge ? -8 : visibleY > collection.bounds.height - edge ? 8 : 0
            guard speed != 0 else { return }
            let maximum = max(-collection.adjustedContentInset.top, collection.contentSize.height - collection.bounds.height + collection.adjustedContentInset.bottom)
            let y = min(max(-collection.adjustedContentInset.top, collection.contentOffset.y + speed), maximum)
            let delta = y - collection.contentOffset.y
            guard delta != 0 else { return }
            collection.contentOffset.y = y
            lastPoint = CGPoint(x: point.x, y: point.y + delta)
            if let next = lastPoint, let path = collection.indexPathForItem(at: next) { applyRange(to: path) }
        }
        func stopAutoScroll() { timer?.invalidate(); timer = nil; dragOrigin = nil; lastPoint = nil }
        deinit { timer?.invalidate() }
    }
}

private final class GallerySelectionCell: UICollectionViewCell {
    private let badge = UIImageView()
    var selectionMode = false { didSet { badge.isHidden = !selectionMode } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.contentMode = .scaleAspectFit
        contentView.addSubview(badge)
        NSLayoutConstraint.activate([badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
                                     badge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
                                     badge.widthAnchor.constraint(equalToConstant: 25), badge.heightAnchor.constraint(equalToConstant: 25)])
        badge.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func showSelected(_ selected: Bool) {
        badge.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
        badge.tintColor = selected ? .systemBlue : .white
        badge.layer.shadowColor = UIColor.black.cgColor; badge.layer.shadowOpacity = 0.8; badge.layer.shadowRadius = 2
        contentView.bringSubviewToFront(badge)
    }
}

private final class GallerySectionHeader: UICollectionReusableView {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                                     label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                                     label.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
