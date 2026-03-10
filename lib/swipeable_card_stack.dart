import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'file_card.dart';
import 'models.dart';

class SwipeableCardStack extends StatefulWidget {
  final List<CategorizedFile> files;
  final Function(CategorizedFile) onSwipeLeft;
  final Function(CategorizedFile) onSwipeRight;

  const SwipeableCardStack({
    Key? key,
    required this.files,
    required this.onSwipeLeft,
    required this.onSwipeRight,
  }) : super(key: key);

  @override
  State<SwipeableCardStack> createState() => SwipeableCardStackState();
}

class SwipeableCardStackState extends State<SwipeableCardStack>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;

  // Configuration for stack
  final double _maxRotationAngle = 20 * (math.pi / 180); // ~20 degrees
  final double _swipeThresholdRatio = 0.25; // 25% of screen width

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));

    _animationController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    if (_animationController.isAnimating) return;
    setState(() {
      _isDragging = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_animationController.isAnimating) return;
    setState(() {
      _dragOffset += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_animationController.isAnimating) return;
    setState(() {
      _isDragging = false;
    });

    final screenWidth = MediaQuery.of(context).size.width;
    final threshold = screenWidth * _swipeThresholdRatio;

    if (_dragOffset.dx.abs() > threshold) {
      // Swipe threshold met, fly off screen
      final isSwipeRight = _dragOffset.dx > 0;
      final endDX = isSwipeRight ? screenWidth * 1.5 : -screenWidth * 1.5;
      final endDY = _dragOffset.dy + (details.velocity.pixelsPerSecond.dy * 0.3); // project y

      final endOffset = Offset(endDX, endDY);

      // Create a tween
      final tween = Tween<Offset>(begin: _dragOffset, end: endOffset);
      final anim = tween.animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ));

      anim.addListener(() {
        if (mounted) {
          setState(() {
            _dragOffset = anim.value;
          });
        }
      });

      _animationController.forward(from: 0.0).then((_) {
        if (mounted) {
          if (Platform.isAndroid) {
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();
          }
          if (isSwipeRight) {
            widget.onSwipeRight(widget.files.first);
          } else {
            widget.onSwipeLeft(widget.files.first);
          }
          // Reset for next card
          setState(() {
            _dragOffset = Offset.zero;
          });
        }
      });
    } else {
      // Snap back to center
      // Create a spring describing the return
      final spring = SpringDescription(
        mass: 1.0,
        stiffness: 500.0,
        damping: 20.0,
      );

      final tween = Tween<Offset>(begin: _dragOffset, end: Offset.zero);
      final anim = tween.animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.elasticOut,
      ));

      anim.addListener(() {
        if (mounted) {
          setState(() {
            _dragOffset = anim.value;
          });
        }
      });

      _animationController.forward(from: 0.0).then((_) {
        if (mounted) {
          setState(() {
            _dragOffset = Offset.zero;
          });
        }
      });
    }
  }

  void swipeLeft({Duration? customDuration}) {
    if (_animationController.isAnimating || widget.files.isEmpty) return;
    _animateProgrammaticSwipe(false, customDuration: customDuration);
  }

  void swipeRight({Duration? customDuration}) {
    if (_animationController.isAnimating || widget.files.isEmpty) return;
    _animateProgrammaticSwipe(true, customDuration: customDuration);
  }

  void _animateProgrammaticSwipe(bool isSwipeRight, {Duration? customDuration}) {
    if (_animationController.isAnimating) return;
    
    setState(() {
      _isDragging = true;
    });

    final screenWidth = MediaQuery.of(context).size.width;
    // We want the programmatic swipe to have the exact same look.
    // That means it needs to travel completely offscreen.
    final endDX = isSwipeRight ? screenWidth * 1.5 : -screenWidth * 1.5;
    // We also give it a slight downward arc similar to a natural thumb swipe
    final endOffset = Offset(endDX, 100);

    final tween = Tween<Offset>(begin: Offset.zero, end: endOffset);
    final anim = tween.animate(CurvedAnimation(
      parent: _animationController,
      // Use the exact same curve as the gesture swipe flying off screen
      curve: Curves.easeOutCubic,
    ));

    anim.addListener(() {
      if (mounted) {
        setState(() {
          _dragOffset = anim.value;
        });
      }
    });

    // Instead of simply forward(), we can set the duration temporarily
    final previousDuration = _animationController.duration;
    if (customDuration != null) {
      _animationController.duration = customDuration;
    }

    _animationController.forward(from: 0.0).then((_) {
      if (customDuration != null) {
        _animationController.duration = previousDuration; // restore
      }
      if (mounted) {
        if (Platform.isAndroid) {
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
        }
        if (isSwipeRight) {
          widget.onSwipeRight(widget.files.first);
        } else {
          widget.onSwipeLeft(widget.files.first);
        }
        setState(() {
          _dragOffset = Offset.zero;
          _isDragging = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;

    // Determine current offset based on drag or animation
    Offset currentOffset = _dragOffset;

    final double pullRatio =
        (currentOffset.dx.abs() / (screenWidth * _swipeThresholdRatio))
            .clamp(0.0, 1.0);

    // Calculate background card properties (scale from 0.9 to 1.0, fade from 0.7 to 1.0)
    final double bgScale = 0.9 + (0.1 * pullRatio);
    final double bgOpacity = 0.7 + (0.3 * pullRatio);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Background Card
        if (widget.files.length > 1)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Opacity(
                opacity: bgOpacity,
                child: Transform.scale(
                  scale: bgScale,
                  child: FileCard(
                    key: ValueKey(widget.files[1].documentUri?.toString() ?? widget.files[1].path),
                    file: widget.files[1],
                    overlayBuilder: null, // No overlay for bg card
                    isCurrent: false,
                  ),
                ),
              ),
            ),
          ),

        // Foreground Card
        Positioned.fill(
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: Transform.translate(
              offset: currentOffset,
              child: Transform.rotate(
                angle: (currentOffset.dx / screenWidth) * _maxRotationAngle,
                child: FileCard(
                  key: ValueKey(widget.files.first.documentUri?.toString() ?? widget.files.first.path),
                  file: widget.files.first,
                  isCurrent: true,
                  // Render gradient overlay on the foreground card
                  overlayBuilder: (context) {
                    final double greenOpacity =
                        currentOffset.dx < 0 ? pullRatio * 0.6 : 0.0;
                    final double redOpacity =
                        currentOffset.dx > 0 ? pullRatio * 0.6 : 0.0;

                    if (greenOpacity == 0 && redOpacity == 0) {
                      return const SizedBox.shrink();
                    }

                    final Color overlayColor = greenOpacity > 0
                        ? const Color(0xFF2ecc71)
                        : Colors.redAccent;
                    final double opacity = math.max(greenOpacity, redOpacity);
                    final Alignment beginAlignment = greenOpacity > 0
                        ? Alignment.centerLeft
                        : Alignment.centerRight;
                    final Alignment endAlignment = greenOpacity > 0
                        ? Alignment.centerRight
                        : Alignment.centerLeft;

                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        gradient: LinearGradient(
                          begin: beginAlignment,
                          end: endAlignment,
                          colors: [
                            overlayColor.withValues(alpha: opacity),
                            overlayColor.withValues(alpha: opacity * 0.5),
                            overlayColor.withValues(alpha: 0.0),
                          ],
                          stops: const [0.0, 0.4, 1.0],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

