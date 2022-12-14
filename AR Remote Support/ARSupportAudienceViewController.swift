//
//  AgoraSupportAudienceViewController.swift
//  AR Remote Support
//
//  Created by digitallysavvy on 10/30/19.
//  Copyright © 2019 Agora.io. All rights reserved.
//

import UIKit
import AgoraRtcKit

class ARSupportAudienceViewController: UIViewController, UIGestureRecognizerDelegate, AgoraRtcEngineDelegate {
    
    var touchStart: CGPoint!                // keep track of the initial touch point of each gesture
    var touchPoints: [CGPoint]!             // for drawing touches to the screen
    
    //  list of colors that user can choose from
    let uiColors: [UIColor] = [UIColor.systemBlue, UIColor.systemGray, UIColor.systemGreen, UIColor.systemYellow, UIColor.systemRed]
    
    var lineColor: UIColor!                 // active color to use when drawing
    let bgColor: UIColor = .white           // set the view bg color
    
    var drawingView: UIView!                // view to draw all the local touches
    var localVideoView: UIView!             // video stream of local camera
    var remoteVideoView: UIView!            // video stream from remote user
    var micBtn: UIButton!                   // button to mute/un-mute the microphone
    var colorSelectionBtn: UIButton!        // button to handle display or hiding the colors avialble to the user
    var colorButtons: [UIButton] = []       // keep track of the buttons for each color
    
    // Agora
    var agoraKit: AgoraRtcEngineKit!        // Agora.io Video Engine reference
    var channelName: String!                // name of the channel to join
    
    var sessionIsActive = false             // keep track if the video session is active or not
    var remoteUser: UInt?                   // remote user id
    var dataStreamId: Int! = 27             // id for data stream
    var streamIsEnabled: Int32 = -1         // acts as a flag to keep track if the data stream is enabled
    
    var dataPointsArray: [CGPoint] = []     // batch list of touches to be sent to remote user
    
    let debug: Bool = false                 // toggle the debug logs
    
    // MARK: VC Events
    override func loadView() {
        super.loadView()
        createUI() // init and add the UI elements to the view
        //  TODO: setup touch gestures
        
        // TODO: Add Agora setup
        guard let appID = getValue(withKey: "AppID", within: "keys") else { return }  // get the AppID from keys.plist
        self.agoraKit = AgoraRtcEngineKit.sharedEngine(withAppId: appID, delegate: self) // - init engine
        self.agoraKit.setChannelProfile(.communication) // - set channel profile
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        self.lineColor = self.uiColors.first        // set the active color to the first in the list
        self.view.backgroundColor = self.bgColor    // set the background color
        self.view.isUserInteractionEnabled = true   // enable user touch events
        
        //  TODO: Add Agora implementation
        setupLocalVideo() //  - set video configuration
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // do something when the view has appeared
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if self.sessionIsActive {
            leaveChannel();
        }
    }
    
    // MARK: Hide status bar
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    // MARK: Gestures
    func setupGestures() {
        // TODO: Add pan gesture
        // pan gesture
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        self.view.addGestureRecognizer(panGesture)
    }
    
