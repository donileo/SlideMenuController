//
//  SlideMenuController.swift
//
//  Created by Adonis Peralta 03/02/2023
//

import Foundation
import UIKit

@objc public protocol SlideMenuControllerDelegate {
    @objc optional func slideMenuController(
        viewController: SlideMenuController, willOpenContainerView view: UIView, containerViewController: UIViewController?,
        containerViewId: SlideMenuController.SideContainerViewId
    )

    @objc optional func slideMenuController(
        viewController: SlideMenuController, didOpenContainerView view: UIView, containerViewController: UIViewController?,
        containerViewId: SlideMenuController.SideContainerViewId
    )

    @objc optional func slideMenuController(
        viewController: SlideMenuController, willCloseContainerView view: UIView, containerViewController: UIViewController?,
        containerViewId: SlideMenuController.SideContainerViewId
    )

    @objc optional func slideMenuController(
        viewController: SlideMenuController, didCloseContainerView view: UIView, containerViewController: UIViewController?,
        containerViewId: SlideMenuController.SideContainerViewId
    )
}

open class SlideMenuController: UIViewController, UIGestureRecognizerDelegate {
    public enum ContainerViewId: Int {
        case left, right, main
    }

    @objc public enum SideContainerViewId: Int {
        case left, right
    }

    public struct Config {
        public static let `default` = Config()

        public var leftViewWidth: CGFloat = 270.0
        public var leftBezelWidth: CGFloat? = 16.0
        public var leftViewOffsetY: CGFloat = 0
        public var rightViewWidth: CGFloat = 270.0
        public var rightBezelWidth: CGFloat? = 16.0
        public var rightViewOffsetY: CGFloat = 0

        public var contentViewScale: CGFloat = 0.96
        public var contentViewOpacity: CGFloat = 0.5
        public var contentViewDrag = false

        public var shadowOpacity: CGFloat = 0
        public var shadowRadius: CGFloat = 0
        public var shadowOffset: CGSize = .init(width: 0, height: 0)

        public var animationDuration: CGFloat = 0.4
        public var animationOptions: UIView.AnimationOptions = []

        public var hideStatusBar = true
        public var panFromBezel = true
        public var rightPanFromBezel = true
        public var pointOfNoReturnWidth: CGFloat = 44.0
        public var simultaneousGestureRecognizers = true
        public var opacityViewBackgroundColor: UIColor = .black
        public var panGesturesEnabled = true
        public var tapGesturesEnabled = true
    }

    public enum SlideAction {
        case open
        case close
    }

    public enum TrackAction {
        case tapOpen
        case tapClose
        case flickOpen
        case flickClose
    }

    struct PanState {
        var frameAtStart: CGRect = .zero
        var startPoint: CGPoint = .zero
        var wasOpenAtStart = false
        var wasHiddenAtStart = false
        var last: UIGestureRecognizer.State = .ended
    }

    struct PanInfo {
        var action: SlideAction
        var shouldBounce: Bool
        var velocity: CGFloat
    }

    open weak var delegate: SlideMenuControllerDelegate?

    open var config = Config()

    open var opacityView = UIView()
    open var mainContainerView = UIView()
    open var leftContainerView = UIView()
    open var rightContainerView = UIView()

    open var mainViewController: UIViewController?
    open var leftViewController: UIViewController?
    open var rightViewController: UIViewController?

    open var leftPanGesture: UIPanGestureRecognizer?
    open var leftTapGesture: UITapGestureRecognizer?
    open var rightPanGesture: UIPanGestureRecognizer?
    open var rightTapGesture: UITapGestureRecognizer?

    open var isLeftOpen: Bool {
        leftViewController != nil && leftContainerView.frame.origin.x == 0.0
    }

    open var isLeftHidden: Bool {
        leftContainerView.frame.origin.x <= leftMinOrigin
    }

    open var isRightOpen: Bool {
        rightViewController != nil &&
            rightContainerView.frame.origin.x == view.bounds.width - rightContainerView.frame.size.width
    }

    open var isRightHidden: Bool {
        rightContainerView.frame.origin.x >= view.bounds.width
    }

