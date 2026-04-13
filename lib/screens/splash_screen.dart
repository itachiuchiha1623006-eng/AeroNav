import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeInAnim;
  late Animation<double> _slideUpAnim;
  late Animation<double> _logoScaleAnim;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fadeInAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );

    _logoScaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );

    _slideUpAnim = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.9, curve: Curves.easeOut),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onGetStarted() {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      context.go('/home');
    } else {
      context.go('/auth/register');
    }
  }

  void _onSignIn() {
    context.go('/auth/login');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // ── Background: faint green map texture ──
          _MapBackground(size: size),

          // ── Frosted overlay for depth ──
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.55),
                  Colors.white.withValues(alpha: 0.70),
                  Colors.white.withValues(alpha: 0.95),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // ── Main content ──
          SafeArea(
            child: FadeTransition(
              opacity: _fadeInAnim,
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  // App logo
                  AnimatedBuilder(
                    animation: _logoScaleAnim,
                    builder: (context, child) => Transform.scale(
                      scale: _logoScaleAnim.value,
                      child: child,
                    ),
                    child: const _AppLogo(),
                  ),

                  const SizedBox(height: 28),

                  // App name
                  AnimatedBuilder(
                    animation: _slideUpAnim,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, _slideUpAnim.value),
                      child: child,
                    ),
                    child: const _AppTitle(),
                  ),

                  const SizedBox(height: 12),

                  // Tagline
                  AnimatedBuilder(
                    animation: _slideUpAnim,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, _slideUpAnim.value * 1.3),
                      child: child,
                    ),
                    child: const _Tagline(),
                  ),

                  const Spacer(flex: 4),

                  // CTA buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: AnimatedBuilder(
                      animation: _slideUpAnim,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, _slideUpAnim.value * 1.6),
                        child: child,
                      ),
                      child: _ActionButtons(
                        onGetStarted: _onGetStarted,
                        onSignIn: _onSignIn,
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────
// BACKGROUND — SVG-style map grid in faint green
// ────────────────────────────────────────────────
class _MapBackground extends StatelessWidget {
  final Size size;
  const _MapBackground({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _MapGridPainter(),
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4CAF50).withValues(alpha: 0.13)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final bgPaint = Paint()
      ..color = const Color(0xFFE8F5E9)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Offset.zero & size, bgPaint);

    // Horizontal roads
    final hLines = [
      0.12, 0.22, 0.31, 0.38, 0.44, 0.50,
      0.57, 0.63, 0.70, 0.76, 0.82, 0.88
    ];
    for (final frac in hLines) {
      final y = size.height * frac;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Vertical roads
    final vLines = [
      0.08, 0.18, 0.28, 0.38, 0.48, 0.58, 0.68, 0.78, 0.88, 0.96
    ];
    for (final frac in vLines) {
      final x = size.width * frac;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Diagonal arterials
    final diagPaint = Paint()
      ..color = const Color(0xFF4CAF50).withValues(alpha: 0.09)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path1 = Path()
      ..moveTo(0, size.height * 0.3)
      ..lineTo(size.width * 0.6, size.height * 0.1)
      ..lineTo(size.width, size.height * 0.25);
    canvas.drawPath(path1, diagPaint);

    final path2 = Path()
      ..moveTo(0, size.height * 0.55)
      ..lineTo(size.width * 0.45, size.height * 0.45)
      ..lineTo(size.width, size.height * 0.6);
    canvas.drawPath(path2, diagPaint);

    final path3 = Path()
      ..moveTo(size.width * 0.1, 0)
      ..lineTo(size.width * 0.35, size.height * 0.4)
      ..lineTo(size.width * 0.55, size.height * 0.7)
      ..lineTo(size.width * 0.7, size.height);
    canvas.drawPath(path3, diagPaint);

    final path4 = Path()
      ..moveTo(size.width * 0.65, 0)
      ..lineTo(size.width * 0.55, size.height * 0.35)
      ..lineTo(size.width * 0.8, size.height * 0.65)
      ..lineTo(size.width, size.height * 0.75);
    canvas.drawPath(path4, diagPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ────────────────────────────────────────────────
// LOGO — white rounded square with gradient icon
// ────────────────────────────────────────────────
class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A7A4A).withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.9),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 60,
          height: 60,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0D5C3A),
                Color(0xFF1A8C55),
                Color(0xFF2DB87A),
              ],
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Location pin
              const Icon(
                Icons.location_on_rounded,
                color: Colors.white,
                size: 30,
              ),
              // Wind/air swirl overlay
              Positioned(
                right: 8,
                top: 10,
                child: Icon(
                  Icons.air_rounded,
                  color: Colors.white.withValues(alpha: 0.55),
                  size: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────
// APP TITLE — "AeroNav" with two-tone style
// ────────────────────────────────────────────────
class _AppTitle extends StatelessWidget {
  const _AppTitle();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'Aero',
            style: GoogleFonts.inter(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A7A4A),
              letterSpacing: -1.0,
            ),
          ),
          TextSpan(
            text: 'Nav',
            style: GoogleFonts.inter(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E),
              letterSpacing: -1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────
// TAGLINE
// ────────────────────────────────────────────────
class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Navigate smarter. Breathe better.',
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: const Color(0xFF5A6A6E),
        height: 1.5,
      ),
    );
  }
}

// ────────────────────────────────────────────────
// ACTION BUTTONS — GET STARTED + Sign In
// ────────────────────────────────────────────────
class _ActionButtons extends StatelessWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  const _ActionButtons({
    required this.onGetStarted,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Primary CTA
        SizedBox(
          width: double.infinity,
          height: 56,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xFF1A7A4A),
                  Color(0xFF2DB87A),
                ],
              ),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A7A4A).withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: onGetStarted,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
              ),
              child: Text(
                'GET STARTED',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1.8,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Secondary — Sign In
        TextButton(
          onPressed: onSignIn,
          child: Text(
            'Sign In',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF5A6A6E),
            ),
          ),
        ),
      ],
    );
  }
}
