/// Microsoft identity platform authentication library.
/// @nodoc
@JS('aadOauth')
library msauth;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop' hide JS;

import 'package:aad_oauth/helper/core_oauth.dart';
import 'package:aad_oauth/model/config.dart';
import 'package:aad_oauth/model/failure.dart';
import 'package:aad_oauth/model/msalconfig.dart';
import 'package:aad_oauth/model/token.dart';
import 'package:aad_oauth/model/web_view_keyboard.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:js/js.dart';

@JS('init')
external void jsInit(MsalConfig config);

@JS('login')
external void jsLogin(
  bool refreshIfAvailable,
  bool useRedirect,
  JSFunction onSuccess,
  JSFunction onError,
);

@JS('logout')
external void jsLogout(
  JSFunction onSuccess,
  JSFunction onError,
  bool showPopup,
);

@JS('getAccessToken')
external JSPromise<JSString?> jsGetAccessToken();

@JS('getIdToken')
external JSPromise<JSString?> jsGetIdToken();

@JS('hasCachedAccountInformation')
external bool jsHasCachedAccountInformation();

@JS('refreshToken')
external void jsRefreshToken(
  JSFunction onSuccess,
  JSFunction onError,
);

class WebOAuth extends CoreOAuth {
  final Config config;
  WebOAuth(this.config) {
    jsInit(MsalConfig.construct(
        tenant: config.tenant,
        policy: config.policy,
        clientId: config.clientId,
        responseType: config.responseType,
        redirectUri: config.redirectUri,
        scope: config.scope,
        responseMode: config.responseMode,
        state: config.state,
        prompt: config.prompt,
        codeChallenge: config.codeChallenge,
        codeChallengeMethod: config.codeChallengeMethod,
        nonce: config.nonce,
        tokenIdentifier: config.tokenIdentifier,
        clientSecret: config.clientSecret,
        resource: config.resource,
        isB2C: config.isB2C,
        customAuthorizationUrl: config.customAuthorizationUrl,
        customTokenUrl: config.customTokenUrl,
        loginHint: config.loginHint,
        domainHint: config.domainHint,
        codeVerifier: config.codeVerifier,
        authorizationUrl: config.authorizationUrl,
        tokenUrl: config.tokenUrl,
        cacheLocation: config.cacheLocation.value,
        customParameters: jsonEncode(config.customParameters),
        postLogoutRedirectUri: config.postLogoutRedirectUri));
  }

  @override
  Future<String?> getAccessToken() async {
    return (await jsGetAccessToken().toDart)?.toDart;
  }

  @override
  Future<String?> getIdToken() async {
    return (await jsGetIdToken().toDart)?.toDart;
  }

  @override
  Future<bool> get hasCachedAccountInformation =>
      Future<bool>.value(jsHasCachedAccountInformation());

  @override
  Future<Either<Failure, Token>> login(
      {bool refreshIfAvailable = false,
      bool clearCookies = false,
      Widget? expandedWidget,
      WebViewKeyboardBuilder? keyboardBuilder,
      bool showKeyboardOnFocus = false,
      TextEditingController? textInputController}) async {
    final completer = Completer<Either<Failure, Token>>();

    jsLogin(
      refreshIfAvailable,
      config.webUseRedirect,
      ((JSString? value) =>
          completer.complete(Right(Token(accessToken: value?.toDart)))).toJS,
      ((JSAny? error) => completer.complete(Left(AadOauthFailure(
            errorType: ErrorType.accessDeniedOrAuthenticationCanceled,
            message:
                'Access denied or authentication canceled. Error: ${error.toString()}',
          )))).toJS,
    );

    return completer.future;
  }

  @override
  Future<Either<Failure, Token>> refreshToken() {
    final completer = Completer<Either<Failure, Token>>();

    jsRefreshToken(
      ((JSString? value) =>
          completer.complete(Right(Token(accessToken: value?.toDart)))).toJS,
      ((JSAny? error) => completer.complete(Left(AadOauthFailure(
            errorType: ErrorType.accessDeniedOrAuthenticationCanceled,
            message:
                'Access denied or authentication canceled. Error: ${error.toString()}',
          )))).toJS,
    );

    return completer.future;
  }

  @override
  Future<void> logout({bool showPopup = true, bool clearCookies = true}) async {
    final completer = Completer<void>();

    jsLogout(
      (() => completer.complete()).toJS,
      ((JSAny? error) => completer.completeError(error ?? 'Logout failed'))
          .toJS,
      showPopup,
    );

    return completer.future;
  }
}

CoreOAuth getOAuthConfig(Config config) => WebOAuth(config);
