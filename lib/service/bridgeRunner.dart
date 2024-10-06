import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class BridgeRunner {
  HeadlessInAppWebView? _web;
  Function? _onLaunched;

  String? _jsCode;

  Map<String, Function> _msgHandlers = {};
  Map<String, Completer> _msgCompleters = {};
  Map<String, Function> _reloadHandlers = {};
  int _evalJavascriptUID = 0;

  bool webViewLoaded = false;
  int jsCodeStarted = -1;
  Timer? _webViewReloadTimer;

  Future<void>? dispose() async {
    return _web?.dispose();
  }

  Future<void> launch(
    Function? onLaunched, {
    String? jsCode,
    Function? socketDisconnectedAction,
  }) async {
    /// reset state before webView launch or reload
    _msgHandlers = {};
    _msgCompleters = {};
    _reloadHandlers = {};
    _evalJavascriptUID = 0;
    _onLaunched = onLaunched;
    webViewLoaded = false;
    jsCodeStarted = -1;

    _jsCode = jsCode;

    if (_web == null) {
      _web = new HeadlessInAppWebView(
        windowId: 2,
        initialOptions: InAppWebViewGroupOptions(
          crossPlatform: InAppWebViewOptions(clearCache: true),
          android: AndroidInAppWebViewOptions(useOnRenderProcessGone: true),
        ),
        androidOnRenderProcessGone: (webView, detail) async {
          if (_web?.webViewController == webView) {
            webViewLoaded = false;
            await _web?.webViewController?.clearCache();
            await _web?.webViewController?.reload();
          }
        },
        initialUrlRequest: URLRequest(url: WebUri("http://localhost:8080/packages/polkawallet_sdk/assets/bridge.html")),
        onWebViewCreated: (controller) async {
          print('Bridge HeadlessInAppWebView created!');
          controller.loadUrl(urlRequest: URLRequest(url: WebUri("http://localhost:8080/packages/polkawallet_sdk/assets/bridge.html")));
        },
        onConsoleMessage: (controller, message) {
          print("CONSOLE MESSAGE: " + message.message);
          if (jsCodeStarted < 0) {
            try {
              final msg = jsonDecode(message.message);
              if (msg['path'] == 'log') {
                if (message.message.contains('js loaded')) {
                  jsCodeStarted = 1;
                } else {
                  jsCodeStarted = 0;
                }
              }
            } catch (err) {
              // ignore
            }
          }
          if (message.message.contains("WebSocket is not connected") && socketDisconnectedAction != null) {
            socketDisconnectedAction();
          }
          if (message.messageLevel != ConsoleMessageLevel.LOG) return;

          try {
            var msg = jsonDecode(message.message);

            final String? path = msg['path'];
            if (_msgCompleters[path!] != null) {
              Completer handler = _msgCompleters[path]!;
              handler.complete(msg['data']);
              if (path.contains('uid=')) {
                _msgCompleters.remove(path);
              }
            }
            if (_msgHandlers[path] != null) {
              Function handler = _msgHandlers[path]!;
              handler(msg['data']);
            }
          } catch (_) {
            // ignore
          }
        },
        onLoadStop: (controller, url) async {
          print('webview loaded $url');
          if (webViewLoaded) return;

          _handleReloaded();
          await _startJSCode();
        },
      );

      await _web?.dispose();
      await _web?.run();
    } else {
      _webViewReloadTimer = Timer.periodic(Duration(seconds: 3), (timer) {
        _tryReload();
      });
    }
  }

  void _tryReload() {
    if (!webViewLoaded) {
      _web?.webViewController?.reload();
    }
  }

  void _handleReloaded() {
    _webViewReloadTimer?.cancel();
    webViewLoaded = true;
  }

  Future<void> _startJSCode() async {
    // inject js file to webView
    if (_jsCode != null) {
      await _web!.webViewController?.evaluateJavascript(source: _jsCode!);
    }

    _onLaunched!();
    _reloadHandlers.forEach((_, value) {
      value();
    });
  }

  int getEvalJavascriptUID() {
    return _evalJavascriptUID++;
  }

  Future<dynamic> evalJavascript(
    String code, {
    bool wrapPromise = true,
    bool allowRepeat = true,
  }) async {
    // check if there's a same request loading
    if (!allowRepeat) {
      for (String i in _msgCompleters.keys) {
        String call = code.split('(')[0];
        if (i.contains(call)) {
          print('request $call loading');
          return _msgCompleters[i]!.future;
        }
      }
    }

    if (!wrapPromise) {
      final res = await _web!.webViewController?.evaluateJavascript(source: code);
      return res;
    }

    final c = new Completer();

    final uid = getEvalJavascriptUID();
    final method = 'uid=$uid;${code.split('(')[0]}';
    _msgCompleters[method] = c;

    final script = '$code.then(function(res) {'
        '  console.log(JSON.stringify({ path: "$method", data: res }));'
        '}).catch(function(err) {'
        '  console.log(JSON.stringify({ path: "log", data: {call: "$method", error: err.message} }));'
        '});';
    _web!.webViewController?.evaluateJavascript(source: script);

    return c.future;
  }

  Future<void> subscribeMessage(
    String code,
    String channel,
    Function callback,
  ) async {
    addMsgHandler(channel, callback);
    evalJavascript(code);
  }

  void unsubscribeMessage(String channel) {
    print('unsubscribe $channel');
    final unsubCall = 'unsub$channel';
    _web!.webViewController?.evaluateJavascript(source: 'window.$unsubCall && window.$unsubCall()');
  }

  void addMsgHandler(String channel, Function onMessage) {
    _msgHandlers[channel] = onMessage;
  }

  void removeMsgHandler(String channel) {
    _msgHandlers.remove(channel);
  }

  void subscribeReloadAction(String reloadKey, Function reloadAction) {
    _reloadHandlers[reloadKey] = reloadAction;
  }

  void unsubscribeReloadAction(String reloadKey) {
    _reloadHandlers.remove(reloadKey);
  }

  Future<void> reload() async {
    webViewLoaded = false;
    await _web?.webViewController?.clearCache();
    return _web?.webViewController?.reload();
  }
}