    // Variable to determine the target ViewController
    // Please to override it if necessary
    open var isTargetViewController: Bool {
        true
    }

    fileprivate var leftMinOrigin: CGFloat {
        -config.leftViewWidth
    }

    fileprivate var rightMinOrigin: CGFloat {
        view.bounds.width
    }

    open var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.flatMap { ($0 as? UIWindowScene)?.windows ?? [] }.first { $0.isKeyWindow }
    }

    fileprivate var openedLeftRatio: CGFloat {
        let width: CGFloat = leftContainerView.frame.size.width
        let currentPosition = leftContainerView.frame.origin.x - leftMinOrigin
        return currentPosition / width
    }

    fileprivate var openedRightRatio: CGFloat {
        let width: CGFloat = rightContainerView.frame.size.width
        let currentPosition: CGFloat = rightContainerView.frame.origin.x
        return -(currentPosition - view.bounds.width) / width
    }

    private var rightPanState = PanState()
    private var leftPanState = PanState()

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    public convenience init(
        mainViewController: UIViewController, leftViewController: UIViewController? = nil,
        rightViewController: UIViewController? = nil
    ) {
        self.init()
        self.mainViewController = mainViewController
        self.leftViewController = leftViewController
        self.rightViewController = rightViewController
        setupViews()
    }

    override open func awakeFromNib() {
        super.awakeFromNib()
        setupViews()
    }

    open func setupViews() {
        setupMainContainerView()
        setupOpacityView()
        setupContainerView(.left)
        setupContainerView(.right)
    }

    private func setupMainContainerView() {
        mainContainerView = UIView(frame: view.bounds)
        mainContainerView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        view.insertSubview(mainContainerView, at: 0)
    }

    private func setupOpacityView() {
        let opacityOffset: CGFloat = 0

        var opacityFrame = view.bounds
        opacityFrame.origin.y = opacityFrame.origin.y + opacityOffset
        opacityFrame.size.height = opacityFrame.size.height - opacityOffset

        opacityView = UIView(frame: opacityFrame)
        opacityView.backgroundColor = config.opacityViewBackgroundColor
        opacityView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        opacityView.alpha = 0 // Starts at 0 since the panels are closed
        opacityView.isHidden = true
        view.insertSubview(opacityView, at: 1)
    }

    private func viewController(for containerViewId: ContainerViewId) -> UIViewController? {
        switch containerViewId {
        case .left:
            return leftViewController
        case .right:
            return rightViewController
        case .main:
            return mainViewController
        }
    }

    private func viewController(for containerViewId: SideContainerViewId) -> UIViewController? {
        switch containerViewId {
        case .left:
            return leftViewController
        case .right:
            return rightViewController
        }
    }

    private func subviewPosition(for containerViewId: SideContainerViewId) -> Int {
        switch containerViewId {
        case .left:
            return 2
        case .right:
            return 3
        }
    }

    private func containerView(for containerViewId: ContainerViewId) -> UIView {
        switch containerViewId {
        case .left:
            return leftContainerView
        case .right:
            return rightContainerView
        case .main:
            return mainContainerView
        }
    }

    private func containerView(for containerViewId: SideContainerViewId) -> UIView {
        switch containerViewId {
        case .left:
            return leftContainerView
        case .right:
            return rightContainerView
        }
    }

    private func setupContainerView(_ containerViewId: SideContainerViewId) {
        guard viewController(for: containerViewId) != nil else { return }
        var containerFrame = view.bounds

        let frameWidth: CGFloat
        let frameOrigin: CGFloat
        let frameOriginYOffset: CGFloat

        switch containerViewId {
        case .left:
            frameWidth = config.leftViewWidth
            frameOrigin = leftMinOrigin
            frameOriginYOffset = config.leftViewOffsetY
        case .right:
            frameWidth = config.rightViewWidth
            frameOrigin = rightMinOrigin
            frameOriginYOffset = config.rightViewOffsetY
        }

        containerFrame.size.width = frameWidth
        containerFrame.origin.x = frameOrigin

        containerFrame.origin.y = containerFrame.origin.y + frameOriginYOffset
        containerFrame.size.height = containerFrame.size.height - frameOriginYOffset

        let containerView: UIView

        switch containerViewId {
        case .left:
            leftContainerView = UIView(frame: containerFrame)
            containerView = leftContainerView
        case .right:
            rightContainerView = UIView(frame: containerFrame)
            containerView = rightContainerView
        }

        containerView.autoresizingMask = .flexibleHeight

        let subViewPos = subviewPosition(for: containerViewId)
        view.insertSubview(containerView, at: subViewPos)
        addGestures(for: containerViewId)
    }

    override open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        mainContainerView.transform = .identity
        leftContainerView.isHidden = true
        rightContainerView.isHidden = true

        coordinator.animate(alongsideTransition: nil) { _ in
            self.closeNonAnimation(for: .left)
            self.closeNonAnimation(for: .right)

            self.leftContainerView.isHidden = false
            self.rightContainerView.isHidden = false

            if self.leftPanGesture != nil {
                self.removeGestures(for: .left)
                self.addGestures(for: .left)
            }

            if self.rightPanGesture != nil {
                self.removeGestures(for: .right)
                self.addGestures(for: .right)
            }
        }
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        edgesForExtendedLayout = .all
    }

    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        mainViewController?.supportedInterfaceOrientations ?? .all
    }

    override open var shouldAutorotate: Bool {
        mainViewController?.shouldAutorotate ?? false
    }

    override open func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        if let mainViewController {
            setUpViewController(mainContainerView, targetViewController: mainViewController)
        }

        if let leftViewController {
            setUpViewController(leftContainerView, targetViewController: leftViewController)
        }

        if let rightViewController {
            setUpViewController(rightContainerView, targetViewController: rightViewController)
        }
    }

    override open var preferredStatusBarStyle: UIStatusBarStyle {
        mainViewController?.preferredStatusBarStyle ?? .default
    }

    override open var prefersStatusBarHidden: Bool {
        mainViewController?.prefersStatusBarHidden ?? false
    }

    open func open(_ containerViewId: SideContainerViewId) {
        guard let containerViewController = viewController(for: containerViewId) else { return }
        let containerView = containerView(for: containerViewId)

        delegate?.slideMenuController?(
            viewController: self, willOpenContainerView: containerView, containerViewController: containerViewController,
            containerViewId: containerViewId
        )

        setOpenWindowLevel()

        let isContainerViewHidden: Bool
        switch containerViewId {
        case .left:
            isContainerViewHidden = isLeftHidden
        case .right:
            isContainerViewHidden = isRightHidden
        }

        containerViewController.beginAppearanceTransition(isContainerViewHidden, animated: true)
        open(containerViewId, withVelocity: 0)
        track(.tapOpen, containerViewId: containerViewId)
    }

    open func close(_ containerViewId: SideContainerViewId) {
        guard let containerViewController = viewController(for: containerViewId) else { return }
        let containerView = containerView(for: containerViewId)

        delegate?.slideMenuController?(
            viewController: self, willCloseContainerView: containerView, containerViewController: containerViewController,
            containerViewId: containerViewId
        )

        let isContainerViewHidden: Bool
        switch containerViewId {
        case .left:
            isContainerViewHidden = isLeftHidden
        case .right:
            isContainerViewHidden = isRightHidden
        }

        containerViewController.beginAppearanceTransition(isContainerViewHidden, animated: true)
        close(containerViewId, withVelocity: 0)
        setCloseWindowLevel()
    }

    private func addGestures(for containerViewId: SideContainerViewId) {
        guard viewController(for: containerViewId) != nil else { return }

        if config.panGesturesEnabled {
            let panGestureForContainerViewId: UIPanGestureRecognizer?
            let panGestureRecognizerAction: Selector?

            switch containerViewId {
            case .left:
                panGestureForContainerViewId = leftPanGesture
                panGestureRecognizerAction = #selector(handleLeftPanGesture)
            case .right:
                panGestureForContainerViewId = rightPanGesture
                panGestureRecognizerAction = #selector(handleRightPanGesture)
            }

            if panGestureForContainerViewId == nil {
                let panGesture = UIPanGestureRecognizer(target: self, action: panGestureRecognizerAction)
                panGesture.delegate = self
                view.addGestureRecognizer(panGesture)

                switch containerViewId {
                case .left:
                    leftPanGesture = panGesture
                case .right:
                    rightPanGesture = panGesture
                }
            }
        }

        if config.tapGesturesEnabled {
            let tapGestureForContainerViewId: UITapGestureRecognizer?
            let tapGestureRecognizerAction: Selector?

            switch containerViewId {
            case .left:
                tapGestureForContainerViewId = leftTapGesture
                tapGestureRecognizerAction = #selector(toggleLeft)
            case .right:
                tapGestureForContainerViewId = rightTapGesture
                tapGestureRecognizerAction = #selector(toggleRight)
            }

            if tapGestureForContainerViewId == nil {
                let tapGesture = UITapGestureRecognizer(target: self, action: tapGestureRecognizerAction)
                tapGesture.delegate = self
                view.addGestureRecognizer(tapGesture)

                switch containerViewId {
                case .left:
                    leftTapGesture = tapGesture
                case .right:
                    rightTapGesture = tapGesture
                }
            }
        }
    }

    open func removeGestures(for containerViewId: SideContainerViewId) {
        let panGesture: UIPanGestureRecognizer?
        let tapGesture: UITapGestureRecognizer?

        switch containerViewId {
        case .left:
            panGesture = leftPanGesture
            tapGesture = leftTapGesture
        case .right:
            panGesture = leftPanGesture
            tapGesture = leftTapGesture
        }

        if let panGesture {
            view.removeGestureRecognizer(panGesture)
        }

        if let tapGesture {
            view.removeGestureRecognizer(tapGesture)
        }

        switch containerViewId {
        case .left:
            leftPanGesture = nil
            leftTapGesture = nil
        case .right:
            rightPanGesture = nil
            leftTapGesture = nil
        }
    }

    open func track(_ trackAction: TrackAction, containerViewId: SideContainerViewId) {}

    @objc func handleLeftPanGesture(_ panGesture: UIPanGestureRecognizer) {
        handlePanGesture(panGesture, for: .left)
    }

    @objc func handleRightPanGesture(_ panGesture: UIPanGestureRecognizer) {
        handlePanGesture(panGesture, for: .right)
    }

    private func handlePanGesture(_ panGesture: UIPanGestureRecognizer, for containerViewId: SideContainerViewId) {
        let isOpen: Bool
        let oppSideOpen: Bool
        let isHidden: Bool
        var panState: PanState

        switch containerViewId {
        case .left:
            oppSideOpen = isRightOpen
            isHidden = isLeftHidden
            isOpen = isLeftOpen
            panState = leftPanState
        case .right:
            oppSideOpen = isLeftOpen
            isHidden = isRightHidden
            isOpen = isRightOpen
            panState = rightPanState
        }

        guard isTargetViewController, !oppSideOpen else { return }

        let containerView = containerView(for: containerViewId)
        let viewController = viewController(for: containerViewId)

        switch panGesture.state {
        case .began:
            guard [.ended, .cancelled, .failed].contains(panState.last) else {
                return
            }

            if isHidden {
                delegate?.slideMenuController?(
                    viewController: self, willOpenContainerView: containerView,
                    containerViewController: viewController, containerViewId: containerViewId
                )
            } else {
                delegate?.slideMenuController?(
                    viewController: self, willCloseContainerView: containerView,
                    containerViewController: viewController, containerViewId: containerViewId
                )
            }

            panState.frameAtStart = containerView.frame
            panState.startPoint = panGesture.location(in: view)
            panState.wasOpenAtStart = isOpen
            panState.wasHiddenAtStart = isHidden

            viewController?.beginAppearanceTransition(panState.wasHiddenAtStart, animated: true)
            addShadowToView(containerView)
            setOpenWindowLevel()
        case .changed:
            guard [.began, .changed].contains(panState.last) else {
                return
            }

            let translation = panGesture.translation(in: panGesture.view!)
            containerView.frame = applyTranslation(containerViewId, translation, toFrame: panState.frameAtStart)
            applyOpacity(containerViewId)
            applyContentViewScale(containerViewId)
        case .ended, .cancelled:
            guard panState.last == .changed else {
                setCloseWindowLevel()
                return
            }

            let velocity = panGesture.velocity(in: panGesture.view)
            let panInfo = panResultInfo(containerViewId, velocity: velocity)

            if panInfo.action == .open {
                if !panState.wasHiddenAtStart {
                    viewController?.beginAppearanceTransition(true, animated: true)
                }

                open(containerViewId, withVelocity: panInfo.velocity)
                track(.flickOpen, containerViewId: containerViewId)
            } else {
                if panState.wasHiddenAtStart {
                    viewController?.beginAppearanceTransition(false, animated: true)
                }

                close(containerViewId, withVelocity: panInfo.velocity)
                setCloseWindowLevel()
                track(.flickClose, containerViewId: containerViewId)
            }
        case .failed, .possible:
            break
        @unknown default:
            break
        }

        panState.last = panGesture.state

        switch containerViewId {
        case .left:
            leftPanState = panState
        case .right:
            rightPanState = panState
        }
    }

    open func open(_ containerViewId: SideContainerViewId, withVelocity velocity: CGFloat) {
        let containerView = containerView(for: containerViewId)

        let xOrigin: CGFloat = containerView.frame.origin.x
        let finalXOrigin: CGFloat

        var duration: TimeInterval = Double(config.animationDuration)

        switch containerViewId {
        case .left:
            finalXOrigin = 0

            if velocity != 0 {
                duration = Double(abs(xOrigin - finalXOrigin) / velocity)
                duration = Double(fmax(0.1, fmin(1.0, duration)))
            }
        case .right:
            finalXOrigin = view.bounds.width - containerView.frame.size.width

            if velocity != 0 {
                duration = Double(abs(xOrigin - view.bounds.width) / velocity)
                duration = Double(fmax(0.1, fmin(1.0, duration)))
            }
        }

        var frame = containerView.frame
        frame.origin.x = finalXOrigin

        addShadowToView(containerView)

        opacityView.isHidden = false

        UIView.animate(
            withDuration: duration, delay: 0, options: config.animationOptions,
            animations: { [weak self] in
                guard let self else { return }

                let transformTranslationX: CGFloat

                switch containerViewId {
                case .left:
                    transformTranslationX = self.config.leftViewWidth
                    self.leftContainerView.frame = frame
                case .right:
                    transformTranslationX = -self.config.rightViewWidth
                    self.rightContainerView.frame = frame
                }

                self.opacityView.alpha = 1 - self.config.contentViewOpacity

                if self.config.contentViewDrag {
                    self.mainContainerView.transform = .init(translationX: transformTranslationX, y: 0)
                } else {
                    self.mainContainerView.transform = .init(
                        scaleX: self.config.contentViewScale, y: self.config.contentViewScale
                    )
                }
            }, completion: { [weak self] _ in
                guard let self else { return }

                let containerView = self.containerView(for: containerViewId)
                let containerViewController = self.viewController(for: containerViewId)

                self.mainContainerView.isUserInteractionEnabled = false

                containerViewController?.endAppearanceTransition()

                self.delegate?.slideMenuController?(
                    viewController: self, didOpenContainerView: containerView,
                    containerViewController: containerViewController, containerViewId: containerViewId
                )
            }
        )
    }

    open func close(_ containerViewId: SideContainerViewId, withVelocity velocity: CGFloat) {
        let containerView = containerView(for: containerViewId)

        let xOrigin: CGFloat = containerView.frame.origin.x
        let finalXOrigin: CGFloat

        var duration: TimeInterval = Double(config.animationDuration)

        switch containerViewId {
        case .left:
            finalXOrigin = leftMinOrigin

            if velocity != 0.0 {
                duration = Double(abs(xOrigin - finalXOrigin) / velocity)
                duration = Double(fmax(0.1, fmin(1.0, duration)))
            }
        case .right:
            finalXOrigin = view.bounds.width

            if velocity != 0.0 {
                duration = Double(abs(xOrigin - view.bounds.width) / velocity)
                duration = Double(fmax(0.1, fmin(1.0, duration)))
            }
        }

        var frame = containerView.frame
        frame.origin.x = finalXOrigin

        UIView.animate(
            withDuration: duration, delay: 0.0, options: config.animationOptions,
            animations: { [weak self] in
                guard let self else { return }

                switch containerViewId {
                case .left:
                    self.leftContainerView.frame = frame
                case .right:
                    self.rightContainerView.frame = frame
                }

                self.opacityView.alpha = 0
                self.mainContainerView.transform = .identity
            }, completion: { [weak self] _ in
                guard let self else { return }

                let containerView = self.containerView(for: containerViewId)
                let containerViewController = self.viewController(for: containerViewId)

                self.removeShadow(containerView)
                self.mainContainerView.isUserInteractionEnabled = true
                self.opacityView.isHidden = true

                containerViewController?.endAppearanceTransition()

                self.delegate?.slideMenuController?(
                    viewController: self, didCloseContainerView: containerView,
                    containerViewController: containerViewController, containerViewId: containerViewId
                )
            }
        )
    }

    open func toggle(_ containerViewId: SideContainerViewId) {
        let isOpen: Bool

        switch containerViewId {
        case .left:
            isOpen = isLeftOpen
        case .right:
            isOpen = isRightOpen
        }

        if isOpen {
            close(containerViewId)
            setCloseWindowLevel()
            // Tracking of close tap is put in here. Because closeMenu is due to be call even when the menu tap.
            track(.tapClose, containerViewId: containerViewId)
        } else {
            open(containerViewId)
        }
    }

    open func change(_ containerViewId: SideContainerViewId, viewWidth width: CGFloat) {
        let frameXOrigin: Double

        switch containerViewId {
        case .left:
            config.leftViewWidth = width
            frameXOrigin = leftMinOrigin
        case .right:
            config.rightBezelWidth = width
            frameXOrigin = rightMinOrigin
        }

        var frame: CGRect = view.bounds
        frame.size.width = width
        frame.origin.x = frameXOrigin

        let offset: CGFloat = 0
        frame.origin.y = frame.origin.y + offset
        frame.size.height = frame.size.height - offset
        containerView(for: containerViewId).frame = frame
    }

    open func replaceViewController(
        for containerViewId: ContainerViewId, with newViewController: UIViewController, closingAfter shouldClose: Bool
    ) {
        let viewController = viewController(for: containerViewId)

        if let viewController {
            removeViewController(viewController)
        }

        switch containerViewId {
        case .left:
            leftViewController = newViewController
        case .right:
            rightViewController = newViewController
        case .main:
            mainViewController = newViewController
        }

        let containerView = containerView(for: containerViewId)
        setUpViewController(containerView, targetViewController: newViewController)

        if shouldClose {
            switch containerViewId {
            case .left:
                close(.left)
            case .right:
                close(.right)
            case .main:
                close(.left)
                close(.right)
            }
        }
    }

    fileprivate func panResultInfo(_ containerViewId: SideContainerViewId, velocity: CGPoint) -> PanInfo {
        let thresholdVelocity: CGFloat
        let pointOfNoReturn: CGFloat
        let origin: CGFloat

        var panInfoAction: SlideAction = .close
        var panInfoVelocity: Double = 0

        switch containerViewId {
        case .left:
            thresholdVelocity = 1000
            pointOfNoReturn = CGFloat(floor(leftMinOrigin)) + config.pointOfNoReturnWidth
            origin = leftContainerView.frame.origin.x
            panInfoAction = origin <= pointOfNoReturn ? .close : .open

            if velocity.x >= thresholdVelocity {
                panInfoAction = .open
                panInfoVelocity = velocity.x
            } else if velocity.x <= (-1 * thresholdVelocity) {
                panInfoAction = .close
                panInfoVelocity = velocity.x
            }
        case .right:
            thresholdVelocity = -1000
            pointOfNoReturn = CGFloat(floor(view.bounds.width) - config.pointOfNoReturnWidth)
            origin = rightContainerView.frame.origin.x
            panInfoAction = origin >= pointOfNoReturn ? .close : .open

            if velocity.x <= thresholdVelocity {
                panInfoAction = .open
                panInfoVelocity = velocity.x
            } else if velocity.x >= (-1 * thresholdVelocity) {
                panInfoAction = .close
                panInfoVelocity = velocity.x
            }
        }

        return PanInfo(action: panInfoAction, shouldBounce: false, velocity: panInfoVelocity)
    }

    fileprivate func applyTranslation(
        _ containerViewId: SideContainerViewId, _ translation: CGPoint, toFrame: CGRect
    ) -> CGRect {
        var newOrigin = toFrame.origin.x
        newOrigin += translation.x

        let minOrigin: CGFloat
        let maxOrigin: CGFloat

        var newFrame = toFrame

        switch containerViewId {
        case .left:
            minOrigin = leftMinOrigin
            maxOrigin = 0

            if newOrigin < minOrigin {
                newOrigin = minOrigin
            } else if newOrigin > maxOrigin {
                newOrigin = maxOrigin
            }
        case .right:
            minOrigin = rightMinOrigin
            maxOrigin = rightMinOrigin - rightContainerView.frame.size.width

            if newOrigin > minOrigin {
                newOrigin = minOrigin
            } else if newOrigin < maxOrigin {
                newOrigin = maxOrigin
            }
        }

        newFrame.origin.x = newOrigin
        return newFrame
    }

    fileprivate func applyOpacity(_ containerViewId: SideContainerViewId) {
        let openedRatio: CGFloat

        switch containerViewId {
        case .left:
            openedRatio = openedLeftRatio
        case .right:
            openedRatio = openedRightRatio
        }

        let alpha = (1 - config.contentViewOpacity) * openedRatio
        opacityView.alpha = alpha
    }

    fileprivate func applyContentViewScale(_ containerViewId: SideContainerViewId) {
        let openedRatio: CGFloat
        let drag: CGFloat

        switch containerViewId {
        case .left:
            openedRatio = openedLeftRatio
            drag = config.leftViewWidth + leftContainerView.frame.origin.x
        case .right:
            openedRatio = openedRightRatio
            drag = rightContainerView.frame.origin.x - mainContainerView.frame.size.width
        }

        let scale = 1.0 - ((1.0 - config.contentViewScale) * openedRatio)

        if config.contentViewDrag {
            mainContainerView.transform = CGAffineTransform(translationX: drag, y: 0)
        } else {
            mainContainerView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }

    fileprivate func addShadowToView(_ targetView: UIView) {
        targetView.clipsToBounds = false
        targetView.layer.shadowOffset = config.shadowOffset
        targetView.layer.shadowOpacity = Float(config.shadowOpacity)
        targetView.layer.shadowRadius = config.shadowRadius
        targetView.layer.shadowPath = UIBezierPath(rect: targetView.bounds).cgPath
    }

    fileprivate func removeShadow(_ targetView: UIView) {
        targetView.clipsToBounds = true
        mainContainerView.alpha = 1
    }

    fileprivate func setOpenWindowLevel() {
        guard config.hideStatusBar else { return }
        DispatchQueue.main.async {
            self.keyWindow?.windowLevel = .statusBar + 1
        }
    }

    fileprivate func setCloseWindowLevel() {
        guard config.hideStatusBar else { return }
        DispatchQueue.main.async {
            self.keyWindow?.windowLevel = .normal
        }
    }

    fileprivate func setUpViewController(_ targetView: UIView, targetViewController: UIViewController) {
        guard !children.contains(targetViewController) else { return }

        addChild(targetViewController)
        targetViewController.view.frame = targetView.bounds
        targetView.addSubview(targetViewController.view)
        targetViewController.didMove(toParent: self)
    }

    fileprivate func removeViewController(_ viewController: UIViewController) {
        // Just to be safe, we check that this view controller
        // is actually added to a parent before removing it.
        guard viewController.parent == self else { return }

        viewController.view.layer.removeAllAnimations()
        viewController.willMove(toParent: nil)
        viewController.view.removeFromSuperview()
        viewController.removeFromParent()
    }

    open func closeNonAnimation(for containerViewId: SideContainerViewId) {
        setCloseWindowLevel()

        let containerView = containerView(for: containerViewId)

        let finalXOrigin: CGFloat

        switch containerViewId {
        case .left:
            finalXOrigin = leftMinOrigin
        case .right:
            finalXOrigin = view.bounds.width
        }

        var frame = containerView.frame
        frame.origin.x = finalXOrigin
        containerView.frame = frame

        opacityView.alpha = 0
        opacityView.isHidden = true

        mainContainerView.transform = .identity
        removeShadow(containerView)
        mainContainerView.isUserInteractionEnabled = true
    }

    // MARK: UIGestureRecognizerDelegate

    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: view)

        if gestureRecognizer == leftPanGesture {
            return shouldSlide(forContainerView: .left, forGestureRecognizer: gestureRecognizer, withTouchPoint: point)
        } else if gestureRecognizer == rightPanGesture {
            return shouldSlide(forContainerView: .right, forGestureRecognizer: gestureRecognizer, withTouchPoint: point)
        } else if gestureRecognizer == leftTapGesture {
            return isLeftOpen && !leftContainerView.frame.contains(point)
        } else if gestureRecognizer == rightTapGesture {
            return isRightOpen && !rightContainerView.frame.contains(point)
        } else {
            return true
        }
    }

    // returning true here helps if the main view is fullwidth with a scrollview
    open func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        config.simultaneousGestureRecognizers
    }

    fileprivate func shouldSlide(
        forContainerView containerViewId: SideContainerViewId, forGestureRecognizer gesture: UIGestureRecognizer,
        withTouchPoint point: CGPoint
    ) -> Bool {
        switch containerViewId {
        case .left:
            return isLeftOpen || config.panFromBezel && isLeftPointContainedWithinBezelRect(point)
        case .right:
            return isRightOpen || config.rightPanFromBezel && isRightPointContainedWithinBezelRect(point)
        }
    }

    fileprivate func isLeftPointContainedWithinBezelRect(_ point: CGPoint) -> Bool {
        guard let bezelWidth = config.leftBezelWidth else { return true }

        var leftBezelRect: CGRect = .zero
        let tuple = view.bounds.divided(atDistance: bezelWidth, from: CGRectEdge.minXEdge)
        leftBezelRect = tuple.slice
        return leftBezelRect.contains(point)
    }

    fileprivate func isRightPointContainedWithinBezelRect(_ point: CGPoint) -> Bool {
        guard let rightBezelWidth = config.rightBezelWidth else { return true }

        var rightBezelRect: CGRect = .zero
        let bezelWidth = view.bounds.width - rightBezelWidth
        let tuple = view.bounds.divided(atDistance: bezelWidth, from: CGRectEdge.minXEdge)

        rightBezelRect = tuple.remainder
        return rightBezelRect.contains(point)
    }
}

