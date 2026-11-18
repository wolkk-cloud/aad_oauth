import 'package:flutter/widgets.dart';

/// Builds an in-app keyboard shown under the desktop login web view.
///
/// [onSubmit] submits the login form in the web view (e.g. presses the
/// "Next" / "Sign in" button), so the keyboard's Enter key can call it.
typedef WebViewKeyboardBuilder = Widget Function(
    BuildContext context, VoidCallback onSubmit);
