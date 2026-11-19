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

enum GalleryEndRefresh {
    static func reached(offset: CGFloat, maximum: CGFloat, fingerMovement: CGPoint) -> Bool {
        offset - maximum >= 54 && -fingerMovement.y > abs(fingerMovement.x)
    }
}

/// A collection view supports pinch-to-resize and selection after entering Select mode.
struct GalleryGrid<Item: Identifiable, Tile: View>: UIViewRepresentable where Item.ID: Hashable {
    let groups: [GalleryGroup<Item>]
    @Binding var selecting: Bool
    @Binding var selected: Set<Item.ID>
    @Binding var columns: Int
    var refreshKey = 0
    var showsSectionHeaders = true
    var contentVersion: Int? = nil
    var newestScrollRequest: Int? = nil
    let tile: (Item) -> Tile
    let open: (Item) -> Void
    var longPress: ((Item) -> Void)? = nil
    var reachedEnd: (() -> Void)? = nil
    var dragToCamera: ((CGFloat, Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 3
        layout.minimumLineSpacing = 3
        layout.headerReferenceSize = CGSize(width: 1, height: 44)
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
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.preview(_:)))
        hold.minimumPressDuration = 0.46
        hold.numberOfTouchesRequired = 1
        hold.delegate = context.coordinator
        view.addGestureRecognizer(hold)
        if dragToCamera != nil {
            let swipe = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.cameraSwipe(_:)))
            swipe.maximumNumberOfTouches = 1
            swipe.delegate = context.coordinator
            context.coordinator.cameraSwipeRecognizer = swipe
            view.addGestureRecognizer(swipe)
            view.panGestureRecognizer.require(toFail: swipe)
        }
        context.coordinator.collection = view
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        let old = coordinator.parent
        let contentChanged: Bool
        if let contentVersion {
            contentChanged = old.contentVersion != contentVersion
        } else {
            contentChanged = old.groups.map { $0.items.map(\.id) } != groups.map { $0.items.map(\.id) } ||
                old.groups.map(\.title) != groups.map(\.title)
        }
        coordinator.parent = self
        if view.isEditing != selecting { view.isEditing = selecting }
        if contentChanged { coordinator.rebuildIndex() }
        if contentChanged || old.columns != columns || old.refreshKey != refreshKey ||
            old.showsSectionHeaders != showsSectionHeaders {
            view.collectionViewLayout.invalidateLayout()
            view.reloadData()
        }
        coordinator.synchronizeSelection()
        if let request = newestScrollRequest { coordinator.scrollToLastIfRequested(request) }
    }

    static func dismantleUIView(_ uiView: UICollectionView, coordinator: Coordinator) {
        coordinator.stopAutoScroll()
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
        var parent: GalleryGrid
        weak var collection: UICollectionView?
        weak var cameraSwipeRecognizer: UIPanGestureRecognizer?
        private var dragOrigin: IndexPath?
        private var dragInitial: Set<Item.ID> = []
        private var dragAdds = true
        private var lastPoint: CGPoint?
        private var timer: CADisplayLink?
        private var positions: [Item.ID: IndexPath] = [:]
        private var orderedPaths: [IndexPath] = []
        private var orderedIDs: [Item.ID] = []
        private var pathOffsets: [IndexPath: Int] = [:]
        private var scrolledRequest: Int?
        private var refreshedThisDrag = false

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            refreshedThisDrag = false
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !parent.selecting, !refreshedThisDrag, scrollView.isDragging,
                  let refresh = parent.reachedEnd else { return }
            let maximum = max(-scrollView.adjustedContentInset.top,
                              scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
            let movement = scrollView.panGestureRecognizer.translation(in: scrollView)
            guard GalleryEndRefresh.reached(offset: scrollView.contentOffset.y, maximum: maximum, fingerMovement: movement) else { return }
            refreshedThisDrag = true
            refresh()
        }

        func scrollToLastIfRequested(_ request: Int) {
            guard scrolledRequest != request, let collection, let path = orderedPaths.last else { return }
            scrolledRequest = request
            DispatchQueue.main.async { [weak self, weak collection] in
                guard let self, let collection, self.parent.newestScrollRequest == request,
                      collection.numberOfSections > path.section,
                      collection.numberOfItems(inSection: path.section) > path.item else { return }
                collection.layoutIfNeeded()
                collection.scrollToItem(at: path, at: .bottom, animated: false)
            }
        }

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
            if !parent.selecting, let longPress = parent.longPress {
                cell.accessibilityCustomActions = [
                    UIAccessibilityCustomAction(name: "Ampliar e compartilhar") { _ in longPress(item); return true }
                ]
            } else {
                cell.accessibilityCustomActions = nil
            }
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
            guard parent.showsSectionHeaders, parent.groups.indices.contains(section) else { return .zero }
            let font = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: collectionView.traitCollection)
            let width = collectionView.bounds.width
            let title = parent.groups[section].title as NSString
            let height = title.boundingRect(with: CGSize(width: max(1, width - 24), height: .greatestFiniteMagnitude),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                                            attributes: [.font: font], context: nil).height
            return CGSize(width: width, height: max(44, ceil(height) + 20))
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
        func collectionView(_ collectionView: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool { false }
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
                if let path = collection.indexPath(for: cell) {
                    let item = parent.groups[path.section].items[path.item]
                    cell.showSelected(parent.selected.contains(item.id))
                    if parent.selecting { cell.accessibilityCustomActions = nil }
                    else if let longPress = parent.longPress {
                        cell.accessibilityCustomActions = [
                            UIAccessibilityCustomAction(name: "Ampliar e compartilhar") { _ in longPress(item); return true }
                        ]
                    }
                }
            }
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let collection else { return false }
            if let swipe = cameraSwipeRecognizer, gestureRecognizer === swipe {
                let velocity = swipe.velocity(in: collection)
                return !parent.selecting && parent.dragToCamera != nil && -velocity.x > abs(velocity.y) * 1.35
            }
            if gestureRecognizer is UIPinchGestureRecognizer { return !parent.selecting }
            guard collection.indexPathForItem(at: gestureRecognizer.location(in: collection)) != nil else { return false }
            if gestureRecognizer is UILongPressGestureRecognizer { return !parent.selecting && parent.longPress != nil }
            return parent.selecting
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer
        }
        @objc func cameraSwipe(_ swipe: UIPanGestureRecognizer) {
            // The collection moves during this gesture. Measure the finger in fixed window coordinates.
            let distance = -swipe.translation(in: swipe.view?.window).x
            switch swipe.state {
            case .began, .changed: parent.dragToCamera?(distance, false)
            case .ended: parent.dragToCamera?(distance, true)
            case .cancelled, .failed: parent.dragToCamera?(0, true)
            default: break
            }
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .ended else { return }
            parent.columns = GalleryZoom.next(columns: parent.columns, magnification: gesture.scale)
        }
        @objc func preview(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, !parent.selecting, let collection,
                  let path = collection.indexPathForItem(at: gesture.location(in: collection)) else { return }
            parent.longPress?(parent.groups[path.section].items[path.item])
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
    private let selectionOverlay = UIView()
    private let badge = UIView()
    private let check = UIImageView(image: UIImage(systemName: "checkmark",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)))

    var selectionMode = false {
        didSet {
            if !selectionMode { showSelected(false) }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        selectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        selectionOverlay.isUserInteractionEnabled = false
        selectionOverlay.backgroundColor = .black.withAlphaComponent(0.15)
        selectionOverlay.isHidden = true
        addSubview(selectionOverlay)

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.backgroundColor = .systemBlue
        badge.layer.cornerRadius = 13
        badge.layer.borderWidth = 1.5
        badge.layer.borderColor = UIColor.white.cgColor
        selectionOverlay.addSubview(badge)

        check.translatesAutoresizingMaskIntoConstraints = false
        check.tintColor = .white
        check.contentMode = .center
        badge.addSubview(check)
        NSLayoutConstraint.activate([
            selectionOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectionOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            selectionOverlay.topAnchor.constraint(equalTo: topAnchor),
            selectionOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            badge.trailingAnchor.constraint(equalTo: selectionOverlay.trailingAnchor, constant: -6),
            badge.bottomAnchor.constraint(equalTo: selectionOverlay.bottomAnchor, constant: -6),
            badge.widthAnchor.constraint(equalToConstant: 26),
            badge.heightAnchor.constraint(equalToConstant: 26),
            check.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            check.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        bringSubviewToFront(selectionOverlay)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        selectionMode = false
    }

    func showSelected(_ selected: Bool) {
        let visible = selectionMode && selected
        selectionOverlay.isHidden = !visible
        if visible { accessibilityTraits.insert(.selected) }
        else { accessibilityTraits.remove(.selected) }
        bringSubviewToFront(selectionOverlay)
    }
}

private final class GallerySectionHeader: UICollectionReusableView {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.accessibilityTraits.insert(.header)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                                     label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                                     label.centerYAnchor.constraint(equalTo: centerYAnchor),
                                     label.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),
                                     label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
