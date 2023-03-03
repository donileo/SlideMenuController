//
//  SlideMenuController.swift
//
//  Created by Adonis Peralta 03/02/2023
//

import Foundation
import UIKit

@objc public protocol SlideMenuControllerDelegate {
    // Container View Notification Methods
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
        public var leftViewWidth: CGFloat = 270.0
        public var leftBezelWidth: CGFloat? = 16.0
        public var rightViewWidth: CGFloat = 270.0
        public var rightBezelWidth: CGFloat? = 16.0

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

    var config = Config()

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

    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
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

    open override func awakeFromNib() {
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
        mainContainerView.backgroundColor = .clear
        mainContainerView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        view.insertSubview(mainContainerView, at: 0)
    }

    private func setupOpacityView() {
        var opacityframe = view.bounds
        let opacityOffset: CGFloat = 0

        opacityframe.origin.y = opacityframe.origin.y + opacityOffset
        opacityframe.size.height = opacityframe.size.height - opacityOffset
        opacityView = UIView(frame: opacityframe)
        opacityView.backgroundColor = config.opacityViewBackgroundColor
        opacityView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        opacityView.layer.opacity = 0.0
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

        switch containerViewId {
        case .left:
            frameWidth = config.leftViewWidth
            frameOrigin = leftMinOrigin
        case .right:
            frameWidth = config.rightViewWidth
            frameOrigin = rightMinOrigin
        }

        containerFrame.size.width = frameWidth
        containerFrame.origin.x = frameOrigin

        let offset: CGFloat = 0
        containerFrame.origin.y = containerFrame.origin.y + offset
        containerFrame.size.height = containerFrame.size.height - offset

        let containerView: UIView

        switch containerViewId {
        case .left:
            leftContainerView = UIView(frame: containerFrame)
            containerView = leftContainerView
        case .right:
            rightContainerView = UIView(frame: containerFrame)
            containerView = rightContainerView
        }

        containerView.backgroundColor = .clear
        containerView.autoresizingMask = .flexibleHeight

        let subViewPos = subviewPosition(for: containerViewId)
        view.insertSubview(containerView, at: subViewPos)
        addGestures(for: containerViewId)
    }

    open override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        mainContainerView.transform = .identity
        leftContainerView.isHidden = true
        rightContainerView.isHidden = true

