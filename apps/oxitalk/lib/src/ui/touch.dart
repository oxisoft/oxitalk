import 'package:flutter/material.dart';

/// Whether the app runs where the screen is touched rather than pointed at with a mouse:
/// Android, iOS (iPads too) and Fuchsia, by the theme's [ThemeData.platform]. There is
/// nothing to hover there, so what shows under the mouse on desktop shows on a tap, or
/// always.
bool isTouchPlatform(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };
