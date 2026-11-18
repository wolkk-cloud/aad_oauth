import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'model/config.dart';
import 'model/web_view_keyboard.dart';
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
      WebViewKeyboardBuilder? keyboardBuilder,
      bool showKeyboardOnFocus = false,
      TextEditingController? textInputController}) async {
    _code = null;
    InAppWebViewController? webController;
    final urlParams = _constructUrlParams();
    final hasKeyboard = keyboardBuilder != null || expandedWidget != null;
    final keyboardVisible = ValueNotifier<bool>(false);

    // True while the controller is being filled from the web field, so that
    // update is not written back into the page.
    var syncingFromWeb = false;

    void pushTextToWeb() {
      final controller = webController;
      final input = textInputController;
      if (controller == null || input == null || syncingFromWeb) return;
      controller.evaluateJavascript(
          source: _setActiveInputValueJs(jsonEncode(input.text)));
    }

    void submitWebForm() {
      webController?.evaluateJavascript(source: _submitActiveFormJs);
    }

    void onTextFieldFocus(List<dynamic> args) {
      final input = textInputController;
      if (input != null) {
        final focusedValue =
            args.isNotEmpty && args[0] is String ? args[0] as String : '';
        syncingFromWeb = true;
        input.value = TextEditingValue(
          text: focusedValue,
          selection: TextSelection.collapsed(offset: focusedValue.length),
        );
        syncingFromWeb = false;
      }
      if (showKeyboardOnFocus && hasKeyboard) {
        keyboardVisible.value = true;
      }
    }

    // A single listener for the whole login flow, removed when the route is
    // closed. It writes into whichever text input is focused in the page.
    textInputController?.addListener(pushTextToWeb);

    final webView = InAppWebView(
      initialSettings: InAppWebViewSettings(
          incognito: true,
          cacheMode: CacheMode.LOAD_NO_CACHE,
          cacheEnabled: false,
          clearSessionCache: true),
      initialUrlRequest:
          URLRequest(url: WebUri("${_authorizationRequest.url}?$urlParams")),
      onWebViewCreated: (controller) {
        webController = controller;
        controller.addJavaScriptHandler(
          handlerName: 'onTextFieldFocus',
          callback: onTextFieldFocus,
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
        controller.evaluateJavascript(source: _textFieldFocusJs);
      },
    );

    if (_config.navigatorKey.currentState == null) {
      textInputController?.removeListener(pushTextToWeb);
      keyboardVisible.dispose();
      throw Exception(
        'Could not push new route using provided navigatorKey, Because '
        'NavigatorState returned from provided navigatorKey is null. Please Make sure '
        'provided navigatorKey is passed to WidgetApp. This can also happen if at the time of this method call '
        'WidgetApp is not part of the flutter widget tree',
      );
    }

    try {
      await _config.navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (context) {
            return ValueListenableBuilder<bool>(
              valueListenable: keyboardVisible,
              builder: (context, isExpanded, _) {
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
                  bottomNavigationBar: isExpanded
                      ? (keyboardBuilder?.call(context, submitWebForm) ??
                          expandedWidget)
                      : null,
                  floatingActionButtonLocation:
                      FloatingActionButtonLocation.startFloat,
                  floatingActionButton: hasKeyboard
                      ? FloatingActionButton(
                          backgroundColor: Colors.black,
                          onPressed: () =>
                              keyboardVisible.value = !keyboardVisible.value,
                          child: Icon(
                            isExpanded
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: Colors.white,
                          ),
                        )
                      : null,
                );
              },
            );
          },
        ),
      );
    } finally {
      textInputController?.removeListener(pushTextToWeb);
      webController = null;
      keyboardVisible.dispose();
    }
    return _code;
  }

  /// Reports focused text inputs to the `onTextFieldFocus` handler.
  ///
  /// Installed once per document. Blur is deliberately not tracked: tapping
  /// the Flutter keyboard blurs the web view, but the input must keep
  /// receiving text. Writes always target `document.activeElement` instead.
  static const _textFieldFocusJs = r"""
(function() {
  if (window.__aadKeyboardInstalled) return;
  window.__aadKeyboardInstalled = true;
  var textTypes = ['', 'text', 'email', 'password', 'tel', 'number', 'search', 'url'];
  function isTextInput(el) {
    if (!el) return false;
    if (el.tagName === 'TEXTAREA') return true;
    return el.tagName === 'INPUT' &&
      textTypes.indexOf((el.getAttribute('type') || '').toLowerCase()) !== -1;
  }
  function report(el) {
    window.flutter_inappwebview.callHandler('onTextFieldFocus', el.value || '');
  }
  document.addEventListener('focusin', function(e) {
    if (isTextInput(e.target)) report(e.target);
  });
  // The page may autofocus an input before this script runs.
  if (isTextInput(document.activeElement)) report(document.activeElement);
})();
""";

  /// Sets the focused text input to [jsonValue] (a JSON string literal) and
  /// fires the events the page's bindings listen to.
  static String _setActiveInputValueJs(String jsonValue) => """
(function() {
  var el = document.activeElement;
  if (!el || (el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA')) return;
  var value = $jsonValue;
  if (el.value === value) return;
  var proto = el.tagName === 'INPUT'
    ? window.HTMLInputElement.prototype
    : window.HTMLTextAreaElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
})();
""";

  /// Presses the page's primary submit button ("Next" / "Sign in" / "Yes" on
  /// the Microsoft login page), falling back to submitting the focused form.
  static const _submitActiveFormJs = r"""
(function() {
  var el = document.activeElement;
  var form = el && el.form;
  var button = document.getElementById('idSIButton9') ||
    (form && form.querySelector('input[type=submit], button[type=submit]')) ||
    document.querySelector('input[type=submit], button[type=submit]');
  if (button && !button.disabled) {
    button.click();
  } else if (form) {
    if (form.requestSubmit) { form.requestSubmit(); } else { form.submit(); }
  }
})();
""";

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
            onPopInvokedWithResult: (bool didPop, _) async {
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