        coordinator.animate(alongsideTransition: nil) { context in
            self.closeNonAnimation(for: .left)
            self.closeNonAnimation(for: .right)
            self.leftContainerView.isHidden = false
            self.rightContainerView.isHidden = false

            if self.leftPanGesture != nil && self.leftPanGesture != nil {
                self.removeGestures(for: .left)
                self.addGestures(for: .left)
            }

            if self.rightPanGesture != nil && self.rightPanGesture != nil {
                self.removeGestures(for: .right)
                self.addGestures(for: .right)
            }
        }
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        edgesForExtendedLayout = .all
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        //automatically called
        //self.mainViewController?.viewWillAppear(animated)
    }

    open override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        mainViewController?.supportedInterfaceOrientations ?? .all
    }

    open override var shouldAutorotate: Bool {
        mainViewController?.shouldAutorotate ?? false
    }

    open override func viewWillLayoutSubviews() {
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

    open override var preferredStatusBarStyle: UIStatusBarStyle {
        mainViewController?.preferredStatusBarStyle ?? .default
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
                    self.leftPanGesture = panGesture
                case .right:
                    self.rightPanGesture = panGesture
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
                    self.leftTapGesture = tapGesture
                case .right:
                    self.rightTapGesture = tapGesture
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
            self.leftPanGesture = nil
            self.leftTapGesture = nil
        case .right:
            self.rightPanGesture = nil
            self.leftTapGesture = nil
        }
    }

    open func track(_ trackAction: TrackAction, containerViewId: SideContainerViewId) {
        // function is for tracking
        // Please to override it if necessary
    }

    @objc func handleLeftPanGesture(_ panGesture: UIPanGestureRecognizer) {
        guard isTargetViewController, !isRightOpen else { return }

        switch panGesture.state {
        case .began:
            if leftPanState.last != .ended &&  leftPanState.last != .cancelled &&  leftPanState.last != .failed {
                return
            }

            if isLeftHidden {
                delegate?.slideMenuController?(
                    viewController: self, willOpenContainerView: leftContainerView,
                    containerViewController: leftViewController, containerViewId: .left
                )
            } else {
                delegate?.slideMenuController?(
                    viewController: self, willCloseContainerView: leftContainerView,
                    containerViewController: leftViewController, containerViewId: .left
                )
            }

            leftPanState.frameAtStart = leftContainerView.frame
            leftPanState.startPoint = panGesture.location(in: view)
            leftPanState.wasOpenAtStart = isLeftOpen
            leftPanState.wasHiddenAtStart = isLeftHidden

            leftViewController?.beginAppearanceTransition(leftPanState.wasHiddenAtStart, animated: true)
            addShadowToView(leftContainerView)
            setOpenWindowLevel()
        case .changed:
            if leftPanState.last != .began && leftPanState.last != .changed {
                return
            }

            let translation: CGPoint = panGesture.translation(in: panGesture.view!)
            leftContainerView.frame = applyTranslation(.left, translation, toFrame: leftPanState.frameAtStart)
            applyOpacity(.left)
            applyContentViewScale(.left)
        case .ended, .cancelled:
            if leftPanState.last != .changed {
                setCloseWindowLevel()
                return
            }

            let velocity:CGPoint = panGesture.velocity(in: panGesture.view)
            let panInfo = panResultInfo(.left, velocity: velocity)

            if panInfo.action == .open {
                if !leftPanState.wasHiddenAtStart {
                    leftViewController?.beginAppearanceTransition(true, animated: true)
                }

                open(.left, withVelocity: panInfo.velocity)
                track(.flickOpen, containerViewId: .left)
            } else {
                if leftPanState.wasHiddenAtStart {
                    leftViewController?.beginAppearanceTransition(false, animated: true)
                }

                close(.left, withVelocity: panInfo.velocity)
                setCloseWindowLevel()
                track(.flickClose, containerViewId: .left)
            }
        case .failed, .possible:
            break
        @unknown default:
            break
        }

        leftPanState.last = panGesture.state
    }

    @objc func handleRightPanGesture(_ panGesture: UIPanGestureRecognizer) {
        guard isTargetViewController, !isLeftOpen else { return }

        switch panGesture.state {
        case .began:
            if rightPanState.last != .ended &&  rightPanState.last != .cancelled &&  rightPanState.last != .failed {
                return
            }

            if isRightHidden {
                delegate?.slideMenuController?(
                    viewController: self, willOpenContainerView: rightContainerView,
                    containerViewController: rightViewController, containerViewId: .right
                )
            } else {
                delegate?.slideMenuController?(
                    viewController: self, willCloseContainerView: rightContainerView,
                    containerViewController: rightViewController, containerViewId: .right
                )
            }

            rightPanState.frameAtStart = rightContainerView.frame
            rightPanState.startPoint = panGesture.location(in: view)
            rightPanState.wasOpenAtStart =  isRightOpen
            rightPanState.wasHiddenAtStart = isRightHidden

            rightViewController?.beginAppearanceTransition(rightPanState.wasHiddenAtStart, animated: true)

            addShadowToView(rightContainerView)
            setOpenWindowLevel()
        case .changed:
            if rightPanState.last != .began && rightPanState.last != .changed {
                return
            }

            let translation: CGPoint = panGesture.translation(in: panGesture.view!)
            rightContainerView.frame = applyTranslation(.right, translation, toFrame: rightPanState.frameAtStart)
            applyOpacity(.right)
            applyContentViewScale(.right)
        case .ended, .cancelled:
            if rightPanState.last != .changed {
                setCloseWindowLevel()
                return
            }

            let velocity: CGPoint = panGesture.velocity(in: panGesture.view)
            let panInfo = panResultInfo(.right, velocity: velocity)

            if panInfo.action == .open {
                if !rightPanState.wasHiddenAtStart {
                    rightViewController?.beginAppearanceTransition(true, animated: true)
                }

                open(.right, withVelocity: panInfo.velocity)
                track(.flickOpen, containerViewId: .right)
            } else {
                if rightPanState.wasHiddenAtStart {
                    rightViewController?.beginAppearanceTransition(false, animated: true)
                }

                close(.right, withVelocity: panInfo.velocity)
                setCloseWindowLevel()
                track(.flickClose, containerViewId: .right)
            }
        case .failed, .possible:
            break
        @unknown default:
            break
        }

        rightPanState.last = panGesture.state
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

                self.opacityView.layer.opacity = Float(self.config.contentViewOpacity)

                if self.config.contentViewDrag {
                    self.mainContainerView.transform = .init(translationX: transformTranslationX, y: 0)
                } else {
                    self.mainContainerView.transform = .init(
                        scaleX: self.config.contentViewScale, y: self.config.contentViewScale
                    )
                }
            }, completion: { [weak self] _ in
                guard let self else { return }
                self.mainContainerView.isUserInteractionEnabled = false

                let containerView = self.containerView(for: containerViewId)
                let containerViewController = self.viewController(for: containerViewId)

                containerViewController?.endAppearanceTransition()

                self.delegate?.slideMenuController?(
                    viewController: self, didOpenContainerView: containerView,
                    containerViewController: containerViewController, containerViewId: containerViewId
                )
            })
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

                self.opacityView.layer.opacity = 0.0
                self.mainContainerView.transform = .identity
            }, completion: { [weak self] _ in
                guard let self else { return }
                self.removeShadow(self.leftContainerView)
                self.mainContainerView.isUserInteractionEnabled = true

                let containerView = self.containerView(for: containerViewId)
                let containerViewController = self.viewController(for: containerViewId)

                containerViewController?.endAppearanceTransition()

                self.delegate?.slideMenuController?(
                    viewController: self, didCloseContainerView: containerView,
                    containerViewController: containerViewController, containerViewId: containerViewId
                )
            })
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
        var newOrigin: CGFloat = toFrame.origin.x
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

        let opacity = config.contentViewOpacity * openedRatio
        opacityView.layer.opacity = Float(opacity)
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
        targetView.layer.masksToBounds = false
        targetView.layer.shadowOffset = config.shadowOffset
        targetView.layer.shadowOpacity = Float(config.shadowOpacity)
        targetView.layer.shadowRadius = config.shadowRadius
        targetView.layer.shadowPath = UIBezierPath(rect: targetView.bounds).cgPath
    }

    fileprivate func removeShadow(_ targetView: UIView) {
        targetView.layer.masksToBounds = true
        mainContainerView.layer.opacity = 1.0
    }

    fileprivate func removeContentOpacity() {
        opacityView.layer.opacity = 0.0
    }

    fileprivate func addContentOpacity() {
        opacityView.layer.opacity = Float(config.contentViewOpacity)
    }

    fileprivate func setOpenWindowLevel() {
        guard config.hideStatusBar else { return }
        DispatchQueue.main.async {
            UIApplication.shared.keyWindow?.windowLevel = UIWindow.Level.statusBar + 1
        }
    }

    fileprivate func setCloseWindowLevel() {
        guard config.hideStatusBar else { return }
        DispatchQueue.main.async {
            UIApplication.shared.keyWindow?.windowLevel = UIWindow.Level.normal
        }
    }

    fileprivate func setUpViewController(_ targetView: UIView, targetViewController: UIViewController) {
        targetViewController.view.frame = targetView.bounds

        guard !children.contains(targetViewController) else { return }

        addChild(targetViewController)
        targetView.addSubview(targetViewController.view)
        targetViewController.didMove(toParent: self)
    }

    fileprivate func removeViewController(_ viewController: UIViewController) {
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

        opacityView.layer.opacity = 0.0
        mainContainerView.transform = .identity
        removeShadow(containerView)
        mainContainerView.isUserInteractionEnabled = true
    }

    // MARK: UIGestureRecognizerDelegate
    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point: CGPoint = touch.location(in: view)

        if gestureRecognizer == leftPanGesture {
            return shouldSlide(forContainerView: .left, forGestureRecognizer: gestureRecognizer, withTouchPoint: point)
        } else if gestureRecognizer == rightPanGesture {
            return shouldSlide(forContainerView: .right, forGestureRecognizer: gestureRecognizer, withTouchPoint: point)
        } else if gestureRecognizer == leftTapGesture {
            return isLeftOpen && !isPointContainedWithinLeftRect(point)
        } else if gestureRecognizer == rightTapGesture {
            return isRightOpen && !isPointContainedWithinRightRect(point)
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

    fileprivate func isLeftPointContainedWithinBezelRect(_ point: CGPoint) -> Bool{
        guard let bezelWidth = config.leftBezelWidth else { return true }

        var leftBezelRect: CGRect = CGRect.zero
        let tuple = view.bounds.divided(atDistance: bezelWidth, from: CGRectEdge.minXEdge)
        leftBezelRect = tuple.slice
        return leftBezelRect.contains(point)
    }

    fileprivate func isPointContainedWithinLeftRect(_ point: CGPoint) -> Bool {
        leftContainerView.frame.contains(point)
    }

    fileprivate func isRightPointContainedWithinBezelRect(_ point: CGPoint) -> Bool {
        guard let rightBezelWidth = config.rightBezelWidth else { return true }

        var rightBezelRect: CGRect = CGRect.zero
        let bezelWidth: CGFloat = view.bounds.width - rightBezelWidth
        let tuple = view.bounds.divided(atDistance: bezelWidth, from: CGRectEdge.minXEdge)

        rightBezelRect = tuple.remainder
        return rightBezelRect.contains(point)
    }

    fileprivate func isPointContainedWithinRightRect(_ point: CGPoint) -> Bool {
        rightContainerView.frame.contains(point)
    }
}

