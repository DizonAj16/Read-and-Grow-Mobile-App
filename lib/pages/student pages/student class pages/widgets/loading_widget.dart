import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class LoadingWidget extends StatefulWidget {
  final String currentFunFact;
  final bool isRefreshingFunFact;

  const LoadingWidget({
    Key? key,
    required this.currentFunFact,
    required this.isRefreshingFunFact,
  }) : super(key: key);

  @override
  State<LoadingWidget> createState() => _LoadingWidgetState();
}

class _LoadingWidgetState extends State<LoadingWidget> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: colorScheme.primary.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLoadingAnimation(colorScheme),
              const SizedBox(height: 20),
              _buildLoadingText(colorScheme),
              const SizedBox(height: 20),
              if (widget.currentFunFact.isNotEmpty)
                _buildFunFactSection(colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingAnimation(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.2),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Lottie.asset(
        'assets/animation/loading_class.json',
        width: 160,
        height: 160,
        repeat: true,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildLoadingText(ColorScheme colorScheme) {
    return Text(
      "Getting your classroom ready...",
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: colorScheme.primary,
        fontFamily: 'ComicNeue',
        letterSpacing: 0.5,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildFunFactSection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withOpacity(0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.secondaryContainer,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lightbulb,
                color: colorScheme.secondary,
                size: 20,
              ),
              SizedBox(width: 6),
              Text(
                "Fun Fact!",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.secondary,
                  fontFamily: 'ComicNeue',
                ),
              ),
              if (widget.isRefreshingFunFact)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.secondary,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            widget.currentFunFact,
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: colorScheme.onSecondaryContainer,
              fontFamily: 'ComicNeue',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}