import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RoundedButton extends StatelessWidget {
  final String? label;
  final Function onTap;
  final bool isEnabled;
  final IconData? leftIcon;
  final IconData? rightIcon;
  final bool expanded;
  final bool isPrimary;
  final bool isWarning;
  final Color? labelColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? iconColor;
  final double? borderRadius;

  final EdgeInsets? padding;
  final Widget? labelWidget;

  const RoundedButton({
    this.label,
    required this.onTap,
    this.expanded = true,
    this.isEnabled = true,
    this.isPrimary = true,
    this.leftIcon,
    this.rightIcon,
    this.labelColor,
    this.backgroundColor,
    this.isWarning = false,
    super.key, this.borderColor,
    this.iconColor,
    this.borderRadius,
    this.padding,
    this.labelWidget,
  });

  @override
  Widget build(BuildContext context) {
    Color backColor = Colors.amber;
    Color textColor = Colors.white;

    if (labelColor != null) {
      textColor = labelColor!;
    }
    if(backgroundColor != null) {
      backColor = backgroundColor!;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: expanded ? double.maxFinite : 160,
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          alignment: Alignment.center,
          padding: padding ?? const EdgeInsets.all(16),
          enableFeedback: isEnabled,
          backgroundColor: backColor,
          splashFactory: isEnabled ? InkSplash.splashFactory : NoSplash.splashFactory,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            side: borderColor != null ? BorderSide(color: borderColor!, width: 1) : BorderSide.none,
            borderRadius: BorderRadius.circular(borderRadius ?? 16),
          ),
        ),
        onPressed: () {
          if (isEnabled) {
            HapticFeedback.mediumImpact();
            onTap();
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leftIcon != null)
              Row(
                children: [
                  Icon(
                    leftIcon,
                    color: iconColor ?? textColor,
                    size: 26,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            if (label != '')
              Flexible(
                child: label != null ? Text(
                  label!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ) : labelWidget!,
              ),
            if (rightIcon != null)
              Row(
                children: [
                  if (label != '')
                    const SizedBox(width: 8),
                  Icon(
                    rightIcon,
                    color: iconColor ?? textColor,
                    size: 26,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}