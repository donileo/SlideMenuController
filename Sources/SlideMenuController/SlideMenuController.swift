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
        viewController: SlideMenuController, willOpenLeftContainerView view: UIView, leftViewController: UIViewController?
    )

    @objc optional func slideMenuController(
        viewController: SlideMenuController, didOpenLeftContainerView view: UIView, leftViewController: UIViewController?
    )

    @objc optional func slideMenuController(
        viewController: SlideMenuController, willCloseLeftContainerView view: UIView, leftViewController: UIViewController?
    )

    @objc optional func slideMenuController(
        viewController: SlideMenuController, didCloseLeftContainerView view: UIView, leftViewController: UIViewController?
    )

    @objc optional func slideMenuController(
        viewController: SlideMenuController, willOpenRightContainerView view: UIView, rightViewController: UIViewController?
    )

    @objc optional func slideMenuController(
        viewController: SlideMenuController, didOpenRightContainerView view: UIView, rightViewController: UIViewController?
    )

    @objc optional func slideMenuController(
        viewController: SlideMenuController, willCloseRightContainerView: UIView, rightViewController: UIViewController?
    )

    @objc optional func slideMenuController(
        viewController: SlideMenuController, didCloseRightContainerView: UIView, rightViewController: UIViewController?
    )
}

open class SlideMenuController: UIViewController, UIGestureRecognizerDelegate {
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
        case leftTapOpen
        case leftTapClose
        case leftFlickOpen
        case leftFlickClose
        case rightTapOpen
        case rightTapClose
        case rightFlickOpen
        case rightFlickClose
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
        setupLeftContainerView()
        setupRightContainerView()
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

    private func setupLeftContainerView() {
        guard leftViewController != nil else { return }

        var leftFrame = view.bounds
        leftFrame.size.width = config.leftViewWidth
        leftFrame.origin.x = leftMinOrigin

        let leftOffset: CGFloat = 0
        leftFrame.origin.y = leftFrame.origin.y + leftOffset
        leftFrame.size.height = leftFrame.size.height - leftOffset

        leftContainerView = UIView(frame: leftFrame)
        leftContainerView.backgroundColor = .clear
        leftContainerView.autoresizingMask = .flexibleHeight

        view.insertSubview(leftContainerView, at: 2)
        addLeftGestures()
    }

    private func setupRightContainerView() {
        guard rightViewController != nil else { return }

        var rightFrame: CGRect = view.bounds
        rightFrame.size.width = config.rightViewWidth
        rightFrame.origin.x = rightMinOrigin

        let rightOffset: CGFloat = 0
        rightFrame.origin.y = rightFrame.origin.y + rightOffset
        rightFrame.size.height = rightFrame.size.height - rightOffset

        rightContainerView = UIView(frame: rightFrame)
        rightContainerView.backgroundColor = .clear
        rightContainerView.autoresizingMask = .flexibleHeight

        view.insertSubview(rightContainerView, at: 3)
        addRightGestures()
    }

    open override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        mainContainerView.transform = .identity
        leftContainerView.isHidden = true
        rightContainerView.isHidden = true

