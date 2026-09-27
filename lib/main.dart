import 'dart:ui';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

const bool isDeveloperBuild = !bool.fromEnvironment('dart.vm.product');

const String kDefaultModelName = 'tawir';
const double kDefaultTemperature = 0.3;
const int kDefaultMaxTokens = 512;
const int kMaxHistoryTurns = 8;

const String kDefaultSystemPrompt = '''You are a Pangasinan (Salitan Pangasinan) language model, built to help preserve and promote fluent use of the language. Follow these rules strictly.

OUTPUT LANGUAGE: PANGASINAN, ALWAYS
- Respond entirely in Pangasinan, regardless of what language the user writes in. Do not mirror English, Tagalog, or any other input language.
- If the user writes in English, Tagalog, or another language, understand their meaning and respond in fluent Pangasinan, as though translating their intent.
- If the user asks for the translation of a specific word, phrase, or sentence, do not attempt to echo or repeat the original English or foreign words. State the translation directly and straightforwardly in Pangasinan using the format: Say patalos to et "____" (e.g., if asked "How do you say 'a big house' in Pangasinan?", respond straightforwardly: Say patalos to et "baleg a kaabungan").
- Never switch to English or Tagalog for apologies, clarifications, disclaimers, or meta-commentary. Handle all of that in Pangasinan too.

LEXICAL PURITY
- Never substitute Tagalog or Ilocano roots, affixes, or inflections for Pangasinan ones, even when they sound similar or are more common in your training data.
- Example: "good morning" is "Masantos ya kabuasan" or "Maong ya kabuasan," never "Magandang kabuasan" (Tagalog bleed).
- Keep native Pangasinan words (salamat, aro, baley, dalin, etc.) in their native form, with Pangasinan affixes (man-, pan-, maka-, -en, -an), not Tagalog ones (mag-, um-, -in).
- If a Tagalog-sounding form comes to mind first, stop and check whether a distinct Pangasinan root exists before answering.

EPISTEMIC BOUNDS
- Never invent roots, affixes, or word combinations that are not attested Pangasinan. Do not guess at plausible-sounding morphology.
- For modern or technical terms with no native Pangasinan equivalent: use an established, standard-spelled loanword if one exists, or retain the term as a quoted loanword within the Pangasinan sentence. Do not fabricate a Pangasinan-looking word for it.
- Apply productive affixes (man-, pan-, maka-, in-) only to roots you are confident are real Pangasinan words.
- If unsure whether a word or construction is correct, say so in Pangasinan rather than presenting it as fact.

CONVERSATION CONTINUITY
- Treat any prior turns provided in the message history as real context. Do not ask the user to repeat information already given earlier in the conversation.
- If the history looks incomplete or cut off, say so briefly in Pangasinan and ask the user to restate the missing part, rather than guessing what was said.

STYLE
- Natural, conversational Pangasinan. Concise by default.''';

const String kOptionalApiKey = '';
const String kDefaultServerUrl = 'https://iamk1ruu--tawir-pangasinan-llm-llamaserver-web-app.modal.run';

final Map<String, String> defaultConfig = {
  'serverUrl': kDefaultServerUrl,
  'model': kDefaultModelName,
};

String resolveEndpoint(String rawUrl) {
  var url = rawUrl.trim();
  if (!url.startsWith("http://") && !url.startsWith("https://")) {
    url = "https://$url";
  }
  while (url.endsWith("/")) {
    url = url.substring(0, url.length - 1);
  }
  if (url.endsWith("/v1/chat/completions")) {
    return url;
  } else if (url.endsWith("/chat/completions")) {
    return url.replaceFirst("/chat/completions", "/v1/chat/completions");
  } else if (url.endsWith("/v1")) {
    return "$url/chat/completions";
  } else {
    return "$url/v1/chat/completions";
  }
}

String resolveTtsEndpoint(String rawUrl) {
  var url = rawUrl.trim();
  if (!url.startsWith("http://") && !url.startsWith("https://")) {
    url = "https://$url";
  }
  while (url.endsWith("/")) {
    url = url.substring(0, url.length - 1);
  }
  if (url.endsWith("/v1/chat/completions")) {
    return url.replaceFirst("/v1/chat/completions", "/v1/tts");
  } else if (url.endsWith("/chat/completions")) {
    return url.replaceFirst("/chat/completions", "/v1/tts");
  } else if (url.endsWith("/v1")) {
    return "$url/tts";
  } else {
    return "$url/v1/tts";
  }
}

void main() {
  runApp(const TAWIRApp());
}