public extension UIViewController {
    var slideMenuController: SlideMenuController? {
        var viewController: UIViewController? = self

        while viewController != nil {
            if viewController is SlideMenuController {
                return viewController as? SlideMenuController
            }

            viewController = viewController?.parent
        }

        return nil
    }

    func addLeftBarButtonWithImage(_ buttonImage: UIImage) {
        let leftButton: UIBarButtonItem = .init(
            image: buttonImage, style: .plain, target: self, action: #selector(toggleLeft)
        )
        navigationItem.leftBarButtonItem = leftButton
    }

    func addRightBarButtonWithImage(_ buttonImage: UIImage) {
        let rightButton: UIBarButtonItem = .init(
            image: buttonImage, style: .plain, target: self, action: #selector(toggleRight)
        )
        navigationItem.rightBarButtonItem = rightButton
    }

    @objc func toggleLeft() {
        slideMenuController?.toggle(.left)
    }

    @objc func toggleRight() {
        slideMenuController?.toggle(.right)
    }

    @objc func openLeft() {
        slideMenuController?.open(.left)
    }

    @objc func openRight() {
        slideMenuController?.open(.right)
    }

    @objc func closeLeft() {
        slideMenuController?.close(.left)
    }

    @objc func closeRight() {
        slideMenuController?.close(.right)
    }

    func addPriorityToMenuGesture(_ targetScrollView: UIScrollView) {
        guard let slideMenuController, let recognizers = slideMenuController.view.gestureRecognizers else {
            return
        }

        for recognizer in recognizers where recognizer is UIPanGestureRecognizer {
            targetScrollView.panGestureRecognizer.require(toFail: recognizer)
        }
    }
}
