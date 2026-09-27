import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Renders either a Material [IconData] or a FontAwesome [FaIconData] from a
/// single `dynamic` value. Several widgets across the app (nav bar items,
/// settings tiles, social buttons, action buttons) accept "any icon" so they
/// can mix FontAwesome and Material icons, and each used to reimplement this
/// same is-it-FontAwesome branch locally — this is the one shared version.
class DynamicIcon extends StatelessWidget {
  final dynamic icon;
  final double size;
  final Color color;

  const DynamicIcon(
    this.icon, {
    super.key,
    this.size = 20,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (icon is FaIconData) {
      return FaIcon(icon as FaIconData, size: size, color: color);
    }
    return Icon(icon as IconData, size: size, color: color);
  }
}
