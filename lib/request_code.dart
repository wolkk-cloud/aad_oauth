import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'model/config.dart';
import 'request/authorization_request.dart';

class RequestCode {
  final Config _config;
  final AuthorizationRequest _authorizationRequest;
  final String _redirectUriHost;
  late NavigationDelegate _navigationDelegate;
  late WebViewCookieManager _cookieManager;
  late CookieManager cookieManagerWindows;

  String? _code;

  RequestCode(Config config)
      : _config = config,
        _authorizationRequest = AuthorizationRequest(config),
        _redirectUriHost = Uri.parse(config.redirectUri).host {
    if (!(Platform.isWindows || Platform.isMacOS)) {
      _navigationDelegate = NavigationDelegate(
        onNavigationRequest: _onNavigationRequest,
      );
      _cookieManager = WebViewCookieManager();
    } else {
      cookieManagerWindows = CookieManager.instance();
    }
  }

  Future<String?> requestCodeWindows(
      {Widget? expandedWidget,
      TextEditingController? textInputController}) async {
    _code = null;
    late final InAppWebViewController webViewWindowsController;
    final urlParams = _constructUrlParams();

    final webView = InAppWebView(
      initialSettings: InAppWebViewSettings(
          incognito: true,
          cacheMode: CacheMode.LOAD_NO_CACHE,
          cacheEnabled: false,
          clearSessionCache: true),
      initialUrlRequest:
          URLRequest(url: WebUri("${_authorizationRequest.url}?$urlParams")),
      onWebViewCreated: (controller) {
        webViewWindowsController = controller;
        webViewWindowsController.addJavaScriptHandler(
          handlerName: 'onTextFieldFocus',
          callback: (args) async {
            textInputController?.clear();
            textInputController?.addListener(() {
              inputControllerListener(
                  textInputController: textInputController,
                  webViewWindowsController: webViewWindowsController);
            });
          },
        );
        webViewWindowsController.addJavaScriptHandler(
          handlerName: 'onTextFieldBlur',
          callback: (args) {
            textInputController?.removeListener(() {
              inputControllerListener(
                  textInputController: textInputController,
                  webViewWindowsController: webViewWindowsController);
            });
          },
        );
      },
      onLoadStart: (controller, url) {
        if (url?.queryParameters['error'] != null) {
          _config.navigatorKey.currentState?.pop();
        }

        var checkHost = url?.host == _redirectUriHost;

        if (url?.queryParameters['code'] != null && checkHost) {
          _code = url?.queryParameters['code'];
          if (_config.onPageFinished != null) {
            _config.onPageFinished?.call(_code!);
          }
          if (_config.navigatorKey.currentState?.canPop() ?? false) {
            _config.navigatorKey.currentState?.pop();
          }
        }
      },
      onLoadStop: (controller, url) {
        // Inject JavaScript to detect text field focus
        controller.evaluateJavascript(source: '''
          document.addEventListener('focusin', function(e) {
            if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
              console.log('Text field focused:', e.target);
              window.flutter_inappwebview.callHandler('onTextFieldFocus', e.target.name);
            }
          });

          document.addEventListener('focusout', function(e) {
            if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
              console.log('Text field blurred:', e.target);
              window.flutter_inappwebview.callHandler('onTextFieldBlur', e.target.name);
            }
          });
        ''');
      },
    );

    if (_config.navigatorKey.currentState == null) {
      throw Exception(
        'Could not push new route using provided navigatorKey, Because '
        'NavigatorState returned from provided navigatorKey is null. Please Make sure '
        'provided navigatorKey is passed to WidgetApp. This can also happen if at the time of this method call '
        'WidgetApp is not part of the flutter widget tree',
      );
    }

    await _config.navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (context) {
          bool isExpanded = false;
          return StatefulBuilder(builder: (context, setState) {
            return Scaffold(
              appBar: _config.appBar,
              body: PopScope(
                canPop: false,
                onPopInvokedWithResult: (bool didPop, _) async {
                  if (didPop) return;
                  final NavigatorState navigator = Navigator.of(context);
                  if (navigator.canPop()) {
                    navigator.pop();
                  }
                },
                child: SafeArea(
                  child: Stack(
                    children: [_config.loader, webView],
                  ),
                ),
              ),
              bottomNavigationBar: isExpanded ? expandedWidget : null,
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.startFloat,
              floatingActionButton: FloatingActionButton(
                backgroundColor: Colors.black,
                onPressed: () {
                  setState(() {
                    isExpanded = !isExpanded;
                  });
                },
                child: Icon(
                  isExpanded ? Icons.arrow_downward : Icons.arrow_upward,
                  color: Colors.white,
                ),
              ),
            );
          });
        },
      ),
    );
    return _code;
  }

  void inputControllerListener(
      {TextEditingController? textInputController,
      required InAppWebViewController webViewWindowsController}) {
    if (textInputController == null) return;
    webViewWindowsController.evaluateJavascript(source: '''
        var activeElement = document.activeElement;
        if (activeElement && (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA')) {
          activeElement.value = "${textInputController.text}";
          var event = new Event('input', { bubbles: true });
          activeElement.dispatchEvent(event);
          event = new Event('change', { bubbles: true });
          activeElement.dispatchEvent(event);
        }
        ''');
  }

  Future clearCookiesWindows() async {
    try {
      await cookieManagerWindows.deleteAllCookies();
    } catch (e, stacktrace) {
      print("ERROR $e || $stacktrace");
    }
  }

  Future<String?> requestCode() async {
    _code = null;

    final urlParams = _constructUrlParams();
    final launchUri = Uri.parse('${_authorizationRequest.url}?$urlParams');
    final controller = WebViewController();
    await controller.setNavigationDelegate(_navigationDelegate);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

    await controller.setBackgroundColor(Colors.transparent);
    await controller.setUserAgent(_config.userAgent);
    await controller.loadRequest(launchUri);
    if (_config.onPageFinished != null) {
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: _config.onPageFinished,
        ),
      );
    }

    final webView = WebViewWidget(controller: controller);

    if (_config.navigatorKey.currentState == null) {
      throw Exception(
        'Could not push new route using provided navigatorKey, Because '
        'NavigatorState returned from provided navigatorKey is null. Please Make sure '
        'provided navigatorKey is passed to WidgetApp. This can also happen if at the time of this method call '
        'WidgetApp is not part of the flutter widget tree',
      );
    }

    await _config.navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: _config.appBar,
          body: PopScope(
            canPop: false,
            onPopInvoked: (bool didPop) async {
              if (didPop) return;
              if (await controller.canGoBack()) {
                await controller.goBack();
                return;
              }
              final NavigatorState navigator = Navigator.of(context);
              navigator.pop();
            },
            child: SafeArea(
              child: Stack(
                children: [_config.loader, webView],
              ),
            ),
          ),
        ),
      ),
    );
    return _code;
  }

  Future<NavigationDecision> _onNavigationRequest(
      NavigationRequest request) async {
    try {
      var uri = Uri.parse(request.url);

      if (uri.queryParameters['error'] != null) {
        _config.navigatorKey.currentState!.pop();
      }

      var checkHost = uri.host == _redirectUriHost;

      if (uri.queryParameters['code'] != null && checkHost) {
        _code = uri.queryParameters['code'];
        _config.navigatorKey.currentState!.pop();
      }
    } catch (_) {}
    return NavigationDecision.navigate;
  }

  Future<void> clearCookies() async {
    if (!(Platform.isWindows || Platform.isMacOS)) {
      await _cookieManager.clearCookies();
    } else {
      await clearCookiesWindows();
    }
  }

  String _constructUrlParams() => _mapToQueryParams(
      _authorizationRequest.parameters, _config.customParameters);

  String _mapToQueryParams(
      Map<String, String> params, Map<String, String> customParams) {
    final queryParams = <String>[];

    params.forEach((String key, String value) =>
        queryParams.add('$key=${Uri.encodeQueryComponent(value)}'));

    customParams.forEach((String key, String value) =>
        queryParams.add('$key=${Uri.encodeQueryComponent(value)}'));
    return queryParams.join('&');
  }
}