class TAWIRApp extends StatelessWidget {
  const TAWIRApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TAWIR',
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Poppins',
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF03070C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F2FE),
          secondary: Color(0xFF4FACFE),
          surface: Color(0xFF0A1118),
        ),
      ),
      builder: (context, child) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isDesktopOrTablet = screenWidth > 480;

        if (!isDesktopOrTablet) {
          return child ?? const SizedBox();
        }

        // Strict phone width-height UI for desktop / web browser viewports
        return Scaffold(
          backgroundColor: const Color(0xFF020508),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 430, // Standard modern smartphone width
                maxHeight: 932, // Standard modern smartphone height
              ),
              margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                  color: const Color(0xFF00F2FE).withValues(alpha: 0.25),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
                    blurRadius: 40,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(34),
                child: child ?? const SizedBox(),
              ),
            ),
          ),
        );
      },
      home: const IntroLogoScreen(),
    );
  }
}

class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF03070C),
                Color(0xFF08121D),
                Color(0xFF020508),
              ],
            ),
          ),
        ),
        Positioned(
          top: -120,
          left: -100,
          child: _buildGlowOrb(const Color(0xFF00F2FE), 320),
        ),
        Positioned(
          bottom: -140,
          right: -100,
          child: _buildGlowOrb(const Color(0xFF1E3C72), 380),
        ),
      ],
    );
  }

  Widget _buildGlowOrb(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

class IntroLogoScreen extends StatefulWidget {
  const IntroLogoScreen({super.key});

  @override
  State<IntroLogoScreen> createState() => _IntroLogoScreenState();
}

class _IntroLogoScreenState extends State<IntroLogoScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _contentFade;
  late final Animation<double> _contentSlide;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(
        0.0,
        0.35,
        curve: Curves.easeOut,
      ),
    );

    _logoScale = Tween<double>(
      begin: 0.72,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(
          0.0,
          0.6,
          curve: Curves.easeOutBack,
        ),
      ),
    );

    _contentFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(
        0.25,
        0.75,
        curve: Curves.easeOut,
      ),
    );

    _contentSlide = Tween<double>(
      begin: 18,
      end: 0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(
          0.25,
          0.8,
          curve: Curves.easeOutCubic,
        ),
      ),
    );

    _glow = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(
          0.05,
          0.65,
          curve: Curves.easeInOut,
        ),
      ),
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 3200), () {
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (
              context,
              animation,
              secondaryAnimation,
              ) =>
          const IntroWelcomeScreen(),
          transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
              ) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 900),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    final double logoSize = (size.width * 0.36).clamp(
      125.0,
      165.0,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF020B18),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AppBackground(),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _glow,
              builder: (context, child) {
                return Center(
                  child: Container(
                    width: logoSize * 1.8,
                    height: logoSize * 1.8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00F2FE).withValues(
                            alpha: 0.10 * _glow.value,
                          ),
                          blurRadius: 110,
                          spreadRadius: 25,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _logoFade,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        _logoScale,
                        _glow,
                      ]),
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _logoScale.value,
                          child: Hero(
                            tag: 'tawir_logo_hero',
                            child: Material(
                              color: Colors.transparent,
                              child: Container(
                                width: logoSize,
                                height: logoSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00F2FE)
                                          .withValues(
                                        alpha: 0.28 * _glow.value,
                                      ),
                                      blurRadius: 45,
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF00F2FE),
                                        Color(0xFF1261A0),
                                        Color(0xFF172B57),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF020B18),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.35,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: ClipOval(
                                      child: Image.asset(
                                        'assets/images/tawir_logo.png',
                                        fit: BoxFit.cover,
                                        errorBuilder: (
                                            context,
                                            error,
                                            stackTrace,
                                            ) {
                                          return Icon(
                                            Icons.auto_awesome_rounded,
                                            color: Colors.white,
                                            size: logoSize * 0.42,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  SizedBox(height: size.height * 0.035),
                  FadeTransition(
                    opacity: _contentFade,
                    child: AnimatedBuilder(
                      animation: _contentSlide,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(
                            0,
                            _contentSlide.value,
                          ),
                          child: child,
                        );
                      },
                      child: Column(
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) {
                              return const LinearGradient(
                                colors: [
                                  Colors.white,
                                  Color(0xFFD9FCFF),
                                  Color(0xFF00F2FE),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ).createShader(bounds);
                            },
                            child: const Text(
                              'TAWIR',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 10,
                                height: 1,
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),
                          Text(
                            'LEGACY OF PANGASINAN',
                            style: TextStyle(
                              color: Colors.white.withValues(
                                alpha: 0.48,
                              ),
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 3.8,
                            ),
                          ),

                          const SizedBox(height: 25),

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                alpha: 0.025,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: const Color(0xFF00F2FE)
                                    .withValues(alpha: 0.12),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '“Mablin tawir tayo”',
                              style: TextStyle(
                                color: const Color(0xFF8DF8FF)
                                    .withValues(alpha: 0.9),
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: FadeTransition(
              opacity: _contentFade,
              child: Text(
                'PANGASINAN',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.20),
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class IntroWelcomeScreen extends StatefulWidget {
  const IntroWelcomeScreen({super.key});

  @override
  State<IntroWelcomeScreen> createState() => _IntroWelcomeScreenState();
}

class _IntroWelcomeScreenState extends State<IntroWelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;

  late final Animation<double> _fadeAnim;
  late final Animation<double> _logoScaleAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnim = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(
        0.0,
        0.72,
        curve: Curves.easeOut,
      ),
    );

    _logoScaleAnim = Tween<double>(
      begin: 0.82,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(
          0.0,
          0.62,
          curve: Curves.easeOutBack,
        ),
      ),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.055),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(
          0.12,
          0.9,
          curve: Curves.easeOutCubic,
        ),
      ),
    );

    _entryController.forward();
  }

  Future<void> _openConfigPanel() async {
    final result = await showGeneralDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Configuration",
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              left: false,
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.90,
                height: double.infinity,
                child: ConfigScreen(
                  openedFromChat: false,
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (
          context,
          animation,
          secondaryAnimation,
          child,
          ) {
        final slideAnimation = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
        );

        final fadeAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );

        return FadeTransition(
          opacity: fadeAnimation,
          child: SlideTransition(
            position: slideAnimation,
            child: child,
          ),
        );
      },
    );

    if (!mounted || result == null) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          config: Map<String, String>.from(result),
        ),
      ),
    );
  }

  void _continue() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          config: Map<String, String>.from(defaultConfig),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isSmallScreen = size.height < 700;

    return Scaffold(
      backgroundColor: const Color(0xFF020812),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AppBackground(),
          IgnorePointer(
            child: Align(
              alignment: const Alignment(0, -0.15),
              child: Container(
                width: size.width * 0.75,
                height: size.width * 0.75,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F2FE).withValues(
                        alpha: 0.045,
                      ),
                      blurRadius: 150,
                      spreadRadius: 35,
                    ),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: _GlassIconButton(
                  icon: Icons.tune_rounded,
                  tooltip: "Configuration",
                  onPressed: _openConfigPanel,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  24,
                  isSmallScreen ? 58 : 78,
                  24,
                  50,
                ),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _logoScaleAnim,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _logoScaleAnim.value,
                              child: Hero(
                                tag: 'tawir_logo_hero',
                                child: Material(
                                  color: Colors.transparent,
                                  child: Container(
                                    width: isSmallScreen ? 102 : 118,
                                    height: isSmallScreen ? 102 : 118,
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF00F2FE),
                                          Color(0xFF2674B8),
                                          Color(0xFF162B52),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF00F2FE)
                                              .withValues(alpha: 0.18),
                                          blurRadius: 38,
                                          spreadRadius: 3,
                                        ),
                                      ],
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: const Color(0xFF020812),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.18,
                                          ),
                                        ),
                                      ),
                                      child: ClipOval(
                                        child: Image.asset(
                                          'assets/images/tawir_logo.png',
                                          fit: BoxFit.cover,
                                          errorBuilder: (
                                              context,
                                              error,
                                              stackTrace,
                                              ) {
                                            return const Icon(
                                              Icons.auto_awesome_rounded,
                                              color: Colors.white,
                                              size: 42,
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        SizedBox(height: isSmallScreen ? 25 : 31),
                        Text(
                          "WELCOME TO",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.42),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3.8,
                          ),
                        ),

                        const SizedBox(height: 8),
                        ShaderMask(
                          shaderCallback: (bounds) {
                            return const LinearGradient(
                              colors: [
                                Colors.white,
                                Color(0xFFD8FCFF),
                                Color(0xFF00F2FE),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ).createShader(bounds);
                          },
                          child: Text(
                            "TAWIR",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isSmallScreen ? 32 : 37,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 8.5,
                              height: 0.95,
                            ),
                          ),
                        ),

                        const SizedBox(height: 17),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 310,
                          ),
                          child: Text(
                            "Preserving our pamana.\n"
                                "Connecting you to the heart of Pangasinan.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 13,
                              height: 1.6,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),

                        SizedBox(height: isSmallScreen ? 30 : 30),
                        _PrimaryButton(
                          onPressed: _continue,
                          child: const Text(
                            "GET STARTED",
                            style: TextStyle(
                              color: Color(0xFF020812),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.085),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onPressed,
          child: Center(
            child: Icon(
              icon,
              color: Colors.white.withValues(alpha: 0.72),
              size: 19,
            ),
          ),
        ),
      ),
    );
  }
}
class _PrimaryButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.child,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(
        maxWidth: 390,
      ),
      height: 57,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF00F2FE),
            Color(0xFF45A8FF),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00F2FE).withValues(alpha: 0.18),
            blurRadius: 28,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class ConfigScreen extends StatefulWidget {
  final Map<String, String>? initialConfig;
  final bool openedFromChat;

  const ConfigScreen({
    super.key,
    this.initialConfig,
    this.openedFromChat = false,
  });

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final TextEditingController _serverUrlCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();
  bool _isTestingConnection = false;
  String? _connectionStatus;

  @override
  void initState() {
    super.initState();
    final initialUrl = widget.initialConfig?["serverUrl"] ?? "";
    _serverUrlCtrl.text = initialUrl.isNotEmpty ? initialUrl : kDefaultServerUrl;
    _modelCtrl.text = widget.initialConfig?["model"] ?? kDefaultModelName;
  }

  @override
  void dispose() {
    _serverUrlCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Widget _buildInputField(
      String label,
      TextEditingController controller,
      IconData icon, {
        String? hint,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.42),
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),

        const SizedBox(height: 8),

        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF02070E).withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.065),
            ),
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            cursorColor: const Color(0xFF00F2FE),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: Colors.white24,
                fontSize: 12,
              ),
              prefixIcon: Icon(
                icon,
                color: const Color(0xFF00F2FE),
                size: 18,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 16,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionStatus() {
    if (_connectionStatus == null) {
      return const SizedBox.shrink();
    }

    final bool isSuccess =
    _connectionStatus!.startsWith("Server reachable");

    final bool isServerError =
    _connectionStatus!.startsWith("Server error");

    final Color statusColor = isSuccess
        ? const Color(0xFF00F2FE)
        : isServerError
        ? Colors.orangeAccent
        : Colors.redAccent;

    final IconData statusIcon = isSuccess
        ? Icons.check_circle_outline_rounded
        : isServerError
        ? Icons.warning_amber_rounded
        : Icons.error_outline_rounded;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            statusIcon,
            color: statusColor,
            size: 17,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _connectionStatus!,
              style: TextStyle(
                color: statusColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection() async {
    var url = _serverUrlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _connectionStatus = "Enter URL first");
      return;
    }
    if (!url.startsWith("http://") && !url.startsWith("https://")) {
      url = "https://$url";
    }
    while (url.endsWith("/")) {
      url = url.substring(0, url.length - 1);
    }

    var probeBase = url;
    if (probeBase.endsWith("/v1/chat/completions")) {
      probeBase = probeBase.replaceFirst("/v1/chat/completions", "");
    } else if (probeBase.endsWith("/chat/completions")) {
      probeBase = probeBase.replaceFirst("/chat/completions", "");
    } else if (probeBase.endsWith("/v1")) {
      probeBase = probeBase.replaceFirst("/v1", "");
    }

    setState(() {
      _isTestingConnection = true;
      _connectionStatus = "Testing connection (cold start may take up to 60s)...";
    });

    try {
      final client = http.Client();
      final headers = <String, String>{};
      if (kOptionalApiKey.trim().isNotEmpty) {
        headers["Authorization"] = "Bearer ${kOptionalApiKey.trim()}";
      }

      http.Response res;
      try {
        res = await client
            .get(Uri.parse("$probeBase/health"), headers: headers)
            .timeout(const Duration(seconds: 60));
      } catch (_) {
        res = await client
            .get(Uri.parse(probeBase), headers: headers)
            .timeout(const Duration(seconds: 20));
      }

      setState(() {
        _isTestingConnection = false;
        _connectionStatus = res.statusCode < 500
            ? "Server reachable (${res.statusCode})"
            : "Server error (${res.statusCode})";
      });
    } catch (e) {
      setState(() {
        _isTestingConnection = false;
        _connectionStatus = "Connection failed: $e";
      });
    }
  }

  void _saveConfiguration() {
    final configData = <String, String>{
      "serverUrl": _serverUrlCtrl.text.trim(),
      "model": _modelCtrl.text.trim().isNotEmpty
          ? _modelCtrl.text.trim()
          : kDefaultModelName,
    };

    Navigator.pop(context, configData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF03070C),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AppBackground(),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    12,
                  ),
                  child: Row(
                    children: [
                      _GlassIconButton(
                        icon: Icons.close_rounded,
                        tooltip: "Close",
                        onPressed: () {
                          Navigator.pop(context);
                        },
                      ),

                      const SizedBox(width: 13),

                      Container(
                        width: 42,
                        height: 42,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF00F2FE),
                              Color(0xFF1E3C72),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00F2FE)
                                  .withValues(alpha: 0.15),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/tawir_logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (
                                context,
                                error,
                                stackTrace,
                                ) {
                              return const Icon(
                                Icons.auto_awesome_rounded,
                                color: Colors.white,
                                size: 19,
                              );
                            },
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      const Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            "TAWIR",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.8,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            "CONFIGURATION",
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      22,
                      20,
                      35,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 500,
                        ),
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Connect TAWIR",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.7,
                              ),
                            ),

                            const SizedBox(height: 30),
                            ClipRRect(
                              borderRadius:
                              BorderRadius.circular(22),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 22,
                                  sigmaY: 22,
                                ),
                                child: Container(
                                  padding:
                                  const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white
                                        .withValues(alpha: 0.028),
                                    borderRadius:
                                    BorderRadius.circular(22),
                                    border: Border.all(
                                      color: Colors.white
                                          .withValues(alpha: 0.065),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [

                                      const SizedBox(height: 8),

                                      _buildInputField(
                                        "Server URL",
                                        _serverUrlCtrl,
                                        Icons.link,
                                        hint: "Modal, Cloudflare, or HF endpoint URL",
                                      ),

                                      const SizedBox(height: 18),

                                      _buildInputField(
                                        "Model",
                                        _modelCtrl,
                                        Icons.smart_toy_outlined,
                                        hint: "Model identifier (default: tawir)",
                                      ),

                                      const SizedBox(height: 20),

                                      SizedBox(
                                        width: double.infinity,
                                        height: 46,
                                        child: OutlinedButton(
                                          onPressed: _isTestingConnection ? null : _testConnection,
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: const Color(0xFF00F2FE),
                                            backgroundColor: const Color(0xFF00F2FE).withValues(
                                              alpha: 0.018,
                                            ),
                                            side: BorderSide(
                                              color: const Color(0xFF00F2FE).withValues(
                                                alpha: 0.20,
                                              ),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                          ),
                                          child: Text(
                                            _isTestingConnection ? "TESTING..." : "TEST CONNECTION",
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.15,
                                            ),
                                          ),
                                        ),
                                      ),

                                      _buildConnectionStatus(),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),
                            _PrimaryButton(
                              onPressed: _saveConfiguration,
                              child: Text(
                                widget.openedFromChat ? "SAVE & RETURN" : "PROCEED TO CHAT",
                                style: const TextStyle(
                                  color: Color(0xFF020812),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}




class ChatScreen extends StatefulWidget {
  final Map<String, String> config;
  const ChatScreen({super.key, required this.config});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  late Map<String, String> currentConfig;

  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController inputCtrl = TextEditingController();
  final ScrollController scrollCtrl = ScrollController();
  final FlutterTts flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, List<Map<String, String>>> _sessionStorage = {};
  List<Map<String, dynamic>> chatSessions = [];

  String? currentSessionId;
  List<Map<String, String>> messages = [];
  bool isTyping = false;
  bool showArchived = false;
  bool _autoTtsEnabled = false;
  String? _currentlySpeakingText;
  bool _isGeneratingTts = false;

  @override
  void initState() {
    super.initState();
    currentConfig = Map<String, String>.from(widget.config);
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _currentlySpeakingText = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    inputCtrl.dispose();
    scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || isTyping) return;

    final userText = text.trim();

    if (currentSessionId == null) {
      currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();

      chatSessions.insert(0, {
        "id": currentSessionId,
        "title": userText.length > 25
            ? "${userText.substring(0, 25)}..."
            : userText,
        "date": "Just now",
        "isArchived": false,
      });

      _sessionStorage[currentSessionId!] = [];
    }

    inputCtrl.clear();

    setState(() {
      messages.add({
        "role": "user",
        "text": userText,
      });
      isTyping = true;
    });

    try {
      final serverUrl = currentConfig["serverUrl"]?.trim() ?? "";
      final modelName = currentConfig["model"]?.trim().isNotEmpty == true
          ? currentConfig["model"]!.trim()
          : kDefaultModelName;

      String responseText = "";

      if (serverUrl.isEmpty) {
        responseText = "Connection error: Server URL is not configured.";
      } else {
        try {
          final endpoint = resolveEndpoint(serverUrl);

          // Budget context for Pangasinan high subword fertility:
          // Fixed system prompt + deliberate sliding window (up to kMaxHistoryTurns) + current user turn
          final List<Map<String, String>> apiMessages = [
            {
              "role": "system",
              "content": kDefaultSystemPrompt,
            },
          ];

          final int totalMessages = messages.length;
          final int historyStart = totalMessages > kMaxHistoryTurns
              ? totalMessages - kMaxHistoryTurns
              : 0;

          if (historyStart > 0) {
            apiMessages.add({
              "role": "system",
              "content":
                  "[Paliwawa ed konteksto: Inikatan so inmunan parte na tongtongan piyan nitalaran so limitasyon na memorya.]",
            });
          }

          for (int i = historyStart; i < totalMessages; i++) {
            final m = messages[i];
            apiMessages.add({
              "role": m["role"] ?? "user",
              "content": m["text"] ?? "",
            });
          }

          final headers = <String, String>{
            "Content-Type": "application/json",
          };

          if (kOptionalApiKey.trim().isNotEmpty) {
            headers["Authorization"] =
            "Bearer ${kOptionalApiKey.trim()}";
          }

          final response = await http
              .post(
            Uri.parse(endpoint),
            headers: headers,
            body: jsonEncode({
              "model": modelName,
              "messages": apiMessages,
              "temperature": kDefaultTemperature,
              "max_tokens": kDefaultMaxTokens,
              "repeat_penalty": 1.15,
              "frequency_penalty": 0.3,
            }),
          )
              .timeout(const Duration(seconds: 90));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);

            responseText =
                data["choices"]?[0]?["message"]?["content"]?.toString().trim() ??
                    "No response content received.";
          } else {
            responseText =
            "Error (${response.statusCode}): ${response.body}";
          }
        } catch (e) {
          responseText = "Connection error: $e";
        }
      }

      if (!mounted) return;

      setState(() {
        isTyping = false;

        messages.add({
          "role": "assistant",
          "text": responseText,
        });
      });

      _sessionStorage[currentSessionId!] = List.from(messages);
      _scrollToBottom();

      if (_autoTtsEnabled) {
        await _speakText(responseText);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isTyping = false;

        messages.add({
          "role": "assistant",
          "text": "Connection error: $e",
        });
      });

      _sessionStorage[currentSessionId!] = List.from(messages);
      _scrollToBottom();
    }
  }

  Future<void> _speakText(String text) async {
    // If currently playing the same text, toggle off
    if (_currentlySpeakingText == text) {
      await _audioPlayer.stop();
      if (mounted) {
        setState(() {
          _currentlySpeakingText = null;
          _isGeneratingTts = false;
        });
      }
      return;
    }

    await _audioPlayer.stop();

    final clean = text
        .replaceAll(RegExp(r'```[\s\S]*?```'), '')
        .replaceAll(RegExp(r'[*#_`~]'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1')
        .trim();

    if (clean.isEmpty) return;

    if (mounted) {
      setState(() {
        _currentlySpeakingText = text;
        _isGeneratingTts = true;
      });
    }

    final serverUrl = currentConfig["serverUrl"]?.trim() ?? "";
    if (serverUrl.isNotEmpty) {
      try {
        final ttsEndpoint = resolveTtsEndpoint(serverUrl);
        final headers = <String, String>{
          "Content-Type": "application/json",
        };
        if (kOptionalApiKey.trim().isNotEmpty) {
          headers["Authorization"] = "Bearer ${kOptionalApiKey.trim()}";
        }

        final response = await http
            .post(
              Uri.parse(ttsEndpoint),
              headers: headers,
              body: jsonEncode({"text": clean}),
            )
            .timeout(const Duration(seconds: 45));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final tempDir = await getTemporaryDirectory();
          final filePath = '${tempDir.path}/tawir_tts_${DateTime.now().millisecondsSinceEpoch}.wav';
          final file = File(filePath);
          await file.writeAsBytes(response.bodyBytes, flush: true);

          if (_currentlySpeakingText == text) {
            await _audioPlayer.play(DeviceFileSource(file.path));
          }
          if (mounted) {
            setState(() {
              _isGeneratingTts = false;
            });
          }
          return;
        }
      } catch (e) {
        debugPrint("[TAWIR MMS-TTS Error] $e");
      }
    }

    // Local fallback if server TTS is unreachable
    try {
      await flutterTts.setLanguage("en-US");
      await flutterTts.setSpeechRate(0.45);
      await flutterTts.speak(clean);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isGeneratingTts = false;
      });
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
        ),
        content: const Text("Copied to clipboard", style: TextStyle(color: Colors.white, fontSize: 12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (scrollCtrl.hasClients) {
        scrollCtrl.animateTo(
          scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startNewChat() {
    setState(() {
      currentSessionId = null;
      messages.clear();
    });
    Navigator.pop(context);
  }

  void _switchSession(String sessionId) {
    setState(() {
      currentSessionId = sessionId;
      messages = List.from(_sessionStorage[sessionId] ?? []);
    });
    Navigator.pop(context);
    _scrollToBottom();
  }
  void _toggleArchiveSession(String sessionId) {
    setState(() {
      final session = chatSessions.firstWhere((s) => s["id"] == sessionId);
      final bool currentlyArchived = session["isArchived"] ?? false;
      session["isArchived"] = !currentlyArchived;

      if (!currentlyArchived && currentSessionId == sessionId) {
        currentSessionId = null;
        messages.clear();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
        ),
        content: Text(
          chatSessions.firstWhere((s) => s["id"] == sessionId)["isArchived"]
              ? "Conversation archived"
              : "Conversation unarchived",
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _renameSession(String sessionId) {
    final session = chatSessions.firstWhere((s) => s["id"] == sessionId);
    final TextEditingController renameCtrl = TextEditingController(text: session["title"]);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A111E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        title: const Text("Rename Conversation", style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: renameCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: "Enter new title...",
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF00F2FE)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F2FE),
              foregroundColor: const Color(0xFF050B14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              if (renameCtrl.text.trim().isNotEmpty) {
                setState(() {
                  session["title"] = renameCtrl.text.trim();
                });
              }
              Navigator.pop(context);
            },
            child: const Text("Save", style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _deleteSession(String sessionId) {
    setState(() {
      _sessionStorage.remove(sessionId);
      chatSessions.removeWhere((session) => session["id"] == sessionId);

      if (currentSessionId == sessionId) {
        currentSessionId = null;
        messages.clear();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
        ),
        content: const Text("Conversation deleted", style: TextStyle(color: Colors.white, fontSize: 12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayedSessions = chatSessions.where((s) => (s["isArchived"] ?? false) == showArchived).toList();

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: const Color(0xFF050B14),
      drawer: Drawer(
        backgroundColor: const Color(0xFF0A111E),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF00F2FE), Color(0xFF1E3C72)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/tawir_logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      "Conversation History",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F2FE).withValues(alpha: 0.1),
                      foregroundColor: const Color(0xFF00F2FE),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _startNewChat,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text("New Conversation", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => showArchived = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: !showArchived ? const Color(0xFF00F2FE) : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text(
                            "Chats",
                            style: TextStyle(
                              color: !showArchived ? Colors.white : Colors.white54,
                              fontWeight: !showArchived ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => showArchived = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: showArchived ? const Color(0xFF00F2FE) : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text(
                            "Archived",
                            style: TextStyle(
                              color: showArchived ? Colors.white : Colors.white54,
                              fontWeight: showArchived ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: displayedSessions.isEmpty
                    ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      showArchived ? "No archived conversations." : "No previous conversations yet.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: displayedSessions.length,
                  itemBuilder: (context, index) {
                    final session = displayedSessions[index];
                    final sessionId = session["id"];
                    final isSelected = sessionId == currentSessionId;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        leading: Icon(
                          showArchived ? Icons.archive_outlined : Icons.history_rounded,
                          color: Colors.white54,
                          size: 18,
                        ),
                        title: Text(
                          session["title"] ?? "",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          session["date"] ?? "",
                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, color: Colors.white38, size: 16),
                          color: const Color(0xFF0F172A),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'rename',
                              child: const Row(
                                children: [
                                  Icon(Icons.edit_outlined, color: Colors.white70, size: 16),
                                  SizedBox(width: 8),
                                  Text("Rename", style: TextStyle(color: Colors.white, fontSize: 12)),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'archive',
                              child: Row(
                                children: [
                                  Icon(
                                    showArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                                    color: Colors.white70,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(showArchived ? "Unarchive" : "Archive", style: const TextStyle(color: Colors.white, fontSize: 12)),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: const Row(
                                children: [
                                  Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                                  SizedBox(width: 8),
                                  Text("Delete", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            if (value == 'rename') {
                              _renameSession(sessionId);
                            } else if (value == 'archive') {
                              _toggleArchiveSession(sessionId);
                            } else if (value == 'delete') {
                              _deleteSession(sessionId);
                            }
                          },
                        ),
                        onTap: () => _switchSession(sessionId),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          const AppBackground(),
          SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A111E).withValues(alpha: 0.8),
                    border: Border(
                      bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: IconButton(
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.menu_rounded, color: Colors.white70, size: 18),
                          onPressed: () {
                            scaffoldKey.currentState?.openDrawer();
                          },
                          tooltip: "Conversation History",
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00F2FE), Color(0xFF1E3C72)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00F2FE).withValues(alpha: 0.3),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/tawir_logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "TAWIR",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF00F2FE),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                "Active session",
                                style: TextStyle(color: Colors.white54, fontSize: 10),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        decoration: BoxDecoration(
                          color: _autoTtsEnabled
                              ? const Color(0xFF00F2FE).withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _autoTtsEnabled
                                ? const Color(0xFF00F2FE).withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: IconButton(
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            _autoTtsEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                            color: _autoTtsEnabled ? const Color(0xFF00F2FE) : Colors.white54,
                            size: 18,
                          ),
                          onPressed: () {
                            setState(() {
                              _autoTtsEnabled = !_autoTtsEnabled;
                            });
                            if (!_autoTtsEnabled) {
                              _audioPlayer.stop();
                              setState(() {
                                _currentlySpeakingText = null;
                              });
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF0F172A),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
                                ),
                                content: Text(
                                  _autoTtsEnabled
                                      ? "Auto-Speak Pangasinan (MMS-TTS) ON"
                                      : "Auto-Speak Pangasinan (MMS-TTS) OFF",
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          tooltip: _autoTtsEnabled ? "Auto-Speech Enabled (Click to Mute)" : "Auto-Speech Disabled (Click to Enable)",
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: IconButton(
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 18),
                          onPressed: () async {
                            final updatedConfig = await Navigator.push<Map<String, String>>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ConfigScreen(
                                  initialConfig: currentConfig,
                                  openedFromChat: true,
                                ),
                              ),
                            );
                            if (updatedConfig != null) {
                              setState(() {
                                currentConfig = updatedConfig;
                              });
                            }
                          },
                          tooltip: "Modify Configuration",
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: IconButton(
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 18),
                          onPressed: () {
                            setState(() {
                              messages.clear();
                              if (currentSessionId != null) {
                                _sessionStorage[currentSessionId!] = [];
                              }
                            });
                          },
                          tooltip: "Clear Chat",
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: messages.isEmpty && !isTyping
                      ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00F2FE).withValues(alpha: 0.06),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.2)),
                            ),
                            child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF00F2FE), size: 30),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            "How can I help you today?",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Ask a question or start a conversation below.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  )
                      : ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    itemCount: messages.length + (isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == messages.length && isTyping) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/images/tawir_logo.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => const Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      color: Color(0xFF00F2FE),
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A111E),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00F2FE)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text("Tawir is typing...", style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final msg = messages[index];
                      final isUser = msg["role"] == "user";
                      final text = msg["text"] ?? "";

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (!isUser) ...[
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/images/tawir_logo.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => const Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      color: Color(0xFF00F2FE),
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? const Color(0xFF00F2FE)
                                      : const Color(0xFF0A111E),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                                    bottomRight: Radius.circular(isUser ? 4 : 16),
                                  ),
                                  border: isUser
                                      ? null
                                      : Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      text,
                                      style: TextStyle(
                                        color: isUser ? const Color(0xFF050B14) : Colors.white,
                                        fontSize: 13.5,
                                        fontWeight: isUser ? FontWeight.w500 : FontWeight.normal,
                                        height: 1.4,
                                      ),
                                    ),
                                    if (!isUser) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          InkWell(
                                            onTap: () => _copyToClipboard(text),
                                            child: const Icon(Icons.copy_rounded, size: 13, color: Colors.white38),
                                          ),
                                          const SizedBox(width: 12),
                                          InkWell(
                                            onTap: () => _speakText(text),
                                            child: (_currentlySpeakingText == text && _isGeneratingTts)
                                                ? const SizedBox(
                                                    width: 13,
                                                    height: 13,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 1.5,
                                                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00F2FE)),
                                                    ),
                                                  )
                                                : Icon(
                                                    _currentlySpeakingText == text
                                                        ? Icons.stop_circle_rounded
                                                        : Icons.volume_up_rounded,
                                                    size: 14,
                                                    color: _currentlySpeakingText == text
                                                        ? const Color(0xFF00F2FE)
                                                        : Colors.white38,
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A111E),
                    border: Border(
                      top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF050B14),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: TextField(
                            controller: inputCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 13.5),
                            decoration: const InputDecoration(
                              hintText: "Message TAWIR...",
                              hintStyle: TextStyle(color: Colors.white30),
                              border: InputBorder.none,
                            ),
                            onSubmitted: sendMessage,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => sendMessage(inputCtrl.text),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
                            ),
                          ),
                          child: const Icon(Icons.arrow_upward_rounded, color: Color(0xFF050B14), size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}