extension UIViewController {
    public var slideMenuController: SlideMenuController? {
        var viewController: UIViewController? = self

        while viewController != nil {
            if viewController is SlideMenuController {
                return viewController as? SlideMenuController
            }

            viewController = viewController?.parent
        }

        return nil
    }

    public func addLeftBarButtonWithImage(_ buttonImage: UIImage) {
        let leftButton: UIBarButtonItem = .init(
            image: buttonImage, style: .plain, target: self, action: #selector(toggleLeft)
        )
        navigationItem.leftBarButtonItem = leftButton
    }

    public func addRightBarButtonWithImage(_ buttonImage: UIImage) {
        let rightButton: UIBarButtonItem = .init(
            image: buttonImage, style: .plain, target: self, action: #selector(toggleRight)
        )
        navigationItem.rightBarButtonItem = rightButton
    }

    @objc public func toggleLeft() {
        slideMenuController?.toggle(.left)
    }

    @objc public func toggleRight() {
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

    public func addPriorityToMenuGesture(_ targetScrollView: UIScrollView) {
        guard let slideMenuController, let recognizers = slideMenuController.view.gestureRecognizers else {
            return
        }

        for recognizer in recognizers where recognizer is UIPanGestureRecognizer {
            targetScrollView.panGestureRecognizer.require(toFail: recognizer)
        }
    }
}
