import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RouteLoadingOverlay extends StatefulWidget {
  final String message;
  const RouteLoadingOverlay({super.key, this.message = 'Analyzing routes and pollution levels...'});

  @override
  State<RouteLoadingOverlay> createState() => _RouteLoadingOverlayState();
}

class _RouteLoadingOverlayState extends State<RouteLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )
      ..repeat(reverse: true); // Simulates calculation progress

    _progressAnimation = Tween<double>(begin: 0.1, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE8F5E9), // Light green top
              Color(0xFFA5D6A7),
              Color(0xFF66BB6A), // Deeper green bottom
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(context),
              const Expanded(flex: 1, child: SizedBox()),
              _buildMainCard(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'AeroNav',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A7A4A),
            ),
          ),
          InkWell(
            onTap: () => context.push('/profile'),
            child: CircleAvatar(
              backgroundColor: Colors.white.withOpacity(0.5),
              radius: 20,
              child: const Icon(Icons.person_outline, color: Color(0xFF1A7A4A)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMainCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Large Icon Circle
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              color: Color(0xFF00BFA5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.air, size: 50, color: Colors.white),
          ),
          const SizedBox(height: 24),
          const Text(
            'AeroNav',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A7A4A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          // Subcards Row
          Row(
            spacing: 16,
            children: [
              Expanded(child: _buildSubCard('AIR QUALITY', Icons.eco, 0.8)),
              Expanded(child: _buildSubCard('OPTIMAL PATH', Icons.route, 0.5)),
            ],
          ),
          const SizedBox(height: 48),
          // Flow Progress
          const Column(
            children: [
              SizedBox(
                height: 64,
                width: 64,
                child: CircularProgressIndicator(
                  backgroundColor: Color(0xFFE8F5E9),
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
                  strokeWidth: 6,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'CALCULATING FLOW',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A7A4A),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubCard(String title, IconData icon, double progress) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8F5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF1A7A4A)),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF00BFA5)),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}
