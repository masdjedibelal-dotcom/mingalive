import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';
import 'main_shell.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onFinished;

  const OnboardingScreen({super.key, this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const String _prefsKey = 'onboarding_seen_v1';
  final PageController _controller = PageController();
  int _index = 0;
  bool _isSaving = false;

  final List<_OnboardingSlide> _slides = const [
    _OnboardingSlide(
      icon: Icons.explore,
      title: 'Entdecke Spots',
      subtitle: 'Finde Orte in deiner Nähe und starte direkt in den Chat.',
      bullets: [
        'Suche nach Titel, Kategorie oder Strasse',
        'Tippe einen Ort an und sieh Details',
      ],
      accent: Color(0xFF45C27E),
      background: Color(0xFF10181A),
    ),
    _OnboardingSlide(
      icon: Icons.stream,
      title: 'Live‑Rooms',
      subtitle: 'Sieh, wo gerade was los ist und tritt sofort bei.',
      bullets: [
        'Swipe durch aktive Rooms',
        'Chatte live mit Leuten vor Ort',
      ],
      accent: Color(0xFF4DA3FF),
      background: Color(0xFF141A22),
    ),
    _OnboardingSlide(
      icon: Icons.collections_bookmark,
      title: 'Collabs',
      subtitle: 'Folge Listen oder kuratiere deine eigenen Spots.',
      bullets: [
        'Speichere deine Lieblingsorte',
        'Teile deine Liste mit Freunden',
      ],
      accent: Color(0xFFFF8A3D),
      background: Color(0xFF1C1712),
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
    if (!mounted) return;
    if (widget.onFinished != null) {
      widget.onFinished!.call();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MainShell(key: mainShellKey)),
    );
  }

  void _next() {
    if (_index >= _slides.length - 1) {
      _complete();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MingaTheme.background,
      body: SafeArea(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: _slides[_index].background,
          ),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: TextButton(
                    onPressed: _complete,
                    style: TextButton.styleFrom(
                      foregroundColor: _slides[_index].accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    child: Text(
                      'Überspringen',
                      style: MingaTheme.bodySmall.copyWith(
                        color: _slides[_index].accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (value) {
                    setState(() {
                      _index = value;
                    });
                  },
                  itemBuilder: (context, index) {
                    final slide = _slides[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: slide.accent.withOpacity(0.16),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              slide.icon,
                              size: 40,
                              color: slide.accent,
                            ),
                          ),
                          SizedBox(height: 24),
                          Text(
                            slide.title,
                            textAlign: TextAlign.center,
                            style: MingaTheme.titleLarge.copyWith(
                              color: MingaTheme.textPrimary,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            slide.subtitle,
                            textAlign: TextAlign.center,
                            style: MingaTheme.body.copyWith(
                              color: MingaTheme.textSubtle,
                              height: 1.4,
                            ),
                          ),
                          SizedBox(height: 18),
                          Column(
                            children: slide.bullets.map((item) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      size: 16,
                                      color: slide.accent,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        item,
                                        textAlign: TextAlign.center,
                                        style: MingaTheme.bodySmall.copyWith(
                                          color: MingaTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _index == index ? 18 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: _index == index
                          ? _slides[_index].accent
                          : MingaTheme.textSubtle.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _slides[_index].accent,
                      foregroundColor: MingaTheme.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
                      ),
                    ),
                    child: Text(
                      _index == _slides.length - 1 ? 'Los geht’s' : 'Weiter',
                      style: MingaTheme.body.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> bullets;
  final Color accent;
  final Color background;

  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bullets,
    required this.accent,
    required this.background,
  });
}








