//
//  SpineItemViewController.swift
//  R2Streamer
//
//  Created by Olivier Körner on 14/12/2016.
//  Copyright © 2016 Readium. All rights reserved.
//

import UIKit
import WebKit

class SpineItemViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    
    var webView: WKWebView!
    var spineItemURL: URL?
    
    init(spineItemURL: URL) {
        super.init(nibName: nil, bundle: nil)
        self.spineItemURL = spineItemURL
        title = spineItemURL.lastPathComponent
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(nibName: nil, bundle: nil)
    }
    
    override func loadView() {
        super.loadView()
        
        let configutation = self.webViewConfig()
        webView = WKWebView(frame: self.view.bounds, configuration: configutation)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        view.addSubview(webView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        NSLog("webView loading \(spineItemURL)")
        webView.load(URLRequest(url: spineItemURL!))
        
        let rightBarBtn = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.action, target: self, action: #selector(callJsMethod))
        self.navigationItem.rightBarButtonItem = rightBarBtn
    }
    
    func callJsMethod() {
        webView.evaluateJavaScript("callJS()") { (value, err) in
            print(value ?? "No value")
            print(err ?? "No error")
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func webView(_ webView: UIWebView, didFailLoadWithError error: Error) {
        NSLog("webView didFailLoadWithError \(error)")
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        
        webView.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        
        //TODO: reload or manage content f(orientation)
        if UIDevice.current.orientation.isLandscape {
            
        } else {
            
        }
    }
 
    
    
    //MARK: WKWebView methods
    
    /**
     
        Get the default configuration for the html/js reader
     
        - Returns: WKWebViewConfiguration The default configuration
     
     */
    func webViewConfig() -> WKWebViewConfiguration {
        
        let jsSource = "function callJS(){ alert(\"Injected JS is called! then catch by uidelegate to display a native alert\"); }"
        
        let script: WKUserScript = WKUserScript(source: jsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)

        let wkUController = WKUserContentController()
        wkUController.addUserScript(script)
        let wkWebConfig = WKWebViewConfiguration()
        wkWebConfig.userContentController = wkUController
        wkWebConfig.allowsInlineMediaPlayback = true
        wkWebConfig.preferences.javaScriptEnabled = true
        
        if #available(iOS 10.0, *) {
            wkWebConfig.ignoresViewportScaleLimits = true
        } else {
            // Fallback on earlier versions
        }
        return wkWebConfig
    }
    
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        
        
        let alertController = UIAlertController(title: message, message: nil,
                                                preferredStyle: UIAlertControllerStyle.alert);
        
        alertController.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.cancel) {
            _ in completionHandler()}
            
        );
        
        self.present(alertController, animated: true, completion: {});
    }

}

