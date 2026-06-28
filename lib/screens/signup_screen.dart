import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  bool _isPasswordObscure = true;
  bool _isConfirmPasswordObscure = true;
  Uint8List? _selectedImageBytes;
  String? _loadingStatus;
  bool _isMintingDialogOpen = false;
  StateSetter? _mintingDialogSetState;
  // --- Controllers ---
  final PageController _pageController = PageController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _studentNumberController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  // --- Regex ---
  final RegExp _emailRegex = RegExp(
    r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$",
  );

  // --- Logic & State ---
  int _currentStep = 0;
  final int _totalSteps = 3;
  String? _stepError;
  bool _isStepLoading = false;
  String _selectedCampus = '';
  String _selectedDepartment = _departmentOptions.first;
  String _selectedLevel = _natedLevels.first;
  String _selectedGender = _genderOptions.first;
  bool _isNated = true;
  bool _agreedToCode = false;
  String? _campusError;
  String? _nicknameError;
  String? _nameError;
  String? _surnameError;
  String? _dobError;
  String? _passwordError;
  String? _confirmPasswordError;
  bool _isEmailValid = false;
  DateTime? _dateOfBirth;
  // Phone verification removed

  // Add other variables and methods as needed
  AnimationController? _pulseController;
  // --- Data Options ---
  static const _campusOptions = [
    'Balfour',
    'Ermelo',
    'Evander',
    'Mpuluzi',
    'Perdekop',
    'Standerton',
  ];
  static const _genderOptions = ['Male', 'Female', 'Prefer not to say'];
  static const _departmentOptions = [
    'Office Administration',
    'Finance',
    'Information Technology',
    'Marketing',
    'Assistant management',
    'Civil Engineering',
    'Electrical Engineering',
  ];
  static const _natedLevels = ['Introduction', 'N4', 'N5', 'N6'];
  static const _ncvLevels = ['Level 2', 'Level 3', 'Level 4'];

  String? _timeZoneName;
  String? _timeZoneOffset;
  String? _deviceLocale;

  final AuthService _authService = AuthService();
  final ConfettiController _confettiController = ConfettiController(
    duration: const Duration(seconds: 3),
  );

  // Focus Nodes
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _surnameFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();

  // Shake Controllers
  final ShakeController _nameShakeController = ShakeController();
  final ShakeController _surnameShakeController = ShakeController();
  final ShakeController _emailShakeController = ShakeController();
  final ShakeController _passwordShakeController = ShakeController();
  final ShakeController _confirmPasswordShakeController = ShakeController();
  final ShakeController _campusShakeController = ShakeController(); // New

  // Removed duplicate/unused fields

  List<String> get _levelOptions => _isNated ? _natedLevels : _ncvLevels;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: 0.95,
      upperBound: 1.05,
    );
    _pulseController?.repeat(reverse: true);
    _emailController.addListener(_validateEmail);
    _populateDeviceContext();
  }

  void _populateDeviceContext() {
    final now = DateTime.now();
    _timeZoneName = now.timeZoneName;
    _timeZoneOffset = now.timeZoneOffset.toString();
    _deviceLocale = WidgetsBinding.instance.platformDispatcher.locale
        .toLanguageTag();
  }

  void _validateEmail() {
    setState(() {
      _isEmailValid = _emailRegex.hasMatch(_emailController.text.trim());
    });
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    _emailController.removeListener(_validateEmail);
    _nameFocusNode.dispose();
    _surnameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    _confettiController.dispose();
    _nicknameController.dispose();
    _nameController.dispose();
    _surnameController.dispose();
    _emailController.dispose();
    _studentNumberController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // --- Navigation Logic ---
  Future<void> _nextStep() async {
    bool canProceed = false;
    setState(() {
      _stepError = null;
    });

    if (_currentStep == 0) {
      final nickname = _nicknameController.text.trim();
      final name = _nameController.text.trim();
      final surname = _surnameController.text.trim();
      final dobValid = _dateOfBirth != null;
      bool nicknameValid = nickname.isNotEmpty && nickname.length >= 3;
      bool nameValid = name.isNotEmpty;
      bool surnameValid = surname.isNotEmpty;

      setState(() {
        _nicknameError = nicknameValid
            ? null
            : 'Nickname is required (3+ characters).';
        _nameError = nameValid ? null : 'First name is required.';
        _surnameError = surnameValid ? null : 'Surname is required.';
        _dobError = dobValid ? null : 'Date of birth is required.';
      });

      if (!nicknameValid) _nameShakeController.shake();
      if (!nameValid) _nameShakeController.shake();
      if (!surnameValid) _surnameShakeController.shake();

      if (nicknameValid && nameValid && surnameValid && dobValid) {
        canProceed = true;
      } else {
        setState(() {
          _stepError = 'Please complete your personal information.';
        });
      }
    } else if (_currentStep == 1) {
      final campusValid = _selectedCampus.trim().isNotEmpty;
      final departmentValid = _selectedDepartment.trim().isNotEmpty;
      final levelValid = _selectedLevel.trim().isNotEmpty;

      setState(() {
        _campusError = campusValid ? null : 'Please select your campus.';
      });

      if (!campusValid) _campusShakeController.shake();

      if (campusValid && departmentValid && levelValid) {
        canProceed = true;
      } else {
        setState(() {
          _stepError = 'Please complete your academic profile.';
        });
      }
    }

    if (canProceed) {
      setState(() => _isStepLoading = true);
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
      if (!mounted) return;
      setState(() {
        _currentStep++;
        _isStepLoading = false;
      });
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
      setState(() => _currentStep--);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _goToStep(int stepIndex) async {
    if (stepIndex == _currentStep) return;
    setState(() => _currentStep = stepIndex);
    await _pageController.animateToPage(
      stepIndex,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Custom Color Palette for Modern Look
    final primaryColor = Color(0xFF2962FF);
    final accentColor = Color(0xFF00E5FF);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 1. Modern Background (Subtle animated gradient feel)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF5F7FA), Color(0xFFE3F2FD)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // 2. Decorative Blobs (Modern UI trend)
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // ignore: deprecated_member_use
                color: primaryColor.withOpacity(0.1),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // ignore: deprecated_member_use
                color: accentColor.withOpacity(0.1),
              ),
            ),
          ),

          // 3. Main Content
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                        onPressed: _prevStep,
                        color: Colors.black87,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _getHeaderTitle(),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0D47A1),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Progress Bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (_currentStep + 1) / _totalSteps,
                                backgroundColor: Colors.grey[200],
                                valueColor: AlwaysStoppedAnimation(
                                  primaryColor,
                                ),
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 40), // Balance the back button
                    ],
                  ),
                ),

                // Wizard Pages
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics:
                        const NeverScrollableScrollPhysics(), // Prevent swiping
                    children: [
                      _buildStep1Personal(),
                      _buildStep2Academic(),
                      _buildStep3Security(),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 4. Confetti Layer (Top)
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 30,
              gravity: 0.3,
              colors: const [Colors.blue, Colors.yellow, Colors.pink],
            ),
          ),
        ],
      ),
    );
  }

  String _getHeaderTitle() {
    switch (_currentStep) {
      case 0:
        return "Personal Info 🧑‍🎓";
      case 1:
        return "Academic Profile 🎓";
      case 2:
        return "Security 🔐";
      default:
        return "Join Us";
    }
  }

  // --- STEP 1: PERSONAL INFO ---
  Widget _buildStep1Personal() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_stepError != null) _buildStepErrorBanner(_stepError!),
          const Text(
            'Who are you?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0D47A1),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Start with your personal details before setting up your login.',
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 32),
          _buildNicknameField(),
          const SizedBox(height: 24),
          _buildNameField(),
          const SizedBox(height: 24),
          _buildSurnameField(),
          const SizedBox(height: 24),
          _buildDobField(),
          const SizedBox(height: 24),
          const Text(
            'Gender',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          _buildSegmentedGender(),
          const SizedBox(height: 40),
          _buildLargeButton(
            label: "Next Step",
            onPressed: _nextStep,
            isLoading: _isStepLoading,
          ),
        ],
      ),
    );
  }

  // --- STEP 3: SECURITY ---
  Widget _buildStep3Security() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_stepError != null) _buildStepErrorBanner(_stepError!),
          const Text(
            'Secure your account',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0D47A1),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add your student email and password so you can access OG Vibes safely.',
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 32),
          _buildEmailField(),
          const SizedBox(height: 24),
          _buildPasswordField(),
          const SizedBox(height: 24),
          _buildConfirmPasswordField(),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => setState(() => _agreedToCode = !_agreedToCode),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _agreedToCode,
                  activeColor: const Color(0xFF2962FF),
                  onChanged: (v) => setState(() => _agreedToCode = v ?? false),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'I agree to the ',
                      style: const TextStyle(fontSize: 13),
                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => _showTermsPrivacyDialog('Terms'),
                            child: const Text(
                              'Terms',
                              style: TextStyle(
                                color: Color(0xFF2962FF),
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(text: ' and '),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => _showTermsPrivacyDialog('Privacy'),
                            child: const Text(
                              'Privacy Policy',
                              style: TextStyle(
                                color: Color(0xFF2962FF),
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
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
          const SizedBox(height: 24),
          _buildLargeButton(
            label: 'Create Account',
            onPressed: _agreedToCode && !_isLoading ? _handleSignup : null,
            isLoading: _isLoading,
            isPrimary: true,
          ),
          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: _prevStep,
              child: const Text('Back to edit'),
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 2: ACADEMIC PROFILE ---
  Widget _buildStep2Academic() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_stepError != null) _buildStepErrorBanner(_stepError!),
          const Text(
            'Academic Profile',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0D47A1),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tell us where and what you study so we can personalize your feed.',
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 32),
          _buildStudentNumberField(),
          const SizedBox(height: 24),
          Text(
            'Campus',
            style: TextStyle(
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ShakeWidget(
            controller: _campusShakeController,
            child: _buildCampusSelector(),
          ),
          if (_campusError != null) ...[
            const SizedBox(height: 8),
            Text(
              _campusError!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _buildTypeToggle(
                  'Nated Report 191',
                  _isNated,
                  () => setState(() {
                    _isNated = true;
                    _selectedLevel = _natedLevels.first;
                  }),
                ),
                _buildTypeToggle(
                  'NC(V)',
                  !_isNated,
                  () => setState(() {
                    _isNated = false;
                    _selectedLevel = _ncvLevels.first;
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildDropdown(
                  value: _selectedDepartment,
                  label: 'Course / Department',
                  items: _departmentOptions,
                  onChanged: (val) => setState(() => _selectedDepartment = val!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: _buildDropdown(
                  value: _selectedLevel,
                  label: 'Level',
                  items: _levelOptions,
                  onChanged: (val) => setState(() => _selectedLevel = val!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _buildLargeButton(
            label: 'Next Step',
            onPressed: _nextStep,
            isLoading: _isStepLoading,
          ),
        ],
      ),
    );
  }

  // --- CUSTOM WIDGETS ---

  Widget _buildTypeToggle(String title, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isSelected ? const Color(0xFF2962FF) : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedGender() {
    return Row(
      children: _genderOptions.map((gender) {
        final isSelected = _selectedGender == gender;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedGender = gender),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    // ignore: deprecated_member_use
                    ? Color(0xFF2962FF).withOpacity(0.1)
                    : Colors.grey[100],
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF2962FF)
                      : Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                gender,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Color(0xFF2962FF) : Colors.black54,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLargeButton({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
    bool isPrimary = true,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFF2962FF),
          foregroundColor: Colors.white,
          elevation: 8,
          // ignore: deprecated_member_use
          shadowColor: Color(0xFF2962FF).withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
      ),
    );
  }

  // --- Original Field Builders (Stylized) ---

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShakeWidget(
          controller: _nameShakeController,
          child: TextField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [_CapitalizeWordsFormatter()],
            decoration: _modernDecoration('First Name', Icons.person_outline),
          ),
        ),
        if (_nameError != null) ...[
          const SizedBox(height: 6),
          Text(
            _nameError!,
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNicknameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShakeWidget(
          controller: _nameShakeController,
          child: TextField(
            controller: _nicknameController,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [_CapitalizeWordsFormatter()],
            decoration: _modernDecoration('Nickname', Icons.emoji_people_outlined),
          ),
        ),
        if (_nicknameError != null) ...[
          const SizedBox(height: 6),
          Text(
            _nicknameError!,
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDobField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _dateOfBirth ?? DateTime.now().subtract(const Duration(days: 3650)),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            );
            if (date != null) {
              setState(() => _dateOfBirth = date);
            }
          },
          child: AbsorbPointer(
            child: TextField(
              decoration: _modernDecoration(
                _dateOfBirth == null
                    ? 'Date of Birth'
                    : '${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}',
                Icons.calendar_today_outlined,
              ),
            ),
          ),
        ),
        if (_dobError != null) ...[
          const SizedBox(height: 6),
          Text(
            _dobError!,
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStudentNumberField() {
    return TextField(
      controller: _studentNumberController,
      keyboardType: TextInputType.text,
      decoration: _modernDecoration('Student Number (optional)', Icons.badge_outlined),
    );
  }

  Widget _buildSurnameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShakeWidget(
          controller: _surnameShakeController,
          child: TextField(
            controller: _surnameController,
            focusNode: _surnameFocusNode,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [_CapitalizeWordsFormatter()],
            decoration: _modernDecoration('Surname', Icons.badge_outlined),
          ),
        ),
        if (_surnameError != null) ...[
          const SizedBox(height: 6),
          Text(
            _surnameError!,
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmailField() {
    final showSuggestion = _emailController.text.trim().endsWith('@gm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShakeWidget(
          controller: _emailShakeController,
          child: TextField(
            controller: _emailController,
            focusNode: _emailFocusNode,
            keyboardType: TextInputType.emailAddress,
            decoration: _modernDecoration('Student Email', Icons.email_outlined)
                .copyWith(
                  suffixIcon: _isEmailValid
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                ),
          ),
        ),
        if (showSuggestion) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _applyGmailSuggestion,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "Use @gmail.com",
                style: TextStyle(
                  color: Color(0xFF1565C0),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShakeWidget(
          controller: _passwordShakeController,
          child: TextField(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            obscureText: _isPasswordObscure,
            decoration: _modernDecoration('Password', Icons.lock_outline)
                .copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordObscure
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Colors.grey,
                    ),
                    onPressed: () => setState(
                      () => _isPasswordObscure = !_isPasswordObscure,
                    ),
                  ),
                ),
          ),
        ),
        if (_passwordError != null) ...[
          const SizedBox(height: 6),
          Text(
            _passwordError!,
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConfirmPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShakeWidget(
          controller: _confirmPasswordShakeController,
          child: TextField(
            controller: _confirmPasswordController,
            focusNode: _confirmPasswordFocusNode,
            obscureText: _isConfirmPasswordObscure,
            decoration:
                _modernDecoration(
                  'Confirm Password',
                  Icons.lock_outline,
                ).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isConfirmPasswordObscure
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Colors.grey,
                    ),
                    onPressed: () => setState(
                      () => _isConfirmPasswordObscure =
                          !_isConfirmPasswordObscure,
                    ),
                  ),
                ),
          ),
        ),
        if (_confirmPasswordError != null) ...[
          const SizedBox(height: 6),
          Text(
            _confirmPasswordError!,
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _modernDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey[600], size: 20),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2962FF), width: 1.5),
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required String label,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: _modernDecoration(label, Icons.layers_outlined),
      dropdownColor: Colors.white,
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(item, style: const TextStyle(fontSize: 14)),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildCampusSelector() {
    return DropdownButtonFormField<String>(
      value: _selectedCampus.isEmpty ? null : _selectedCampus,
      decoration: _modernDecoration('Select Campus', Icons.school_outlined),
      dropdownColor: Colors.white,
      hint: const Text('Choose your campus'),
      items: _campusOptions
          .map(
            (campus) => DropdownMenuItem(
              value: campus,
              child: Text(campus, style: const TextStyle(fontSize: 14)),
            ),
          )
          .toList(),
      onChanged: (val) => setState(() => _selectedCampus = val ?? ''),
    );
  }

  Widget _buildProfilePicker() {
    return Semantics(
      label: 'Upload profile photo',
      button: true,
      child: GestureDetector(
        onTap: _pickProfileImage,
        child: SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: Colors.grey[100],
                backgroundImage: _selectedImageBytes != null
                    ? MemoryImage(_selectedImageBytes!)
                    : null,
                child: _selectedImageBytes == null
                    ? const Icon(Icons.person, size: 40, color: Colors.grey)
                    : null,
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF2962FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Logic Helpers ---

  Future<void> _pickProfileImage() async {
    try {
      setState(() {});
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _selectedImageBytes = bytes);
    } catch (_) {}
  }

  void _applyGmailSuggestion() {
    final text = _emailController.text;
    if (text.endsWith('@gm')) {
      _emailController.text = '${text.substring(0, text.length - 3)}@gmail.com';
    }
  }

  Future<void> _handleSignup() async {
    if (!_validateSecurityStep()) return;

    setState(() => _isLoading = true);
    _openMintingDialog();
    _updateMintingStatus('Initializing Student ID...');

    try {
      await Future.delayed(const Duration(seconds: 1));
      final result = await _authService.signUp(
        email: _emailController.text,
        password: _passwordController.text,
        name: _nameController.text,
        surname: _surnameController.text,
        nickname: _nicknameController.text.trim(),
        campus: _selectedCampus,
        department: _selectedDepartment,
        level: _selectedLevel,
        studentType: _isNated ? 'Nated' : 'NCV',
        gender: _selectedGender,
        studentNumber: _studentNumberController.text.trim(),
        timeZoneName: _timeZoneName,
        timeZoneOffset: _timeZoneOffset,
        deviceLocale: _deviceLocale,
      );

      _updateMintingStatus('Preparing your account...');
      final user = result.response.user;

      _closeMintingDialog();
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Verify your email',
            style: TextStyle(
              color: Color(0xFF0D47A1),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'A verification link has been sent to your email. Please verify your email address before logging in.',
            style: TextStyle(color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'OK',
                style: TextStyle(color: Color(0xFF2962FF)),
              ),
            ),
          ],
        ),
      );
      Navigator.of(
        // ignore: use_build_context_synchronously
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));

      if (user != null) {
        Future.microtask(() => _maybeUploadProfileImage(user));
      }
    } catch (e, st) {
      _closeMintingDialog();
      // Print full stack to browser console for debugging
      // ignore: avoid_print
      print('Signup error: $e');
      // ignore: avoid_print
      print(st);
      final message = '$e\nSee console for stack trace.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _validateSecurityStep() {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final emailValid = email.isNotEmpty && _emailRegex.hasMatch(email);
    final passValid = password.isNotEmpty && password.length >= 6;
    final confirmValid = confirmPassword.isNotEmpty && confirmPassword == password;
    final termsValid = _agreedToCode;

    setState(() {
      _passwordError = passValid ? null : 'Use at least 6 characters for your password.';
      _confirmPasswordError = confirmValid ? null : 'Passwords do not match. Please re-type.';
      _stepError = null;
    });

    if (!emailValid || !passValid || !confirmValid || !termsValid) {
      setState(() {
        _stepError = termsValid
            ? 'Please fill all required security fields correctly.'
            : 'Please accept the Terms and Privacy Policy.';
      });
      if (!emailValid) _emailShakeController.shake();
      if (!passValid) _passwordShakeController.shake();
      if (!confirmValid) _confirmPasswordShakeController.shake();
      return false;
    }
    return true;
  }

  // --- Dialogs & Utilities (Kept from original but cleaned up) ---

  void _openMintingDialog() {
    _isMintingDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            _mintingDialogSetState = setState;
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(color: Color(0xFF2962FF)),
                  const SizedBox(height: 24),
                  Text(
                    _loadingStatus ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0D47A1),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _isMintingDialogOpen = false;
      _mintingDialogSetState = null;
    });
  }

  void _updateMintingStatus(String status) {
    _loadingStatus = status;
    if (!_isMintingDialogOpen || !mounted) return;
    try {
      _mintingDialogSetState?.call(() {});
    } catch (_) {
      _mintingDialogSetState = null;
      _isMintingDialogOpen = false;
    }
  }

  void _closeMintingDialog() {
    if (!_isMintingDialogOpen) return;
    if (!mounted) {
      _mintingDialogSetState = null;
      _isMintingDialogOpen = false;
      return;
    }
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    _mintingDialogSetState = null;
    _isMintingDialogOpen = false;
  }

  Future<void> _maybeUploadProfileImage(dynamic user) async {
    if (_selectedImageBytes == null || user == null) return;
    try {
      setState(() {});
      await Supabase.instance.client.storage
          .from('profile_images')
          .uploadBinary('${user.id}.jpg', _selectedImageBytes!);

      final signedUrl = await Supabase.instance.client.storage
          .from('profile_images')
          .createSignedUrl('${user.id}.jpg', 60 * 60 * 24 * 365);

      await Supabase.instance.client
          .from('public.profiles')
          .update({'photoUrl': signedUrl}).eq('id', user.id);

      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _showVibeCodeDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("The Vibe Code 📜"),
        content: const Text(
          "1. Respect everyone.\n2. Keep it clean.\n3. Helping others is cool.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Got it"),
          ),
        ],
      ),
    );
  }

  void _showTermsPrivacyDialog(String type) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              24 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    type,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF0D47A1),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    type == 'Terms'
                        ? 'These terms explain how OG Vibes works and what we expect from students.'
                        : 'We only use your data to provide campus services and keep your account secure.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Full policy text goes here. We can replace this with the official document when ready.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black45),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSuccessConfirmation() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.check_circle, size: 64, color: Color(0xFF2962FF)),
                SizedBox(height: 12),
                Text(
                  'Account ready!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Color(0xFF0D47A1),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Taking you to your dashboard…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        );
      },
    );
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Widget _buildStep4Review() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_stepError != null) _buildStepErrorBanner(_stepError!),
          const Text(
            'Review your details before creating the account.',
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 20),
          _buildReviewTile('Email', _emailController.text.trim(), stepIndex: 0),
          _buildReviewTile(
            'Name',
            '${_nameController.text.trim()} ${_surnameController.text.trim()}',
            stepIndex: 1,
          ),
          _buildReviewTile(
            'Campus',
            _selectedCampus.isEmpty ? 'Not set' : _selectedCampus,
            stepIndex: 2,
          ),
          _buildReviewTile('Department', _selectedDepartment, stepIndex: 2),
          _buildReviewTile('Level', _selectedLevel, stepIndex: 2),
          _buildReviewTile(
            'Student Type',
            _isNated ? 'Nated' : 'NCV',
            stepIndex: 2,
          ),
          _buildReviewTile('Gender', _selectedGender, stepIndex: 1),
          _buildReviewTile(
            'Time Zone',
            _timeZoneName == null || _timeZoneName!.isEmpty
                ? 'Not set'
                : _timeZoneName!,
          ),
          const SizedBox(height: 24),
          _buildLargeButton(
            label: 'Create Account',
            onPressed: _agreedToCode && !_isLoading ? _handleSignup : null,
            isLoading: _isLoading,
            isPrimary: true,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _prevStep,
              child: const Text('Back to edit'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewTile(String label, String value, {int? stepIndex}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: stepIndex != null ? () => _goToStep(stepIndex) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value.isEmpty ? '—' : value,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0D47A1),
                        ),
                      ),
                    ],
                  ),
                ),
                if (stepIndex != null)
                  const Icon(Icons.edit, size: 18, color: Colors.black45),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Helpers kept from original ---

class _CapitalizeWordsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final words = newValue.text.split(' ');
    final capitalizedWords = words.map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).toList();

    final formattedText = capitalizedWords.join(' ');

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.fromPosition(
        TextPosition(offset: formattedText.length),
      ),
    );
  }
}

class ShakeController {
  VoidCallback? _listener;
  void shake() => _listener?.call();
}

class ShakeWidget extends StatefulWidget {
  const ShakeWidget({super.key, required this.controller, required this.child});
  final ShakeController controller;
  final Widget child;
  @override
  State<ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<ShakeWidget>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _offsetAnimation = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _controller!, curve: Curves.easeInOut));
    widget.controller._listener = () => _controller?.forward(from: 0);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(_offsetAnimation?.value ?? 0, 0),
      child: widget.child,
    );
  }
}