    // MARK: Touch Capture
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // TODO: Get the initial touch event
        // get the initial touch event
        if self.sessionIsActive, let touch = touches.first {
            let position = touch.location(in: self.view)
            self.touchStart = position
            self.touchPoints = []
            if debug {
                print(position)
            }
        }
        // check if the color selection menu is visible
        if let colorSelectionBtn = self.colorSelectionBtn, colorSelectionBtn.alpha < 1 {
            toggleColorSelection() // make sure to hide the color menu
        }
    }
    
    @IBAction func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        
        if self.sessionIsActive && gestureRecognizer.state == .began && self.streamIsEnabled == 0 {
            // send message to remote user that touches have started
            self.agoraKit.sendStreamMessage(self.dataStreamId, data: "touch-start".data(using: String.Encoding.ascii)!)
        }
        
        if self.sessionIsActive && (gestureRecognizer.state == .began || gestureRecognizer.state == .changed) {
            let translation = gestureRecognizer.translation(in: self.view)
            // calculate touch movement relative to the superview
            guard let touchStart = self.touchStart else { return } // ignore accidental finger drags
            let pixelTranslation = CGPoint(x: touchStart.x + translation.x, y: touchStart.y + translation.y)
            
            // normalize the touch point to use view center as the reference point
            let translationFromCenter = CGPoint(x: pixelTranslation.x - (0.5 * self.view.frame.width), y: pixelTranslation.y - (0.5 * self.view.frame.height))
            
            self.touchPoints.append(pixelTranslation)
            
            // TODO: Send captured points
            
            DispatchQueue.main.async {
                // draw user touches to the DrawView
                guard let drawView = self.drawingView else { return }
                guard let lineColor: UIColor = self.lineColor else { return }
                let layer = CAShapeLayer()
                layer.path = UIBezierPath(roundedRect: CGRect(x:  pixelTranslation.x, y: pixelTranslation.y, width: 25, height: 25), cornerRadius: 50).cgPath
                layer.fillColor = lineColor.cgColor
                drawView.layer.addSublayer(layer)
            }
            
            if debug {
                print(translationFromCenter)
                print(pixelTranslation)
            }
        }
        
        if gestureRecognizer.state == .ended {
            // TODO: send message to remote user that touches have ended
            if self.streamIsEnabled == 0 {
                // transmit any left over points
                if self.dataPointsArray.count > 0 {
                    sendTouchPoints() // send touch data to remote user
                    clearSubLayers() // remove touches drawn to the screen
                }
                self.agoraKit.sendStreamMessage(self.dataStreamId, data: "touch-end".data(using: String.Encoding.ascii)!)
            }
            // clear list of points
            if let touchPointsList = self.touchPoints {
                self.touchStart = nil // clear starting point
                if debug {
                    print(touchPointsList)
                }
            }
        }
    }
    
    func sendTouchPoints() {
        // TODO: Transmit touch data
        let pointsAsString: String = self.dataPointsArray.description
        self.agoraKit.sendStreamMessage(self.dataStreamId, data: pointsAsString.data(using: String.Encoding.ascii)!)
        self.dataPointsArray = []
    }
    
    func clearSubLayers() {
        // TODO: Remove touches drawn to the screen
        DispatchQueue.main.async {
            // loop through layers drawn from touches and remove them from the view
            guard let sublayers = self.drawingView.layer.sublayers else { return }
            for layer in sublayers {
                layer.isHidden = true
                layer.removeFromSuperlayer()
            }
        }
    }
    
    // MARK: UI
    func createUI() {
        
        // add remote video view
        let remoteView = UIView()
        remoteView.frame = CGRect(x: 0, y: 0, width: self.view.frame.width, height: self.view.frame.height)
        remoteView.backgroundColor = UIColor.lightGray
        self.view.insertSubview(remoteView, at: 0)
        self.remoteVideoView = remoteView
        
        // add branded logo to remote view
        guard let agoraLogo = UIImage(named: "agora-logo") else { return }
        let remoteViewBagroundImage = UIImageView(image: agoraLogo)
        remoteViewBagroundImage.frame = CGRect(x: remoteView.frame.midX-56.5, y: remoteView.frame.midY-100, width: 117, height: 126)
        remoteViewBagroundImage.alpha = 0.25
        remoteView.insertSubview(remoteViewBagroundImage, at: 1)
        
        // ui view that the finger drawings will appear on
        let drawingView = UIView(frame: CGRect(x: 0, y: 0, width: self.view.frame.width, height: self.view.frame.height))
        self.view.insertSubview(drawingView, at: 1)
        self.drawingView = drawingView
        
        // add local video view
        let localViewScale = self.view.frame.width * 0.33
        let localView = UIView()
        localView.frame = CGRect(x: self.view.frame.maxX - (localViewScale+17.5), y: self.view.frame.maxY - (localViewScale+25), width: localViewScale, height: localViewScale)
        localView.layer.cornerRadius = 25
        localView.layer.masksToBounds = true
        localView.backgroundColor = UIColor.darkGray
        self.view.insertSubview(localView, at: 2)
        self.localVideoView = localView
        
        // mute button
        let micBtn = UIButton()
        micBtn.frame = CGRect(x: self.view.frame.midX-37.5, y: self.view.frame.maxY-100, width: 75, height: 75)
        if let imageMicBtn = UIImage(named: "mic") {
            micBtn.setImage(imageMicBtn, for: .normal)
        } else {
            micBtn.setTitle("mute", for: .normal)
        }
        micBtn.addTarget(self, action: #selector(toggleMic), for: .touchDown)
        self.view.insertSubview(micBtn, at: 3)
        self.micBtn = micBtn
        
        //  back button
        let backBtn = UIButton()
        backBtn.frame = CGRect(x: self.view.frame.maxX-55, y: self.view.frame.minY+20, width: 30, height: 30)
        //        backBtn.layer.cornerRadius = 10
        if let imageExitBtn = UIImage(named: "exit") {
            backBtn.setImage(imageExitBtn, for: .normal)
        } else {
            backBtn.setTitle("x", for: .normal)
        }
        backBtn.addTarget(self, action: #selector(popView), for: .touchUpInside)
        self.view.insertSubview(backBtn, at: 3)
        
        // color palette button
        let colorSelectionBtn = UIButton(type: .custom)
        colorSelectionBtn.frame = CGRect(x: self.view.frame.minX+20, y: self.view.frame.maxY-60, width: 40, height: 40)
        if let colorSelectionBtnImage = UIImage(named: "color") {
            let tinableImage = colorSelectionBtnImage.withRenderingMode(.alwaysTemplate)
            colorSelectionBtn.setImage(tinableImage, for: .normal)
            colorSelectionBtn.tintColor = self.uiColors.first
        } else {
            colorSelectionBtn.setTitle("color", for: .normal)
        }
        colorSelectionBtn.addTarget(self, action: #selector(toggleColorSelection), for: .touchUpInside)
        self.view.insertSubview(colorSelectionBtn, at: 4)
        self.colorSelectionBtn = colorSelectionBtn
        
        // set up color buttons
        for (index, color) in uiColors.enumerated() {
            let colorBtn = UIButton(type: .custom)
            colorBtn.frame = CGRect(x: colorSelectionBtn.frame.midX-13.25, y: colorSelectionBtn.frame.minY-CGFloat(35+(index*35)), width: 27.5, height: 27.5)
            colorBtn.layer.cornerRadius = 0.5 * colorBtn.bounds.size.width
            colorBtn.clipsToBounds = true
            colorBtn.backgroundColor = color
            colorBtn.addTarget(self, action: #selector(setColor), for: .touchDown)
            colorBtn.alpha = 0
            colorBtn.isHidden = true
            colorBtn.isUserInteractionEnabled = false
            self.view.insertSubview(colorBtn, at: 3)
            self.colorButtons.append(colorBtn)
        }
        
        // add undo button
        let undoBtn = UIButton()
        undoBtn.frame = CGRect(x: colorSelectionBtn.frame.maxX+25, y: colorSelectionBtn.frame.minY+5, width: 30, height: 30)
        if let imageUndoBtn = UIImage(named: "undo") {
            undoBtn.setImage(imageUndoBtn, for: .normal)
        } else {
            undoBtn.setTitle("undo", for: .normal)
        }
        undoBtn.addTarget(self, action: #selector(sendUndoMsg), for: .touchUpInside)
        self.view.insertSubview(undoBtn, at: 3)
        
    }
    
    // MARK: Button Events
    @IBAction func popView() {
        leaveChannel()                                  // leave the channel
        self.dismiss(animated: true, completion: nil)   // dismiss the view
    }
    
    @IBAction func toggleMic() {
        guard let activeMicImg = UIImage(named: "mic") else { return }
        guard let disabledMicImg = UIImage(named: "mute") else { return }
        if self.micBtn.imageView?.image == activeMicImg {
            self.agoraKit.muteLocalAudioStream(true) // Disable Mic using Agora Engine
            self.micBtn.setImage(disabledMicImg, for: .normal)
            if debug {
                print("disable active mic")
            }
        } else {
            self.agoraKit.muteLocalAudioStream(false) // Enable Mic using Agora Engine
            self.micBtn.setImage(activeMicImg, for: .normal)
            if debug {
                print("enable mic")
            }
        }
    }
    
    @IBAction func toggleColorSelection() {
        guard let colorSelectionBtn = self.colorSelectionBtn else { return }
        var isHidden = false
        var alpha: CGFloat = 1
        
        if colorSelectionBtn.alpha == 1 {
            colorSelectionBtn.alpha = 0.65
        } else {
            colorSelectionBtn.alpha = 1
            alpha = 0
            isHidden = true
        }
        
        for button in self.colorButtons {
            // highlihgt the selected color
            button.alpha = alpha
            button.isHidden = isHidden
            button.isUserInteractionEnabled = !isHidden
            // use CGColor in comparison: BackgroundColor and TintColor do not init the same for the same UIColor.
            if button.backgroundColor?.cgColor == colorSelectionBtn.tintColor.cgColor {
                button.layer.borderColor = UIColor.white.cgColor
                button.layer.borderWidth = 2
            } else {
                button.layer.borderWidth = 0
            }
        }
        
    }
    
    @IBAction func setColor(_ sender: UIButton) {
        guard let colorSelectionBtn = self.colorSelectionBtn else { return }
        colorSelectionBtn.tintColor = sender.backgroundColor
        self.lineColor = colorSelectionBtn.tintColor
        toggleColorSelection()
        // TODO: Send data message with updated color
        if self.streamIsEnabled == 0 {
            guard let colorComponents = sender.backgroundColor?.cgColor.components else { return }
            self.agoraKit.sendStreamMessage(self.dataStreamId, data: "color: \(colorComponents)".data(using: String.Encoding.ascii)!)
            if debug {
                print("color: \(colorComponents)")
            }
        }
    }
    
    @IBAction func sendUndoMsg() {
        // TODO: Send undo msg
        // if data stream is enabled, send undo message
        if self.streamIsEnabled == 0 {
            self.agoraKit.sendStreamMessage(self.dataStreamId, data: "undo".data(using: String.Encoding.ascii)!)
        }
    }
    
    // MARK: Agora Implementation
    func setupLocalVideo() {
        // TODO: enable the local video stream
        guard let localVideoView = self.localVideoView else { return } // get a reference to the localVideo UI element
        
        // enable the local video stream
        self.agoraKit.enableVideo()
        
        // Set video encoding configuration (dimensions, frame-rate, bitrate, orientation)
        let videoConfig = AgoraVideoEncoderConfiguration(size: AgoraVideoDimension360x360, frameRate: .fps15, bitrate: AgoraVideoBitrateStandard, orientationMode: .fixedPortrait)
        self.agoraKit.setVideoEncoderConfiguration(videoConfig)
        // Set up local video view
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = 0
        videoCanvas.view = localVideoView
        videoCanvas.renderMode = .hidden
        // Set the local video view.
        self.agoraKit.setupLocalVideo(videoCanvas)
        
        // stylin - round the corners for the view
        guard let videoView = localVideoView.subviews.first else { return }
        videoView.layer.cornerRadius = 25
    }
    
    func joinChannel() {
        // Set audio route to speaker
        self.agoraKit.setDefaultAudioRouteToSpeakerphone(true)
        // get the token - returns nil if no value is set
        let token = getValue(withKey: "token", within: "keys")
        // Join the channel
        self.agoraKit.joinChannel(byToken: token, channelId: self.channelName, info: nil, uid: 0) { (channel, uid, elapsed) in
            if self.debug {
                print("Successfully joined: \(channel), with \(uid): \(elapsed) secongs ago")
            }
        }
        UIApplication.shared.isIdleTimerDisabled = true     // Disable idle timmer
    }
    
    func leaveChannel() {
        // TODO: leave channel - end chat session
        self.agoraKit.leaveChannel(nil)                     // leave channel and end chat
        self.sessionIsActive = false                        // session is no longer active
        UIApplication.shared.isIdleTimerDisabled = false    // Enable idle timer
    }
    
    // MARK: Agora Delegate
    func rtcEngine(_ engine: AgoraRtcEngineKit, firstRemoteVideoDecodedOfUid uid:UInt, size:CGSize, elapsed:Int) {
        // first remote video frame
        if self.debug {
            print("firstRemoteVideoDecoded for Uid: \(uid)")
        }
        if self.remoteUser == uid {
            // ...
            // create the data stream
            self.streamIsEnabled = self.agoraKit.createDataStream(&self.dataStreamId, reliable: true, ordered: true)
            if self.debug {
                print("Data Stream initiated - STATUS: \(self.streamIsEnabled)")
            }
        }
        
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        if self.debug {
            print("error: \(errorCode.rawValue)")
        }
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurWarning warningCode: AgoraWarningCode) {
        if self.debug {
            print("warning: \(warningCode.rawValue)")
        }
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        if self.debug {
            print("local user did join channel with uid:\(uid)")
        }
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        if self.debug {
            print("remote user did joined of uid: \(uid)")
        }
        // TODO: keep track of the remote user -- limit to a single user
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        if self.debug {
            print("remote user did offline of uid: \(uid)")
        }
        // TODO: Nullify remote user reference
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didAudioMuted muted: Bool, byUid uid: UInt) {
        // add logic to show icon that remote stream is muted
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, receiveStreamMessageFromUid uid: UInt, streamId: Int, data: Data) {
        // successfully received message from user
        if self.debug {
            print("STREAMID: \(streamId)\n - DATA: \(data)")
        }
        
    }
    
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurStreamMessageErrorFromUid uid: UInt, streamId: Int, error: Int, missed: Int, cached: Int) {
        // message failed to send(
        if self.debug {
            print("STREAMID: \(streamId)\n - ERROR: \(error)")
        }
    }
    
}