        coordinator.animate(alongsideTransition: nil) { context in
            self.closeLeftNonAnimation()
            self.closeRightNonAnimation()
            self.leftContainerView.isHidden = false
            self.rightContainerView.isHidden = false

            if self.leftPanGesture != nil && self.leftPanGesture != nil {
                self.removeLeftGestures()
                self.addLeftGestures()
            }

            if self.rightPanGesture != nil && self.rightPanGesture != nil {
                self.removeRightGestures()
                self.addRightGestures()
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

    open override func openLeft() {
        guard let leftViewController else { return }

        delegate?.slideMenuController?(
            viewController: self, willOpenLeftContainerView: leftContainerView, leftViewController: leftViewController
        )

        setOpenWindowLevel()
        leftViewController.beginAppearanceTransition(isLeftHidden, animated: true)
        openLeftWithVelocity(0.0)

        track(.leftTapOpen)
    }

    open override func openRight() {
        guard let rightViewController else { return }

        delegate?.slideMenuController?(
            viewController: self, willOpenRightContainerView: rightContainerView, rightViewController: rightViewController
        )

        setOpenWindowLevel()
        rightViewController.beginAppearanceTransition(isRightHidden, animated: true)
        openRightWithVelocity(0.0)

        track(.rightTapOpen)
    }

    open override func closeLeft() {
        guard let leftViewController else { return }

        delegate?.slideMenuController?(
            viewController: self, willCloseLeftContainerView: leftContainerView, leftViewController: leftViewController
        )

        leftViewController.beginAppearanceTransition(isLeftHidden, animated: true)
        closeLeftWithVelocity(0.0)
        setCloseWindowLevel()
    }

    open override func closeRight() {
        guard let rightViewController else { return }

        delegate?.slideMenuController?(
            viewController: self, willCloseRightContainerView: rightContainerView, rightViewController: rightViewController
        )

        rightViewController.beginAppearanceTransition(isRightHidden, animated: true)
        closeRightWithVelocity(0.0)
        setCloseWindowLevel()
    }

    open func addLeftGestures() {
        guard leftViewController != nil else { return }

        if config.panGesturesEnabled {
            if leftPanGesture == nil {
                let leftPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleLeftPanGesture))
                leftPanGesture.delegate = self
                view.addGestureRecognizer(leftPanGesture)
                self.leftPanGesture = leftPanGesture
            }
        }

        if config.tapGesturesEnabled {
            if leftTapGesture == nil {
                let leftTapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleLeft))
                leftTapGesture.delegate = self
                view.addGestureRecognizer(leftTapGesture)
                self.leftTapGesture = leftTapGesture
            }
        }
    }

    open func addRightGestures() {
        guard rightViewController != nil else { return }

        if config.panGesturesEnabled {
            if rightPanGesture == nil {
                let rightPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleRightPanGesture))
                rightPanGesture.delegate = self
                view.addGestureRecognizer(rightPanGesture)
                self.rightPanGesture = rightPanGesture
            }
        }

        if config.tapGesturesEnabled {
            if rightTapGesture == nil {
                let rightTapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleRight))
                rightTapGesture.delegate = self
                view.addGestureRecognizer(rightTapGesture)
                self.rightTapGesture = rightTapGesture
            }
        }
    }

    open func removeLeftGestures() {
        if let leftPanGesture {
            view.removeGestureRecognizer(leftPanGesture)
            self.leftPanGesture = nil
        }

        if let leftTapGesture {
            view.removeGestureRecognizer(leftTapGesture)
            self.leftTapGesture = nil
        }
    }

    open func removeRightGestures() {
        if let rightPanGesture {
            view.removeGestureRecognizer(rightPanGesture)
            self.rightPanGesture = nil
        }

        if let rightTapGesture {
            view.removeGestureRecognizer(rightTapGesture)
            self.rightTapGesture = nil
        }
    }

    open func track(_ trackAction: TrackAction) {
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
                    viewController: self, willOpenLeftContainerView: leftContainerView,
                    leftViewController: leftViewController
                )
            } else {
                delegate?.slideMenuController?(
                    viewController: self, willCloseLeftContainerView: leftContainerView,
                    leftViewController: leftViewController
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
            leftContainerView.frame = applyLeftTranslation(translation, toFrame: leftPanState.frameAtStart)
            applyLeftOpacity()
            applyLeftContentViewScale()
        case .ended, .cancelled:
            if leftPanState.last != .changed {
                setCloseWindowLevel()
                return
            }

            let velocity:CGPoint = panGesture.velocity(in: panGesture.view)
            let panInfo: PanInfo = panLeftResultInfoForVelocity(velocity)

            if panInfo.action == .open {
                if !leftPanState.wasHiddenAtStart {
                    leftViewController?.beginAppearanceTransition(true, animated: true)
                }

                openLeftWithVelocity(panInfo.velocity)
                track(.leftFlickOpen)
            } else {
                if leftPanState.wasHiddenAtStart {
                    leftViewController?.beginAppearanceTransition(false, animated: true)
                }

                closeLeftWithVelocity(panInfo.velocity)
                setCloseWindowLevel()
                track(.leftFlickClose)
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
                    viewController: self, willOpenRightContainerView: rightContainerView,
                    rightViewController: rightViewController
                )
            } else {
                delegate?.slideMenuController?(
                    viewController: self, willCloseRightContainerView: rightContainerView,
                    rightViewController: rightViewController
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
            rightContainerView.frame = applyRightTranslation(translation, toFrame: rightPanState.frameAtStart)
            applyRightOpacity()
            applyRightContentViewScale()
        case .ended, .cancelled:
            if rightPanState.last != .changed {
                setCloseWindowLevel()
                return
            }

            let velocity: CGPoint = panGesture.velocity(in: panGesture.view)
            let panInfo: PanInfo = panRightResultInfoForVelocity(velocity)

            if panInfo.action == .open {
                if !rightPanState.wasHiddenAtStart {
                    rightViewController?.beginAppearanceTransition(true, animated: true)
                }

                openRightWithVelocity(panInfo.velocity)
                track(.rightFlickOpen)
            } else {
                if rightPanState.wasHiddenAtStart {
                    rightViewController?.beginAppearanceTransition(false, animated: true)
                }

                closeRightWithVelocity(panInfo.velocity)
                setCloseWindowLevel()
                track(.rightFlickClose)
            }
        case .failed, .possible:
            break
        @unknown default:
            break
        }

        rightPanState.last = panGesture.state
    }

    open func openLeftWithVelocity(_ velocity: CGFloat) {
        let xOrigin: CGFloat = leftContainerView.frame.origin.x
        let finalXOrigin: CGFloat = 0.0

        var frame = leftContainerView.frame
        frame.origin.x = finalXOrigin

        var duration: TimeInterval = Double(config.animationDuration)
        if velocity != 0.0 {
            duration = Double(abs(xOrigin - finalXOrigin) / velocity)
            duration = Double(fmax(0.1, fmin(1.0, duration)))
        }

        addShadowToView(leftContainerView)

        UIView.animate(
            withDuration: duration, delay: 0.0, options: config.animationOptions,
            animations: { [weak self] in
                guard let self else { return }

                self.leftContainerView.frame = frame
                self.opacityView.layer.opacity = Float(self.config.contentViewOpacity)

                if self.config.contentViewDrag {
                    self.mainContainerView.transform = .init(translationX: self.config.leftViewWidth, y: 0)
                } else {
                    self.mainContainerView.transform = .init(
                        scaleX: self.config.contentViewScale, y: self.config.contentViewScale
                    )
                }
            }, completion: { [weak self] _ in
                guard let self else { return }
                self.mainContainerView.isUserInteractionEnabled = false
                self.leftViewController?.endAppearanceTransition()
                self.delegate?.slideMenuController?(
                    viewController: self, didOpenLeftContainerView: self.leftContainerView,
                    leftViewController: self.leftViewController
                )
            })
    }

    open func openRightWithVelocity(_ velocity: CGFloat) {
        let xOrigin: CGFloat = rightContainerView.frame.origin.x

        //    CGFloat finalXOrigin = options.rightViewOverlapWidth
        let finalXOrigin: CGFloat = view.bounds.width - rightContainerView.frame.size.width

        var frame = rightContainerView.frame
        frame.origin.x = finalXOrigin

        var duration: TimeInterval = Double(config.animationDuration)
        if velocity != 0 {
            duration = Double(abs(xOrigin - view.bounds.width) / velocity)
            duration = Double(fmax(0.1, fmin(1.0, duration)))
        }

        addShadowToView(rightContainerView)

        UIView.animate(
            withDuration: duration, delay: 0.0, options: config.animationOptions,
            animations: { [weak self] in
                guard let self else { return }
                self.rightContainerView.frame = frame
                self.opacityView.layer.opacity = Float(self.config.contentViewOpacity)

                if self.config.contentViewDrag {
                    self.mainContainerView.transform = .init(translationX: -self.config.rightViewWidth, y: 0)
                } else {
                    self.mainContainerView.transform = .init(scaleX: self.config.contentViewScale, y: self.config.contentViewScale
                    )
                }
            }, completion: { [weak self] _ in
                guard let self else { return }
                self.mainContainerView.isUserInteractionEnabled = false
                self.rightViewController?.endAppearanceTransition()
                self.delegate?.slideMenuController?(
                    viewController: self, didOpenRightContainerView: self.rightContainerView,
                    rightViewController: self.rightViewController
                )
        })
    }

    open func closeLeftWithVelocity(_ velocity: CGFloat) {
        let xOrigin: CGFloat = leftContainerView.frame.origin.x
        let finalXOrigin: CGFloat = leftMinOrigin

        var frame: CGRect = leftContainerView.frame
        frame.origin.x = finalXOrigin

        var duration: TimeInterval = Double(config.animationDuration)
        if velocity != 0.0 {
            duration = Double(abs(xOrigin - finalXOrigin) / velocity)
            duration = Double(fmax(0.1, fmin(1.0, duration)))
        }

        UIView.animate(
            withDuration: duration, delay: 0.0, options: config.animationOptions,
            animations: { [weak self] in
                guard let self else { return }
                self.leftContainerView.frame = frame
                self.opacityView.layer.opacity = 0.0
                self.mainContainerView.transform = .identity
            }, completion: { [weak self] _ in
                guard let self else { return }
                self.removeShadow(self.leftContainerView)
                self.mainContainerView.isUserInteractionEnabled = true
                self.leftViewController?.endAppearanceTransition()
                self.delegate?.slideMenuController?(
                    viewController: self, didCloseLeftContainerView: self.leftContainerView,
                    leftViewController: self.leftViewController
                )
        })
    }


    open func closeRightWithVelocity(_ velocity: CGFloat) {
        let xOrigin: CGFloat = rightContainerView.frame.origin.x
        let finalXOrigin: CGFloat = view.bounds.width

        var frame: CGRect = rightContainerView.frame
        frame.origin.x = finalXOrigin

        var duration: TimeInterval = Double(config.animationDuration)
        if velocity != 0.0 {
            duration = Double(abs(xOrigin - view.bounds.width) / velocity)
            duration = Double(fmax(0.1, fmin(1.0, duration)))
        }

        UIView.animate(
            withDuration: duration, delay: 0.0, options: config.animationOptions,
            animations: { [weak self] in
                guard let self else { return }
                self.rightContainerView.frame = frame
                self.opacityView.layer.opacity = 0.0
                self.mainContainerView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
            }, completion: { [weak self] _ in
                guard let self else { return }
                self.removeShadow(self.rightContainerView)
                self.mainContainerView.isUserInteractionEnabled = true
                self.rightViewController?.endAppearanceTransition()
                self.delegate?.slideMenuController?(
                    viewController: self, didCloseRightContainerView: self.rightContainerView,
                    rightViewController: self.rightViewController
                )
            })
    }

    open override func toggleLeft() {
        if isLeftOpen {
            closeLeft()
            setCloseWindowLevel()
            // Tracking of close tap is put in here. Because closeMenu is due to be call even when the menu tap.
            track(.leftTapClose)
        } else {
            openLeft()
        }
    }

    open override func toggleRight() {
        if isRightOpen {
            closeRight()
            setCloseWindowLevel()
            // Tracking of close tap is put in here. Because closeMenu is due to be call even when the menu tap.
            track(.rightTapClose)
        } else {
            openRight()
        }
    }

    open func changeLeftViewWidth(_ width: CGFloat) {
        config.leftViewWidth = width
        var leftFrame: CGRect = view.bounds
        leftFrame.size.width = width
        leftFrame.origin.x = leftMinOrigin

        let leftOffset: CGFloat = 0
        leftFrame.origin.y = leftFrame.origin.y + leftOffset
        leftFrame.size.height = leftFrame.size.height - leftOffset
        leftContainerView.frame = leftFrame
    }

    open func changeRightViewWidth(_ width: CGFloat) {
        config.rightBezelWidth = width
        var rightFrame: CGRect = view.bounds
        rightFrame.size.width = width
        rightFrame.origin.x = rightMinOrigin

        let rightOffset: CGFloat = 0
        rightFrame.origin.y = rightFrame.origin.y + rightOffset
        rightFrame.size.height = rightFrame.size.height - rightOffset
        rightContainerView.frame = rightFrame
    }

    open func replaceMainViewController(with viewController: UIViewController, closingLeftRightPanels closePanels: Bool) {
        if let mainViewController {
            removeViewController(mainViewController)
        }

        mainViewController = viewController

        setUpViewController(mainContainerView, targetViewController: viewController)

        if closePanels {
            closeLeft()
            closeRight()
        }
    }

    open func replaceLeftViewController(with viewController: UIViewController, closingAfter shouldClose: Bool) {
        if let leftViewController {
            removeViewController(leftViewController)
        }

        leftViewController = viewController

        // viewController is by now the same reference as leftViewController so they can be used interchangeably
        setUpViewController(leftContainerView, targetViewController: viewController)

        if shouldClose {
            closeLeft()
        }
    }

    open func replaceRightViewController(with viewController: UIViewController, closingAfter shouldClose: Bool) {
        if let rightViewController {
            removeViewController(rightViewController)
        }

        rightViewController = viewController

        // viewController is by now the same reference as leftViewController so they can be used interchangeably
        setUpViewController(rightContainerView, targetViewController: viewController)

        if shouldClose {
            closeRight()
        }
    }

    fileprivate func panLeftResultInfoForVelocity(_ velocity: CGPoint) -> PanInfo {
        let thresholdVelocity: CGFloat = 1000.0
        let pointOfNoReturn = CGFloat(floor(leftMinOrigin)) + config.pointOfNoReturnWidth
        let leftOrigin = leftContainerView.frame.origin.x

        var panInfo = PanInfo(action: .close, shouldBounce: false, velocity: 0.0)
        panInfo.action = leftOrigin <= pointOfNoReturn ? .close : .open

        if velocity.x >= thresholdVelocity {
            panInfo.action = .open
            panInfo.velocity = velocity.x
        } else if velocity.x <= (-1.0 * thresholdVelocity) {
            panInfo.action = .close
            panInfo.velocity = velocity.x
        }

        return panInfo
    }

    fileprivate func panRightResultInfoForVelocity(_ velocity: CGPoint) -> PanInfo {
        let thresholdVelocity: CGFloat = -1000.0
        let pointOfNoReturn = CGFloat(floor(view.bounds.width) - config.pointOfNoReturnWidth)
        let rightOrigin: CGFloat = rightContainerView.frame.origin.x

        var panInfo = PanInfo(action: .close, shouldBounce: false, velocity: 0.0)

        panInfo.action = rightOrigin >= pointOfNoReturn ? .close : .open

        if velocity.x <= thresholdVelocity {
            panInfo.action = .open
            panInfo.velocity = velocity.x
        } else if velocity.x >= (-1.0 * thresholdVelocity) {
            panInfo.action = .close
            panInfo.velocity = velocity.x
        }

        return panInfo
    }

    fileprivate func applyLeftTranslation(_ translation: CGPoint, toFrame:CGRect) -> CGRect {
        var newOrigin: CGFloat = toFrame.origin.x
        newOrigin += translation.x

        let minOrigin = leftMinOrigin
        let maxOrigin: CGFloat = 0
        var newFrame: CGRect = toFrame

        if newOrigin < minOrigin {
            newOrigin = minOrigin
        } else if newOrigin > maxOrigin {
            newOrigin = maxOrigin
        }

        newFrame.origin.x = newOrigin
        return newFrame
    }

    fileprivate func applyRightTranslation(_ translation: CGPoint, toFrame: CGRect) -> CGRect {
        var newOrigin: CGFloat = toFrame.origin.x
        newOrigin += translation.x

        let minOrigin = rightMinOrigin
        let maxOrigin = rightMinOrigin - rightContainerView.frame.size.width
        var newFrame: CGRect = toFrame

        if newOrigin > minOrigin {
            newOrigin = minOrigin
        } else if newOrigin < maxOrigin {
            newOrigin = maxOrigin
        }

        newFrame.origin.x = newOrigin
        return newFrame
    }

    fileprivate func applyLeftOpacity() {
        let opacity: CGFloat = config.contentViewOpacity * openedLeftRatio
        opacityView.layer.opacity = Float(opacity)
    }


    fileprivate func applyRightOpacity() {
        let opacity: CGFloat = config.contentViewOpacity * openedRightRatio
        opacityView.layer.opacity = Float(opacity)
    }

    fileprivate func applyLeftContentViewScale() {
        let scale: CGFloat = 1.0 - ((1.0 - config.contentViewScale) * openedLeftRatio)
        let drag: CGFloat = config.leftViewWidth + leftContainerView.frame.origin.x

        config.contentViewDrag == true ? (mainContainerView.transform = CGAffineTransform(translationX: drag, y: 0)) : (mainContainerView.transform = CGAffineTransform(scaleX: scale, y: scale))
    }

    fileprivate func applyRightContentViewScale() {
        let scale: CGFloat = 1.0 - ((1.0 - config.contentViewScale) * openedRightRatio)
        let drag: CGFloat = rightContainerView.frame.origin.x - mainContainerView.frame.size.width

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

    open func closeLeftNonAnimation(){
        setCloseWindowLevel()

        let finalXOrigin: CGFloat = leftMinOrigin
        var frame: CGRect = leftContainerView.frame
        frame.origin.x = finalXOrigin

        leftContainerView.frame = frame
        opacityView.layer.opacity = 0.0
        mainContainerView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
        removeShadow(leftContainerView)
        mainContainerView.isUserInteractionEnabled = true
    }

    open func closeRightNonAnimation(){
        setCloseWindowLevel()

        let finalXOrigin: CGFloat = view.bounds.width
        var frame: CGRect = rightContainerView.frame
        frame.origin.x = finalXOrigin
        rightContainerView.frame = frame

        opacityView.layer.opacity = 0.0
        mainContainerView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
        removeShadow(rightContainerView)
        mainContainerView.isUserInteractionEnabled = true
    }

    // MARK: UIGestureRecognizerDelegate
    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point: CGPoint = touch.location(in: view)

        if gestureRecognizer == leftPanGesture {
            return slideLeftForGestureRecognizer(gestureRecognizer, point: point)
        } else if gestureRecognizer == rightPanGesture {
            return slideRightViewForGestureRecognizer(gestureRecognizer, withTouchPoint: point)
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

    fileprivate func slideLeftForGestureRecognizer(_ gesture: UIGestureRecognizer, point:CGPoint) -> Bool{
        isLeftOpen || config.panFromBezel && isLeftPointContainedWithinBezelRect(point)
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

    fileprivate func slideRightViewForGestureRecognizer(_ gesture: UIGestureRecognizer, withTouchPoint point: CGPoint) -> Bool {
        isRightOpen || config.rightPanFromBezel && isRightPointContainedWithinBezelRect(point)
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
        slideMenuController?.toggleLeft()
    }

    @objc public func toggleRight() {
        slideMenuController?.toggleRight()
    }

    @objc public func openLeft() {
        slideMenuController?.openLeft()
    }

    @objc public func openRight() {
        slideMenuController?.openRight()
    }

    @objc public func closeLeft() {
        slideMenuController?.closeLeft()
    }

    @objc public func closeRight() {
        slideMenuController?.closeRight()
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
